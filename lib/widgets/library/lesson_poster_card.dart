import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../../theme/listenloop_theme.dart';
import '../subtitle_mode_selector.dart' show SubtitleModeX;
import 'lesson_cover.dart';

/// 双列海报卡片（课程库海报书架视图）：
/// 16:9 海报封面、微圆角、语种徽标、视频角标、进度微条，标题两行，极简黑白。
class LessonPosterCard extends StatelessWidget {
  const LessonPosterCard({
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
    final lesson = item.lesson;
    final progress = item.progress;
    final lang = SubtitleModeX.resolveLanguageCode(lesson.language);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(LLRadius.small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              LessonPosterCover(path: lesson.coverPath, height: 104),
              // Language badge
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xB3000000),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    lang,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              // Video badge
              if (lesson.video != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              // Progress bar
              if (progress != null && lesson.sentenceCount > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(LLRadius.small),
                    ),
                    child: LinearProgressIndicator(
                      value: ((progress.lastSentenceIndex + 1) /
                              lesson.sentenceCount)
                          .clamp(0.0, 1.0),
                      minHeight: 2.5,
                      backgroundColor: const Color(0x26FFFFFF),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(ll.textPrimary),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: LLSpacing.sm),
          Text(
            lesson.title,
            style: LLText.rowTitle.copyWith(
              color: ll.textPrimary,
              fontSize: 13,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${lesson.sentenceCount} sentences · ${_mmss(lesson.durationMs)}',
            style: LLText.caption.copyWith(
              color: ll.textTertiary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
