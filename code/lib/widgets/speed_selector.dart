import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// Discrete speed selector: 0.75× / 1.0× / 1.25×, current value white with
/// a short underline, the rest tertiary grey (spec V2 §二十七). No slider on
/// purpose — three choices cover the listening use case (spec V0.1 §14).
/// Long-pressing the row still opens the continuous 0.5×–2.0× sheet.
class SpeedSelector extends StatelessWidget {
  const SpeedSelector({
    super.key,
    required this.playbackRate,
    required this.onChanged,
    this.enabled = true,
  });

  static const List<double> rates = [0.75, 1.0, 1.25];

  final double playbackRate;
  final ValueChanged<double> onChanged;
  final bool enabled;

  String _label(double rate) =>
      rate == rate.roundToDouble() ? '${rate.toStringAsFixed(1)}×' : '$rate×';

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final rate in rates)
          _RateOption(
            label: _label(rate),
            selected: rate == playbackRate,
            enabled: enabled,
            onTap: () => onChanged(rate),
            palette: ll,
          ),
      ],
    );
  }
}

class _RateOption extends StatelessWidget {
  const _RateOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final LLPalette palette;

  @override
  Widget build(BuildContext context) {
    final active = selected && enabled;
    final color = !enabled
        ? palette.disabled
        : active
        ? palette.textPrimary
        : palette.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: active ? palette.textPrimary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
