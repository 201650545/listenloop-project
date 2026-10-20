import 'package:flutter/material.dart';

import '../theme/ll_style.dart';
import '../theme/listenloop_theme.dart';
import 'll_backdrop.dart';
import 'll_primitives.dart';

/// 扉页架（WP-I §三.3.A 重构版，2026-10-15）——「纸与光」的风格选择器。
///
/// 旧版是一排四张 84×112 的色块卡，每张用**色条**表示风格。问题是四套风格
/// 的 bg 区分度不够（学堂 `#F2EAD8` 与书院 `#E9E3D7` 只差约 8/255），accent
/// 是唯一可靠的区分点——于是"选纸"这件事在选之前几乎看不出来，郭老师一句
/// 「还不是我想要的」指的正是这个。
///
/// 现在分上下两截：
///
/// 1. **签名小卡**（上）——四张并排做横向对比，每张画一件**只有该风格有**
///    的东西：基础画投影卡片、学堂画宣纸帘纹与朱砂眉批、书院画稿纸横线与
///    双线界栏、都市画幕墙分格与斜向高光。指纹而非配色，所以并排时分得出。
/// 2. **大扉页**（下）——满幅展示**当前选中**那套：该风格的纹理铺底
///    （[LLBackdrop]）、三层色阶、真标题、真课文段、真控件组、真评分。
///
/// 两截共用同一个 [selected]：点签名卡即切换，大扉页跟着重绘——"换纸"的
/// 那一下它是主角。
class LLStyleRack extends StatelessWidget {
  const LLStyleRack({
    super.key,
    required this.selected,
    required this.brightness,
    required this.zh,
    required this.onSelect,
  });

  final LLStyle selected;

  /// 当前明暗。两截都按这个明暗预览——换风格不该顺带换昼夜。
  final Brightness brightness;
  final bool zh;
  final ValueChanged<LLStyle> onSelect;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 上截：签名小卡（横向对比）
        Row(
          children: [
            for (final style in LLStyle.values) ...[
              if (style != LLStyle.values.first) const SizedBox(width: 8),
              Expanded(
                child: _SignatureCard(
                  style: style,
                  brightness: brightness,
                  selected: style == selected,
                  zh: zh,
                  onTap: () => onSelect(style),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: LLSpacing.md),
        Text(
          selected.blurb(zh),
          textAlign: TextAlign.center,
          style: LLText.itemSummary.copyWith(color: ll.textTertiary),
        ),
        const SizedBox(height: LLSpacing.md),
        // ── 下截：大扉页（满幅展示当前风格）
        _TitlePage(style: selected, brightness: brightness, zh: zh),
      ],
    );
  }
}

/// 一张签名小卡：只画这件风格独有的那点东西。
class _SignatureCard extends StatelessWidget {
  const _SignatureCard({
    required this.style,
    required this.brightness,
    required this.selected,
    required this.zh,
    required this.onTap,
  });

