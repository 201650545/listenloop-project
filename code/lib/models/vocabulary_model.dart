/// 生词本两层模型 —— 附属层（`EPIC-04`），但**必须离线完整可用**。
///
/// 设计依据：`docs/02_工程架构与系统设计/10_生词本与Anki记忆卡设计.md` §十三。
///
/// **一句话区别**：
///   * [VocabularyItem]      = 「这个词是什么」   —— 1 份，判重键 [VocabularyItem.itemKey]
///   * [VocabularyOccurrence] = 「在哪儿遇到、当时发生了什么」 —— N 份，判重键
///     [VocabularyOccurrence.occurrenceKey]
///
/// 三条派生规则（本文件的实现契约）：
///   1. `status` 代表该词的整体学习状态，**不随单次证据自动升降**，只由显式动作转移；
///   2. `seenCount` 恒等于它挂载的 occurrence 数量；
///   3. **SRS 调度挂在 Item 级** —— 一个词一张卡，而不是一句一张卡。
library;

/// 词条形态：单字/单词，还是一个短语（`take off`）。
enum VocabularyKind {
  word,
  phrase;

  static VocabularyKind parse(String? raw) => VocabularyKind.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => VocabularyKind.word,
  );
}

/// 词条的整体学习状态。
///
/// ⚠️ 与诊断维度（听辨弱/语义弱/使用弱/形态弱）**不是一回事**，不要合并。
enum VocabularyStatus {
  /// 候选池：随手点存或刚产生证据，尚未确认要学。
  candidate,

  /// 正式学习队列：用户确认学习，或可靠证据 + 用户接受计划。
  learning,

  /// 已掌握。
  known,

  /// 用户主动忽略，不再出现。
  ignored;

  static VocabularyStatus parse(String? raw) =>
      VocabularyStatus.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => VocabularyStatus.candidate,
      );
}

/// 证据来源。
enum VocabularySource {
  /// 用户在积累模式里点词保存。
  tap,

  /// 听写错误带出来的（来自听写引擎）。
  dictation,

  /// AI 诊断产生。
  ai;

  static VocabularySource parse(String? raw) =>
      VocabularySource.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => VocabularySource.tap,
      );
}

