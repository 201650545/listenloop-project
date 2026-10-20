import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// A quiet capsule control for the audio dock: one short label (optionally
/// led by a small glyph), hairline border, no fill in its resting state.
///
/// The visible pill stays slim so a full row of them keeps the dock calm,
/// but the hit target is inflated to ≥48×44 — the padding around the pill is
/// transparent and belongs to the gesture, not the look.
///
/// Every colour and typeface comes from the palette / typography tokens:
/// [active] means "the value behind this pill is doing something" (a
/// non-default loop count, an armed toggle, a saved flashcard) and reads as
/// ink on a faint emphasis wash; resting reads as secondary text on a bare
/// hairline. Nothing here is a literal colour.
class LLPillButton extends StatelessWidget {
  const LLPillButton({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.active = false,
    this.enabled = true,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;

  /// Whether the value behind the pill is currently doing something.
  final bool active;

  final bool enabled;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    final fg = !enabled
        ? ll.disabled
        : active
            ? ll.textPrimary
            : ll.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      onLongPressStart: enabled ? onLongPressStart : null,
      onLongPressMoveUpdate: enabled ? onLongPressMoveUpdate : null,
      onLongPressEnd: enabled ? onLongPressEnd : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: AnimatedContainer(
            duration: LLMotion.fast,
            curve: LLMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? ll.emphasis : null,
              borderRadius: BorderRadius.circular(shape.pill),
              border: Border.all(
                color: active
                    ? ll.textPrimary.withValues(alpha: 0.35)
                    : ll.divider,
                width: shape.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 4),
                ] else if (icon != null) ...[
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: LLText.chipLabel.copyWith(
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
