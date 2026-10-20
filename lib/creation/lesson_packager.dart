import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../lesson/lesson_manifest.dart';
import '../lesson/lesson_package_reader.dart';
import '../models/sentence.dart';
import '../models/video_source.dart';
import 'creation_errors.dart';
import 'segmentation_service.dart';

/// Turns drafts + translations into a validated in-memory [ParsedLessonPackage]
/// and feeds it to the EXISTING import pipeline (spec V1 §二十七/§二十八) —
/// mobile never writes its own database rows and never bypasses the importer.
abstract final class LessonPackager {
  /// Packaging Safety QA (§五十四): structural checks only, no content review.
  static void validate({
    required List<DraftSentence> drafts,
    required List<String> translations,
    required int audioDurationMs,
  }) {
    if (drafts.isEmpty) {
      throw const CreationException(
        CreationError.packageError,
        'transcription produced no sentences',
      );
    }
    if (translations.length != drafts.length) {
      throw const CreationException(
        CreationError.packageError,
        'translation count mismatch',
      );
    }
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      if (draft.endMs <= draft.startMs) {
        throw CreationException(
          CreationError.packageError,
          'sentence $i has end <= start',
        );
      }
      if (i > 0 && draft.startMs < drafts[i - 1].endMs) {
        throw CreationException(
          CreationError.packageError,
          'sentence $i overlaps the previous one',
        );
      }
    }
    if (audioDurationMs > 0) {
      final last = drafts.last.endMs;
      if (last > audioDurationMs + 1000) {
        throw CreationException(
          CreationError.packageError,
          'sentences run past the end of the audio',
        );
      }
    }
  }

  /// Builds the in-memory package. [audioBytes] are the ORIGINAL media bytes
  /// (no re-encode) so the packaged audio is byte-identical to the source.
  ///
  /// 2026-09-21 用户需求（原声连贯无缝）：whisper 转写的句间天然带小 gap
  /// （换气/词间停顿，如樱花草 77.7-80.0 → 80.7），字幕切换出现细缝。
  /// 打包时把 ≤2s 的句间 gap 归入前一句（endMs 延伸到下一句 startMs），
  /// 使相邻句严丝合缝；>2s 的间奏 gap 保留——跳过空白模式跳的就是这些
  /// 大空隙，不能吞掉。最后一句延伸到音频末尾。
  static ParsedLessonPackage package({
    required String lessonId,
    required String title,
    required List<DraftSentence> drafts,
    required List<String> translations,
    required Uint8List audioBytes,
    required String audioFileName,
    String language = 'en',
    VideoSource? video,
    int audioDurationMs = 0,
  }) {
    // 小 gap 无缝化：endMs 延伸到下一句 startMs（不动 startMs，不越过大 gap）。
    const seamGapMaxMs = 2000;
    final seamlessEnds = List<int>.generate(drafts.length, (i) {
      if (i == drafts.length - 1) {
        // 最后一句延伸到音频末尾（留 200ms 余量防越界断言）。
        return audioDurationMs > 0
            ? audioDurationMs - 200
            : drafts[i].endMs;
      }
      final nextStart = drafts[i + 1].startMs;
      return nextStart - drafts[i].endMs <= seamGapMaxMs
          ? nextStart
          : drafts[i].endMs;
    });
    final durationMs = (drafts.isEmpty ? 0 : seamlessEnds.last) + 1000;
    final manifest = LessonManifest(
      formatVersion: 1,
      lessonId: lessonId,
      title: title,
      language: language,
      durationMs: durationMs,
      sentenceCount: drafts.length,
      audioFile: audioFileName,
      sentenceFile: 'sentences.json',
      video: video,
    );
    final sentences = <Sentence>[
      for (var i = 0; i < drafts.length; i++)
        Sentence(
          // Same id shape as tool/whisper_to_lesson.py so PC and mobile
          // packages are indistinguishable.
          id:
              '${lessonId.substring(0, lessonId.length.clamp(0, 12))}-'
              '${(i + 1).toString().padLeft(3, '0')}',
          index: i,
          startMs: drafts[i].startMs,
          endMs: seamlessEnds[i],
          english: drafts[i].text,
          chinese: translations[i],
        ),
    ];
    return ParsedLessonPackage(
      manifest: manifest,
      sentences: sentences,
      audioBytes: audioBytes,
      audioFileName: audioFileName,
    );
  }
}
