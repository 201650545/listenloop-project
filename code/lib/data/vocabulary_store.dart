import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vocabulary_model.dart';
import '../training/lemma_normalizer.dart';

/// 生词本存储 —— 两层模型的**判重与聚合**都收在这里。
///
/// 设计依据：`docs/02_工程架构与系统设计/10_生词本与Anki记忆卡设计.md` §十三。
///
/// 判重分两级，这是整个改造的技术核心：
///   * **Item 层**：按 [normalizeTerm] 归一化词形合并 —— 跨课程、跨句子同一个词只占一份；
///   * **Occurrence 层**：按 `(lessonId, sentenceId, charStart, charEnd)` 判重 ——
///     同一句里同一个词点两下**不会**产生第二条证据，只增加 `seenCount`。
///
/// 现状缺陷对照：`AiGovernorService.createAnkiCardFromSentence()` 按
/// `lessonId + sentenceIndex` 判重，导致一句里第二个生词会覆盖第一个。
/// 本存储不复用那套逻辑。
///
/// 全内存 + JSON 序列化，**不依赖网络与 AI**。
///
/// 持久化走 `SharedPreferences`（与 `AiGovernorService` 的弱点/Anki 卡同一套打法）：
/// 调 [load] 装载一次，之后的每次变更自动落盘。订阅者（精听页 / 生词本页）
/// 应当共用**同一个实例**，否则两边会各存一份。
class VocabularyStore extends ChangeNotifier {
  VocabularyStore({
    List<VocabularyItem>? initial,
    bool persist = true,
    SharedPreferences? preferences,
  }) : _autoPersist = persist,
       _prefs = preferences {
    if (initial != null) {
      for (final item in initial) {
        _items[item.id] = item;
      }
    }
    _reindexCounters();
  }

  /// 落盘键 —— 与 `listenloop:` 前缀的既有偏好保持一致。
  static const String storageKey = 'listenloop:vocab_items';

  final Map<String, VocabularyItem> _items = <String, VocabularyItem>{};
  int _itemSeq = 0;
  int _occurrenceSeq = 0;

  final bool _autoPersist;
  SharedPreferences? _prefs;
  bool _loaded = false;

  /// 写盘串行化，避免并发写产生交错覆盖。
  Future<void> _writeChain = Future<void>.value();

