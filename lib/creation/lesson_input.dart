import 'package:flutter/foundation.dart';

/// What a creation job starts from (spec V1 §五).
///
/// v1 supports local media files only; link input arrives in M3 and is
/// modelled as [LessonInputKind.link] with a [source] URL.
@immutable
class LessonInput {
  const LessonInput.localFile({
    required this.path,
    this.titleHint,
    this.language,
    this.readingMode = false,
  }) : source = null;

  const LessonInput.link({
    required this.source,
    this.titleHint,
    this.language,
    this.readingMode = false,
  }) : path = null;

  /// Absolute path for [LessonInputKind.localFile].
  final String? path;

  /// Source URL for [LessonInputKind.link] (M3).
  final String? source;

  /// Optional title hint (file name / share subject), refined later.
  final String? titleHint;

  /// Optional language hint (e.g. 'en', 'ja', 'zh'). Null = auto-detect.
  final String? language;

  /// 课文朗读模式（2026-09-29 用户需求）：中文按「逗号/句号」的朗读
  /// 单元切句，每个短句都可单独循环——早读带读用。对已导入课程无影响
  /// （切句发生在导入时）。仅中文链路生效。
  final bool readingMode;

  /// `audio` or `video` — drives whether audio extraction is needed (M2).
  LessonInputMediaType get mediaType {
    final p = (path ?? source ?? '').toLowerCase();
    if (p.endsWith('.mp4') ||
        p.endsWith('.mkv') ||
        p.endsWith('.webm') ||
        p.endsWith('.mov')) {
      return LessonInputMediaType.video;
    }
    return LessonInputMediaType.audio;
  }

  LessonInputKind get kind => source != null && path == null
      ? LessonInputKind.link
      : LessonInputKind.localFile;
}

enum LessonInputKind { localFile, link }

enum LessonInputMediaType { audio, video }
