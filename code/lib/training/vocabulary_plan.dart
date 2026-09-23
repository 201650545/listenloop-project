/// v1 学习计划 —— **纯本地规则映射，不依赖任何 AI**。
///
/// 设计依据：`docs/02_工程架构与系统设计/10_生词本与Anki记忆卡设计.md` §十四。
///
/// 范围（v1 刻意做小）：
///   * 输入信号只取两类 —— **听写证据**（来自 `DictationEngine`）＋ **手动点存**；
///   * 组件只用白名单里 [StudyComponent] 的前四个（全部本地可判定）；
///   * **不做** AI 出题、不做开放答案评判、不做多次到期的节奏编排。
///
/// 三条硬约束（对应 §14.1）：
///   1. 一个词一次**最多 2 个组件**；
///   2. 受 SRS 配额约束（新卡 [newQuota] / 复习 [reviewQuota]）；
///   3. 每个组件都能回答「因为哪条证据」——由 [VocabularyPlanEntry.reason] 唯一出口给出，
///      UI 不得自己拼条件。
///
/// ⚠️ 一条**超出原表**的补充规则（已在此显式标注）：
/// [DictationDiffType.extra]（多写）在设计文档的规则表里没有出现。
/// 多写意味着用户听到了原文里没有的东西，属**听辨**问题而非拼写问题，
/// 因此按听辨处理但**只给原声回听、不给重听写**——因为「重写一遍」
/// 对「多写」并没有针对性（他不知道该少写哪个）。命中（`matched`）则什么都不出。
library;

import '../models/vocabulary_model.dart';
import 'dictation_engine.dart';

/// 学习组件白名单。
///
/// v1 **只实现前四个**；[StudyComponent.srsReview] 仅用于已掌握且到期的词。
enum StudyComponent {
  /// 回原声听 —— 必须用**原片句轴音频**，不允许用 TTS 合成音替代（08 定调红线）。
  originalRelisten,

  /// 重听写这一句。
  dictationRetry,

  /// 英文 Cloze 回忆（拼写/形态类问题的针对性练习）。
  clozeRecall,

  /// 形态纠错展示 —— 只展示正确形态，**不判开放答案**（v1 边界）。
  morphologyNote,

  /// 纯 SRS 到期待复习。
  srsReview;

  static StudyComponent parse(String? raw) => StudyComponent.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => StudyComponent.originalRelisten,
  );
}

/// 出这些组件的**唯一原因**。
///
/// 验收标准第 2 条要求「每个组件都能回答因为哪条证据」——所以原因
/// 由引擎给出而不是 UI 推断，避免两处条件判断漂移。
enum PlanReason {
  /// 可靠听写证据（漏词/替换/合并/拆分）→ 听辨问题。
  reliableHearing,

  /// 只有「多写」——本表未覆盖，按听辨处理但只回原声（见文件头说明）。
  extraOnly,

  /// 只有拼写问题 —— **不判听力差**。
  spellingOnly,

  /// 只有词尾形态问题。
  morphologyOnly,

  /// 对齐不可靠 —— 只回原声，禁止派发精确词训练。
  uncertainOnly,

  /// 只有手动点存、没有其它证据 —— 按 v1 规则**什么都不出**，留在候选池。
  tapOnly,

  /// 已判「会」且 SRS 到期。
  knownDue,

  /// 已判「会」但未到期 / 已忽略 —— 什么都不出。
  settled;

  static PlanReason parse(String? raw) => PlanReason.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => PlanReason.tapOnly,
  );
}

/// 一个词的今日计划条目。
class VocabularyPlanEntry {
  const VocabularyPlanEntry({
    required this.item,
    required this.components,
    required this.reason,
  });

  final VocabularyItem item;

  /// 建议组件，最多 2 个（由引擎保证）。
  final List<StudyComponent> components;

  final PlanReason reason;

  /// 建议的**主导一句**要不要展示 —— 空条目不应出现在 UI 里。
  bool get isActionable => components.isNotEmpty;

  @override
  String toString() =>
      'VocabularyPlanEntry(${item.surfaceForm} → ${components.map((c) => c.name).join('+')}, ${reason.name})';
}

/// v1 计划生成器。
class VocabularyPlanner {
  const VocabularyPlanner({this.newQuota = 5, this.reviewQuota = 30});

  /// 新词（候选池升上来的）单次计划上限。
  final int newQuota;

  /// 复习（已在学习队列 / 已掌握到期）单次计划上限。
  final int reviewQuota;

