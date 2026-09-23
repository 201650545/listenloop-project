/// Why a `.lllesson` package could not be opened.
enum LessonPackageError {
  /// The picked file does not exist (deleted between pick and read).
  notFound,

  /// The file exists but cannot be read, or is not a ZIP container.
  unreadable,

  /// No `manifest.json` inside the package.
  missingManifest,

  /// `manifest.json` is not valid JSON, not an object, or has missing /
  /// wrongly-typed / unsafe fields.
  badManifest,

  /// `formatVersion` is not supported (only 1 is).
  unsupportedVersion,

  /// The declared sentence file is absent from the package.
  missingSentences,

  /// Sentences file is not valid JSON, or a sentence has missing fields,
  /// non-monotonic indexes, or invalid time bounds.
  badSentences,

  /// `manifest.sentenceCount` does not match the parsed sentence count.
  sentenceCountMismatch,

  /// The declared audio file is absent from the package.
  missingAudio,

  /// The package contains zero sentences.
  emptySentences,
}

/// Thrown by [LessonPackageReader] when a lesson package fails validation.
///
/// [code] is stable for programmatic handling (the import UI maps it to a
/// Chinese user-facing message); [detail] is a technical English string for
/// logs.
class LessonPackageException implements Exception {
  const LessonPackageException(this.code, this.detail);

  final LessonPackageError code;
  final String detail;

  @override
  String toString() => 'LessonPackageException(${code.name}: $detail)';
}
