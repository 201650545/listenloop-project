import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// The single base every listening control sits on: a hairline progress
/// trace for the sentence under the needle, the centred transport cluster,
/// a wrap of capsule controls, and the discrete speed / subtitle rows — one
/// quiet surface instead of four floating strips.
///
/// The bar is deliberately dumb. Every child arrives fully wired from the
/// screen (the playback cluster, the pills, the selectors, the inline
/// fine-tune card); it owns layout, rhythm and the progress trace, and
/// knows nothing about playback. Controller callbacks are passed through
/// untouched by construction — there is no playback logic here to break.
class LLAudioControlBar extends StatelessWidget {
  const LLAudioControlBar({
    super.key,
    required this.progress,
    required this.playback,
    required this.pills,
    this.inlineSlider,
    this.speedRow,
    this.subtitleRow,
    this.compact = false,
  });

  /// Position inside the current sentence, 0–1. Display-only: the controller
  /// exposes no public seek, so the trace never pretends to be a scrubber.
  final double progress;

  /// The prev / play-pause / next cluster, already wired to the controller.
  final Widget playback;

  /// Capsule controls (loop / gap / silence / flashcard…), each fully wired.
  final List<Widget> pills;

  /// The long-press fine-tune card (speed / gap / loop), when one is open.
  final Widget? inlineSlider;

  /// The discrete speed row — always visible, it is the speed affordance.
  final Widget? speedRow;

  /// The subtitle visibility row (non-Chinese lessons only).
  final Widget? subtitleRow;

  /// 矮视口（横屏 / 分屏）下收紧自身节奏。
  ///
  /// 为什么需要：这条底座的固有高约 163dp（进度线 + 播放簇 + 胶囊 +
  /// 倍速行）。竖屏 849dp 高时它毫不起眼；横屏 382dp 高、扣掉状态栏与
  /// 导航栏后只剩约 310dp，顶栏 + 听读/视听 + 它三件固定高度子件就把
  /// 可用高度吃满 —— 于是控制条下缘 bottom overflow，而本该占大头
  /// 的课文句子区被压成 0（2026-10-15 郭老师小米 14 横屏实测：
  /// 「BOTTOM OVERFLOWED BY 2.4 PIXELS」，同时句子一个字都看不见）。
  ///
  /// compact 只动内外边距与行间距，不动任何选项：矮屏下选项一个不少，
  /// 只是排得紧一些。默认 false —— 竖屏路径的布局与以前逐像素一致。
  final bool compact;

  /// Overflow guard for the two discrete rows.
  ///
  /// [SpeedSelector] and [SubtitleModeSelector] are plain `Row`s with no
  /// `Flexible` inside, so their natural width grows with the text scale
  /// (measured at 360dp: the speed row wants 259.5dp @1.0× → 318.3 @1.3× →
  /// 377.1 @1.6× → 455.5 @2.0×). Past ~1.3× they no longer fit inside this
  /// bar's gutter and throw a horizontal `RenderFlex` overflow — the
  /// yellow-striped bar, and an option the user cannot reach.
  ///
  /// Scaling the row down keeps every option present, legible and tappable at
  /// any scale up to 2.0×, and it is the only lever on this side of the
  /// boundary: the real cure is for those two widgets to flex or wrap their
  /// own children, which lives in WP-B's files, not here. Until then the bar
  /// does not hand the overflow to the user.
  Widget _shrinkToFit(Widget row) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: row,
      );

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return Container(
      decoration: BoxDecoration(
        color: ll.brightness == Brightness.light
            ? Color.lerp(ll.surface, ll.bg, 0.5)!
            : ll.surface,
        borderRadius: BorderRadius.circular(shape.card),
        border: Border.all(
          color: ll.divider.withValues(alpha: 0.7),
          width: shape.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: ll.brightness == Brightness.light ? 0.03 : 0.18,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LLSentenceProgressTrace(value: progress),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : shape.gutter,
              compact ? 2 : 6,
              compact ? 8 : shape.gutter,
              compact ? 4 : shape.gutter - 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                playback,
                if (inlineSlider != null) ...[
                  SizedBox(height: compact ? 2 : 6),
                  inlineSlider!,
                ],
                if (pills.isNotEmpty) ...[
                  SizedBox(height: compact ? 0 : 4),
                  // 一行做完：严禁折成两行。自适应缩放保底，大字号或窄屏下平滑容纳
                  _shrinkToFit(
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < pills.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          pills[i],
                        ],
                      ],
                    ),
                  ),
                ],
                if (speedRow != null) ...[
                  SizedBox(height: compact ? 0 : 2),
                  _shrinkToFit(speedRow!),
                ],
                if (subtitleRow != null) ...[
                  SizedBox(height: compact ? 0 : 2),
                  _shrinkToFit(subtitleRow!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The 2.5dp trace along the bar's top edge: how far the needle has travelled
/// inside the current sentence. Track = divider, fill = ink; the fill eases
/// between values so sentence switches read as motion, not jumps.
class LLSentenceProgressTrace extends StatelessWidget {
  const LLSentenceProgressTrace({super.key, required this.value});

  /// 0–1 position inside the current sentence.
  final double value;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      key: const Key('ll-progress-trace'),
      height: 2.5,
      width: double.infinity,
      child: ColoredBox(
        color: ll.divider.withValues(alpha: 0.45),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: v),
            duration: LLMotion.fast,
            curve: LLMotion.curve,
            builder: (context, t, _) => FractionallySizedBox(
              widthFactor: t,
              child: ColoredBox(color: ll.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
