import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';
import '../theme/ll_style.dart';

/// 微缩书页风格选择卡（纸墨剧场 · 设置页风格选择器示例件）。
///
/// 把一种风格渲染成一页"缩小的书"：桌面底 = 该风格 bg，书页 = surface +
/// 该风格的卡片圆角与发丝边框，页内用**色条**（不是文字）摆出正文/次级/
/// 弱化/强调/分隔线——因为这一件的目的是让你**在选之前先看见纸**，
/// 而色条在 golden 测试里不依赖字体，预览图永远干净。
///
/// 关键技巧在 [Theme]：每张卡**自己套自己风格的主题**，所以一行里能并排
/// 预览四种纸墨，互不串色。选中态用 accent 描一圈 + 角标，不放文字。
class LLThemeSwatch extends StatelessWidget {
  const LLThemeSwatch({
    super.key,
    required this.style,
    required this.brightness,
    this.selected = false,
    this.onTap,
  });

  final LLStyle style;
  final Brightness brightness;
  final bool selected;
  final VoidCallback? onTap;

  /// 供设置页选择器与 golden 示例共用的尺寸（3:4 像一页书）。
  static const Size size = Size(84, 112);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildListenLoopTheme(brightness, style: style),
      child: Builder(
        builder: (context) {
          final ll = context.ll;
          final shape = context.llShape;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: LLMotion.fast,
              curve: LLMotion.curve,
              width: size.width,
              height: size.height,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(shape.card + 4),
                border: Border.all(
                  color: selected ? ll.accent : ll.divider.withValues(alpha: 0),
                  width: 1.6,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: ll.bg,
                  borderRadius: BorderRadius.circular(shape.card + 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // 书页本体
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: ll.surface,
                            borderRadius: BorderRadius.circular(shape.card),
                            border: Border.all(
                              color: ll.divider,
                              width: shape.hairline,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _bar(ll.accent, 0.62, 3),
                                const SizedBox(height: 7),
                                _bar(ll.textPrimary, 0.78, 6),
                                const SizedBox(height: 5),
                                _bar(ll.textSecondary, 0.92, 3.5),
                                const SizedBox(height: 4),
                                _bar(ll.textSecondary, 0.80, 3.5),
                                const SizedBox(height: 4),
                                _bar(ll.textTertiary, 0.55, 3.5),
                                const Spacer(),
                                Container(height: shape.hairline, color: ll.divider),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      width: 26,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: ll.accent,
                                        borderRadius:
                                            BorderRadius.circular(shape.pill),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _bar(ll.divider, 1.0, 3.5),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 选中角标（右上角一个实心小点，accent 色）
                    if (selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ll.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 一条"字"：宽度按比例、高度固定的圆角色条，颜色吃 palette。
  Widget _bar(Color color, double widthFactor, double height) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}