  /// 从磁盘装载 —— **幂等**，重复调用只生效一次。
  ///
  /// 不做磁盘 IO 失败即抛：测试环境没有插件实现时静默降级为纯内存。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = _prefs ?? await SharedPreferences.getInstance();
      _prefs = sp;
      final raw = sp.getStringList(storageKey) ?? const <String>[];
      if (raw.isEmpty) return;
      var changed = false;
      for (final entry in raw) {
        try {
          final item = VocabularyItem.fromJson(
            (jsonDecode(entry) as Map).cast<String, Object?>(),
          );
          _items[item.id] = item;
          changed = true;
        } catch (e) {
          debugPrint('[VocabularyStore] skip malformed item: $e');
        }
      }
      if (!changed) return;
      _reindexCounters();
      notifyListeners();
      // 13 号 §四：装载后跑一次 lemma 迁移（幂等，打过标记即跳过）。
      await migrateToLemmaV2();
    } catch (e) {
      debugPrint('[VocabularyStore] load failed (memory-only): $e');
    }
  }

  void _schedulePersist() {
    if (!_autoPersist) return;
    _writeChain = _writeChain.then((_) => _persist()).catchError((Object e) {
      debugPrint('[VocabularyStore] persist failed: $e');
    });
  }

  Future<void> _persist() async {
    try {
      final sp = _prefs ?? await SharedPreferences.getInstance();
      _prefs = sp;
      final payload = <String>[
        for (final item in _items.values) jsonEncode(item.toJson()),
      ];
      await sp.setStringList(storageKey, payload);
    } catch (e) {
      debugPrint('[VocabularyStore] persist failed (memory-only): $e');
    }
  }

  /// 立即把当前状态写盘 —— 供测试与"退出前"场景使用。
  Future<void> flush() => _schedulePersistAndWait();

  Future<void> _schedulePersistAndWait() {
    _schedulePersist();
    return _writeChain;
  }

  /// 全部词条，按最近见到倒序。
  List<VocabularyItem> get items {
    final out = _items.values.toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return List<VocabularyItem>.unmodifiable(out);
  }

  int get itemCount => _items.length;

  /// 仍在候选池、尚未进入正式学习队列的词条数。
  int get candidateCount =>
      _items.values.where((i) => i.isCandidate).length;

  int get learningCount =>
      _items.values.where((i) => i.status == VocabularyStatus.learning).length;

  int get knownCount =>
      _items.values.where((i) => i.status == VocabularyStatus.known).length;

  int get ignoredCount =>
      _items.values.where((i) => i.status == VocabularyStatus.ignored).length;

  /// 按状态取词条（null 表示「全部」），保持最近见到倒序。
  List<VocabularyItem> byStatus(VocabularyStatus? status) => status == null
      ? items
      : List<VocabularyItem>.unmodifiable(
          items.where((i) => i.status == status),
        );

  /// 是否已有该词的词条（跨课程合并的口径）。
  bool containsSurface(String surface) => itemBySurface(surface) != null;

  VocabularyItem? itemById(String id) => _items[id];

  /// 按归一化词形查词条（跨课程合并的公开查询口，kind 未知）。
  ///
  /// 13 号 §四：三段优先级 —— word 的 lemma 键 → phrase 键空间 →
  /// 归一化原形兜底。word 命中优先（附属动作以词为中心）。
  VocabularyItem? itemBySurface(String surface) {
    final normalized = normalizeTerm(surface);
    final wordKey = lemmaKey(normalized);
    final phraseKey = 'p:$normalized';
    VocabularyItem? fallback;
    for (final item in _items.values) {
      if (item.itemKey == wordKey) return item;
      if (fallback == null &&
          (item.itemKey == phraseKey || item.itemKey == normalized)) {
        fallback = item;
      }
    }
    return fallback;
  }

  /// 该位置是否已保存 —— 字幕高亮要用。
  bool isSaved({
    required String lessonId,
    required String sentenceId,
    required int charStart,
    required int charEnd,
  }) =>
      _findOccurrence(lessonId, sentenceId, charStart, charEnd) != null;

  /// 保存一次上下文证据（幂等）。
  ///
  /// 已存在同一位置的证据时直接返回既有词条，**不重复生成**。
  VocabularyItem saveOccurrence({
    required String surface,
    required VocabularyKind kind,
    required String lessonId,
    required String lessonTitle,
    required String sentenceId,
    required int sentenceIndex,
    required String sentenceText,
    required int startMs,
    required int endMs,
    required String audioPath,
    required int charStart,
    required int charEnd,
    VocabularySource source = VocabularySource.tap,
    String? dictationDiffType,
    String? expected,
    String? actual,
    bool uncertain = false,
    List<String> causeHints = const <String>[],
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();

    // ① Item 层：按归并键找已有词条（kind 定键空间 —— 13 号 §四/§五）
    final mergeKey = vocabularyMergeKey(surface, kind);
    VocabularyItem? item;
    for (final candidate in _items.values) {
      if (candidate.itemKey == mergeKey) {
        item = candidate;
        break;
      }
    }
    final lemma = kind == VocabularyKind.word ? lemmaKey(surface) : null;

    item ??= VocabularyItem(
      id: 'voc_${++_itemSeq}',
      surfaceForm: surface,
      kind: kind,
      lemma: lemma,
      createdAt: stamp,
      lastSeenAt: stamp,
    );

    // ② Occurrence 层：同位置已存在则不重复记
    final existing = _findOccurrence(lessonId, sentenceId, charStart, charEnd);
    if (existing != null) {
      _items[item.id] = item; // 首次调用时把新建的词条落库
      notifyListeners();
      _schedulePersist();
      return item;
    }

    final occurrence = VocabularyOccurrence(
      id: 'occ_${++_occurrenceSeq}',
      itemId: item.id,
      lessonId: lessonId,
      lessonTitle: lessonTitle,
      sentenceId: sentenceId,
      sentenceIndex: sentenceIndex,
      sentenceText: sentenceText,
      startMs: startMs,
      endMs: endMs,
      audioPath: audioPath,
      charStart: charStart,
      charEnd: charEnd,
      source: source,
      dictationDiffType: dictationDiffType,
      expected: expected,
      actual: actual,
      uncertain: uncertain,
      causeHints: causeHints,
      lemma: lemma,
      createdAt: stamp,
    );

    // 新生成一条证据时刷新最近见到时间；重复点击不会走到这里。
    // 主卡的 lemma 缺失（旧档未迁移场景）时顺手补上 —— 保守回填。
    item = item.copyWith(
      lemma: item.lemma ?? lemma,
      lastSeenAt: stamp,
      occurrences: <VocabularyOccurrence>[...item.occurrences, occurrence],
    );
    _items[item.id] = item;
    notifyListeners();
    _schedulePersist();
    return item;
  }

  /// 点一下保存 / 再点取消。
  ///
  /// 返回 true 表示**现在是已保存**，false 表示刚被取消。
  /// 取消后若该词条已无任何证据，词条本身一并移除 —— 不留空壳。
  bool toggleOccurrence({
    required String surface,
    required VocabularyKind kind,
    required String lessonId,
    required String lessonTitle,
    required String sentenceId,
    required int sentenceIndex,
    required String sentenceText,
    required int startMs,
    required int endMs,
    required String audioPath,
    required int charStart,
    required int charEnd,
    DateTime? now,
  }) {
    final existing = _findOccurrence(lessonId, sentenceId, charStart, charEnd);
    if (existing != null) {
      removeOccurrence(existing.itemId, existing.id);
      return false;
    }
    saveOccurrence(
      surface: surface,
      kind: kind,
      lessonId: lessonId,
      lessonTitle: lessonTitle,
      sentenceId: sentenceId,
      sentenceIndex: sentenceIndex,
      sentenceText: sentenceText,
      startMs: startMs,
      endMs: endMs,
      audioPath: audioPath,
      charStart: charStart,
      charEnd: charEnd,
      now: now,
    );
    return true;
  }

  /// 删除一条证据；词条没有证据后自动移除。
  void removeOccurrence(String itemId, String occurrenceId) {
    final item = _items[itemId];
    if (item == null) return;
    final rest = item.occurrences
        .where((o) => o.id != occurrenceId)
        .toList(growable: false);
    if (rest.isEmpty) {
      _items.remove(itemId);
    } else {
      _items[itemId] = item.copyWith(occurrences: rest, lastSeenAt: DateTime.now());
    }
    notifyListeners();
    _schedulePersist();
  }

  /// 记录一次学习组件的执行结果（§14.1 硬约束 ③：执行后必须回写证据）。
  ///
  /// 走 [VocabularyItem.drills] 而**不是** occurrence —— 练习是"对词条的动作"，
  /// occurrence 的判重键是上下文位置，同一处反复练会被吞掉。
  ///
  /// 刻意**不动** `lastSeenAt`：那是"最近见到"的语义（列表按它排序），
  /// 练一次不该把这个词顶到列表最前面。
  VocabularyItem? recordDrill({
    required String itemId,
    required String component,
    required bool passed,
    String? detail,
    DateTime? now,
  }) {
    final item = _items[itemId];
    if (item == null) return null;
    final updated = item.copyWith(
      drills: <VocabularyDrillLog>[
        ...item.drills,
        VocabularyDrillLog(
          component: component,
          passed: passed,
          detail: detail,
          createdAt: now ?? DateTime.now(),
        ),
      ],
    );
    _items[itemId] = updated;
    notifyListeners();
    _schedulePersist();
    return updated;
  }

  /// 显式转移学习状态（派生规则 1：状态不随单次证据自动升降）。
  void setStatus(String itemId, VocabularyStatus status) {
    final item = _items[itemId];
    if (item == null || item.status == status) return;
    _items[itemId] = item.withStatus(status);
    notifyListeners();
    _schedulePersist();
  }

  /// 把候选词升入正式学习队列（用户主动确认）。
  void startLearning(String itemId) => setStatus(itemId, VocabularyStatus.learning);

  void markKnown(String itemId) => setStatus(itemId, VocabularyStatus.known);

  void ignore(String itemId) => setStatus(itemId, VocabularyStatus.ignored);

  /// 记录一次闪卡复习（Item 级 SRS，**一个词一张卡**）。
  ///
  /// 同时留一条练习记录：SRS 只记"下次什么时候来"，而评级历史
  /// （什么时候忘过、忘了多少次）对理解这个词真正有价值。
  VocabularyItem? recordReview({
    required String itemId,
    required ReviewRating rating,
    DateTime? now,
  }) {
    final item = _items[itemId];
    if (item == null) return null;
    final stamp = now ?? DateTime.now();
    // 首次复习 = 建卡；之后在既有状态上递进。
    final base = item.srs ?? VocabularySrs.newCard(stamp);
    final updated = item.copyWith(
      srs: base.applyRating(rating, now: stamp),
      drills: <VocabularyDrillLog>[
        ...item.drills,
        VocabularyDrillLog(
          component: 'srsReview',
          passed: rating.isPass,
          detail: rating.name,
          createdAt: stamp,
        ),
      ],
    );
    _items[itemId] = updated;
    notifyListeners();
    _schedulePersist();
    return updated;
  }

  /// 到期需要复习的词条（已有 SRS 卡且已到期），按到期时间升序。
  ///
  /// 配额（新卡 5 / 复习 30）由调用方施加 —— 存储层只回答"哪些到期了"。
  List<VocabularyItem> dueForReview({DateTime? now}) {
    final stamp = now ?? DateTime.now();
    final due = <VocabularyItem>[];
    for (final item in _items.values) {
      final srs = item.srs;
      if (srs == null) continue;
      // 与 VocabularyReviewQueue 同一口径：候选池与已忽略都不催复习
      if (item.status == VocabularyStatus.candidate) continue;
      if (item.status == VocabularyStatus.ignored) continue;
      if (srs.isDue(stamp)) due.add(item);
    }
    due.sort((a, b) => a.srs!.dueAt.compareTo(b.srs!.dueAt));
    return due;
  }

  /// 还没有卡、但已在学习队列里的词 —— 首次复习即为建卡。
  ///
  /// **候选池不进复习**：还没确认要学，不该背复习债。
  List<VocabularyItem> newReviewCards() {
    final fresh = <VocabularyItem>[];
    for (final item in _items.values) {
      if (item.srs != null) continue;
      if (item.status != VocabularyStatus.learning &&
          item.status != VocabularyStatus.known) {
        continue;
      }
      fresh.add(item);
    }
    fresh.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return fresh;
  }

  /// 清空全部内容并落盘（重置用；测试与"重新开始"）。
  void clear() {
    _items.clear();
    _itemSeq = 0;
    _occurrenceSeq = 0;
    notifyListeners();
    _schedulePersist();
  }

  // ------------------------------------------------------------ 序列化

  Map<String, Object?> toJson() => <String, Object?>{
    'items': [for (final i in _items.values) i.toJson()],
  };

  static VocabularyStore fromJson(Map<String, Object?> json) {
    final raw = json['items'] as List? ?? const <Object?>[];
    return VocabularyStore(
      initial: <VocabularyItem>[
        for (final e in raw)
          VocabularyItem.fromJson((e as Map).cast<String, Object?>()),
      ],
    );
  }

  // ------------------------------------------------------------ 内部

  VocabularyOccurrence? _findOccurrence(
    String lessonId,
    String sentenceId,
    int charStart,
    int charEnd,
  ) {
    for (final item in _items.values) {
      for (final o in item.occurrences) {
        if (o.lessonId == lessonId &&
            o.sentenceId == sentenceId &&
            o.charStart == charStart &&
            o.charEnd == charEnd) {
          return o;
        }
      }
    }
    return null;
  }

  /// 装载既有数据后把自增游标推到最大，避免新建 id 撞车。
  void _reindexCounters() {
    var itemMax = 0;
    var occMax = 0;
    final itemPattern = RegExp(r'^voc_(\d+)$');
    final occPattern = RegExp(r'^occ_(\d+)$');
    for (final item in _items.values) {
      final m = itemPattern.firstMatch(item.id);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (n > itemMax) itemMax = n;
      }
      for (final o in item.occurrences) {
        final om = occPattern.firstMatch(o.id);
        if (om != null) {
          final n = int.parse(om.group(1)!);
          if (n > occMax) occMax = n;
        }
      }
    }
    _itemSeq = itemMax;
    _occurrenceSeq = occMax;
  }

  // ------------------------------------------------------------ lemma 迁移

  /// 迁移标记 —— 打过就永不重跑（13 号 §四）。
  static const String _lemmaMigratedKey = 'listenloop:vocab_lemma_migrated';

  /// 迁移前快照键 —— 出问题整包恢复的兜底。
  static const String _backupKey = 'listenloop:vocab_items_backup_pre_lemma';

  /// 一次性迁移：按 lemma 归并既有词条（13 号 §四，郭老师 2026-09-25 拍板
  /// 方案 A + 快照兜底 + 启动时自动）。
  ///
  /// * 迁移前把整个 store JSON 快照进 [\_backupKey]；
  /// * 主卡 = 组内 createdAt 最早者；occurrences / drills 全部并入（不丢证据）；
  /// * status 取组内最高（known > learning > candidate；ignored 独立保留）；
  /// * srs 保留 reviews + lapses 更大的一张；
  /// * 迁移过的旧 occurrence 顺手补 lemma 字段；
  /// * 返回 true 表示本轮确实迁移了（幂等：打过标记直接 false）。
  Future<bool> migrateToLemmaV2() async {
    final sp = _prefs ?? await SharedPreferences.getInstance();
    _prefs = sp;
    if (sp.getBool(_lemmaMigratedKey) ?? false) return false;

    if (_items.isNotEmpty) {
      final snapshot = <String>[
        for (final item in _items.values) jsonEncode(item.toJson()),
      ];
      await sp.setStringList(_backupKey, snapshot);
    }

    final merged = mergeByLemma(_items.values.toList(growable: false));
    _items
      ..clear()
      ..addEntries([for (final i in merged) MapEntry(i.id, i)]);
    _reindexCounters();
    await sp.setBool(_lemmaMigratedKey, true);
    _schedulePersist();
    notifyListeners();
    return true;
  }

  /// 归并纯函数（13 号 §四 的合并规则，`@visibleForTesting` 供表驱动测试）。
  @visibleForTesting
  static List<VocabularyItem> mergeByLemma(List<VocabularyItem> items) {
    final groups = <String, List<VocabularyItem>>{};
    for (final item in items) {
      final key = vocabularyMergeKey(item.surfaceForm, item.kind);
      (groups[key] ??= <VocabularyItem>[]).add(item);
    }

    final out = <VocabularyItem>[];
    for (final entry in groups.entries) {
      final groupKey = entry.key;
      final group = entry.value;
      if (group.length == 1) {
        out.add(_backfillLemma(group.single));
        continue;
      }
      final sorted = [...group]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final primary = sorted.first;

      var seen = 0;
      var lapses = 0;
      VocabularySrs? srs;
      for (final it in group) {
        final s = it.srs;
        if (s == null) continue;
        if (s.reviews + s.lapses >= seen + lapses) {
          srs = s;
          seen = s.reviews;
          lapses = s.lapses;
        }
      }

      final status = _highestStatus(group);
      final occurrences = <VocabularyOccurrence>[];
      final usedIds = <String>{};
      for (final it in sorted) {
        for (final o in it.occurrences) {
          var id = o.id;
          while (usedIds.contains(id)) {
            id = '${id}m';
          }
          usedIds.add(id);
          occurrences.add(
            VocabularyOccurrence(
              id: id,
              itemId: primary.id,
              lessonId: o.lessonId,
              lessonTitle: o.lessonTitle,
              sentenceId: o.sentenceId,
              sentenceIndex: o.sentenceIndex,
              sentenceText: o.sentenceText,
              startMs: o.startMs,
              endMs: o.endMs,
              audioPath: o.audioPath,
              charStart: o.charStart,
              charEnd: o.charEnd,
              source: o.source,
              dictationDiffType: o.dictationDiffType,
              expected: o.expected,
              actual: o.actual,
              uncertain: o.uncertain,
              causeHints: o.causeHints,
              lemma: primary.kind == VocabularyKind.word
              ? (o.lemma ?? groupKey)
              : null,
              createdAt: o.createdAt,
            ),
          );
        }
      }

      out.add(
        VocabularyItem(
          id: primary.id,
          surfaceForm: primary.surfaceForm,
          kind: primary.kind,
          status: status,
          englishDefinition: _firstNonEmpty(group, (i) => i.englishDefinition),
          chineseGloss: _firstNonEmpty(group, (i) => i.chineseGloss),
          aiUsageNote: _firstNonEmpty(group, (i) => i.aiUsageNote),
          lemma: primary.kind == VocabularyKind.word
              ? lemmaKey(primary.surfaceForm)
              : null,
          createdAt: primary.createdAt,
          lastSeenAt: group
              .map((i) => i.lastSeenAt)
              .reduce((a, b) => a.isAfter(b) ? a : b),
          occurrences: occurrences,
          drills: [
            for (final it in sorted) ...it.drills,
          ],
          ankiCardIds: [
            for (final it in sorted) ...it.ankiCardIds,
          ],
          srs: srs,
        ),
      );
    }
    return out;
  }

  static String? _firstNonEmpty(
    List<VocabularyItem> group,
    String? Function(VocabularyItem) pick,
  ) {
    for (final i in group) {
      final v = pick(i);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static VocabularyStatus _highestStatus(List<VocabularyItem> group) {
    var best = VocabularyStatus.candidate;
    var sawAny = false;
    for (final i in group) {
      if (i.status == VocabularyStatus.ignored) continue;
      sawAny = true;
      if (_statusRank(i.status) > _statusRank(best)) best = i.status;
    }
    // 组内全是 ignored → 保留 ignored（不凭空抬成候选）。
    return sawAny ? best : VocabularyStatus.ignored;
  }

  static int _statusRank(VocabularyStatus s) => switch (s) {
    VocabularyStatus.known => 3,
    VocabularyStatus.learning => 2,
    VocabularyStatus.candidate => 1,
    VocabularyStatus.ignored => 0,
  };

  static VocabularyItem _backfillLemma(VocabularyItem item) {
    if (item.kind != VocabularyKind.word) return item;
    final lemma = lemmaKey(item.surfaceForm);
    final allTagged = item.occurrences.every((o) => o.lemma != null);
    if (item.lemma == lemma && allTagged) return item;
    return VocabularyItem(
      id: item.id,
      surfaceForm: item.surfaceForm,
      kind: item.kind,
      status: item.status,
      englishDefinition: item.englishDefinition,
      chineseGloss: item.chineseGloss,
      aiUsageNote: item.aiUsageNote,
      lemma: lemma,
      createdAt: item.createdAt,
      lastSeenAt: item.lastSeenAt,
      occurrences: [
        for (final o in item.occurrences)
          VocabularyOccurrence(
            id: o.id,
            itemId: o.itemId,
            lessonId: o.lessonId,
            lessonTitle: o.lessonTitle,
            sentenceId: o.sentenceId,
            sentenceIndex: o.sentenceIndex,
            sentenceText: o.sentenceText,
            startMs: o.startMs,
            endMs: o.endMs,
            audioPath: o.audioPath,
            charStart: o.charStart,
            charEnd: o.charEnd,
            source: o.source,
            dictationDiffType: o.dictationDiffType,
            expected: o.expected,
            actual: o.actual,
            uncertain: o.uncertain,
            causeHints: o.causeHints,
            lemma: o.lemma ?? lemma,
            createdAt: o.createdAt,
          ),
      ],
      drills: item.drills,
      ankiCardIds: item.ankiCardIds,
      srs: item.srs,
    );
  }
}
