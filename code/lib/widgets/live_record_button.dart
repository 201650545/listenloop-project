import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// **圆形录音按钮**（2026-10-21 郭老师定的交互）。
///
/// > 「按钮整合：把开始识别和暂停识别浓缩为一个**圆形的录音按钮**，集合在
/// > 底部中间的"听"和"读"上面。」
///
/// 一颗按钮三种状态（不额外摆"开始/停止"两枚）：
///   · [LiveRecordButtonState.idle]      —— 待命，点一下开始（进入等口令）
///   · [LiveRecordButtonState.waitingWake]—— 麦克风已开，**在等口令**
///   · [LiveRecordButtonState.reading]   —— 口令已识别，正在正式判读
///
/// 视觉：外圈是脉冲环（录音时呼吸），中间是麦克风 / 停止图标。
class LiveRecordButton extends StatelessWidget {
  const LiveRecordButton({
    super.key,
    required this.state,
    required this.onTap,
    this.wakePhrase,
    this.level = 0,
  });

  final LiveRecordButtonState state;
  final VoidCallback onTap;

  /// 等口令时显示的口令（让孩子知道要说什么）。
  final String? wakePhrase;

  /// 音量 0~1（驱动脉冲环的幅度）。
  final double level;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final active = state != LiveRecordButtonState.idle;
    final color = active ? ll.accent : ll.textPrimary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context, ll),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: switch (state) {
            LiveRecordButtonState.idle => '开始朗读',
            LiveRecordButtonState.waitingWake => '暂停朗读',
            LiveRecordButtonState.reading => '暂停朗读',
          },
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? ll.accent.withValues(alpha: 0.16)
                    : ll.textPrimary.withValues(alpha: 0.08),
                border: Border.all(
                  color: active ? ll.accent : ll.divider,
                  width: 2,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: ll.accent.withValues(alpha: 0.24),
                          blurRadius: 18 + level * 18,
                          spreadRadius: 2 + level * 4,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                active ? Icons.stop_rounded : Icons.mic_rounded,
                size: 30,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 按钮上方的说明行。
  Widget _label(BuildContext context, LLPalette ll) {
    final String text;
    switch (state) {
      case LiveRecordButtonState.idle:
        text = '点一下开始读';
      case LiveRecordButtonState.waitingWake:
        text = wakePhrase == null || wakePhrase!.isEmpty
            ? '请说出口令'
            : '说「${wakePhrase!}」开始';
      case LiveRecordButtonState.reading:
        text = '正在判读，点一下暂停';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ll.divider, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: ll.textSecondary),
      ),
    );
  }
}

/// 圆形录音按钮的三种状态。
enum LiveRecordButtonState {
  /// 待命（麦克风未开）。
  idle,

  /// 麦克风已开，在等口令。
  waitingWake,

  /// 口令已识别，正式判读中。
  reading,
}
