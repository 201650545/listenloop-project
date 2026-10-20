import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// 版权页（WP-I §三.6）：版本、引擎、定位语，压成页脚小字。
///
/// 原来这些挤在一张「关于」卡里，还夹着一句给开发者看的调试提示——书的最后一页
/// 不该印编译说明。现在只留两行 colophon，居中、`meta` 档、`textTertiary`，
/// 像书的版权页：有信息，但不抢戏。
class LLColophon extends StatelessWidget {
  const LLColophon({
    super.key,
    required this.lines,
    this.rule = true,
  });

  final List<String> lines;

  /// 页脚上方那道界栏（印得下一道短横线）。
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rule)
          Container(
            width: LLSpacing.huge,
            height: shape.hairline,
            color: ll.divider,
          ),
        if (rule) const SizedBox(height: LLSpacing.md),
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 3),
          Text(
            lines[i],
            textAlign: TextAlign.center,
            style: LLText.meta.copyWith(color: ll.textTertiary),
          ),
        ],
      ],
    );
  }
}