/// 归一化词形 —— **Item 层判重的唯一依据**。
///
/// 规则：小写 → 撇号统一 → 去掉首尾非字母数字字符 → 压缩空白。
/// 保留词内撇号与连字符（`don't`、`mother-in-law` 不能被切开）。
///
/// 注意：这里**不展开缩写**。展开是听写比对的处理，会破坏用户看到的词形。
String normalizeTerm(String raw) {
  var s = raw
      .toLowerCase()
      .replaceAll('\u2019', "'")
      .replaceAll('\u2018', "'");
  // 词内保留 [a-z0-9'-]，其余（含标点、中文标点）视为分隔
  s = s.replaceAll(RegExp(r"[^a-z0-9'\-\s]"), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 去掉首尾的撇号/连字符残渣
  s = s.replaceAll(RegExp(r"^['\-\s]+|['\-\s]+$"), '');
  return s;
}

/// 一次上下文证据。
class VocabularyOccurrence {
  const VocabularyOccurrence({
    required this.id,
    required this.itemId,
    required this.lessonId,
    required this.lessonTitle,
    required this.sentenceId,
    required this.sentenceIndex,
    required this.sentenceText,
    required this.startMs,
    required this.endMs,
    required this.audioPath,
    required this.charStart,
    required this.charEnd,
    required this.source,
    this.dictationDiffType,
    this.expected,
    this.actual,
    this.uncertain = false,
    this.causeHints = const <String>[],
    required this.createdAt,
  }) : assert(charStart >= 0, 'charStart must be >= 0'),
       assert(charEnd >= charStart, 'charEnd must be >= charStart');

  final String id;
  final String itemId;

  final String lessonId;
  final String lessonTitle;
  final String sentenceId;
  final int sentenceIndex;
  final String sentenceText;

  /// 原声切片区间 —— 「回原声」跳转用。
  final int startMs;
  final int endMs;
  final String audioPath;

  /// 命中的字符区间（相对整句原文）—— 点词精度用。
  final int charStart;
  final int charEnd;

  final VocabularySource source;

  /// 听写带出来的证据（来自听写引擎的 diff 类型名），非听写来源时为 null。
  final String? dictationDiffType;
  final String? expected;
  final String? actual;

  /// 听写对齐不可靠时为 true —— 此时**不允许**派发精确词训练组件。
  final bool uncertain;

  /// 音变**提示**（弱读/连读/失爆/闪音）。永远只是推测，不是声学结论。
  final List<String> causeHints;

  final DateTime createdAt;

  /// Occurrence 层判重键：同一句、同一字符区间、同一个词，只算一次证据。
  ///
  /// 用户把同一个词在字幕里点了两下，不应产生两条证据，只应增加 `seenCount`。
  String get occurrenceKey =>
      '$itemId|$lessonId|$sentenceId|$charStart|$charEnd';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'itemId': itemId,
    'lessonId': lessonId,
    'lessonTitle': lessonTitle,
    'sentenceId': sentenceId,
    'sentenceIndex': sentenceIndex,
    'sentenceText': sentenceText,
    'startMs': startMs,
    'endMs': endMs,
    'audioPath': audioPath,
    'charStart': charStart,
    'charEnd': charEnd,
    'source': source.name,
    'dictationDiffType': dictationDiffType,
    'expected': expected,
    'actual': actual,
    'uncertain': uncertain,
    'causeHints': causeHints,
    'createdAt': createdAt.toIso8601String(),
  };

  static VocabularyOccurrence fromJson(Map<String, Object?> json) =>
      VocabularyOccurrence(
        id: json['id']! as String,
        itemId: json['itemId']! as String,
        lessonId: (json['lessonId'] ?? '') as String,
        lessonTitle: (json['lessonTitle'] ?? '') as String,
        sentenceId: (json['sentenceId'] ?? '') as String,
        sentenceIndex: (json['sentenceIndex'] ?? 0) as int,
        sentenceText: (json['sentenceText'] ?? '') as String,
        startMs: (json['startMs'] ?? 0) as int,
        endMs: (json['endMs'] ?? 0) as int,
        audioPath: (json['audioPath'] ?? '') as String,
        charStart: (json['charStart'] ?? 0) as int,
        charEnd: (json['charEnd'] ?? 0) as int,
        source: VocabularySource.parse(json['source'] as String?),
        dictationDiffType: json['dictationDiffType'] as String?,
        expected: json['expected'] as String?,
        actual: json['actual'] as String?,
        uncertain: (json['uncertain'] ?? false) as bool,
        causeHints: <String>[
          for (final h in (json['causeHints'] as List? ?? const <Object?>[]))
            h as String,
        ],
        createdAt:
            DateTime.tryParse((json['createdAt'] ?? '') as String) ??
            DateTime.now(),
      );
}

/// 词本体 —— 一个词/短语一份，**跨课程、跨句子累积**。
class VocabularyItem {
  VocabularyItem({
    required this.id,
    required this.surfaceForm,
    required this.kind,
    this.status = VocabularyStatus.candidate,
    this.englishDefinition,
    this.chineseGloss,
    this.aiUsageNote,
    required this.createdAt,
    required this.lastSeenAt,
    List<VocabularyOccurrence>? occurrences,
    List<String>? ankiCardIds,
  }) : occurrences = List<VocabularyOccurrence>.unmodifiable(
         occurrences ?? const <VocabularyOccurrence>[],
       ),
       ankiCardIds = List<String>.unmodifiable(ankiCardIds ?? const <String>[]);

  final String id;

  /// 用户实际看到并保存的表面形式（可能是 `take off`）。
  final String surfaceForm;

  final VocabularyKind kind;

  /// 整体学习状态。**不随单次证据自动升降**，只由显式动作转移。
  final VocabularyStatus status;

  final String? englishDefinition;
  final String? chineseGloss;

  /// AI 用法笔记。V1 可为空；**不得**用它当判重依据。
  final String? aiUsageNote;

