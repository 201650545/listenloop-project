import 'package:flutter/material.dart';

import '../l10n/ll_strings.dart';
import '../theme/listenloop_theme.dart';

/// Main control cluster: previous / play-pause / next with the centre button
/// as the largest touch target (≥48px touch areas) — spec V0.1 §9.
///
/// §二十五 (V1): only the centre button sits in a filled circle — white in
/// dark mode, near-black in light mode (§三十七) — so it naturally becomes
/// the control area's single focal point. Playback semantics are owned by
/// the controller; replaying a sentence is done by tapping its subtitle.
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    this.enabled = true,
  });

  final bool isPlaying;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// When false (e.g. audio failed to load) all controls are disabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final disabledColor = ll.disabled;
    // NOTE: the side columns are NOT height-constrained — a fixed 72dp box
    // overflowed by ~2dp with some system fonts (the "BOTTOM OVERFLOWED"
    // stripe under 上一句/下一句). The row sizes itself to its tallest
    // child and the centre button stays vertically centred.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 88,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('previous-button'),
                onPressed: (enabled && canGoPrevious) ? onPrevious : null,
                icon: Icon(
                  Icons.skip_previous,
                  size: 30,
                  color: (enabled && canGoPrevious)
                      ? ll.textPrimary
                      : disabledColor,
                ),
              ),
              Text(
                s.prev,
                style: LLText.caption.copyWith(
                  color: ll.textTertiary,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 88,
          child: FilledButton(
            key: const Key('play-pause-button'),
            onPressed: enabled ? onPlayPause : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(72, 72),
              maximumSize: const Size(72, 72),
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: ll.textPrimary,
              foregroundColor: ll.onPrimary,
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              key: ValueKey(isPlaying),
              size: 40,
            ),
          ),
        ),
        SizedBox(
          width: 88,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('next-button'),
                onPressed: (enabled && canGoNext) ? onNext : null,
                icon: Icon(
                  Icons.skip_next,
                  size: 30,
                  color: (enabled && canGoNext)
                      ? ll.textPrimary
                      : disabledColor,
                ),
              ),
              Text(
                s.next,
                style: LLText.caption.copyWith(
                  color: ll.textTertiary,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
