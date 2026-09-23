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

/// 复习评级 —— 四档，与既有闪卡（`AnkiRating`）**同一套手感**。
///
/// 为什么另立枚举而不是直接复用 `AnkiRating`：那套属于旧的按句闪卡
/// （`AnkiCard`，判重键是课程+句号），生词本属另一条数据链。两者并存
/// 期间保持解耦，等旧链下线再统一。
enum ReviewRating {
  /// 忘了 —— 重置连击，10 分钟后再来。
  again,

  /// 想得吃力 —— 间隔小幅增长。
  hard,

  /// 想起来了 —— 走标准 SM-2 递进。
  good,

  /// 太简单 —— 间隔额外奖励。
  easy;

  static ReviewRating parse(String? raw) => ReviewRating.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => ReviewRating.good,
  );

  /// 是否算"通过了这次复习"（用于练习记录里的 passed）。
  bool get isPass => this != ReviewRating.again;
}

/// Item 级 SRS 调度状态（派生规则 3：**调度挂在 Item 级，一个词一张卡**）。
///
/// 算法沿用既有实现（SM-2 简化版）：Again 10 分钟、Good 首次 1 天/二次 3 天、
/// Easy 首次 3 天/二次 7 天、ease 夹在 1.3~3.0、间隔 ≥21 天视为已掌握。
/// 手感与旧闪卡一致，避免同一个 App 里两种复习节奏。
class VocabularySrs {
  const VocabularySrs({
    required this.dueAt,
    this.reviews = 0,
    this.intervalDays = 0,
    this.easeFactor = 2.5,
    this.lapses = 0,
    this.lastReviewedAt,
  });

  /// 建卡：刚升入学习队列、还没复习过。
  factory VocabularySrs.newCard(DateTime now) => VocabularySrs(dueAt: now);

  final DateTime dueAt;

  /// 连续通过次数（Again 归零）。
  final int reviews;

  /// 当前间隔（天）。
  final double intervalDays;

  final double easeFactor;

  /// 遗忘次数 —— 旧闪卡缺这个字段，是 07 号文档点出的缺陷之一。
  final int lapses;

  final DateTime? lastReviewedAt;

  bool get isNew => lastReviewedAt == null;

  /// 间隔超过 21 天视为已掌握（与既有实现同阈值）。
  bool get isMastered => intervalDays >= 21.0;

  bool isDue(DateTime now) => !dueAt.isAfter(now);

  /// 应用一次评级，返回新的调度状态。
  VocabularySrs applyRating(ReviewRating rating, {DateTime? now}) {
    final stamp = now ?? DateTime.now();
    var nextReviews = reviews;
    var nextInterval = intervalDays;
    var nextEase = easeFactor;
    var nextLapses = lapses;

    switch (rating) {
      case ReviewRating.again:
        nextReviews = 0;
        nextInterval = 0;
        nextEase = (easeFactor - 0.2) < 1.3 ? 1.3 : (easeFactor - 0.2);
        nextLapses++;
      case ReviewRating.hard:
        nextInterval = intervalDays <= 0 ? 1.0 : intervalDays * 1.2;
        nextEase = (easeFactor - 0.15) < 1.3 ? 1.3 : (easeFactor - 0.15);
      case ReviewRating.good:
        if (reviews == 0) {
          nextInterval = 1.0;
        } else if (reviews == 1) {
          nextInterval = 3.0;
        } else {
          nextInterval = intervalDays * easeFactor;
        }
        nextReviews++;
      case ReviewRating.easy:
        if (reviews == 0) {
          nextInterval = 3.0;
        } else if (reviews == 1) {
          nextInterval = 7.0;
        } else {
          nextInterval = intervalDays * easeFactor * 1.3;
        }
        nextReviews++;
        nextEase = (easeFactor + 0.15) > 3.0 ? 3.0 : (easeFactor + 0.15);
    }

    final nextDue = rating == ReviewRating.again
        ? stamp.add(const Duration(minutes: 10))
        : stamp.add(Duration(hours: (nextInterval * 24).round()));

    return VocabularySrs(
      dueAt: nextDue,
      reviews: nextReviews,
      intervalDays: nextInterval,
      easeFactor: nextEase,
      lapses: nextLapses,
      lastReviewedAt: stamp,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'dueAt': dueAt.toIso8601String(),
    'reviews': reviews,
    'intervalDays': intervalDays,
    'easeFactor': easeFactor,
    'lapses': lapses,
    'lastReviewedAt': lastReviewedAt?.toIso8601String(),
  };

  static VocabularySrs fromJson(Map<String, Object?> json) => VocabularySrs(
    dueAt:
        DateTime.tryParse((json['dueAt'] ?? '') as String) ?? DateTime.now(),
    reviews: (json['reviews'] as num?)?.toInt() ?? 0,
    intervalDays: (json['intervalDays'] as num?)?.toDouble() ?? 0,
    easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
    lapses: (json['lapses'] as num?)?.toInt() ?? 0,
    lastReviewedAt: DateTime.tryParse(
      (json['lastReviewedAt'] ?? '') as String? ?? '',
    ),
  );
}

/// 一次学习组件的执行记录 —— **Item 级**，不是上下文证据。
///
/// 为什么不复用 [VocabularyOccurrence]：occurrence 的语义是「在哪儿遇到」，
/// 判重键是 `(课程, 句子, 字符区间)`。而练习是**对词条的动作**，
/// 同一处反复练同一次会被判重键吞掉 —— 但「练了三次仍然错」恰恰是
/// 最该留下的信息。所以学习行为单独记在 [VocabularyItem.drills] 里。
class VocabularyDrillLog {
  const VocabularyDrillLog({
    required this.component,
    required this.passed,
    required this.createdAt,
    this.detail,
  });