  final LLStyle style;
  final Brightness brightness;
  final bool selected;
  final bool zh;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: LLMotion.normal,
        curve: LLMotion.curve,
        // 选中抬起 3dp：换纸的那一下它是主角。
        transform: Matrix4.translationValues(0, selected ? -3 : 0, 0),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? ll.accent : ll.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Signature(style: style, brightness: brightness),
            const SizedBox(height: 5),
            Text(
              style.label(zh),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LLText.meta.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? ll.textPrimary : ll.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 每种风格的"指纹"——只有它有的那点东西。画在 84×56 的小窗里。
class _Signature extends StatelessWidget {
  const _Signature({required this.style, required this.brightness});

  final LLStyle style;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final p = style.paletteFor(brightness);
    final shape = style.shapeFor(brightness);
    // CustomPaint 没给 child 时按自己的 `size` 属性取尺寸，默认 Size.zero，
    // 于是画布宽 0 —— 四张签名卡全是空的（2026-10-15：golden 实测四张卡
    // 主色完全一致、maxdev=0，就是这样来的）。传 Size.infinite 则是另一个
    // 极端，`Offset.zero & size` 会画到画布外。正确做法是给一个铺满的
    // child，让尺寸由父级约束决定。
    return SizedBox(
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: CustomPaint(
          painter: _SignaturePainter(
            style: style,
            palette: p,
            shape: shape,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({
    required this.style,
    required this.palette,
    required this.shape,
  });

  final LLStyle style;
  final LLPalette palette;
  final LLShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    // 底：该风格的 bg，四张卡第一眼就能分出色温。
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.bg,
    );
    switch (style) {
      case LLStyle.base:
        _base(canvas, size);
      case LLStyle.academy:
        _academy(canvas, size);
      case LLStyle.oxbridge:
        _oxbridge(canvas, size);
      case LLStyle.metropolis:
        _metropolis(canvas, size);
    }
  }

  /// 基础：投影卡片——这一套是唯一还在用投影的。
  void _base(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(12, 10, size.width - 24, size.height - 20),
      Radius.circular(shape.card),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = palette.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(r, Paint()..color = palette.surface);
    // 一道 accent 实心条：这一套的强调是功能性的蓝。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(20, 18, 34, 6),
        Radius.circular(shape.chip / 2),
      ),
      Paint()..color = palette.accent,
    );
    final line = Paint()..color = palette.textSecondary;
    canvas.drawRect(
      Rect.fromLTWH(20, 30, size.width - 44, 4),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(20, 38, size.width - 58, 4),
      Paint()..color = palette.divider,
    );
  }

  /// 学堂：宣纸帘纹 + 朱砂眉批线。
  void _academy(Canvas canvas, Size size) {
    final weave = Paint()
      ..color = palette.textPrimary.withValues(alpha: 0.13)
      ..strokeWidth = 0.6;
    for (double x = 5; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), weave);
    }
    // 书页
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 8, size.width - 20, size.height - 16),
        Radius.circular(shape.card / 2),
      ),
      Paint()
        ..color = palette.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.hairline,
    );
    // 朱砂眉批：一道竖线 + 一枚批点
    canvas.drawLine(
      Offset(16, 12),
      Offset(16, size.height - 12),
      Paint()
        ..color = palette.annotation
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(
      Offset(24, 20),
      2.4,
      Paint()..color = palette.annotation,
    );
    final line = Paint()..color = palette.textSecondary;
    for (final y in [22.0, 30.0, 38.0]) {
      canvas.drawLine(
        Offset(24, y),
        Offset(size.width - 16, y),
        line..strokeWidth = 3,
      );
    }
  }

  /// 书院：稿纸横线 + 双线界栏 + 直角。
  void _oxbridge(Canvas canvas, Size size) {
    final ruled = Paint()
      ..color = palette.divider.withValues(alpha: 0.75)
      ..strokeWidth = 0.6;
    for (double y = 12; y < size.height - 6; y += 9) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), ruled);
    }
    // 左侧栏线（accent，常春藤绿）
    canvas.drawLine(
      Offset(12, 0),
      Offset(12, size.height),
      Paint()
        ..color = palette.accent.withValues(alpha: 0.45)
        ..strokeWidth = 1.2,
    );
    // 直角书页 + **双线**边框——这一套的签名
    final page = Rect.fromLTWH(
      18,
      8,
      size.width - 30,
      size.height - 16,
    );
    canvas.drawRect(page, Paint()..color = palette.surface);
    canvas.drawRect(
      page,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.rule,
    );
    canvas.drawRect(
      page.deflate(3),
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.hairline,
    );
    final line = Paint()..color = palette.textSecondary;
    for (final y in [22.0, 32.0, 42.0]) {
      canvas.drawLine(
        Offset(26, y),
        Offset(page.right - 8, y),
        line..strokeWidth = 3,
      );
    }
  }

  /// 都市：幕墙分格 + 一道斜向高光 + 地铁黄线。
  void _metropolis(Canvas canvas, Size size) {
    // 幕墙竖格
    final mullion = Paint()
      ..color = palette.textPrimary.withValues(alpha: 0.10)
      ..strokeWidth = 0.8;
    for (double x = 18; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), mullion);
    }
    // 玻璃面
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 8, size.width - 20, size.height - 16),
        Radius.circular(shape.card),
      ),
      Paint()..color = palette.surface,
    );
    // 斜向高光（天光，不是墨——见 glazeSheen 的注释）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 8, size.width - 20, size.height - 16),
        Radius.circular(shape.card),
      ),
      Paint()..shader = glazeSheen(size),
    );
    // 地铁黄线：这一套的签名
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(18, size.height - 18, size.width - 36, 5),
        Radius.circular(shape.chip / 2),
      ),
      Paint()..color = palette.accent,
    );
    final line = Paint()..color = palette.textSecondary;
    for (final y in [20.0, 28.0]) {
      canvas.drawLine(
        Offset(18, y),
        Offset(size.width - 28, y),
        line..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) =>
      old.style != style ||
      old.palette.bg != palette.bg ||
      old.palette.accent != palette.accent ||
      old.shape.rule != shape.rule;
}

