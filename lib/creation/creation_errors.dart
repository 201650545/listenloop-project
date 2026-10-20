/// Creation pipeline error taxonomy (spec V1 §五十五): the UI shows a human
/// message, the debug log carries the raw exception.
enum CreationError {
  inputError,

  /// 链接本身有效，但**取源通道不可用**（YouTube 音频拿不到）。
  ///
  /// 与 [inputError] 分开的原因：用户没有犯错，重敲链接也不会好；
  /// 要做的是把取源通道恢复起来，或换 B 站链接。笼统报"输入无效"会让人
  /// 往错误方向排查（2026-09-23 用户实际反馈）。
  sourceUnavailable,

  mediaError,
  asrError,
  translationError,
  packageError,
  storageError,
  cancelled,
}

/// [CreationError.sourceUnavailable] 的细分原因 —— 决定界面给哪一份操作清单。
///
/// 这两种故障的处置动作**完全不同**，给同一份清单必然把人带偏：
/// 中继没起来要去启动中继；中继活着但 YouTube 拒绝服务要去检查代理。
enum SourceHint {
  /// 中继进程根本没在监听该端口 —— 手机端去 Termux 跑一次启动脚本。
  relayDown,

  /// 中继在线，但它自己拿不到音频（代理断线 / YouTube 拒绝服务）。
  relayBlocked,
}

/// Carries a [CreationError] plus the human-facing message.
class CreationException implements Exception {
  const CreationException(this.code, this.message, {this.hint});

  final CreationError code;
  final String message;

  /// Optional finer-grained reason — see [SourceHint].
  final SourceHint? hint;

  @override
  String toString() => 'CreationException(${code.name}: $message)';
}
