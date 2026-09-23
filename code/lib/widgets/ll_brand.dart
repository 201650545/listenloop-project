import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// The `∞` brand mark (spec §四): Listen · Loop · Repeat · Continuous
/// practice. The single brand symbol of the app — no complex logo needed.
class LLMark extends StatelessWidget {
  const LLMark({super.key, this.size = 64, this.color = LLColors.textPrimary});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '∞',
      style: TextStyle(
        fontSize: size,
        height: 1,
        color: color,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

/// Quiet loading indicator (spec §三十六): the brand mark breathing
/// 0.35 → 1 → 0.35. Replaces big spinners.
class LLInfinityLoader extends StatefulWidget {
  const LLInfinityLoader({super.key, this.size = 28});

  final double size;

  @override
  State<LLInfinityLoader> createState() => _LLInfinityLoaderState();
}

class _LLInfinityLoaderState extends State<LLInfinityLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Triangle wave: 0 → 1 → 0 over one cycle.
        final t = (2 * _controller.value - 1).abs();
        final opacity = 0.35 + 0.65 * (1 - t);
        return Opacity(
          opacity: opacity,
          child: LLMark(size: widget.size, color: LLColors.textSecondary),
        );
      },
    );
  }
}
