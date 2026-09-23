/// Job stages (spec V1 §八): user-facing stage names only — technical
/// details (whisper.cpp, model files) live in the debug log.
enum LessonJobStage {
  queued,
  acquiringMedia,
  preparingAudio,
  transcribing,
  segmenting,
  translating,
  packaging,
  completed,
  failed,
  cancelled;

  /// Terminal stages — a new job may only start when none of these is
  /// running (spec V1 §十二: one active job).
  bool get isActive =>
      this != LessonJobStage.completed &&
      this != LessonJobStage.failed &&
      this != LessonJobStage.cancelled;
}
