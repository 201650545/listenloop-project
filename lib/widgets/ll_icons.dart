import 'package:flutter/material.dart';

/// 句读 (Phrasing) 核心极简矢量符号标志集
/// 
/// 契约：
/// 1. 100% 纯黑白（随主题自动变换：浅色用深墨 #14161A，深色用月白 #FAFAF8）；
/// 2. 14×14 ~ 18×18 紧凑高精几何矢量，绝无插画冗余；
/// 3. 线宽严格 1.4 ~ 1.8px，高密屏下锐利纯粹。

/// 1. 「整课连读」精简符号：无断点流水回环 + 播放三角
class LLContinuousPlayIcon extends StatelessWidget {
  const LLContinuousPlayIcon({
    super.key,
    this.size = 14,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return CustomPaint(
      size: Size(size, size),
      painter: _ContinuousPlayPainter(color: c),
    );
  }
}

class _ContinuousPlayPainter extends CustomPainter {
  _ContinuousPlayPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paintStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final paintFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 播放小实心三角（居中偏左）
    final playPath = Path()
      ..moveTo(w * 0.28, h * 0.22)
      ..lineTo(w * 0.74, h * 0.50)
      ..lineTo(w * 0.28, h * 0.78)
      ..close();
    canvas.drawPath(playPath, paintFill);

    // 下方平滑连贯回环波纹线（象征整篇原声流水贯通）
    final wavePath = Path()
      ..moveTo(w * 0.10, h * 0.88)
      ..cubicTo(w * 0.35, h * 0.98, w * 0.65, h * 0.76, w * 0.92, h * 0.88);
    canvas.drawPath(wavePath, paintStroke);
  }

