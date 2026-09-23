import 'package:flutter/foundation.dart';

import '../models/sentence.dart';
import 'dictation_engine.dart';

/// 听写阶段。
enum DictationPhase {
  /// 录入中：字幕与中文全部锁定，逐句写，不揭答案。
  entering,

  /// 批改中：本段已提交，可以看 diff 与原文。
  reviewing,
}

/// 一句的录入状态。
class DictationEntry {
  DictationEntry({required this.sentenceIndex});

  /// 句在课程内的下标。
  final int sentenceIndex;

  /// 用户所写内容。
  String text = '';

  /// 用户是否明确点过「没听出来」。
  ///
  /// 这不是错误行为——原方法本来就允许「听不出的先空着」。
  bool markedUnknown = false;

  bool get isEmpty => text.trim().isEmpty;

  /// 算作已作答：写了东西，或明确标记没听出来。
  bool get isAnswered => !isEmpty || markedUnknown;

  /// 交给引擎的文本：明确留空时给空串。
  String get effectiveText => markedUnknown ? '' : text;
}

/// 听写会话状态机 —— 核心层（P1），纯本地、零网络。
///
/// 关键设计（对齐 08 与外部评审结论）：
///   * **句级录入、段级集中批改**：写完一句就跳下一句，绝不即时揭答案，
///     保证「先通听多遍 → 写完全篇 → 再对原文」的方法本体不被破坏。
///   * **留空是合法答案**：`markedUnknown` 与「写错了」不是一回事。
///   * **播放进度与训练进度分离**：本类只维护训练进度。
class DictationSession extends ChangeNotifier {
  DictationSession({
    required List<Sentence> sentences,
    this.segmentLength = 5,
    int initialSegment = 0,
  }) : assert(sentences.isNotEmpty, 'sentences must not be empty'),
       assert(segmentLength > 0, 'segmentLength must be > 0'),
       sentences = List<Sentence>.unmodifiable(sentences),
       _segmentIndex = initialSegment {
    _resetEntries();
  }

  /// 整课句子（只读）。
  final List<Sentence> sentences;

  /// 一段包含多少句。
  final int segmentLength;

  int _segmentIndex;
  int _cursor = 0;
  DictationPhase _phase = DictationPhase.entering;
  final Map<int, DictationEntry> _entries = <int, DictationEntry>{};
  final Map<int, DictationSegmentResult> _results = <int, DictationSegmentResult>{};

  // ------------------------------------------------------------------ 段

  /// 总段数。
  int get segmentCount =>
      (sentences.length + segmentLength - 1) ~/ segmentLength;

  /// 当前段序号（0 基）。
  int get segmentIndex => _segmentIndex;

  /// 当前段在整课中的起止（含头含尾）。
  int get segmentStart => _segmentIndex * segmentLength;

  int get segmentEndExclusive {
    final end = segmentStart + segmentLength;
    return end > sentences.length ? sentences.length : end;
  }

  int get sentenceCountInSegment => segmentEndExclusive - segmentStart;

  List<Sentence> get segmentSentences =>
      sentences.sublist(segmentStart, segmentEndExclusive);

  DictationPhase get phase => _phase;

  /// 录入阶段是否隐藏答案 —— UI 必须遵守。
  bool get shouldReveal => _phase == DictationPhase.reviewing;

  // -------------------------------------------------------------- 逐句录入

  /// 当前光标所在的段内下标（0 基）。
  int get cursor => _cursor;

  /// 当前句在课程内的下标。
  int get absoluteIndex => segmentStart + _cursor;

  Sentence get currentSentence => sentences[absoluteIndex];

  DictationEntry entryAt(int segmentOffset) {
    final abs = segmentStart + segmentOffset;
    return _entries[abs] ??= DictationEntry(sentenceIndex: abs);
  }

  DictationEntry get currentEntry => entryAt(_cursor);

  /// 段内已作答句数。
  int get answeredCount => List<int>.generate(
    sentenceCountInSegment,
    (i) => i,
  ).where((i) => entryAt(i).isAnswered).length;

  /// 段级进度 0~1。
  double get progress =>
      sentenceCountInSegment == 0 ? 0 : answeredCount / sentenceCountInSegment;

