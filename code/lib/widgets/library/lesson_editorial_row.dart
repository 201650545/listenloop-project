import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../../theme/listenloop_theme.dart';
import 'lesson_cover.dart';

/// An editorial list row — index number, cover, title, meta line, hairline.
/// More magazine table of contents than app cards.
class LessonEditorialRow extends StatelessWidget {
  const LessonEditorialRow({
    super.key,
    required this.index,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final int index;
  final LessonWithProgress item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final lesson = item.lesson;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LLSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LessonCover(path: lesson.coverPath, size: 44),
            const SizedBox(width: LLSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _two(index + 1),
                    style: LLText.sectionLabel.copyWith(color: ll.textTertiary),
                  ),
                  const SizedBox(height: LLSpacing.sm),
                  Text(
                    lesson.title,
                    style: LLText.rowTitle.copyWith(color: ll.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: LLSpacing.xs),
                  Text(
                    '${lesson.sentenceCount} sentences · ${_mmss(lesson.durationMs)}',
                    style: LLText.caption.copyWith(color: ll.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _mmss(int durationMs) {
    final minutes = durationMs ~/ 60000;
    final seconds = (durationMs % 60000) ~/ 1000;
    return '${_two(minutes)}:${_two(seconds)}';
  }
}
