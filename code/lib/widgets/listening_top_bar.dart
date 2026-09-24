import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// Top bar of the listening screen (spec V2 follow-up): the sentence
/// counter sits centred and hugs the status bar as closely as possible —
/// user request 2026-09-17: raise it towards the camera cutout to give the
/// content below more room. The presentation toggle stays RIGHT-ALIGNED at
/// its original spot — never crowded next to the counter.
class ListeningTopBar extends StatelessWidget {
  const ListeningTopBar({
    super.key,
    required this.displayIndex,
    required this.sentenceCount,
    this.leading,
    this.trailing,
    this.slotWidth = 48,
  });

  final int displayIndex;
  final int sentenceCount;

  /// Optional leading widget (e.g. AI Tutor button), pinned left.
  final Widget? leading;

  /// Presentation toggle (fluid ⇄ single-page transcript), pinned right.
  final Widget? trailing;

  /// Width reserved on **both** sides.
  ///
  /// The counter is centred by giving left and right identical slots, so this
  /// must be widened as a pair — adding a second right-hand icon without
  /// widening the left slot would push the counter off-centre (and overflow).
  final double slotWidth;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            // Balances the trailing toggle's width so the counter stays
            // truly centred while leading and trailing sit flush left/right.
            SizedBox(width: slotWidth, child: Center(child: leading)),
            Expanded(
              // 「总句数被挤到下面挡住」修复（2026-09-25 用户反馈）：
              // 顶栏右侧图标从 2 个变 3 个后槽位吃紧，无防换行约束的
              // Text 会在宽度不足时 wrap，「/ NN」超出 32 高度被裁。
              // FittedBox 必须直接吃 Expanded 的 tight 约束 —— 若包一层
              // Center（loose 约束）它不会缩放（大字体下照旧溢出）。
              // BoxFit.scaleDown 只缩不放：宽了缩进来，窄了也不放大。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${_two(displayIndex)} / ${_two(sentenceCount)}',
                  maxLines: 1,
                  softWrap: false,
                  style: LLText.counter.copyWith(
                    fontSize: 13,
                    color: ll.textSecondary,
                  ),
                ),
              ),
            ),
            SizedBox(width: slotWidth, child: Center(child: trailing)),
          ],
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