  /// 生成今日计划。
  ///
  /// [dueAt] 缺省为 null 表示**尚无 SRS 卡**（v1 现状：Item 级调度还没接），
  /// 此时已掌握的词一律不出组件——宁可少出，也不凭空声称「到期」。
  List<VocabularyPlanEntry> build(
    Iterable<VocabularyItem> items, {
    DateTime? now,
    DateTime? Function(VocabularyItem item)? dueAt,
  }) {
    final stamp = now ?? DateTime.now();
    final out = <VocabularyPlanEntry>[];
    var newUsed = 0;
    var reviewUsed = 0;

    // 最近见到的排前面：与生词本列表同一顺序，避免两处观感不一致。
    final sorted = items.toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));

    for (final item in sorted) {
      if (item.status == VocabularyStatus.ignored) continue;

      if (item.status == VocabularyStatus.known) {
        final due = dueAt?.call(item);
        if (due == null || due.isAfter(stamp)) continue;
        if (reviewUsed >= reviewQuota) continue;
        reviewUsed++;
        out.add(
          VocabularyPlanEntry(
            item: item,
            components: const <StudyComponent>[StudyComponent.srsReview],
            reason: PlanReason.knownDue,
          ),
        );
        continue;
      }

      final entry = _drillFor(item);
      if (entry == null) continue;

      // 候选池算「新词」配额；学习中的算复习配额。
      final isNew = item.status == VocabularyStatus.candidate;
      if (isNew && newUsed >= newQuota) continue;
      if (!isNew && reviewUsed >= reviewQuota) continue;
      if (isNew) {
        newUsed++;
      } else {
        reviewUsed++;
      }
      out.add(entry);
    }

    return out;
  }

  /// 单词语音/拼写训练规则表（§14.1 的全部行 + 一条显式补充）。
  VocabularyPlanEntry? _drillFor(VocabularyItem item) {
    final dictation = item.occurrences
        .where((o) => o.source == VocabularySource.dictation)
        .toList(growable: false);

    // 只有手动点存（或干脆没有证据）：留候选池，不出组件——防止把
    // 「随手收藏」立刻变成复习债务（§14 硬约束 ③）。
    if (dictation.isEmpty) return null;

    // 存在对齐不可靠的听写：只回原声。此时派发「重听写」等于伪造精确诊断。
    if (dictation.any((o) => o.uncertain)) {
      return _entry(item, const <StudyComponent>[
        StudyComponent.originalRelisten,
      ], PlanReason.uncertainOnly);
    }

    final types = <DictationDiffType>{
      for (final o in dictation)
        if (o.dictationDiffType != null)
          DictationDiffType.values.firstWhere(
            (t) => t.name == o.dictationDiffType,
            orElse: () => DictationDiffType.matched,
          ),
    };

    final hearing = <DictationDiffType>{
      DictationDiffType.missing,
      DictationDiffType.replaced,
      DictationDiffType.merged,
      DictationDiffType.split,
    };
    if (types.any(hearing.contains)) {
      return _entry(item, const <StudyComponent>[
        StudyComponent.originalRelisten,
        StudyComponent.dictationRetry,
      ], PlanReason.reliableHearing);
    }

    // 补充规则：只有「多写」→ 只回原声（见文件头）。
    if (types.contains(DictationDiffType.extra)) {
      return _entry(item, const <StudyComponent>[
        StudyComponent.originalRelisten,
      ], PlanReason.extraOnly);
    }

    // 拼写问题：只给 Cloze，**不判听力差**。
    if (types.contains(DictationDiffType.spelling)) {
      return _entry(item, const <StudyComponent>[
        StudyComponent.clozeRecall,
      ], PlanReason.spellingOnly);
    }

    if (types.contains(DictationDiffType.morphology)) {
      return _entry(item, const <StudyComponent>[
        StudyComponent.morphologyNote,
        StudyComponent.clozeRecall,
      ], PlanReason.morphologyOnly);
    }

    // 只剩「命中」：没有可训练的错误。
    return null;
  }

  VocabularyPlanEntry _entry(
    VocabularyItem item,
    List<StudyComponent> components,
    PlanReason reason,
  ) {
    // 上限 2 个组件 —— 在引擎里强制，不依赖调用方自觉。
    final capped = components.length > maxComponentsPerItem
        ? components.sublist(0, maxComponentsPerItem)
        : components;
    return VocabularyPlanEntry(
      item: item,
      components: List<StudyComponent>.unmodifiable(capped),
      reason: reason,
    );
  }

  /// 一个词一次最多 2 个组件（§14.1 硬约束 ①）。
  static const int maxComponentsPerItem = 2;
}
