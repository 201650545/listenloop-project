// The primitives every screen is built from: card, hairline, section label,
// row, nav row, icon chip, segmented control, empty state, marginal note.
//
// They read the active palette from `context.ll` instead of taking a
// `palette` argument. That is the whole point of the file: a screen that
// threads a palette down its private widgets ends up recomputing "am I dark"
// at every leaf, and those recomputations are exactly the hardcoded colours
// the theme transition cannot reach.
//
// Geometry comes from LLShape where the shape tokens are the style's own
// vocabulary (card radius, hairline width); the nested radii inside a control
// (track 13 / pill 10 / item 7) stay component-local, because they are a
// relationship between two parts of one widget, not a style choice.

import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// Micro-heading that gives a page its rhythm.
class LLSectionLabel extends StatelessWidget {
  const LLSectionLabel({
    required this.text,
    super.key,
    this.tracking,
  });

  final String text;

  /// Letter-spacing that suits the script: wide tracking is a Latin display
  /// convention and makes CJK look loose, so the value is derived from the
  /// label itself rather than passed in per call site.
  final double? tracking;

  /// Latin labels read better in caps; CJK must keep its own case.
  bool get _isLatin => text.codeUnits.every((c) => c < 128);

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        _isLatin ? text.toUpperCase() : text,
        style: LLText.groupLabel.copyWith(
          letterSpacing: tracking ?? (_isLatin ? 1.3 : 0.4),
          color: ll.textTertiary,
        ),
      ),
    );
  }
}

/// Hairline separator between rows.
///
/// [indent] lets a list align the line with the row text (past the icon chip)
/// instead of letting it run under the icon.
class LLHairline extends StatelessWidget {
  const LLHairline({super.key, this.indent = 12, this.end = 12});

  final double indent;
  final double end;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Padding(
      padding: EdgeInsets.only(left: indent, right: end),
      child: Divider(
        color: ll.divider.withValues(alpha: 0.7),
        height: 1,
        thickness: 1,
      ),
    );
  }
}

/// Grouped-card container: the surface every settings-style list sits on.
///
/// 缺省留白取自 `shape.gutter`——儒雅那一套卡片不投影、不浮起，层次全靠留白，
/// 所以留白必须是风格令牌而不是全站一个数（doc 21 队列 10）。
class LLCard extends StatelessWidget {
  const LLCard({required this.children, super.key, this.padding});

  final List<Widget> children;
  /// Null means "this style's gutter". Override only when the card's own
  /// geometry demands it, not because one style looks better with a hack.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return Container(
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(shape.card),
        border: Border.all(color: ll.divider, width: shape.hairline),
        // 儒雅那一套（学堂 / 书院）刻意不投影：层次靠留白与墨线，不靠浮起
        // （doc 21 队列 10「卡片不浮，靠留白撑」）。此前 `shadowOn` 只有
        // anki dialog 与语言 tab 读它，卡片本体照画投影，等于这个令牌
        // 在最大的容器上是失效的。
        boxShadow: shape.shadowOn
            ? [
                BoxShadow(
                  color: ll.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ??
            EdgeInsets.fromLTRB(
              shape.gutter,
              shape.gutter - 1,
              shape.gutter,
              shape.gutter - 1,
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// The optical icon container in front of a list row (spec: 20dp line icons).
class LLChip extends StatelessWidget {
  const LLChip({
    required this.icon,
    super.key,
    this.size = 28,
    this.radius,
    this.iconSize = 20,
  });

  final IconData icon;
  final double size;

  /// 圆角。null = 跟随风格的 `shape.chip`（2026-10-20 评审：组件不该各自
  /// 写死圆角，令牌要真正统治形态）；确实需要特殊形状时再显式传。
  final double? radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ll.emphasis,
        borderRadius: BorderRadius.circular(radius ?? shape.chip),
      ),
      child: Center(
        child: Icon(icon, size: iconSize, color: ll.textSecondary),
      ),
    );
  }
}

/// A list row: label on the left, one trailing thing on the right.
///
/// The trailing thing is either a short [value] ([trailing] stays null) or a
/// widget. [indicator] adds the 7px status dot that tells you whether a key is
/// filled in without opening the row.
class LLRow extends StatelessWidget {
  const LLRow({
    required this.label,
    super.key,
    this.value,
    this.trailing,
    this.onTap,
    this.valueMuted = false,
    this.indicator,
    this.showChevron = false,
    this.vertical = 10,
  }) : assert(
         value == null || trailing == null,
         'LLRow takes either a value or a trailing widget, not both',
       );

  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Dim the value: used for "not configured yet" placeholders.
  final bool valueMuted;

