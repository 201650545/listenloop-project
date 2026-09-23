import 'dart:io';
import 'dart:isolate';


import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../preferences/app_preferences.dart';
import 'asr_engine.dart';
import 'asr_window_planner.dart';
import 'seam_reconciler.dart';
import 'vad_segmenter.dart';
import 'word_timestamp.dart';

/// Runs INSIDE a spawned isolate.
///
/// Decodes the media one BOUNDED window at a time rather than in a single
/// pass. Two reasons, and both are load-bearing (Creation V2 §六十一):
///
/// * a single pass longer than ~400 s deterministically kills the model — the
///   encoder aborts inside `/layers.0/self_attn/Add_2` with a broadcast shape
///   mismatch (`2513 by 7513` at 601 s, `63 by 5063` at 405 s), so a lesson
///   longer than about six and a half minutes could not be created at all;
/// * attention cost grows faster than linearly with length, so windowing is
///   also ~3x faster on the same material.
///
/// Words are grouped, offset and de-duplicated HERE, inside the window loop:
/// the ownership rule needs each token's midpoint relative to the window that
/// produced it, and the layers above must never learn that chunks exist.
///
/// Progress is streamed back over `payload['port']` — a 30 minute job would
/// otherwise sit on a frozen bar for minutes.
void _decodeInIsolate(Map<String, Object> payload) {
  final port = payload['port'] as SendPort;
  void progress(double value) => port.send(value);

  sherpa.initBindings();
  final dir = payload['dir']! as String;
  final sep = Platform.pathSeparator;
  // Self-exported whisper with cross-attention outputs (see the class doc):
  // the only model form that yields word-level timestamps, hence the only
  // shipped engine configuration.
  final targetLanguage = (payload['language'] as String? ?? '').trim();
  final config = sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      whisper: sherpa.OfflineWhisperModelConfig(
        encoder: '$dir$sep${payload['encoder']}',
        decoder: '$dir$sep${payload['decoder']}',
        // Multilingual checkpoints: targetLanguage supports 'en', 'ja', 'zh' etc.,
        // or empty string for automatic language detection.
        language: targetLanguage,
        task: 'transcribe',
        enableTokenTimestamps: true,
      ),
      tokens: '$dir$sep${payload['tokens']}',
      modelType: 'whisper',
      // Creation V2 §十五: not "all cores". The Snapdragon 8 Gen 3 is
      // big.LITTLE; oversubscribing past the performance cluster buys heat,
      // not throughput. Configurable so the 2/4/6/8 sweep needs no rebuild.
      numThreads: int.tryParse(payload['threads'] as String? ?? '') ??
          kDefaultAsrThreads,
      debug: false,
      provider: 'cpu',
    ),
    decodingMethod: 'greedy_search',
  );
  final recognizer = sherpa.OfflineRecognizer(config);

  final bytes = File(payload['wav']! as String).readAsBytesSync();
  const dataOffset = 44;
  // 16-bit mono at 16 kHz: 2 bytes per sample, 16 samples per millisecond.
  final audioMs = (bytes.length - dataOffset) ~/ 2 * 1000 ~/ 16000;

  // Windowing is independent of VAD: with no silence map the planner simply
  // hard-splits at the target length, which is already bounded and safe. VAD
  // only improves WHERE the cuts land (Creation V2 §九/§十) — so a missing VAD
  // model degrades the boundary quality, it never fails the job.
  var silenceGaps = const <SpeechRegion>[];
  final vadPath = '$dir$sep${payload['vad']}';
  if (payload['vad'] != null && File(vadPath).existsSync()) {
    try {
      silenceGaps = VadSegmenter.silenceGaps(
        vadModelPath: vadPath,
        wavBytes: bytes,
        totalMs: audioMs,
      );
    } catch (error) {
      debugPrint('[ListenLoop][vad] unavailable, hard-splitting: $error');
    }
  }

  final windows = AsrWindowPlanner.plan(
    totalMs: audioMs,
    silenceGaps: silenceGaps,
    targetWindowMs:
        int.tryParse(payload['windowTargetMs'] as String? ?? '') ??
        kDefaultTargetWindowMs,
    hardMaxWindowMs:
        int.tryParse(payload['windowHardMaxMs'] as String? ?? '') ??
        kHardMaxWindowMs,
  );
  debugPrint(
    '[ListenLoop][vad] pauses=${silenceGaps.length} windows=${windows.length}',
  );
  progress(0);

  final collected = <SeamWord>[];
  for (var i = 0; i < windows.length; i++) {
    final window = windows[i];
    final samples = _samplesFor(bytes, window.readStartMs, window.readEndMs);
    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);

    final local = tokensToWords(
      result.tokens,
      result.timestamps,
    );
    for (final word in local) {
      // The one invariant that keeps the Timeline honest: global requires the
      // window's read offset, because local times are relative to what the
      // model actually saw (Creation V2 §八).
      final startMs = word.startMs + window.readStartMs;
      final endMs = word.endMs + window.readStartMs;
      // Owned by whichever window contains the midpoint. This stays the first
      // ownership signal; the seam pass below refines it (§二十七).
      final midpoint = (startMs + endMs) ~/ 2;
      if (midpoint < window.keepStartMs || midpoint >= window.keepEndMs) {
        continue;
      }
      collected.add(
        SeamWord(
          word: word.word,
          startMs: startMs,
          endMs: endMs,
          windowId: i,
          readStartMs: window.readStartMs,
          readEndMs: window.readEndMs,
        ),
      );
    }
    progress((i + 1) / windows.length);
  }

  collected.sort((a, b) => a.startMs.compareTo(b.startMs));
  // Ownership alone is not enough: the two windows straddling a seam estimate
  // a token's midpoint independently, and a millisecond of disagreement puts
  // the same word in both keep ranges (§二十八).
  final words = reconcileSeams(
    collected,
    [for (final window in windows.skip(1)) window.keepStartMs],
  );
  port.send({
    'words': [
      for (final word in words) [word.word, word.startMs, word.endMs],
    ],
    'windows': windows.length,
    'audioMs': audioMs,
  });
}