  final DateTime createdAt;
  final DateTime lastSeenAt;

  /// 挂载的上下文证据。
  final List<VocabularyOccurrence> occurrences;

  /// 下游 SRS 卡 id —— **调度挂在 Item 级**。
  final List<String> ankiCardIds;

  /// Item 层判重键：归一化词形。跨课程、跨句子合并同一个词。
  String get itemKey => normalizeTerm(surfaceForm);

  /// 见到次数恒等于证据条数（派生规则 2）。
  int get seenCount => occurrences.length;

  bool get isCandidate => status == VocabularyStatus.candidate;

  /// 证据里是否含「可靠听写错误」——今日计划规则要读它。
  bool get hasReliableDictationEvidence => occurrences.any(
    (o) => o.source == VocabularySource.dictation && !o.uncertain,
  );

  /// 证据里是否存在对齐不可靠的听写 —— 存在时**禁止**派发精确词训练组件。
  bool get hasUncertainDictationEvidence => occurrences.any(
    (o) => o.source == VocabularySource.dictation && o.uncertain,
  );

  /// 只有「手动点存」、没有任何其它证据 —— 按 v1 规则**什么都不出**。
  bool get isTapOnly => occurrences.isNotEmpty &&
      occurrences.every((o) => o.source == VocabularySource.tap);

  /// 最近一条证据（用于展示与"回原声"）。
  VocabularyOccurrence? get latestOccurrence {
    if (occurrences.isEmpty) return null;
    var best = occurrences.first;
    for (final o in occurrences) {
      if (o.createdAt.isAfter(best.createdAt)) best = o;
    }
    return best;
  }

  /// 按显式动作转移状态（派生规则 1）。
  VocabularyItem withStatus(VocabularyStatus next) => copyWith(status: next);

  VocabularyItem copyWith({
    String? surfaceForm,
    VocabularyKind? kind,
    VocabularyStatus? status,
    String? englishDefinition,
    String? chineseGloss,
    String? aiUsageNote,
    DateTime? lastSeenAt,
    List<VocabularyOccurrence>? occurrences,
    List<String>? ankiCardIds,
  }) => VocabularyItem(
    id: id,
    surfaceForm: surfaceForm ?? this.surfaceForm,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    englishDefinition: englishDefinition ?? this.englishDefinition,
    chineseGloss: chineseGloss ?? this.chineseGloss,
    aiUsageNote: aiUsageNote ?? this.aiUsageNote,
    createdAt: createdAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    occurrences: occurrences ?? this.occurrences,
    ankiCardIds: ankiCardIds ?? this.ankiCardIds,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'surfaceForm': surfaceForm,
    'kind': kind.name,
    'status': status.name,
    'englishDefinition': englishDefinition,
    'chineseGloss': chineseGloss,
    'aiUsageNote': aiUsageNote,
    'createdAt': createdAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
    'ankiCardIds': ankiCardIds,
    'occurrences': [for (final o in occurrences) o.toJson()],
  };

  static VocabularyItem fromJson(Map<String, Object?> json) => VocabularyItem(
    id: json['id']! as String,
    surfaceForm: json['surfaceForm']! as String,
    kind: VocabularyKind.parse(json['kind'] as String?),
    status: VocabularyStatus.parse(json['status'] as String?),
    englishDefinition: json['englishDefinition'] as String?,
    chineseGloss: json['chineseGloss'] as String?,
    aiUsageNote: json['aiUsageNote'] as String?,
    createdAt:
        DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.now(),
    lastSeenAt:
        DateTime.tryParse((json['lastSeenAt'] ?? '') as String) ?? DateTime.now(),
    ankiCardIds: <String>[
      for (final c in (json['ankiCardIds'] as List? ?? const <Object?>[]))
        c as String,
    ],
    occurrences: <VocabularyOccurrence>[
      for (final o in (json['occurrences'] as List? ?? const <Object?>[]))
        VocabularyOccurrence.fromJson(
          (o as Map).cast<String, Object?>(),
        ),
    ],
  );
}
