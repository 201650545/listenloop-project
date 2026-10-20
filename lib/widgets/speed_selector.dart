import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';
import 'll_icons.dart';

/// The discrete speed affordance under the transport cluster.
///
/// 2026-10-20 郭老师：「下面的改倍速功能也不要显示文字，也是图标化」。
/// 原来是三个并排的文字档位（0.8× / 1.0× / 1.3×），现在收成**一个**
/// 倍速图标 + 当前数值：
///   · 图标 = LLSpeedIcon（双快进箭头 + 速度线，与控制条其它图标同一套语言）；
///   · 数值 = 当前档位读数（读数不是文字标签，倍速必须看得见）；
///   · 点按 = 在三档之间循环；长按 = 仍开 0.5×–2.0× 连续细调（行为不变）。
class SpeedSelector extends StatelessWidget {
  const SpeedSelector({
    super.key,
    required this.playbackRate,
    required this.onChanged,
    this.enabled = true,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  static const List<double> rates = [0.75, 1.0, 1.25];

  final double playbackRate;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;

  String _label(double rate) =>
      rate == rate.roundToDouble() ? '${rate.toStringAsFixed(1)}×' : '$rate×';

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final idx = rates.indexOf(playbackRate);
    final next = rates[idx < 0 ? 1 : (idx + 1) % rates.length];
    final color = enabled ? ll.textSecondary : ll.disabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged(next) : null,
      onLongPressStart: enabled ? onLongPressStart : null,
      onLongPressMoveUpdate: enabled ? onLongPressMoveUpdate : null,
      onLongPressEnd: enabled ? onLongPressEnd : null,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LLSpeedIcon(size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              _label(playbackRate),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