  /// null = no dot, true/false = dot lit or unlit.
  final bool? indicator;
  final bool showChevron;
  final double vertical;

  TextStyle _labelStyle(LLPalette ll) =>
      LLText.rowLabel.copyWith(color: ll.textPrimary);

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: vertical),
        // LayoutBuilder 必须包住整个 Row：Row 主轴对非 flex 子节点传的是
        // 无界宽度，若把 LayoutBuilder 放进 Row 里，constraints.maxWidth
        // 会是 infinity，按比例设上限就失效了。
        child: LayoutBuilder(
          builder: (context, constraints) {
            // label 原先无约束：窄屏 + 系统大字号下 label 自身撑爆整行
            // （382dp、1.5× 实测溢出 12px）。给 label 设 45% 上限并省略，
            // value 仍吃满剩余并右对齐 —— 若做成 Flexible/Expanded 五五分，
            // 会把原本能完整显示的 value 无谓截断。
            final maxLabelWidth = constraints.maxWidth * 0.45;
            return Row(
              children: [
                if (indicator != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: indicator! ? ll.success : ll.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (trailing != null) ...[
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _labelStyle(ll),
                    ),
                  ),
                  // trailing 原为无约束子节点：窄屏 + 系统大字号下
                  // LLSegmented 这类控件按自然宽度排会撑爆整行
                  // （382dp、1.5× 实测溢出 12px）。改为可收缩。
                  Flexible(child: trailing!),
                ] else ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxLabelWidth),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _labelStyle(ll),
                    ),
                  ),
                  const SizedBox(width: LLSpacing.md),
                  Expanded(
                    child: Text(
                      value ?? '',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LLText.rowValue.copyWith(
                        color: valueMuted ? ll.textTertiary : ll.textSecondary,
                      ),
                    ),
                  ),
                  if (showChevron) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 18, color: ll.textTertiary),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A hub row: icon chip, title, live summary, chevron.
