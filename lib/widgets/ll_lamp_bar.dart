import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// 一项「灯」：值 + 图标 + 名字。
typedef LlLampOption<T> = ({T value, IconData icon, String label});

/// 灯绳（WP-I §三.3.C）——明暗不从三个等重的 tab 里挑，是拨一根灯绳。
///
/// 与 `LLSegmented` 同源：轨道是 `controlTrack`，选中的胶囊是 `controlThumb` +
/// `controlThumbBorder` + `shadow`，所以它在昼夜过渡里能跟着色板缓动，不会像
/// `isDark ?` 写死的控件那样中途硬切。
///
/// 区别只在图标：白昼画太阳、黑夜画台灯——这是本产品「开灯 / 天亮」叙事的入口，
/// 图标比文字更快让人知道自己在挑的是"光"，不是"主题"。
class LLLampBar<T> extends StatelessWidget {
  const LLLampBar({
    super.key,
    required this.selected,
    required this.options,
    required this.onSelect,
  });

  final T selected;
  final List<LlLampOption<T>> options;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ll.controlTrack,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(option.value),
                child: AnimatedContainer(
                  duration: LLMotion.normal,
                  curve: LLMotion.curve,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: option.value == selected
                        ? ll.controlThumb
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: option.value == selected
                          ? ll.controlThumbBorder
                          : Colors.transparent,
                    ),
                    boxShadow: option.value == selected
                        ? [
                            BoxShadow(
                              color: ll.shadow,
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        option.icon,
                        size: 15,
                        color: option.value == selected
                            ? ll.textPrimary
                            : ll.textTertiary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LLText.controlLabel.copyWith(
                            fontSize: 13,
                            fontWeight: option.value == selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: option.value == selected
                                ? ll.textPrimary
                                : ll.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
