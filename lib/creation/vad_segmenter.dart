import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'asr_window_planner.dart';

/// Silero VAD window size, in samples, as the model requires.
const int _windowSamples = 512;

/// How much audio is pushed into the detector per call.
///
/// A multiple of [_windowSamples] so the detector never has to partial-buffer
/// across calls, and large enough that the per-call native copy does not
/// dominate — one second of audio, roughly.
const int _chunkSamples = _windowSamples * 32;

/// Pauses shorter than this are not worth cutting at.
const int kMinCuttablePauseMs = 300;

/// Runs voice-activity detection and reports where the PAUSES are.
///
/// The output is a list of silences, not of speech, because that is what the
/// planner consumes: a pause is a place where a window may end naturally
/// (Creation V2 §九/§十一).
///
/// Two rules this deliberately obeys:
///
/// * **VAD never touches the audio.** It does not delete silence, does not
///   concatenate speech, and does not produce a new file — the media keeps its
///   original timeline so `global = readStart + local` stays exact (§十二/§十九).
/// * **VAD never decides a sentence.** A pause is only a candidate place to end
///   an ASR window; sentence boundaries stay the segmenter's business (§三十).
abstract final class VadSegmenter {
  /// Returns the silences in `wavBytes` (16-bit mono 16 kHz), as ranges on the
  /// original timeline.
  ///
  /// Throws if the detector cannot be created — the caller treats a missing
  /// VAD model as "no silence map" rather than as a failed job.
  static List<SpeechRegion> silenceGaps({
    required String vadModelPath,
    required Uint8List wavBytes,
    required int totalMs,
    double threshold = 0.5,
    double minSilenceMs = 500,
    double minSpeechMs = 250,
    double maxSpeechMs = 30 * 1000,
  }) {
    final detector = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: vadModelPath,
          threshold: threshold,
          minSilenceDuration: minSilenceMs / 1000,
          minSpeechDuration: minSpeechMs / 1000,
          windowSize: _windowSamples,
          // A guard so one unbroken monologue cannot make the detector emit a
          // single unbounded segment. The planner enforces its own hard ceiling
          // as well, so this is defence in depth, not the enforcement point.
          maxSpeechDuration: maxSpeechMs / 1000,
        ),
        sampleRate: 16000,
        numThreads: 1,
        provider: 'cpu',
        debug: false,
      ),
      // Has to hold at least one whole segment; comfortably above
      // maxSpeechMs so a long stretch is never truncated by the ring.
      bufferSizeInSeconds: (maxSpeechMs / 1000).ceil() * 3,
    );

    final speech = <SpeechRegion>[];
    try {
      const dataOffset = 44;
      final totalSamples = (wavBytes.length - dataOffset) ~/ 2;
      final view = ByteData.sublistView(wavBytes);
      for (var start = 0; start < totalSamples; start += _chunkSamples) {
        final count = (start + _chunkSamples).clamp(0, totalSamples) - start;
        final chunk = Float32List(count);
        for (var i = 0; i < count; i++) {
          chunk[i] =
              view.getInt16(dataOffset + (start + i) * 2, Endian.little) /
              32768.0;
        }
        detector.acceptWaveform(chunk);
        _drain(detector, speech);
      }
      detector.flush();
      _drain(detector, speech);
    } finally {
      detector.free();
    }

    return silencesBetween(speech, totalMs);
  }

  static void _drain(
    sherpa.VoiceActivityDetector detector,
    List<SpeechRegion> into,
  ) {
    while (!detector.isEmpty()) {
      final segment = detector.front();
      detector.pop();
      if (segment.samples.isEmpty) continue;
      final startMs = segment.start ~/ 16; // samples -> ms at 16 kHz
      final endMs = startMs + segment.samples.length ~/ 16;
      into.add(SpeechRegion(startMs: startMs, endMs: endMs));
    }
  }

  /// Turns the speech segments into the pauses between them.
  ///
  /// Adjacent segments are merged first: the detector splits a long unbroken
  /// stretch at `maxSpeechDuration`, and a forced split is not a real pause —
  /// treating it as one would hand the planner a boundary that does not exist.
  ///
  /// Public because it is the whole of the interesting logic here and needs no
  /// native model to exercise.
  static List<SpeechRegion> silencesBetween(
    List<SpeechRegion> speech,
    int totalMs,
  ) {
    // No speech at all means no evidence of where a pause is, and inventing a
    // cut point from nothing would be worse than letting the planner
    // hard-split. An empty map is a valid, safe answer.
    if (speech.isEmpty) return const [];
    final sorted = [...speech]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final merged = <SpeechRegion>[sorted.first];
    for (final region in sorted.skip(1)) {
      final last = merged.last;
      // Strictly shorter than the minimum cuttable pause: a gap of exactly
      // that length IS a usable cut point, so it must not be merged away.
      if (region.startMs < last.endMs + kMinCuttablePauseMs) {
        merged[merged.length - 1] = SpeechRegion(
          startMs: last.startMs,
          endMs: region.endMs > last.endMs ? region.endMs : last.endMs,
        );
      } else {
        merged.add(region);
      }
    }

    final gaps = <SpeechRegion>[];
    var cursor = 0;
    for (final region in merged) {
      if (region.startMs - cursor >= kMinCuttablePauseMs) {
        gaps.add(SpeechRegion(startMs: cursor, endMs: region.startMs));
      }
      if (region.endMs > cursor) cursor = region.endMs;
    }
    if (totalMs - cursor >= kMinCuttablePauseMs) {
      gaps.add(SpeechRegion(startMs: cursor, endMs: totalMs));
    }
    return gaps;
  }
}
