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

  /// 中文（及日文）朗读的静音断句阈值：二年级课文语速慢、句间停顿长
  /// （实测 0.6-1.5 s，见 18 号 §四），按英语成人语速调校的 0.9 s 阈值
  /// 会把句内自然停顿也切断。中文流改用 1.3 s——真正的句尾停顿基本
  /// 都能保住，句内的换气停顿大多被放过。
  static const int kCjkGapBreakMs = 1300;

  static const int _maxWordsPerSentence = 35;
  static const int _minWordsToKeep = 5;
  /// Minimum words accumulated before a comma before a coordinating
  /// conjunction may end a draft. 8 keeps "I like apples, bananas, and
  /// oranges." intact while still splitting compound clauses like
  /// "…jeans, but the Greeks…". Because _minWordsToKeep is 5, an 8-word
  /// leading clause survives the fragment-merge pass.
  static const int _englishCommaMinWords = 8;
  /// FANBOYS coordinating conjunctions. A comma before one of these (with
  /// enough leading clause) marks a compound sentence — the natural spot to
  /// give each clause its own card. Subordinating conjunctions
  /// (when/while/if/because…) are deliberately excluded: "…Greece, when it
  /// came to music, things…" is one thought and should stay whole.
  static const Set<String> _coordinatingConjunctions = {
    'but', 'and', 'so', 'yet', 'or', 'nor', 'for',
  };
  static final RegExp _sentenceEndPattern = RegExp(
    r'''[.!?。！？]["')\]」』”’]?$''',
  );
  static final RegExp _cjkCharPattern = RegExp(
    r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]',
  );
  static final RegExp _cjkCommaPattern = RegExp(r'[、，,;；…—~～]');

  /// 课文朗读模式的单元边界标点：逗号/句号/分号/冒号/问叹号后即朗读单元。
  /// 顿号（、）刻意不在内——「有吃的、玩的」是一个朗读单元。
  static final RegExp _readingClauseEndPattern = RegExp(
    r'''[，,。！？；：…—]["')\]」』”’]?$''',
  );
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
  ///
  /// [gapBreakMs] 覆盖默认静音阈值；中文朗读调用方传 [kCjkGapBreakMs]。
  ///
  /// [readingMode]（课文朗读模式，2026-09-29 用户需求）：在常规规则之上，
  /// 每个 CJK 逗号/句号处都切开（顿号除外——「有吃的、玩的」是一个朗读
  /// 单元），并**跳过短句合并**——小学生早读要按「读到逗号截止」的短句
  /// 单句循环，合并正好会破坏它。
  static List<DraftSentence> segment(
    List<WordTimestamp> words, {
    int? gapBreakMs,
    bool readingMode = false,
  }) {
    if (words.isEmpty) return const [];
    final effectiveGapBreakMs = gapBreakMs ?? _gapBreakMs;
    final sentences = <DraftSentence>[];
    var current = <WordTimestamp>[];
    for (final word in words) {
      final wordText = word.word.trim();

      // English compound-clause break. Fires BEFORE the conjunction is added:
      // "…jeans, but the Greeks…" should split into "…jeans," and "but the
      // Greeks…", so the conjunction starts the second clause.
      // Subordinating conjunctions (when/while/if…) are excluded because
      // "…Greece, when it came to music…" is one thought.
      final prevWord =
          current.isNotEmpty ? current.last.word.trim() : '';
      final englishConnectorBreak =
          !_cjkCharPattern.hasMatch(wordText) &&
          prevWord.isNotEmpty &&
          prevWord.endsWith(',') &&
          _coordinatingConjunctions.contains(
            wordText.toLowerCase().replaceAll(RegExp(r'[,.]$'), ''),
          ) &&
          current.length >= _englishCommaMinWords;
      if (englishConnectorBreak) {
        final draft = _draftFrom(current);
        if (draft.text.trim().isNotEmpty) {
          sentences.add(draft);
        }
        current = [];
      }

      current.add(word);
      final sentenceDuration = current.last.endMs - current.first.startMs;
      final gapBreak =
          current.length > 1 &&
          word.startMs - current[current.length - 2].endMs >
              effectiveGapBreakMs;
      final punctBreak = _sentenceEndPattern.hasMatch(wordText);

      // 课文朗读模式：逗号/句号/分号/冒号处即朗读单元边界（顿号除外）。
      // 标点无论是否独立成词（whisper 通常把标点粘在前字上，sherpa
      // 偶尔单独吐标点 token）都要触发；朗读模式只对中文流启用，
      // 英文逗号不会走到这里。
      final clauseBreak =
          readingMode && _readingClauseEndPattern.hasMatch(wordText);

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
      if (punctBreak || gapBreak || clauseBreak || cjkCommaBreak ||
          durationCeilingBreak || longBreak) {
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
    // 课文朗读模式跳过：短朗读单元正是这个模式要保留的循环单位。
    final merged = <DraftSentence>[];
    if (readingMode) {
      merged.addAll(sentences);
    } else {
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
