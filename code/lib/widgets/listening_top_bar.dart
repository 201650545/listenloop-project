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
    this.leadingSlotWidth = 48,
    this.trailingSlotWidth = 48,
  });

  final int displayIndex;
  final int sentenceCount;

  /// Optional leading widget (e.g. AI Tutor button), pinned left.
  final Widget? leading;

  /// Presentation toggle (fluid ⇄ single-page transcript), pinned right.
  final Widget? trailing;

  /// Width reserved on the left side only.
  ///
  /// 左右槽宽独立：中文课时左槽 1 枚（初读/熟读分段器）、右槽 3 枚
  /// （跟读验收/课文目录/显示模式）；英文课时左槽 1 枚（AI 伴学）、右槽
  /// 4 枚（听写/more/课文目录/显示模式）。原先两侧共用同一个 slotWidth
  /// 并取较大值，会让一侧顶到屏幕外（RenderFlex overflowed by 56px）。
  final double leadingSlotWidth;

  /// Width reserved on the right side only.
  final double trailingSlotWidth;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: SizedBox(
        // WP-G 终审实测：原 32 高把里面的 IconButton 压成 40×32dp，低于
        // 总纲「触摸热区 ≥48×48dp」（也低于 WCAG 2.5.5）。抬到 48 后，
        // 槽位里的 3×48 图标（slotWidth 144）刚好各得一个 48×48 的热区，
        // 顶栏也仍然是"贴着状态栏的一条静带"，不是一行按钮。
        height: 48,
        child: Row(
          children: [
            // Balances the trailing toggle's width so the counter stays
            // truly centred while leading and trailing sit flush left/right.
            SizedBox(width: leadingSlotWidth, child: Center(child: leading)),
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
            SizedBox(width: trailingSlotWidth, child: Center(child: trailing)),
          ],
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