  /// 组件名（`StudyComponent.name`）。**存字符串不存枚举** ——
  /// 生词本属附属层，不该因为训练层增删组件而无法解析旧存档。
  final String component;

  final bool passed;

  /// 用户实际输入（Cloze / 听写），供复盘。
  final String? detail;

  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'component': component,
    'passed': passed,
    'detail': detail,
    'createdAt': createdAt.toIso8601String(),
  };

  static VocabularyDrillLog fromJson(Map<String, Object?> json) =>
      VocabularyDrillLog(
        component: (json['component'] ?? '') as String,
        passed: json['passed'] == true,
        detail: json['detail'] as String?,
        createdAt:
            DateTime.tryParse((json['createdAt'] ?? '') as String) ??
            DateTime.now(),
      );

  @override
  String toString() =>
      'VocabularyDrillLog($component, ${passed ? 'pass' : 'fail'})';
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
    List<VocabularyDrillLog>? drills,
    List<String>? ankiCardIds,
    this.srs,
  }) : occurrences = List<VocabularyOccurrence>.unmodifiable(
         occurrences ?? const <VocabularyOccurrence>[],
       ),
       drills = List<VocabularyDrillLog>.unmodifiable(
         drills ?? const <VocabularyDrillLog>[],
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

  /// 学习组件的执行记录（Item 级，不做判重）。
  final List<VocabularyDrillLog> drills;

  /// SRS 调度状态 —— **一个词一张卡**（派生规则 3）。
  ///
  /// null 表示"还没有卡"（刚进候选池、或还没升入学习队列）。
  final VocabularySrs? srs;

  /// 下游 SRS 卡 id —— **调度挂在 Item 级**。
  final List<String> ankiCardIds;

  /// 最近一次练习记录。
  ///
  /// ⚠️ 用**追加顺序**而不是 `createdAt` 排序：列表只增不改，
  /// 顺序天然就是时间顺序。而在测试或快速连点时，几条记录的
  /// `createdAt` 会落在同一毫秒，按时间比较的结果是不确定的
  /// （这个坑是测试抓出来的）。
  VocabularyDrillLog? get lastDrill => drills.isEmpty ? null : drills.last;

  /// 某个组件连续通过了几次（从最近往前数，跳过其它组件的记录）。
  ///
  /// 与 [lastDrill] 同理，用追加顺序倒着数。
  int consecutivePasses(String component) {
    var count = 0;
    for (final d in drills.reversed) {
      if (d.component != component) continue;
      if (!d.passed) break;
      count++;
    }
    return count;
  }

  /// 某个组件失败过几次 —— 用于给出"这个词还不行"的提示。
  int failCount(String component) =>
      drills.where((d) => d.component == component && !d.passed).length;

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
  ///
  /// 与 [lastDrill] 同一口径：证据列表只增不改，追加顺序即时间顺序 ——
  /// 不按 `createdAt` 比较，避免同毫秒记录的排序不确定。
  VocabularyOccurrence? get latestOccurrence =>
      occurrences.isEmpty ? null : occurrences.last;

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
    List<VocabularyDrillLog>? drills,
    List<String>? ankiCardIds,
    VocabularySrs? srs,
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
    drills: drills ?? this.drills,
    ankiCardIds: ankiCardIds ?? this.ankiCardIds,
    srs: srs ?? this.srs,
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
    'drills': [for (final d in drills) d.toJson()],
    'srs': srs?.toJson(),
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
    drills: <VocabularyDrillLog>[
      for (final d in (json['drills'] as List? ?? const <Object?>[]))
        VocabularyDrillLog.fromJson((d as Map).cast<String, Object?>()),
    ],
    srs: json['srs'] == null
        ? null
        : VocabularySrs.fromJson((json['srs']! as Map).cast<String, Object?>()),
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
