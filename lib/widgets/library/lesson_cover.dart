import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/listenloop_theme.dart';
import '../ll_brand.dart';

/// Small restrained cover used in lists and continue cards.
/// Audio-only lessons keep the brand mark instead of a music-note icon.
class LessonCover extends StatelessWidget {
  const LessonCover({super.key, this.path, this.size = 56});

  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return ClipRRect(
      borderRadius: BorderRadius.circular(LLRadius.small),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null
            ? _placeholder(ll)
            : Image.file(
                File(path!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(ll),
              ),
      ),
    );
  }

  Widget _placeholder(LLPalette ll) => Container(
        color: ll.surfaceHigh,
        alignment: Alignment.center,
        child: LLMark(size: size * 0.36, color: ll.textTertiary),
      );
}

/// Wide poster cover for grid cards (16:9 / 4:3).
class LessonPosterCover extends StatelessWidget {
  const LessonPosterCover({super.key, this.path, required this.height});

  final String? path;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: ll.surfaceHigh,
        borderRadius: BorderRadius.circular(LLRadius.small),
        border: Border.all(color: ll.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: path == null
          ? _placeholder(ll)
          : Image.file(
              File(path!),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(ll),
            ),
    );
  }

  Widget _placeholder(LLPalette ll) => Container(
        color: ll.surfaceHigh,
        alignment: Alignment.center,
        child: LLMark(size: 24, color: ll.textTertiary),
      );
}