  /// 是否允许提交：每句都必须有交代（写了或点了没听出来）。
  bool get canSubmit =>
      _phase == DictationPhase.entering && answeredCount == sentenceCountInSegment;

  /// 写入某一句的内容。
  void setText(int segmentOffset, String text) {
    if (_phase == DictationPhase.reviewing) return; // 揭答案后禁止再改
    if (segmentOffset < 0 || segmentOffset >= sentenceCountInSegment) return;
    final entry = entryAt(segmentOffset);
    entry.text = text;
    entry.markedUnknown = false;
    notifyListeners();
  }

  /// 明确标记「没听出来」（合法答案，不视为乱写）。
  void markUnknown(int segmentOffset) {
    if (_phase == DictationPhase.reviewing) return;
    if (segmentOffset < 0 || segmentOffset >= sentenceCountInSegment) return;
    final entry = entryAt(segmentOffset);
    entry.text = '';
    entry.markedUnknown = true;
    notifyListeners();
  }

  /// 上/下一句。录入阶段只移动光标，**不揭任何答案**。
  void goTo(int segmentOffset) {
    if (segmentOffset < 0 || segmentOffset >= sentenceCountInSegment) return;
    _cursor = segmentOffset;
    notifyListeners();
  }

  void next() => goTo(_cursor + 1 > sentenceCountInSegment - 1 ? _cursor : _cursor + 1);

  void previous() => goTo(_cursor - 1 < 0 ? 0 : _cursor - 1);

  // ---------------------------------------------------------------- 批改

  /// 提交本段 → 一次性批改，进入 [DictationPhase.reviewing]。
  ///
  /// 返回段级结果；提交前未完成则返回 null。
  DictationSegmentResult? submitSegment() {
    if (!canSubmit) return null;
    final expected = segmentSentences
        .map((s) => s.english)
        .toList(growable: false);
    final actual = List<String>.generate(
      sentenceCountInSegment,
      (i) => entryAt(i).effectiveText,
    );

    final result = DictationEngine.compareSegment(
      expectedLines: expected,
      actualLines: actual,
    );
    _results[_segmentIndex] = result;
    _phase = DictationPhase.reviewing;
    notifyListeners();
    return result;
  }

  DictationSegmentResult? get currentResult => _results[_segmentIndex];

  /// 该句的比对结果（仅批改阶段可用）。
  DictationLineResult? lineResultAt(int segmentOffset) {
    final result = _results[_segmentIndex];
    if (result == null) return null;
    if (segmentOffset < 0 || segmentOffset >= result.lines.length) return null;
    return result.lines[segmentOffset];
  }

  // ------------------------------------------------------------ 段间流转

  bool get hasNextSegment => _segmentIndex < segmentCount - 1;

  bool get hasPreviousSegment => _segmentIndex > 0;

  /// 是否有任一段已完成批改。
  bool get hasAnyResult => _results.isNotEmpty;

  /// 全部已完成段落的结果（按段序）。
  List<DictationSegmentResult> get completedResults {
    final keys = _results.keys.toList()..sort();
    return keys.map((k) => _results[k]!).toList(growable: false);
  }

  /// 整课训练进度（已完成批改的段数 / 总段数）。
  double get trainingProgress =>
      segmentCount == 0 ? 0 : _results.length / segmentCount;

  /// 进入下一段（保留已批改的结果）。
  void goToSegment(int index) {
    if (index < 0 || index >= segmentCount) return;
    _segmentIndex = index;
    _cursor = 0;
    _resetEntries();
    final done = _results.containsKey(index);
    _phase = done ? DictationPhase.reviewing : DictationPhase.entering;
    notifyListeners();
  }

  void nextSegment() {
    if (!hasNextSegment) return;
    goToSegment(_segmentIndex + 1);
  }

  void previousSegment() {
    if (!hasPreviousSegment) return;
    goToSegment(_segmentIndex - 1);
  }

  /// 重写本段：清空录入与批改结果。
  void redoSegment() {
    _results.remove(_segmentIndex);
    _cursor = 0;
    _resetEntries();
    _phase = DictationPhase.entering;
    notifyListeners();
  }

  void _resetEntries() {
    for (final s in segmentSentences) {
      _entries[s.index] = DictationEntry(sentenceIndex: s.index);
    }
  }
}
