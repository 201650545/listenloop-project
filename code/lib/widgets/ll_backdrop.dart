import 'package:flutter/material.dart';

import '../theme/ll_style.dart';
import '../theme/listenloop_theme.dart';

/// Paints the style's background material behind a screen.
///
/// Vector only — no raster assets (doc 21 §三): textures are derived from the
/// active ink color, so they follow both the style and the brightness, and they
/// stay crisp at every text scale.
///
/// 2026-10-20（GPT 镜像评审 §四 P0）：**四套风格的底纹全部归零**。
///
/// 原来的宣纸竖纹（每 7dp 一条）、稿纸横线（每 26dp 一条）、幕墙分格
/// （每 56dp 一条）铺满整屏 —— 老板的原话是"背景图片是一条一条的线，
/// 不好看"。评审的判断很准：**用背景纹理证明"风格存在"，会让背景和课文
/// 争夺注意力**；那些横竖线本该属于课文行距与栏线，铺满屏就成了噪声。
///
/// 所以四套风格的 `LLShape.texture` 现在都是 [LLTexture.none]，[LLBackdrop]
/// 直接返回 child，页面回到纯色画布。下面的 painter 保留着，等哪天要在
/// **局部**（比如课文承载面）试极微弱的纸感时再用 —— 但绝不再回到全屏。
class LLBackdrop extends StatelessWidget {
  const LLBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final texture = context.llShape.texture;
    if (texture == LLTexture.none) return child;
    return CustomPaint(
      painter: _LLTexturePainter(texture, context.ll),
      child: child,
    );
  }
}

class _LLTexturePainter extends CustomPainter {
  const _LLTexturePainter(this.texture, this.palette);

  final LLTexture texture;
  final LLPalette palette;
  /// Ink-derived stroke color: paper styles get a warm fibre, 都市 gets a cold
  /// grid. Always a wash, never a line you have to think about.
  ///
  /// 2026-10-15 提高：原 0.035 / 0.05 在真机上淡到几乎不存在（郭老师：
  /// 「四套风格看不出区别」的根因之一），纸纹与稿纸各上调约 1.7×，
  /// 幕墙分格 0.05。仍然远低于"需要你去读它"的阈值。
  Color get _fibre => palette.textPrimary.withValues(
    alpha: palette.brightness == Brightness.dark ? 0.085 : 0.06,
  );

  @override
  void paint(Canvas canvas, Size size) {
    switch (texture) {
      case LLTexture.none:
        return;
      case LLTexture.ricePaper:
        _ricePaper(canvas, size);
      case LLTexture.inkRules:
        _inkRules(canvas, size);
      case LLTexture.glaze:
        _glaze(canvas, size);
    }
  }

  /// 宣纸：竹帘留下的竖向细纹，外加少量不均匀纤维点。
  void _ricePaper(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _fibre
      ..strokeWidth = 0.6;
    const step = 7.0;
    for (double x = step; x < size.width; x += step) {
      // 帘纹不是机械等距：每根略偏，纸才不像表格。
      final wobble = ((x * 13.0) % 5.0 - 2.0) * 0.35;
      canvas.drawLine(Offset(x + wobble, 0), Offset(x + wobble, size.height), line);
    }
    final dot = Paint()..color = palette.textPrimary.withValues(alpha: 0.03);
    for (var i = 0; i < 90; i++) {
      final x = (i * 97.13) % size.width;
      final y = (i * 151.7) % size.height;
      canvas.drawCircle(Offset(x, y), 0.7, dot);
    }
  }

  /// 古典：稿纸式横向细行 + 一道左侧栏线，学的是石版与账线的秩序。
  void _inkRules(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _fibre
      ..strokeWidth = 0.6;
    const step = 26.0;
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final margin = Paint()
      ..color = palette.accent.withValues(alpha: 0.16)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(LLSpacing.xl, 0),
      Offset(LLSpacing.xl, size.height),
      margin,
    );
  }

  /// 幕墙：竖向分格 + 一道自左上往右下的斜向高光。都市的语言是"玻璃"，
  /// 所以它要的是反射，不是纸的纤维——高光用白而不是墨色。
  void _glaze(Canvas canvas, Size size) {
    final mullion = Paint()
      ..color = palette.textPrimary.withValues(
        alpha: palette.brightness == Brightness.dark ? 0.05 : 0.04,
      )
      ..strokeWidth = 0.8;
    const step = 56.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), mullion);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = glazeSheen(size));
  }

  @override
  bool shouldRepaint(_LLTexturePainter old) =>
      old.texture != texture ||
      old.palette.textPrimary != palette.textPrimary ||
      old.palette.bg != palette.bg ||
      old.palette.accent != palette.accent;
}

/// 玻璃幕墙的那道斜向高光（都市风格的签名材质）。
///
/// **为什么是常量而不是令牌**：高光是天光，不是这一套的配色——它不随风格、
/// 不随明暗改变。黑夜里的幕墙照样反光，只是被压暗的底衬吃掉一部分。
/// 若改用 `onInverseSurface` 之类，明暗切换时高光会从白翻成墨，玻璃就死了。
///
/// 收在这里（而不是 ll_style_rack）是为了让 `no_hardcoded_colors` 的
/// ratchet 只在这里见到这 3 个字面量：材质语言有一处家，调用方零字面量。
Shader glazeSheen(Size size) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: const [
    Color(0x00FFFFFF),
    Color(0x1AFFFFFF),
    Color(0x00FFFFFF),
  ],
  stops: const [0.0, 0.42, 0.9],
).createShader(Offset.zero & size);
