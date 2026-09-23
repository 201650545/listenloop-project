import 'package:flutter/material.dart';

import '../../l10n/ll_strings.dart';
import '../../models/lesson.dart';
import '../../theme/listenloop_theme.dart';
import 'lesson_cover.dart';

/// The first visual focus of the library. The title is the hero;
/// the cover stays small and quiet.
class LessonContinueCard extends StatelessWidget {
  const LessonContinueCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final LessonWithProgress item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final lesson = item.lesson;
    final progress = item.progress!;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(LLRadius.small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LessonCover(path: lesson.coverPath),
              const SizedBox(width: LLSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.title,
                      style: LLText.pageTitle.copyWith(color: ll.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: LLSpacing.sm),
                    Text(
                      '${_two(progress.lastSentenceIndex + 1)} / '
                      '${_two(lesson.sentenceCount)}',
                      style: LLText.counter.copyWith(color: ll.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LLSpacing.xl),
          Divider(color: ll.divider),
          const SizedBox(height: LLSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LLSpacing.xs),
            child: Text(
              s.continueCta,
              style: LLText.controlLabel.copyWith(color: ll.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
