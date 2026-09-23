import 'package:flutter/foundation.dart';

import '../models/vocabulary_model.dart';

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
class VocabularyStore extends ChangeNotifier {
  VocabularyStore({List<VocabularyItem>? initial}) {
    if (initial != null) {
      for (final item in initial) {
        _items[item.id] = item;
      }
    }
    _reindexCounters();
  }

  final Map<String, VocabularyItem> _items = <String, VocabularyItem>{};
  int _itemSeq = 0;
  int _occurrenceSeq = 0;

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

  VocabularyItem? itemById(String id) => _items[id];

  /// 按归一化词形查词条（跨课程合并的入口）。
  VocabularyItem? itemBySurface(String surface) {
    final key = normalizeTerm(surface);
    for (final item in _items.values) {
      if (item.itemKey == key) return item;
    }
    return null;
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

    // ① Item 层：按归一化词形找已有词条，找到就复用（跨课程合并）
    var item = itemBySurface(surface);

    item ??= VocabularyItem(
      id: 'voc_${++_itemSeq}',
      surfaceForm: surface,
      kind: kind,
      createdAt: stamp,
      lastSeenAt: stamp,
    );

    // ② Occurrence 层：同位置已存在则不重复记
    final existing = _findOccurrence(lessonId, sentenceId, charStart, charEnd);
    if (existing != null) {
      _items[item.id] = item; // 首次调用时把新建的词条落库
      notifyListeners();
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
      createdAt: stamp,
    );

    // 新生成一条证据时刷新最近见到时间；重复点击不会走到这里
    item = item.copyWith(
      lastSeenAt: stamp,
      occurrences: <VocabularyOccurrence>[...item.occurrences, occurrence],
    );
    _items[item.id] = item;
    notifyListeners();
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
  }

  /// 显式转移学习状态（派生规则 1：状态不随单次证据自动升降）。
  void setStatus(String itemId, VocabularyStatus status) {
    final item = _items[itemId];
    if (item == null || item.status == status) return;
    _items[itemId] = item.withStatus(status);
    notifyListeners();
  }

  /// 把候选词升入正式学习队列（用户主动确认）。
  void startLearning(String itemId) => setStatus(itemId, VocabularyStatus.learning);

  void markKnown(String itemId) => setStatus(itemId, VocabularyStatus.known);

  void ignore(String itemId) => setStatus(itemId, VocabularyStatus.ignored);

  void clear() {
    _items.clear();
    _itemSeq = 0;
    _occurrenceSeq = 0;
    notifyListeners();
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
}
