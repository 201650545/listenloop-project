import 'video_source.dart';

/// A lesson imported into the local library (Milestone 2A).
///
/// Metadata only — the sentences live in their own table and the media file
/// on disk ([audioPath]). All data comes from an imported `.lllesson`
/// package and is copied into app storage, so the app is fully offline.
class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.language,
    required this.durationMs,
    required this.sentenceCount,
    required this.audioPath,
    required this.importedAt,
    this.coverPath,
    this.video,
  });

  /// Stable package identifier (`manifest.lessonId`).
  final String id;

  /// Display title (`manifest.title`).
  final String title;

  /// BCP-47-ish language tag, e.g. `en`.
  final String language;

  /// Total audio duration in milliseconds (informational).
  final int durationMs;

  /// Number of sentences in the lesson.
  final int sentenceCount;

  /// Absolute path of the audio file inside app storage.
  final String audioPath;

  /// Absolute path of the cover image inside app storage, or null.
  final String? coverPath;

  /// Optional online video source (Phase 3A). Null for audio-only lessons.
  final VideoSource? video;

  /// When the lesson was imported (local time).
  final DateTime importedAt;

  /// Visual Polish V2 follow-up: covers fetched at runtime (e.g. the B站
  /// cover for video lessons imported from packages that predate the cover
  /// pipeline) are persisted with this copy.
  Lesson copyWith({String? coverPath}) => Lesson(
    id: id,
    title: title,
    language: language,
    durationMs: durationMs,
    sentenceCount: sentenceCount,
    audioPath: audioPath,
    importedAt: importedAt,
    coverPath: coverPath ?? this.coverPath,
    video: video,
  );
}

/// Where the user left off in a lesson (spec V0.2 §20, extended V0.2.1 §8).
class LearningProgress {
  const LearningProgress({
    required this.lessonId,
    required this.lastSentenceIndex,
    required this.positionMs,
    required this.updatedAt,
    this.repeatTarget = 1,
    this.playbackRate = 1.0,
    this.subtitleMode = 'bilingual',
    this.displayMode = 'fluid',
  });

  final String lessonId;

  /// Zero-based index of the sentence the user was on.
  final int lastSentenceIndex;

  /// Playback position in milliseconds within the audio timeline. Kept for
  /// diagnostics only — restore always uses [lastSentenceIndex] + startMs.
  final int positionMs;

  /// 0 = infinite loop, N = play each sentence N times.
  final int repeatTarget;

  final double playbackRate;

  /// 'hidden' | 'english' | 'bilingual'.
  final String subtitleMode;

  /// 'fluid' | 'page'.
  final String displayMode;

  final DateTime updatedAt;
}

/// A [Lesson] joined with its optional [LearningProgress] for library UI.
class LessonWithProgress {
  const LessonWithProgress({required this.lesson, this.progress});

  final Lesson lesson;
  final LearningProgress? progress;
}