class LLNavRow extends StatelessWidget {
  const LLNavRow({
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return InkWell(
      onTap: onTap,
      // 2026-10-20 评审：行控件的圆角收归令牌（原先写死 10）。
      borderRadius: BorderRadius.circular(shape.controlRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            LLChip(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LLText.itemTitle.copyWith(
                      color: ll.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LLText.itemSummary.copyWith(color: ll.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: ll.textTertiary.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}

/// How the segmented control sizes itself.
enum LLSegmentVariant {
  /// Each option takes an equal share of the width — the hub's 跟随系统/白昼/黑夜.
  expand,

  /// The control hugs its labels and sits at the end of a row.
  dense,
}

/// Segmented pill selector: a raised thumb sliding on a recessed track.
///
/// Both steps are palette roles ([LLPalette.controlTrack] under
/// [LLPalette.controlThumb]) rather than per-theme literals, so a 白昼↔黑夜
/// change carries the thumb along with the canvas instead of leaving an
/// ink-dark thumb on an ink-dark page mid-way.
class LLSegmented<T> extends StatelessWidget {
  const LLSegmented({
    required this.selected,
    required this.options,
    required this.onSelect,
    super.key,
    this.variant = LLSegmentVariant.expand,
  });

  final T selected;
  final List<(T, String)> options;
  final ValueChanged<T> onSelect;
  final LLSegmentVariant variant;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    // 2026-10-20 评审：分段控件的圆角由 `shape.controlRadius` 推导，
    // 不再各写各的 13/10/7；选中/未选中的文字色也不再写死色值 ——
    // 写死的 #14161A / #FAFAF8 / #5C6169 会让学堂、书院的控件混进
    // 基础风格的颜色（这正是"组件形状不协调"的一部分）。
    final outerRadius = shape.controlRadius;
    final innerRadius = (outerRadius - 3).clamp(2.0, 20.0);
    if (variant == LLSegmentVariant.expand) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: ll.controlTrack,
          borderRadius: BorderRadius.circular(outerRadius),
        ),
        child: Row(
          children: [
            for (final (value, text) in options)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: value == selected
                          ? ll.controlThumb
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(innerRadius),
                      border: Border.all(
                        color: value == selected
                            ? ll.controlThumbBorder
                            : Colors.transparent,
                      ),
                      boxShadow: value == selected
                          ? [
                              BoxShadow(
                                color: ll.shadow,
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: LLText.controlLabel.copyWith(
                        fontWeight: value == selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: value == selected
                            ? ll.textPrimary
                            : ll.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ll.controlTrack,
        borderRadius: BorderRadius.circular(outerRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, text) in options)
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: value == selected ? ll.controlThumb : Colors.transparent,
                    borderRadius: BorderRadius.circular(innerRadius),
                    boxShadow: value == selected
                        ? [
                            BoxShadow(
                              color: ll.shadow,
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: value == selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: value == selected
                          ? ll.textPrimary
                          : ll.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The zero-content state: an icon, one line that says what is missing, one
/// line that says what to do about it.
class LLEmptyState extends StatelessWidget {
  const LLEmptyState({
    required this.icon,
    required this.title,
    super.key,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: ll.textTertiary),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: ll.textSecondary)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: LLText.itemSummary.copyWith(color: ll.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 竖排眉批 — 儒雅那一套的灵魂件（doc 21 队列 10）。
///
/// 汉字竖排不用旋转：一格一字、自上而下、列自右向左，所以它贴在它所批注内容的
/// **右缘**。列数由可用高度算出（[maxHeight] 是一列能塞几字），默认单列。
///
/// 字体走 `LLStyle.noteFont`（学堂/书院 = 仿宋；全量楷体 +10~12 MB，doc 21 §三
/// 未拍板，所以先用随包的 FangSong），颜色走 `ll.annotation` 而**不是** `accent`：
/// 批注不是按钮，这套风格的朱砂只准出现在批注和错处上。
class LLMarginalNote extends StatelessWidget {
  const LLMarginalNote({
    required this.text,
    super.key,
    this.maxHeight,
    this.rule = true,
  });

  final String text;
  /// Pixels available to one column; decides how many characters fit before
  /// the note wraps into a second column to its left. Null = one long column.
  final double? maxHeight;
  /// Whether to draw the 界栏 (the hairline between body and margin).
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    if (text.isEmpty) return const SizedBox.shrink();

    final style = LLText.marginalNote.copyWith(
      color: ll.annotation,
      fontFamily: context.llStyle.noteFont,
    );
    // 竖排没有水平行距可调，字间呼吸就是这个 height 乘字号。
    final lineH = style.fontSize! * style.height!;
    final runes = text.runes.map(String.fromCharCode).toList();
    final fit = maxHeight == null ? runes.length : (maxHeight! / lineH).floor();
    final perColumn = fit <= 1 ? 1 : (fit >= runes.length ? runes.length : fit);
    final columns = <List<String>>[];
    for (var i = 0; i < runes.length; i += perColumn) {
      columns.add(runes.skip(i).take(perColumn).toList());
    }

    // 列自右向左：首列贴着正文，其余往左排，所以 children 要反着给。
    final stacked = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = columns.length - 1; c >= 0; c--) ...[
          if (c < columns.length - 1) const SizedBox(width: LLSpacing.xs),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final ch in columns[c])
                Text(ch, style: style, textAlign: TextAlign.center),
            ],
          ),
        ],
      ],
    );

    if (!rule) return stacked;
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: shape.hairline, color: ll.divider),
          const SizedBox(width: LLSpacing.sm),
          stacked,
        ],
      ),
    );
  }
}
