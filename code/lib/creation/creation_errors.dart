/// Creation pipeline error taxonomy (spec V1 §五十五): the UI shows a human
/// message, the debug log carries the raw exception.
enum CreationError {
  inputError,

  /// 链接本身有效，但**取源通道不可用**（YouTube 需要 PC 端中继）。
  ///
  /// 与 [inputError] 分开的原因：用户没有犯错，重敲链接也不会好；
  /// 要做的是插线 / 启动中继 / 换 B 站链接。笼统报"输入无效"会让人
  /// 往错误方向排查（2026-09-23 用户实际反馈）。
  sourceUnavailable,

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
