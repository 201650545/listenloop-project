import 'package:flutter/material.dart';

import '../data/vocabulary_store.dart';
import '../l10n/ll_strings.dart';
import '../models/vocabulary_model.dart';
import '../theme/listenloop_theme.dart';
import '../training/vocabulary_plan.dart';

/// 生词本 —— Library 的**二级页面**（附属层，见 08 定调与 10 号文档 §十二）。
///
/// 三块内容，一屏到底：
///   1. 汇总（候选 / 学习中 / 已掌握）—— 一眼看清存量；
///   2. **今日计划** —— v1 纯本地规则映射的结果，每条都能说得出依据；
///   3. 词条列表（可按状态筛选）—— 管理动作都在行尾的 ⋯ 菜单里。
///
/// 为什么计划与词条放在同一页：两者是同一件事的两个视角（"我今天练什么"
/// 与"我总共存了什么"），分成两页会让用户在两级入口之间反复横跳。
/// 等闪卡复习上线、入口变多时再拆。
///
/// 本页**不依赖网络与 AI**：断网时计划与全部管理动作照常可用。
class VocabularyBookScreen extends StatefulWidget {
  const VocabularyBookScreen({
    super.key,
    required this.store,
    this.onOpenOccurrence,
  });

  final VocabularyStore store;

  /// 「回原声」——把用户送到该证据所在的课程与句子上。
  ///
  /// 由调用方（Library）负责真正的导航：本页不认识课程仓库，
  /// 也不认识播放器 —— 保持附属层不反向依赖核心层。
  final void Function(VocabularyOccurrence occurrence)? onOpenOccurrence;

  @override
  State<VocabularyBookScreen> createState() => _VocabularyBookScreenState();
}

class _VocabularyBookScreenState extends State<VocabularyBookScreen> {
  /// null = 全部。
  VocabularyStatus? _filter;

