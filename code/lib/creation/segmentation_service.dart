import 'package:flutter/foundation.dart';

import 'word_timestamp.dart';

/// Ports the PC pipeline's sentence rules 1:1 (tool/whisper_to_lesson.py,
/// transcribe_sentences): split at sentence punctuation, at a silence gap
/// > 0.9 s, or at ~35 words; merge fragments shorter than 5 words forward.
///
/// The segmenter consumes [WordTimestamp]s ONLY — it never knows which ASR
/// engine produced them (spec V1 §十六/§十七).
abstract final class SegmentationService {
  static const int _gapBreakMs = 900;
  static const int _maxWordsPerSentence = 35;
  static const int _minWordsToKeep = 5;
  static final RegExp _sentenceEndPattern = RegExp(
    r'''[.!?。！？]["')\]」』”’]?$''',
  );
  static final RegExp _cjkCharPattern = RegExp(
    r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]',
  );
  static final RegExp _cjkCommaPattern = RegExp(r'[、，,;；…—~～]');
  static final RegExp _hallucinationPattern = RegExp(
    r'([^\s，,。！？、]{1,6}[，,。！？、\s]*)\1{2,}',
  );

  /// Collapses pathological Whisper hallucination loops (e.g. "あ、あ、あ、あ、..." -> "あ、").
  static String cleanHallucination(String text) {
    var cleaned = text;
    while (_hallucinationPattern.hasMatch(cleaned)) {
      cleaned = cleaned.replaceAllMapped(_hallucinationPattern, (m) => m.group(1)!);
    }
    return cleaned;
  }

  /// Groups [words] into draft sentences.
  static List<DraftSentence> segment(List<WordTimestamp> words) {
    if (words.isEmpty) return const [];
    final sentences = <DraftSentence>[];
    var current = <WordTimestamp>[];
    for (final word in words) {
      current.add(word);
      final wordText = word.word.trim();
      final sentenceDuration = current.last.endMs - current.first.startMs;
      final gapBreak =
          current.length > 1 &&
          word.startMs - current[current.length - 2].endMs > _gapBreakMs;
      final punctBreak = _sentenceEndPattern.hasMatch(wordText);

      // CJK clause break: if sentence duration is at least 3.5s or contains >= 8 chars,
      // a comma/pause break is natural for listening comprehension.
      final cjkCommaBreak =
          _cjkCharPattern.hasMatch(wordText) &&
          sentenceDuration >= 3500 &&
          _cjkCommaPattern.hasMatch(wordText);

      // Duration hard ceiling: a sentence should never exceed 10-12s in a listening app.
      final durationCeilingBreak =
          (sentenceDuration >= 7500 && (gapBreak || _cjkCommaPattern.hasMatch(wordText))) ||
          sentenceDuration >= 11000;

      final longBreak = current.length >= _maxWordsPerSentence;
      if (punctBreak || gapBreak || cjkCommaBreak || durationCeilingBreak || longBreak) {
        final draft = _draftFrom(current);
        if (draft.text.trim().isNotEmpty) {
          sentences.add(draft);
        }
        current = [];
      }
    }
    if (current.isNotEmpty) {
      final draft = _draftFrom(current);
      if (draft.text.trim().isNotEmpty) {
        sentences.add(draft);
      }
    }

    // Merge fragments shorter than 5 words (or short CJK fragments) forward into the previous one.
    final merged = <DraftSentence>[];
    for (final sentence in sentences) {
      final isShort = _isFragment(sentence);
      if (merged.isNotEmpty && isShort) {
        final previous = merged.last;
        merged[merged.length - 1] = DraftSentence(
          startMs: previous.startMs,
          endMs: sentence.endMs > previous.endMs ? sentence.endMs : previous.endMs,
          text: _joinSentenceTexts(previous.text, sentence.text),
        );
      } else {
        merged.add(sentence);
      }
    }

    // Ensure strictly monotonic non-overlapping timestamps (§五十四 packaging safety).
    // ASR word boundaries across window seams or rapid speech can have jitter where
    // sentence[i].startMs < sentence[i-1].endMs. We reconcile any overlaps here.
    final sanitized = <DraftSentence>[];
    for (final s in merged) {
      if (sanitized.isEmpty) {
        sanitized.add(s);
        continue;
      }
      final prev = sanitized.last;
      var cur = s;
      if (cur.startMs < prev.endMs) {
        if (cur.endMs <= prev.endMs) {
          // Engulfed entirely inside the previous sentence: merge text into previous.
          sanitized[sanitized.length - 1] = DraftSentence(
            startMs: prev.startMs,
            endMs: prev.endMs,
            text: _joinSentenceTexts(prev.text, cur.text),
          );
          continue;
        }
        // Partial overlap: clamp cur.startMs to prev.endMs so they meet cleanly at the seam.
        cur = DraftSentence(
          startMs: prev.endMs,
          endMs: cur.endMs,
          text: cur.text,
        );
      }
      if (cur.endMs <= cur.startMs) {
        cur = DraftSentence(
          startMs: cur.startMs,
          endMs: cur.startMs + 500,
          text: cur.text,
        );
      }
      sanitized.add(cur);
    }
    return sanitized;
  }

  static bool _isFragment(DraftSentence sentence) {
    final text = sentence.text.trim();
    if (text.isEmpty) return true;
    final hasCjk = _cjkCharPattern.hasMatch(text);
    if (hasCjk) {
      // In Japanese/Chinese, an utterance ending with punctuation (。！？) is a
      // complete sentence.
      if (_sentenceEndPattern.hasMatch(text)) return false;
      final durationMs = sentence.endMs - sentence.startMs;
      if (durationMs >= 2200) return false;
      return text.length < 5 && durationMs < 1200;
    }
    final wordCount = text.split(RegExp(r'\s+')).length;
    return wordCount < _minWordsToKeep;
  }

  static String _joinSentenceTexts(String a, String b) {
    final trimA = a.trim();
    final trimB = b.trim();
    if (trimA.isEmpty) return trimB;
    if (trimB.isEmpty) return trimA;
    final lastA = trimA[trimA.length - 1];
    final firstB = trimB[0];
    if (_cjkCharPattern.hasMatch(lastA) || _cjkCharPattern.hasMatch(firstB)) {
      return '$trimA$trimB';
    }
    return '$trimA $trimB';
  }

  static DraftSentence _draftFrom(List<WordTimestamp> current) {
    final buffer = StringBuffer();
    for (var i = 0; i < current.length; i++) {
      final w = current[i].word;
      if (i > 0) {
        final prev = current[i - 1].word;
        final lastChar = prev.isNotEmpty ? prev[prev.length - 1] : '';
        final firstChar = w.isNotEmpty ? w[0] : '';
        if (!_cjkCharPattern.hasMatch(lastChar) &&
            !_cjkCharPattern.hasMatch(firstChar)) {
          buffer.write(' ');
        }
      }
      buffer.write(w);
    }
    return DraftSentence(
      startMs: current.first.startMs,
      endMs: current.last.endMs,
      text: buffer.toString().trim(),
    );
  }
}

/// A sentence produced by segmentation, before translation and packaging.
@immutable
class DraftSentence {
  const DraftSentence({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int startMs;
  final int endMs;
  final String text;
}