/// Builds one window's samples straight out of the WAV bytes.
///
/// Deliberately per window rather than one buffer for the whole media: a
/// 30 minute clip would otherwise hold a 115 MB Float32List for the entire
/// job (Creation V2 §十六).
Float32List _samplesFor(Uint8List bytes, int startMs, int endMs) {
  const dataOffset = 44;
  const samplesPerMs = 16; // 16 kHz
  final first = dataOffset + startMs * samplesPerMs * 2;
  final last = (dataOffset + endMs * samplesPerMs * 2).clamp(0, bytes.length);
  final count = last > first ? (last - first) ~/ 2 : 0;
  final out = Float32List(count);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < count; i++) {
    out[i] = view.getInt16(first + i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Production ASR engine: a self-exported Whisper ONNX model with
/// cross-attention outputs, served by sherpa-onnx. Two tiers share the same
/// pipeline (2026-09-18 用户拍板, both multilingual checkpoints):
///
/// * fast — whisper base (`models/asr/whisper-base/`, ~160 MB int8);
/// * precise — whisper small (`models/asr/whisper-small/`, ~374 MB int8).
///
/// WHY SELF-EXPORTED (the M1 blocker, resolved 2026-09-18): the whisper
/// exports sherpa-onnx publishes carry NO cross-attention outputs, so
/// `enableTokenTimestamps` warns and every token timestamp is 0 — a 4:46
/// transcript collapses to a single word. Word timestamps exist only when the
/// decoder has the 4th `cross_attention_weights` output; sherpa-onnx then
/// derives per-token times via DTW. The official `export-onnx-with-attention.py`
/// produces exactly that — BUT it must run under torch ≤2.8: the torch 2.14
/// dynamo exporter bakes the dynamic T axis and the runtime fails with a
/// Reshape error (verified both ways on PC). The multilingual checkpoints are
/// used deliberately (用户: 不要把路走窄 — 中文课是同一管道换个语言参数).
///
/// Whisper still caps a single inference at 30 s ("Only waves less than 30
/// seconds are supported" — longer input is silently truncated), so windows
/// are planned at 25 s keep / 27 s hard max: with the 2 s context overlap the
/// read span stays under the cap while the windowing architecture is
/// untouched.
///
/// Windows are decoded in a spawned isolate so the UI keeps breathing
/// (spec V1 §四十二) and so progress can be reported per window.
class SherpaOnnxAsrEngine implements AsrEngine {
  SherpaOnnxAsrEngine({
    required this.modelDirResolver,
    this.tier,
    this.vadModelFile = 'silero_vad.onnx',
    int Function()? threads,
  }) : _threads = threads ?? (() => kDefaultAsrThreads);

  /// Resolves the ASR models root (resolved lazily — the directory may be
  /// created/pushed after app start). The tier selects a subdirectory under
  /// it via [AsrTier.modelDirName].
  final Future<String> Function() modelDirResolver;

  /// Which quality tier to transcribe with, read per job so a settings
  /// change applies without rebuilding the engine. Null = fast tier.
  final AsrTier Function()? tier;

  /// Silero VAD model, relative to the resolved directory. Optional: when it
  /// is absent the planner hard-splits instead of cutting at pauses.
  final String vadModelFile;

  /// Decode threads, read per call so a settings change applies to the next
  /// job without rebuilding the engine (Creation V2 §十五).
  final int Function() _threads;

  String? _resolvedRoot;

  Future<String> _resolveTierDir() async {
    final root = _resolvedRoot ??= await modelDirResolver();
    final currentTier = tier?.call() ?? AsrTier.fast;
    final sep = Platform.pathSeparator;
    return '$root$sep${currentTier.modelDirName}';
  }

  Future<bool> get _modelFilesExist async {
    final dir = await _resolveTierDir();
    final currentTier = tier?.call() ?? AsrTier.fast;
    final sep = Platform.pathSeparator;
    return File('$dir$sep${currentTier.encoderFile}').existsSync() &&
        File('$dir$sep${currentTier.decoderFile}').existsSync() &&
        File('$dir$sep${currentTier.tokensFile}').existsSync();
  }

  @override
  Future<List<WordTimestamp>> transcribe(
    String wavPath, {
    String? language,
    required void Function(double progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    onProgress(0);
    if (!await _modelFilesExist) {
      final currentTier = tier?.call() ?? AsrTier.fast;
      final dir = await _resolveTierDir();
      throw StateError(
        'ASR model not installed in $dir '
        '(expected ${currentTier.encoderFile}, ${currentTier.decoderFile} '
        'and ${currentTier.tokensFile})',
      );
    }
    if (isCancelled()) return const [];

    final dir = await _resolveTierDir();
    final currentTier = tier?.call() ?? AsrTier.fast;

    final messages = ReceivePort();
    try {
      await Isolate.spawn(_decodeInIsolate, <String, Object>{
        'dir': dir,
        'encoder': currentTier.encoderFile,
        'decoder': currentTier.decoderFile,
        'tokens': currentTier.tokensFile,
        'vad': vadModelFile,
        'wav': wavPath,
        'threads': '${_threads()}',
        'language': language ?? '',
        // Whisper caps a single inference at 30 s; 25 s keep + 27 s hard max
        // keeps the 2 s context overlap inside the cap (90 s is the NeMo
        // bring-up value and no longer used by any shipped model).
        'windowTargetMs': '25000',
        'windowHardMaxMs': '27000',
        'port': messages.sendPort,
      });
      // Progress arrives as doubles; the single Map is the final result.
      Object? result;
      await for (final message in messages) {
        if (message is double) {
          onProgress(message);
        } else if (message is Map) {
          result = message;
          break;
        }
      }
      if (isCancelled()) return const [];
      if (result is! Map) return const [];

      final raw = (result['words'] as List?) ?? const [];
      final words = <WordTimestamp>[
        for (final entry in raw)
          WordTimestamp(
            word: (entry as List)[0] as String,
            startMs: entry[1] as int,
            endMs: entry[2] as int,
          ),
      ];
      debugPrint(
        '[ListenLoop][asr] windows=${result['windows']} '
        'audioMs=${result['audioMs']} words=${words.length}',
      );
      onProgress(1);
      return words;
    } finally {
      messages.close();
    }
  }
}

/// Upper bound on how far a word may be extended past its own last token.
///
/// sherpa-onnx reports the frame each CTC token FIRED on, i.e. its start, so a
/// word's end has to be inferred from the next boundary. Clamping the reach
/// keeps a real silence visible as a gap — without it every inter-word gap
/// would close to zero and the segmenter's 900 ms silence rule would never
/// fire again.
const int kMaxTokenMs = 320;

/// Sentencepiece / byte-level-BPE word-start markers.
final RegExp _wordStartMarker = RegExp(r'^[\u2581\u0120]');

/// Standalone whitespace piece.
final RegExp _leadingWhitespace = RegExp(r'^\s');

/// A piece carrying no word of its own — it attaches to the word it follows
/// ("music" + "." -> "music.").
final RegExp _punctuationOnly = RegExp(
  r'''^[\s.,!?;:'"()\[\]\u2019\u201c\u201d、。！？…—·～「」『』【】《》-]+$''',
);

/// CJK character pattern (Japanese kana/kanji, Chinese, Korean).
final RegExp _cjkPattern = RegExp(
  r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]',
);

/// Groups CTC token pieces into words.
///
/// Handles both English space-separated pieces and CJK (Japanese/Chinese)
/// continuous characters using punctuation, acoustic pauses (>250ms), and
/// CJK word-span limits.
List<WordTimestamp> tokensToWords(
  List<String> tokens,
  List<double> timestamps,
) {
  final words = <WordTimestamp>[];
  final buffer = StringBuffer();
  var startMs = 0;
  var lastMs = 0;
  var open = false;
  var pendingBreak = false;

  void flush(int nextMs) {
    final text = buffer.toString().trim();
    if (text.isNotEmpty) {
      final reach = nextMs > lastMs ? (nextMs - lastMs).clamp(0, kMaxTokenMs) : 0;
      words.add(
        WordTimestamp(word: text, startMs: startMs, endMs: lastMs + reach),
      );
    }
    buffer.clear();
    open = false;
    pendingBreak = false;
  }

  for (var i = 0; i < tokens.length; i++) {
    final raw = tokens[i];
    final ms = i < timestamps.length ? (timestamps[i] * 1000).round() : lastMs;
    final body = raw.replaceFirst(_wordStartMarker, '').trim();
    if (body.isEmpty) {
      pendingBreak = true;
      continue;
    }

    final isPunct = _punctuationOnly.hasMatch(body);
    final isCjk = _cjkPattern.hasMatch(body);
    final prevIsCjk = buffer.isNotEmpty && _cjkPattern.hasMatch(buffer.toString());

    // In CJK (Japanese/Chinese), tokens have no leading space. We use acoustic pauses
    // (>= 300ms) or natural CJK span length to identify word boundaries.
    final cjkAcousticPause = open && (isCjk || prevIsCjk) && (ms - lastMs >= 300);
    final cjkLengthBreak = open && isCjk && prevIsCjk && buffer.length >= 4;

    final startsWord =
        pendingBreak ||
        _leadingWhitespace.hasMatch(raw) ||
        _wordStartMarker.hasMatch(raw) ||
        cjkAcousticPause ||
        cjkLengthBreak;

    if (open && startsWord && !isPunct) {
      flush(ms);
    }

    if (!open) {
      startMs = ms;
      open = true;
    }
    lastMs = ms;
    buffer.write(body);

    // If this token was punctuation, force next token to start anew.
    if (isPunct) {
      pendingBreak = true;
    }
  }
  flush(lastMs + kMaxTokenMs);
  return words;
}