  @override
  bool shouldRepaint(covariant _ContinuousPlayPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 2. 「非连读（逐句精听）」精简符号：句读双顿号/竖线留白 + 播放三角
class LLSentencePauseIcon extends StatelessWidget {
  const LLSentencePauseIcon({
    super.key,
    this.size = 14,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return CustomPaint(
      size: Size(size, size),
      painter: _SentencePausePainter(color: c),
    );
  }
}

class _SentencePausePainter extends CustomPainter {
  _SentencePausePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paintStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.12
      ..strokeCap = StrokeCap.round;

    final paintFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 左侧：断句顿挫双竖标（代表句读留白）
    canvas.drawLine(Offset(w * 0.14, h * 0.24), Offset(w * 0.14, h * 0.76), paintStroke);
    canvas.drawLine(Offset(w * 0.32, h * 0.24), Offset(w * 0.32, h * 0.76), paintStroke);

    // 右侧：播放小三角
    final playPath = Path()
      ..moveTo(w * 0.52, h * 0.26)
      ..lineTo(w * 0.88, h * 0.50)
      ..lineTo(w * 0.52, h * 0.74)
      ..close();
    canvas.drawPath(playPath, paintFill);
  }

  @override
  bool shouldRepaint(covariant _SentencePausePainter oldDelegate) =>
      oldDelegate.color != color;
}

// ════════════════════════════════════════════════════════════════════
// 2026-10-20 郭老师：底部导航四图标定制化（替换 Material 老图标）
// 设计稿由商汤日日新 image-gen 生成（docs/icons/nav_icons_*.png），
// 按其形态重绘为矢量——纯黑白，1.6 描边，主题自动反色。
// 课程=开卷+声波 · 听=耳机+声波 · 读=侧脸开口+声波 · 设置=三滑杆
// ════════════════════════════════════════════════════════════════════

/// 1. 课程：摊开的书 + 右上两道声波
class LLNavCourseIcon extends StatelessWidget {
  const LLNavCourseIcon({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return CustomPaint(
      size: Size(size, size),
      painter: _NavCoursePainter(color: c),
    );
  }
}

class _NavCoursePainter extends CustomPainter {
  _NavCoursePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 书页：两页弧形
    final book = Path()
      ..moveTo(w * 0.08, h * 0.78)
      ..lineTo(w * 0.08, h * 0.30)
      ..quadraticBezierTo(w * 0.28, h * 0.22, w * 0.50, h * 0.36)
      ..quadraticBezierTo(w * 0.72, h * 0.22, w * 0.92, h * 0.30)
      ..lineTo(w * 0.92, h * 0.78)
      ..quadraticBezierTo(w * 0.70, h * 0.68, w * 0.50, h * 0.82)
        ..quadraticBezierTo(w * 0.30, h * 0.68, w * 0.08, h * 0.78)
      ..close();
    canvas.drawPath(book, s);
    // 文字行
    for (final dy in [0.44, 0.54, 0.64]) {
      canvas.drawLine(Offset(w * 0.16, h * dy), Offset(w * 0.42, h * dy - 0.01), s);
      canvas.drawLine(Offset(w * 0.58, h * dy - 0.01), Offset(w * 0.84, h * dy), s);
    }
    // 声波
    for (final r in [0.10, 0.17]) {
      canvas.drawArc(
          Rect.fromCircle(
              center: Offset(w * 0.60, h * 0.16), radius: w * r),
          -1.3,
          1.9,
          false,
          s);
    }
  }

  @override
  bool shouldRepaint(covariant _NavCoursePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 2. 听：耳机 + 右侧声波
class LLNavListenIcon extends StatelessWidget {
  const LLNavListenIcon({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return CustomPaint(
      size: Size(size, size),
      painter: _NavListenPainter(color: c),
    );
  }
}

class _NavListenPainter extends CustomPainter {
  _NavListenPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 头梁
    canvas.drawArc(
        Rect.fromCircle(center: Offset(w * 0.42, h * 0.55), radius: w * 0.36),
        -3.0,
        3.6,
        false,
        s);
    // 耳罩
    canvas.drawRRect(
        RRect.fromLTRBR(w * 0.08, h * 0.50, w * 0.26, h * 0.86,
            Radius.circular(w * 0.09)),
        s);
    canvas.drawRRect(
        RRect.fromLTRBR(w * 0.58, h * 0.50, w * 0.76, h * 0.86,
            Radius.circular(w * 0.09)),
        s);
    // 声波
    for (final r in [0.09, 0.16]) {
      canvas.drawArc(
          Rect.fromCircle(
              center: Offset(w * 0.62, h * 0.68), radius: w * r),
          -1.2,
          2.0,
          false,
          s);
    }
  }

  @override
  bool shouldRepaint(covariant _NavListenPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 3. 读：侧脸开口 + 声波
class LLNavReadIcon extends StatelessWidget {
  const LLNavReadIcon({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return CustomPaint(
      size: Size(size, size),
      painter: _NavReadPainter(color: c),
    );
  }
}

class _NavReadPainter extends CustomPainter {
  _NavReadPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 侧脸：额→鼻→唇→下巴
    final face = Path()
      ..moveTo(w * 0.30, h * 0.12)
      ..quadraticBezierTo(w * 0.16, h * 0.26, w * 0.22, h * 0.40)
      ..quadraticBezierTo(w * 0.30, h * 0.46, w * 0.22, h * 0.54)
      ..quadraticBezierTo(w * 0.18, h * 0.58, w * 0.24, h * 0.62)
      ..quadraticBezierTo(w * 0.34, h * 0.70, w * 0.26, h * 0.86);
    canvas.drawPath(face, s);
    // 嘴
    canvas.drawArc(
        Rect.fromLTRB(w * 0.24, h * 0.40, w * 0.40, h * 0.56),
        0.4,
        2.4,
        false,
        s);
    // 声波
    for (final r in [0.11, 0.19, 0.27]) {
      canvas.drawArc(
          Rect.fromCircle(
              center: Offset(w * 0.46, h * 0.50), radius: w * r),
          -0.9,
          1.8,
          false,
          s);
    }
  }

  @override
  bool shouldRepaint(covariant _NavReadPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 4. 设置：三条滑杆 + 圆点
class LLNavSettingsIcon extends StatelessWidget {
  const LLNavSettingsIcon({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return CustomPaint(
      size: Size(size, size),
      painter: _NavSettingsPainter(color: c),
    );
  }
}

class _NavSettingsPainter extends CustomPainter {
  _NavSettingsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;
    final f = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const knobs = [0.32, 0.62, 0.42];
    for (var i = 0; i < 3; i++) {
      final y = h * (0.26 + i * 0.24);
      canvas.drawLine(Offset(w * 0.12, y), Offset(w * 0.88, y), s);
      canvas.drawCircle(Offset(w * knobs[i], y), w * 0.085, f);
    }
  }

  @override
  bool shouldRepaint(covariant _NavSettingsPainter oldDelegate) =>
      oldDelegate.color != color;
}
// 设计稿由 API 转换网关「商汤日日新 image-gen」生成（docs/icons/icon_design_*.png），
// 按其形态重绘为矢量——PNG 有水印/色偏/缩放锯齿且无法跟随主题，矢量可自动反色。
// 契约同文件头：纯黑白，1.4~1.8px 描边，14~18px 紧凑高精几何。
// ════════════════════════════════════════════════════════════════════

/// 3. 「整课」单图形符号：回环箭头 + 中心播放三角（不再用 🔁 emoji）
class LLLessonLoopIcon extends StatelessWidget {
  const LLLessonLoopIcon({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return CustomPaint(
      size: Size(size, size),
      painter: _LessonLoopPainter(color: c),
    );
  }
}

class _LessonLoopPainter extends CustomPainter {
  _LessonLoopPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.115
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 回环弧（缺口留在右上，箭头指回起点）
    final arc = Path()
      ..moveTo(w * 0.78, h * 0.22)
      ..arcToPoint(Offset(w * 0.16, h * 0.26),
          radius: Radius.circular(w * 0.52), clockwise: false)
      ..arcToPoint(Offset(w * 0.20, h * 0.80),
          radius: Radius.circular(w * 0.52), clockwise: false)
      ..arcToPoint(Offset(w * 0.84, h * 0.70),
          radius: Radius.circular(w * 0.52), clockwise: false);
    canvas.drawPath(arc, stroke);

    // 右上箭头（三角）
    final head = Path()
      ..moveTo(w * 0.60, h * 0.10)
      ..lineTo(w * 0.90, h * 0.26)
      ..lineTo(w * 0.66, h * 0.36)
      ..close();
    canvas.drawPath(head, fill);

    // 中心播放三角
    final play = Path()
      ..moveTo(w * 0.40, h * 0.38)
      ..lineTo(w * 0.68, h * 0.52)
      ..lineTo(w * 0.40, h * 0.66)
      ..close();
    canvas.drawPath(play, fill);
  }

  @override
  bool shouldRepaint(covariant _LessonLoopPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 4. 「每句循环次数」：回环 + 数字徽标（当前次数）
class LLLoopCountIcon extends StatelessWidget {
  const LLLoopCountIcon({super.key, this.size = 16, this.color, this.count});

  final double size;
  final Color? color;

  /// 当前循环次数；null 时只画回环，不画徽标。
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _LoopCountPainter(color: c),
          ),
          if (count != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(size * 0.22),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: size * 0.42,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoopCountPainter extends CustomPainter {
  _LoopCountPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final arc = Path()
      ..moveTo(w * 0.72, h * 0.20)
      ..arcToPoint(Offset(w * 0.18, h * 0.26),
          radius: Radius.circular(w * 0.46), clockwise: false)
      ..arcToPoint(Offset(w * 0.22, h * 0.70),
          radius: Radius.circular(w * 0.46), clockwise: false);
    canvas.drawPath(arc, stroke);

    final head = Path()
      ..moveTo(w * 0.56, h * 0.08)
      ..lineTo(w * 0.84, h * 0.24)
      ..lineTo(w * 0.60, h * 0.34)
      ..close();
    canvas.drawPath(head, fill);
  }

  @override
  bool shouldRepaint(covariant _LoopCountPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 5. 「每句循环间隔」：钟面（可带数值徽标，如 0.8s）
class LLLoopGapIcon extends StatelessWidget {
  const LLLoopGapIcon({super.key, this.size = 16, this.color, this.badge});

  final double size;
  final Color? color;

  /// 间隔数值徽标（如 '0.8s'）；null 时只画钟面。
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _LoopGapPainter(color: c),
          ),
          if (badge != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(size * 0.22),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: size * 0.36,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoopGapPainter extends CustomPainter {
  _LoopGapPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.38, stroke);
    // 时针（竖）与分针（斜）
    canvas.drawLine(Offset(w * 0.5, h * 0.5), Offset(w * 0.5, h * 0.26), stroke);
    canvas.drawLine(Offset(w * 0.5, h * 0.5), Offset(w * 0.66, h * 0.60), stroke);
    // 12 点刻度
    canvas.drawLine(Offset(w * 0.5, h * 0.16), Offset(w * 0.5, h * 0.24), stroke);
  }

  @override
  bool shouldRepaint(covariant _LoopGapPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 6. 「倍速」：双快进箭头 + 速度线
class LLSpeedIcon extends StatelessWidget {
  const LLSpeedIcon({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return CustomPaint(
      size: Size(size, size),
      painter: _SpeedPainter(color: c),
    );
  }
}

class _SpeedPainter extends CustomPainter {
  _SpeedPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.10
      ..strokeCap = StrokeCap.round;

    // 双快进三角
    final a = Path()
      ..moveTo(w * 0.12, h * 0.30)
      ..lineTo(w * 0.44, h * 0.50)
      ..lineTo(w * 0.12, h * 0.70)
      ..close();
    final b = Path()
      ..moveTo(w * 0.42, h * 0.30)
      ..lineTo(w * 0.74, h * 0.50)
      ..lineTo(w * 0.42, h * 0.70)
      ..close();
    canvas.drawPath(a, fill);
    canvas.drawPath(b, fill);

    // 速度线
    canvas.drawLine(Offset(w * 0.82, h * 0.34), Offset(w * 0.94, h * 0.34), stroke);
    canvas.drawLine(Offset(w * 0.82, h * 0.50), Offset(w * 0.98, h * 0.50), stroke);
    canvas.drawLine(Offset(w * 0.82, h * 0.66), Offset(w * 0.94, h * 0.66), stroke);
  }

  @override
  bool shouldRepaint(covariant _SpeedPainter oldDelegate) =>
      oldDelegate.color != color;
}