/// 大扉页：满幅展示当前风格。
///
/// 铺该风格的纹理（[LLBackdrop]），上面摆三层色阶、真标题、真课文段、
/// 真控件组与评分——"这一页纸读起来是什么样"，在选之前先看全。
class _TitlePage extends StatelessWidget {
  const _TitlePage({required this.style, required this.brightness, required this.zh});

  final LLStyle style;
  final Brightness brightness;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildListenLoopTheme(brightness, style: style),
      child: LLBackdrop(
        child: Builder(
          builder: (context) {
            final ll = context.ll;
            final shape = context.llShape;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(LLSpacing.lg),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(shape.card + 2),
                border: Border.all(color: ll.divider, width: shape.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 扉页标题：该风格自己的标题字体
                  Text(
                    zh ? '花的学校' : 'The Flower School',
                    style: LLText.sectionLabel.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: ll.textPrimary,
                      fontFamily: style.headingFont,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'huā de xué xiào',
                    style: LLText.meta.copyWith(
                      color: ll.textTertiary,
                      fontFamily: style.pinyinFont,
                    ),
                  ),
                  const SizedBox(height: LLSpacing.md),
                  // 真课文段：正文 + 一句眉批（有 noteFont 的风格才显示）
                  Text(
                    zh
                        ? '当雷云在天上轰响，六月的阵雨落下的时候，'
                            '湿润的东风走过荒野。'
                        : 'When thunderclouds rumble and the June rain falls, '
                            'the damp east wind walks across the wilderness.',
                    style: LLText.body.copyWith(
                      color: ll.textPrimary,
                      height: 1.6,
                    ),
                  ),
                  if (style.noteFont != null) ...[
                    const SizedBox(height: LLSpacing.sm),
                    Text(
                      zh ? '润湿的东风' : 'the damp east wind',
                      style: LLText.meta.copyWith(
                        color: ll.annotation,
                        fontFamily: style.noteFont,
                      ),
                    ),
                  ],
                  const SizedBox(height: LLSpacing.md),
                  const LLHairline(indent: 2, end: 2),
                  const SizedBox(height: LLSpacing.md),
                  // 真控件组：分段器（选中/未选中两态）
                  Container(
                    decoration: BoxDecoration(
                      color: ll.controlTrack,
                      borderRadius: BorderRadius.circular(shape.pill),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Pip(
                          ll: ll,
                          shape: shape,
                          active: true,
                          label: zh ? '初读' : 'First',
                        ),
                        _Pip(
                          ll: ll,
                          shape: shape,
                          active: false,
                          label: zh ? '熟读' : 'Fluent',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: LLSpacing.md),
                  // 真进度：吃 shape.rule 作为强调粗细
                  Container(
                    height: shape.rule + 3,
                    decoration: BoxDecoration(
                      color: ll.divider,
                      borderRadius: BorderRadius.circular(shape.pill),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.62,
                      child: Container(
                        decoration: BoxDecoration(
                          color: ll.accent,
                          borderRadius: BorderRadius.circular(shape.pill),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: LLSpacing.sm),
                  // 真评分
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Icon(Icons.star_rounded, size: 14, color: ll.accent),
                      for (var i = 0; i < 2; i++)
                        Icon(Icons.star_border_rounded,
                            size: 14, color: ll.divider),
                      const Spacer(),
                      Text(
                        '3 / 5',
                        style: LLText.meta.copyWith(color: ll.textTertiary),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({
    required this.ll,
    required this.shape,
    required this.active,
    required this.label,
  });

  final LLPalette ll;
  final LLShape shape;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? ll.controlThumb : Colors.transparent,
        borderRadius: BorderRadius.circular(shape.pill),
        border: active
            ? Border.all(color: ll.controlThumbBorder, width: shape.hairline)
            : null,
      ),
      child: Text(
        label,
        style: LLText.meta.copyWith(
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? ll.textPrimary : ll.textTertiary,
        ),
      ),
    );
  }
}
