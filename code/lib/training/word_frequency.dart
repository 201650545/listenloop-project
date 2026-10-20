/// 离线词频读取器 —— NGSL 1.01 前 2801 词（rank 1 = 最常用）。
///
/// 设计依据：`docs/02_工程架构与系统设计/10_生词本与Anki记忆卡设计.md` §20.4 P0。
///
/// **用途边界（必须遵守）**：
///   * 只影响**候选池 / 今日计划**的排序与过滤 —— 即「学什么」；
///   * **绝不**参与 `VocabularySrs` 的间隔数学 —— 那是「什么时候复习」，
///     由 SM-2 决定，词频不得改动任何 `dueAt` / `easeFactor` / `intervalDays`。
///
/// **查询键用 lemma 归一化**（`lemmaKey`）：`walking` 会查到 `walk` 的频率，
/// 与生词本判重口径（`vocabularyMergeKey`）一致，避免词形变体各自查不到。
///
/// 纯函数、零依赖、离线：解析一次，之后全部是 O(1) Map 查询。
library;

import 'lemma_normalizer.dart';

/// NGSL 词频表。rank 越小越常用。
class WordFrequency {
  const WordFrequency._(this._ranks);

  /// 空表 —— 词频信息不可用时降级用，**不抛错、不影响调用方**。
  const WordFrequency.empty() : _ranks = const <String, int>{};

  /// 从 TSV（`词形\trank`，UTF-8）解析。
  ///
  /// * 词形按小写存储（解析时即归一化，查询端只做 lemma 归一化）；
  /// * 空行 / 缺列 / rank 非数字 / rank ≤ 0 的行**跳过**（防御性，不炸）；
  /// * 同词形重复出现以**首个**为准（表内词形唯一，防御性处理）。
  factory WordFrequency.parse(String raw) {
    final ranks = <String, int>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final tab = trimmed.indexOf('\t');
      if (tab <= 0) continue;
      final word = trimmed.substring(0, tab).trim().toLowerCase();
      final rank = int.tryParse(trimmed.substring(tab + 1).trim());
      if (word.isEmpty || rank == null || rank <= 0) continue;
      ranks.putIfAbsent(word, () => rank);
    }
    return WordFrequency._(ranks);
  }

  final Map<String, int> _ranks;

  /// 表内词条数。
  int get size => _ranks.length;

  bool get isEmpty => _ranks.isEmpty;

  /// 该词的 NGSL 排名（1 = 最常用）；不在表内返回 null。
  ///
  /// NGSL 是 **lemma 表**（只存原形，如 `walk`），所以查询走两步：
  ///   1. 先按 lemma 归一化键查 —— `walked` / `walking` 归到 `walk`；
  ///   2. **原形兜底** —— `found`、`been` 等在 NGSL 表里是**独立条目**，
  ///      `lemmaKey` 会把它们归到 `find`/`be` 而漏掉；此时直接查
  ///      归一化原形兜住。
  int? rankOf(String surface) {
    final key = lemmaKey(surface);
    if (key.isEmpty) return null;
    final hit = _ranks[key];
    if (hit != null) return hit;
    final raw = surface.trim().toLowerCase();
    return raw.isEmpty ? null : _ranks[raw];
  }

  /// 是否为高频词（rank ≤ [threshold]，默认 1000）。
  bool isHighFrequency(String surface, {int threshold = 1000}) {
    final r = rankOf(surface);
    return r != null && r <= threshold;
  }

  /// 是否为低频词（rank > [threshold]，默认 2000）。
  bool isLowFrequency(String surface, {int threshold = 2000}) {
    final r = rankOf(surface);
    return r != null && r > threshold;
  }

  /// 排序优先级：**值越大越该先练**（低频优先）。
  ///
  /// * rank 大（低频罕见）→ 大值 → **先练**；
  /// * rank 小（高频常用）→ 小值 → **后练**；
  /// * **未登录词**（NGSL 2801 之外）→ 1500（中间偏前）。
  ///   理由：NGSL 只覆盖核心高频词，未登录 ≠ 低频——它可能是 COCA/BNC
  ///   前 5 万里的普通词，也可能是专有名词。给中间值既不让生僻词霸榜、
  ///   也不把它们压到底（压底反而漏掉真正该练的词）。
  int priorityOf(String surface) => rankOf(surface) ?? _unknownPriority;

  /// 未登录词的优先级（NGSL 之外）。
  static const int _unknownPriority = 1500;
}