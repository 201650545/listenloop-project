import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';
import 'll_brand.dart';

/// Visual area at the top of the listening screen.
///
/// Shows the lesson cover when available; audio-only lessons get an
/// extremely quiet `∞` mark instead of a placeholder illustration (spec V2
/// §十九/§二十六) — audio mode should feel intentional, not like a missing
/// video. Doubles as the video slot when the mode is active.
class MediaArea extends StatelessWidget {
  const MediaArea({super.key, this.coverPath, this.loading = false});

  final String? coverPath;

  /// Shows a subtle loading cue instead of jumping the layout around.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (coverPath != null)
          Image.file(
            File(coverPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _defaultVisual(ll),
          )
        else
          _defaultVisual(ll),
        if (loading)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(child: LLInfinityLoader(size: 16)),
          ),
      ],
    );
  }

  Widget _defaultVisual(LLPalette ll) => Container(
    color: ll.surfaceHigh,
    alignment: Alignment.center,
    child: LLMark(size: 44, color: ll.textTertiary),
  );
}
