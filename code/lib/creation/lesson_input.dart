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
  }) : source = null;

  const LessonInput.link({
    required this.source,
    this.titleHint,
    this.language,
  }) : path = null;

  /// Absolute path for [LessonInputKind.localFile].
  final String? path;

  /// Source URL for [LessonInputKind.link] (M3).
  final String? source;

  /// Optional title hint (file name / share subject), refined later.
  final String? titleHint;

  /// Optional language hint (e.g. 'en', 'ja', 'zh'). Null = auto-detect.
  final String? language;

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