  static const VocabularyPlanner _planner = VocabularyPlanner();

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);

    return Scaffold(
      backgroundColor: ll.bg,
      appBar: AppBar(
        backgroundColor: ll.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: ll.textPrimary),
        titleSpacing: 0,
        title: Text(
          s.vocabBook,
          style: LLText.pageTitle.copyWith(color: ll.textPrimary, fontSize: 22),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final items = widget.store.items;
          final plan = _planner.build(items);

          if (items.isEmpty) {
            return _EmptyVocabulary(palette: ll, text: s.vocabEmpty);
          }

          final visible = widget.store.byStatus(_filter);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _SummaryHeader(
                  palette: ll,
                  summary: s.vocabSummary(
                    widget.store.candidateCount,
                    widget.store.learningCount,
                    widget.store.knownCount,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _PlanSection(
                  palette: ll,
                  entries: plan,
                  emptyText: s.vocabTodayPlanEmpty,
                ),
              ),
              SliverToBoxAdapter(
                child: _FilterBar(
                  palette: ll,
                  selected: _filter,
                  labels: <VocabularyStatus?, (String, int)>{
                    null: (s.vocabAll, items.length),
                    VocabularyStatus.candidate: (
                      s.vocabStatusLabel('candidate'),
                      widget.store.candidateCount,
                    ),
                    VocabularyStatus.learning: (
                      s.vocabStatusLabel('learning'),
                      widget.store.learningCount,
                    ),
                    VocabularyStatus.known: (
                      s.vocabStatusLabel('known'),
                      widget.store.knownCount,
                    ),
                  },
                  onSelect: (value) => setState(() => _filter = value),
                ),
              ),
              if (visible.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(LLSpacing.xxl),
                    child: Center(
                      child: Text(
                        s.vocabNoItemsForFilter,
                        style: TextStyle(fontSize: 13, color: ll.textTertiary),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    if (i.isOdd) {
                      // 分隔线从文字左边缘起画 —— 与设置页一级页同一套视觉语言。
                      return Divider(color: ll.divider, height: 1, indent: 20);
                    }
                    final item = visible[i ~/ 2];
                    return _VocabularyRow(
                      key: Key('vocab-item-${item.id}'),
                      palette: ll,
                      item: item,
                      reason: _reasonFor(plan, item.id),
                      onTap: () => _showEvidence(item),
                      onStartLearning: () =>
                          widget.store.startLearning(item.id),
                      onMarkKnown: () => widget.store.markKnown(item.id),
                      onIgnore: () => widget.store.ignore(item.id),
                      onRestore: () => widget.store.setStatus(
                        item.id,
                        VocabularyStatus.candidate,
                      ),
                      onDelete: () => _confirmDelete(item),
                    );
                  }, childCount: visible.length * 2 - 1),
                ),
              const SliverPadding(
                padding: EdgeInsets.only(bottom: LLSpacing.huge),
              ),
            ],
          );
        },
      ),
    );
  }

  PlanReason? _reasonFor(List<VocabularyPlanEntry> plan, String itemId) {
    for (final entry in plan) {
      if (entry.item.id == itemId) return entry.reason;
    }
    return null;
  }

  Future<void> _confirmDelete(VocabularyItem item) async {
    final s = LLStrings.of(context);
    final ll = context.ll;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ll.surface,
        title: Text(s.vocabDelete, style: const TextStyle(fontSize: 16)),
        content: Text(
          item.surfaceForm,
          style: TextStyle(fontSize: 14, color: ll.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.vocabDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 词条级删除 = 删掉它的全部证据（词条随最后一条证据消失）。
    for (final occurrence in item.occurrences) {
      widget.store.removeOccurrence(item.id, occurrence.id);
    }
  }

  /// 证据面板：**只有这里才展示上下文**（点词时不弹）。
  void _showEvidence(VocabularyItem item) {
    final ll = context.ll;
    final s = LLStrings.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ll.bg,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        key: const Key('vocab-evidence-sheet'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.surfaceForm,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: ll.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.vocabEvidence,
                style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: ll.textTertiary),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: item.occurrences.length,
                  separatorBuilder: (_, _) => Divider(color: ll.divider, height: 20),
                  itemBuilder: (context, i) {
                    final o = item.occurrences[i];
                    return _OccurrenceTile(
                      palette: ll,
                      strings: s,
                      occurrence: o,
                      onOpen: widget.onOpenOccurrence == null
                          ? null
                          : () {
                              final open = widget.onOpenOccurrence!;
                              Navigator.of(sheetContext).pop();
                              // 二级页也要退出。回原声的目的是「回到听」——
                              // 若把用户留在生词本页，声音在后台响而眼前毫无
                              // 变化，就是一个明显的交互断层（测试抓到的）。
                              Navigator.of(context).maybePop();
                              open(o);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 汇总

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.palette, required this.summary});

  final LLPalette palette;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Text(
        summary,
        key: const Key('vocab-summary'),
        style: TextStyle(fontSize: 12, color: palette.textTertiary, height: 1.4),
      ),
    );
  }
}

// ------------------------------------------------------------------ 计划

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.palette,
    required this.entries,
    required this.emptyText,
  });

  final LLPalette palette;
  final List<VocabularyPlanEntry> entries;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final s = LLStrings.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: ll.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.vocabTodayPlan,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: ll.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Text(
                emptyText,
                key: const Key('vocab-plan-empty'),
                style: TextStyle(fontSize: 12, height: 1.5, color: ll.textTertiary),
              )
            else
              for (final entry in entries)
                Padding(
                  key: Key('vocab-plan-${entry.item.id}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.item.surfaceForm,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: ll.textPrimary,
                              ),
                            ),
                          ),
                          for (final component in entry.components)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _Pill(
                                palette: ll,
                                text: s.planComponentLabel(component.name),
                                filled: true,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.vocabReason}: ${s.planReasonLabel(entry.reason.name)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ll.textTertiary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 筛选

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.palette,
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  final LLPalette palette;
  final VocabularyStatus? selected;

  /// 有序映射 —— Dart 的 Map 保持插入顺序，正好当"固定顺序的筛选条"用。
  final Map<VocabularyStatus?, (String, int)> labels;

  final ValueChanged<VocabularyStatus?> onSelect;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in labels.entries)
            GestureDetector(
              key: Key('vocab-filter-${entry.key?.name ?? 'all'}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: entry.key == selected ? ll.surfaceHigh : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: entry.key == selected ? ll.divider : ll.divider,
                  ),
                ),
                child: Text(
                  '${entry.value.$1} ${entry.value.$2}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        entry.key == selected ? FontWeight.w600 : FontWeight.w500,
                    color: entry.key == selected
                        ? ll.textPrimary
                        : ll.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 词条行

class _VocabularyRow extends StatelessWidget {
  const _VocabularyRow({
    super.key,
    required this.palette,
    required this.item,
    required this.reason,
    required this.onTap,
    required this.onStartLearning,
    required this.onMarkKnown,
    required this.onIgnore,
    required this.onRestore,
    required this.onDelete,
  });

  final LLPalette palette;
  final VocabularyItem item;
  final PlanReason? reason;
  final VoidCallback onTap;
  final VoidCallback onStartLearning;
  final VoidCallback onMarkKnown;
  final VoidCallback onIgnore;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final s = LLStrings.of(context);
    final latest = item.latestOccurrence;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.surfaceForm,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: ll.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Pill(
                        palette: ll,
                        text: s.vocabStatusLabel(item.status.name),
                      ),
                      if (item.kind == VocabularyKind.phrase) ...[
                        const SizedBox(width: 6),
                        _Pill(palette: ll, text: 'phrase'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    <String>[
                      s.vocabSeenTimes(item.seenCount),
                      if (latest != null)
                        s.vocabSentenceAt(
                          latest.lessonTitle,
                          latest.sentenceIndex,
                        ),
                    ].join(' · '),
                    style: TextStyle(fontSize: 11.5, color: ll.textTertiary, height: 1.4),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${s.vocabSuggest}: ${s.planReasonLabel(reason!.name)}',
                      style: TextStyle(fontSize: 11.5, color: ll.textSecondary, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: Key('vocab-menu-${item.id}'),
              icon: Icon(Icons.more_vert_rounded, size: 18, color: ll.textTertiary),
              color: ll.surfaceHigh,
              onSelected: (value) {
                switch (value) {
                  case 'learn':
                    onStartLearning();
                  case 'known':
                    onMarkKnown();
                  case 'ignore':
                    onIgnore();
                  case 'restore':
                    onRestore();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                if (item.status != VocabularyStatus.learning)
                  PopupMenuItem(value: 'learn', child: Text(s.vocabStartLearning)),
                if (item.status != VocabularyStatus.known)
                  PopupMenuItem(value: 'known', child: Text(s.vocabMarkKnown)),
                if (item.status == VocabularyStatus.ignored)
                  PopupMenuItem(value: 'restore', child: Text(s.vocabRestore))
                else
                  PopupMenuItem(value: 'ignore', child: Text(s.vocabIgnore)),
                PopupMenuItem(value: 'delete', child: Text(s.vocabDelete)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 证据

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile({
    required this.palette,
    required this.strings,
    required this.occurrence,
    required this.onOpen,
  });

  final LLPalette palette;
  final LLStrings strings;
  final VocabularyOccurrence occurrence;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final o = occurrence;
    final diff = o.dictationDiffType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          o.sentenceText,
          style: TextStyle(fontSize: 13.5, height: 1.5, color: ll.textPrimary),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Pill(palette: ll, text: strings.vocabSourceLabel(o.source.name)),
            if (diff != null)
              _Pill(palette: ll, text: strings.dictationDiffType(diff)),
            if (o.uncertain)
              _Pill(palette: ll, text: strings.dictationUncertainShort),
            Text(
              strings.vocabSentenceAt(o.lessonTitle, o.sentenceIndex),
              style: TextStyle(fontSize: 11, color: ll.textTertiary),
            ),
          ],
        ),
        if (o.expected != null && o.actual != null) ...[
          const SizedBox(height: 6),
          Text(
            '${strings.dictationExpected}: ${o.expected}   ${strings.dictationYourAnswer}: ${o.actual}',
            style: TextStyle(fontSize: 11.5, color: ll.textSecondary, height: 1.4),
          ),
        ],
        if (onOpen != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('vocab-open-original'),
              onPressed: onOpen,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.play_arrow_rounded, size: 16, color: ll.textPrimary),
              label: Text(
                strings.vocabOpenOriginal,
                style: TextStyle(fontSize: 12.5, color: ll.textPrimary),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ 小件

class _Pill extends StatelessWidget {
  const _Pill({required this.palette, required this.text, this.filled = false});

  final LLPalette palette;
  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? ll.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: ll.divider),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: filled ? ll.textPrimary : ll.textTertiary,
        ),
      ),
    );
  }
}

class _EmptyVocabulary extends StatelessWidget {
  const _EmptyVocabulary({required this.palette, required this.text});

  final LLPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('vocab-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded, size: 34, color: palette.textTertiary),
            const SizedBox(height: LLSpacing.lg),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: palette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
