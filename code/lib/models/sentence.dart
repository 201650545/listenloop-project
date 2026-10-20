/// Immutable model describing one sentence of listening material.
///
/// A [Sentence] maps a slice of an audio asset (`startMs` -> `endMs`) to its
/// English transcript and Chinese translation. Milestone 1 uses hard-coded
/// sentences, but the model is intentionally data-source agnostic so it can
/// later be produced by Whisper transcription without any change here.
class Sentence {
  const Sentence({
    required this.id,
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.english,
    required this.chinese,
    this.charStarts,
  }) : assert(startMs >= 0, 'startMs must be >= 0'),
       assert(endMs > startMs, 'endMs must be strictly greater than startMs'),
       assert(index >= 0, 'index must be >= 0');

  /// Stable unique identifier (e.g. `'s1'`).
  final String id;

  /// Zero-based position of this sentence within its track.
  final int index;

  /// Inclusive playback start offset in milliseconds.
  final int startMs;

  /// Exclusive playback end offset in milliseconds. Playback should stop here.
  final int endMs;

  /// Original English transcript.
  final String english;

  /// Chinese translation.
  final String chinese;

  /// Optional character-level start timestamps in milliseconds (for follow-along finger reading).
  final List<int>? charStarts;

  /// Semantic alias for original transcript (supports multi-language).
  String get originalText => english;

  /// Semantic alias for translated text (supports multi-language).
  String get translatedText => chinese;

  /// Total duration of this sentence in milliseconds.
  int get durationMs => endMs - startMs;

  /// Returns the number of characters in [originalText] that have been spoken by [positionMs].
  /// If [charStarts] is provided, uses exact timestamps;
  /// otherwise linearly interpolates across [durationMs].
  int activeCharIndexAt(int positionMs) {
    if (positionMs <= startMs) return 0;
    if (positionMs >= endMs) return originalText.length;
    if (charStarts != null && charStarts!.isNotEmpty) {
      final starts = charStarts!;
      int active = 0;
      for (int i = 0; i < starts.length && i < originalText.length; i++) {
        if (positionMs >= starts[i]) {
          active = i + 1;
        } else {
          break;
        }
      }
      return active;
    }
    // Fallback: smooth linear interpolation
    final ratio = (positionMs - startMs) / durationMs;
    return (ratio * originalText.length).floor().clamp(0, originalText.length);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Sentence &&
          other.id == id &&
          other.index == index &&
          other.startMs == startMs &&
          other.endMs == endMs &&
          other.english == english &&
          other.chinese == chinese;

  @override
  int get hashCode => Object.hash(id, index, startMs, endMs, english, chinese);

  @override
  String toString() =>
      'Sentence(id: $id, index: $index, ${startMs}ms -> ${endMs}ms)';
}
