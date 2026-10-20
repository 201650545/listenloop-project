import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// 昼夜过渡里那一点「光」——一层从**顶部中心**漫开的径向光晕（WP-G §二.2）。
///
/// 昼夜切换在这个产品里不是「换皮肤」，是「开灯 / 天亮」。颜色本身的三拍分层
/// 由 [LLPalette.staggerTo] 负责；这一层只负责回答「光从哪来」：一个半透明、
/// 有中心点、柔和扩散的光晕，从屏幕顶部中心亮起。
///
/// 它不是「一块黑布」——那种整屏遮罩式的擦除已经被否掉过（doc 21 §十六：
/// 「直接一块黑布，把所有动画都做了」）。所以这里只有一道从中心向外衰减的渐变，
/// 峰值透明度压得很低（见 [_LLVeilPainter._peakAlpha]），文字始终压得住。
///
/// 三个方向共用同一套几何，只是时间轴与收放方向不同：
/// * [LLVeilMode.dawn]（夜→昼，开灯）：光从中心亮起、向外扩散，到 80% 处淡出；
/// * [LLVeilMode.dusk]（昼→夜，熄灯）：光从满屏收敛回中心、同时变暗，被夜色收走；
/// * [LLVeilMode.shift]（同亮度换风格）：没有昼夜可言，只落一下极轻的光尘，
///   让「换了一张纸」有个来处，但不假装是天亮了。
///
/// 颜色**全部从令牌算出来**（暖白 = 白昼墨色的反相），不写死任何色值。
/// 时长不在这里：它吃的是外部喂进来的 [progress]，与 [LLMotion.themeDepth] 同拍。
class LLDaynightVeil extends StatelessWidget {
  const LLDaynightVeil({
    super.key,
    required this.progress,
    this.mode = LLVeilMode.dawn,
  });

  /// 0 → 1 的过渡进度，直接吃 `main.dart` 的 `_depth.value`。
  final double progress;

  /// 这一次过渡是开灯、熄灯，还是只换纸。
  final LLVeilMode mode;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _LLVeilPainter(progress: progress, mode: mode),
        size: Size.infinite,
      ),
    );
  }
}

/// 光晕往哪个方向走。由调用方比较「当前明暗 → 目标明暗」得出。
enum LLVeilMode {
  /// 夜 → 昼：开灯 / 天亮。
  dawn,

  /// 昼 → 夜：熄灯 / 入夜。
  dusk,

  /// 明暗不变、只换风格：一层极轻的光尘。
  shift,
}

class _LLVeilPainter extends CustomPainter {
  const _LLVeilPainter({required this.progress, required this.mode});

  final double progress;
  final LLVeilMode mode;

  /// 峰值透明度。刻意很低：这一层是「光」，不是「罩」——它不许把文字压下去。
  static const double _peakAlpha = 0.11;

  /// 光晕的颜色：白昼墨色（[LLPalette.daylightLight.textPrimary]）的**反相**，
  /// 也就是一抹暖白。从令牌推出来，不写死色值——换色板时它会自己跟上。
  static final Color _light = _invert(LLPalette.daylightLight.textPrimary);

  static Color _invert(Color c) =>
      Color.from(alpha: c.a, red: 1 - c.r, green: 1 - c.g, blue: 1 - c.b);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = progress.clamp(0.0, 1.0);

    final alpha = _alphaAt(t);
    if (alpha <= 0) return;
    final radius = _reach(size) * _radiusAt(t);
    if (radius <= 0) return;

    // 中心点固定在顶部中心：灯在书页上方，光才有来处。
    final center = Offset(size.width / 2, 0);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          _light.withValues(alpha: alpha),
          _light.withValues(alpha: alpha * 0.35),
          _light.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawRect(Offset.zero & size, paint);
  }

  /// 光能照到多远：以屏幕高度为主、宽度补一点，保证整屏能被漫到，
  /// 又不至于在小屏上把中心糊死。
  double _reach(Size size) => size.height * 1.15 + size.width * 0.35;

  /// 透明度随进度：开灯是「亮起 → 淡出」，熄灯是「还亮着 → 被收走」。
  double _alphaAt(double t) {
    switch (mode) {
      case LLVeilMode.dawn:
        if (t >= 0.80) return 0;
        final rise = (t / 0.30).clamp(0.0, 1.0);
        final fade = (1 - (t - 0.30) / 0.50).clamp(0.0, 1.0);
        return _peakAlpha *
            Curves.easeOut.transform(rise) *
            Curves.easeIn.transform(fade);
      case LLVeilMode.dusk:
        if (t >= 0.80) return 0;
        return _peakAlpha * Curves.easeInOut.transform(1 - t / 0.80);
      case LLVeilMode.shift:
        if (t >= 0.70) return 0;
        final rise = (t / 0.25).clamp(0.0, 1.0);
        final fade = (1 - (t - 0.25) / 0.45).clamp(0.0, 1.0);
        return _peakAlpha *
            0.6 *
            Curves.easeOut.transform(rise) *
            Curves.easeIn.transform(fade);
    }
  }

  /// 半径随进度：开灯向外扩散，熄灯向中心收敛。
  double _radiusAt(double t) {
    switch (mode) {
      case LLVeilMode.dawn:
        return 0.28 + 0.72 * Curves.easeOutCubic.transform(t);
      case LLVeilMode.dusk:
        return 1.0 - 0.80 * Curves.easeInCubic.transform(t);
      case LLVeilMode.shift:
        return 0.45 + 0.45 * Curves.easeOut.transform(t);
    }
  }

  @override
  bool shouldRepaint(_LLVeilPainter old) =>
      old.progress != progress || old.mode != mode;
}
