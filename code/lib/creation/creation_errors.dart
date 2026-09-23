/// Creation pipeline error taxonomy (spec V1 §五十五): the UI shows a human
/// message, the debug log carries the raw exception.
enum CreationError {
  inputError,
  mediaError,
  asrError,
  translationError,
  packageError,
  storageError,
  cancelled,
}

/// Carries a [CreationError] plus the human-facing message.
class CreationException implements Exception {
  const CreationException(this.code, this.message);

  final CreationError code;
  final String message;

  @override
  String toString() => 'CreationException(${code.name}: $message)';
}
