import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// 底部实时识别栏（2026-10-20 读页重构）。
///
/// 2026-10-20 郭老师：「页面上会显示你要读的东西，你在下方边读，它就边实时
/// 识别出内容。就跟语音输入是一样的道理呀，我边说它就边识别」
///
/// 所以这一条是**读页唯一的"操作区"**：只显示系统刚刚听到的字、一个极轻的
/// 收音指示，**不放**下一句/完成/重读这些句级按钮 —— 整篇是一个流程，
/// 不该有"下一步"这种东西。
class LiveReadingDock extends StatelessWidget {
  const LiveReadingDock({
    super.key,
    required this.transcript,
    required this.listening,
    this.hint,
    this.level = 0,
    this.onTap,
  });

  /// 最近识别出的文字（边说边出字）。
  final String transcript;

  /// 是否正在收音。
  final bool listening;

  /// 给孩子的提示（可空）。
  final String? hint;

  /// 音量强度 0..1（只驱动一个很小的波形，不做整条栏呼吸）。
  final double level;

  /// 点一下开始/停止读。
  ///
  /// 2026-10-20 郭老师：「没有开始读的按钮呀，怎么读」—— 去掉句级按钮是
  /// 对的，但**入口必须还在**，而且要显眼、要好按。所以整条底栏就是那颗
  /// "开始读"的按钮：没在听的时候，底栏明明白白写着「点这里开始读」。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final idle = transcript.isEmpty && !listening;
    return Material(
      color: ll.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: ll.divider.withValues(alpha: 0.7), width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _MicIndicator(listening: listening, level: level),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      transcript.isEmpty
                          ? (listening ? '正在听你读…' : '点下面的话筒开始读')
                          : transcript,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: idle ? ll.textSecondary : ll.textPrimary,
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        hint!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              // 明确给出"现在是什么状态 / 下一步做什么"，不让人猜。
              if (onTap != null)
                Icon(
                  listening ? Icons.stop_circle_outlined : Icons.mic_none_rounded,
                  size: 22,
                  color: listening ? ll.textTertiary : ll.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 收音指示：一个小圆点 + 随音量起伏的两根竖条。
///
/// 刻意做得很轻 —— 整块底栏不停呼吸会干扰孩子找字（镜像评审 §七）。
class _MicIndicator extends StatelessWidget {
  const _MicIndicator({required this.listening, required this.level});

  final bool listening;
  final double level;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final active = listening;
    final h = (6 + level * 14).clamp(6.0, 20.0);
    return SizedBox(
      width: 26,
      height: 26,
      child: active
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _bar(4.0, ll.textSecondary),
                const SizedBox(width: 3),
                _bar(h, ll.textPrimary),
                const SizedBox(width: 3),
                _bar(4.0, ll.textSecondary),
              ],
            )
          : Icon(
              Icons.mic_off_outlined,
              size: 18,
              color: ll.textTertiary,
            ),
    );
  }

  Widget _bar(double height, Color color) => Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}
