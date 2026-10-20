import 'word_timestamp.dart';

/// ASR boundary (spec V1 §十六): the creation pipeline consumes
/// [WordTimestamp]s and never knows which engine produced them.
///
/// v1 engine: sherpa-onnx (whisper onnx models, token timestamps) — wired in
/// `SherpaOnnxAsrEngine`. Tests use [MockAsrEngine].
abstract class AsrEngine {
  /// Transcribes a mono 16 kHz WAV file into word timestamps.
  ///
  /// [onProgress] reports 0..1 across the audio duration when the engine can
  /// estimate it; [isCancelled] is polled between internal chunks so a cancel
  /// request can abort early (best effort — see spec V1 §四十四).
  Future<List<WordTimestamp>> transcribe(
    String wavPath, {
    String? language,
    required void Function(double progress) onProgress,
    required bool Function() isCancelled,
  });
}

/// Deterministic engine for tests and UI development: replays a scripted
/// word list spread over [durationMs], reporting progress in [steps] ticks.
class MockAsrEngine implements AsrEngine {
  MockAsrEngine({required this.words, this.durationMs = 30000, this.steps = 4});

  final List<WordTimestamp> words;
  final int durationMs;
  final int steps;

  @override
  Future<List<WordTimestamp>> transcribe(
    String wavPath, {
    String? language,
    required void Function(double progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(Duration.zero);
      onProgress(i / steps);
    }
    return List.of(words);
  }
}

/// Convenience builder used by tests and fixtures: spreads [text] words
/// evenly across [durationMs] with [wordsPerSentence]-word sentence groups
/// ending in a period (produces punctuation breaks for the segmenter).
List<WordTimestamp> buildScriptWords(
  String text,
  int durationMs, {
  int wordsPerSentence = 8,
}) {
  final words = text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList(growable: false);
  final per = durationMs / words.length;
  final result = <WordTimestamp>[];
  for (var i = 0; i < words.length; i++) {
    final isSentenceEnd =
        (i + 1) % wordsPerSentence == 0 || i == words.length - 1;
    result.add(
      WordTimestamp(
        word: isSentenceEnd ? '${words[i]}.' : words[i],
        startMs: (i * per).round(),
        endMs: ((i + 1) * per).round() - 1,
      ),
    );
  }
  return result;
}
