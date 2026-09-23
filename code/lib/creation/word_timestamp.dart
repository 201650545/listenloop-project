import 'package:flutter/foundation.dart';

/// One recognised word with its position on the media timeline.
///
/// This is the currency of the whole creation pipeline (spec V1 §十六/§五十二):
/// the ASR engine produces these, the segmenter consumes them, and nothing
/// downstream ever talks to Whisper directly.
@immutable
class WordTimestamp {
  const WordTimestamp({
    required this.word,
    required this.startMs,
    required this.endMs,
  });

  /// Single word, already trimmed (no leading/trailing spaces).
  final String word;
  final int startMs;
  final int endMs;
}
