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

  /// Semantic alias for original transcript (supports multi-language).
  String get originalText => english;

  /// Semantic alias for translated text (supports multi-language).
  String get translatedText => chinese;

  /// Total duration of this sentence in milliseconds.
  int get durationMs => endMs - startMs;

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
