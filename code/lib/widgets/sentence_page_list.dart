import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/sentence.dart';
import '../preferences/app_preferences.dart';
import '../theme/listenloop_theme.dart';

/// 单页文本 / Transcript mode (virtualized ListView.builder for 1000+ items):
/// * current sentence: English near-white + Chinese secondary, with a 2px
///   bar on the left edge (never a filled box);
/// * other sentences: English secondary, Chinese tertiary.
/// * interlude badges: displayed between sentences when gap >= 10s.
/// * virtualized scrolling: only builds visible items; auto-centers with user scroll detection.
class SentencePageList extends StatefulWidget {
  const SentencePageList({
    super.key,
    required this.sentences,
    required this.currentIndex,
    required this.showEnglish,
    required this.showChinese,
    required this.onSentenceTap,
    this.itemKeys = const [],
    required this.preferences,
    this.header,
    this.revealToken = 0,
    this.onVisibleIndexChanged,
  });
  final List<Sentence> sentences;
  final int currentIndex;
  final bool showEnglish;
  final bool showChinese;
  final ValueChanged<int> onSentenceTap;

  /// Optional item keys for backwards compatibility.
  final List<GlobalKey> itemKeys;

  final AppPreferences preferences;

  /// Lesson title + meta block shown once at the top of the transcript.
  final Widget? header;

  /// Bumped by the parent to request an immediate re-align to
  /// [currentIndex] (tab re-entry, presentation-mode switch).
  final int revealToken;

  /// Notifies the parent of the currently visible sentence index at the focus line (~32% viewport).
  final ValueChanged<int>? onVisibleIndexChanged;

  @override
  State<SentencePageList> createState() => _SentencePageListState();
}

class _SentencePageListState extends State<SentencePageList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: LLMotion.normal,
  );

  late final ScrollController _scrollController = ScrollController();

  /// The row that is fading OUT during a sentence switch (null = idle).
  int? _fromIndex;

  /// +1 = next (outgoing drifts left), -1 = previous (mirrored).
  int _direction = 1;

  bool _userScrolling = false;
  Timer? _resumeTimer;

  /// Rough average height of a bilingual transcript row (JP+ZH+counter).
  /// Only used for the initial jump estimate; the actual target offset is
  /// refined from real rendered-row offsets (see _alignToIndex).
  static const double _estimatedRowHeight = 175.0;

  @override
  void didUpdateWidget(SentencePageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = oldWidget.currentIndex;
    final newIndex = widget.currentIndex;
    if (oldIndex != newIndex) {
      _fromIndex = oldIndex;
      _direction = newIndex > oldIndex ? 1 : -1;
      _transition
        ..stop()
        ..reset()
        ..forward();

      if (!_userScrolling) {
        _autoScrollToIndex(newIndex);
      }
    } else if (!identical(widget.sentences, oldWidget.sentences)) {
      _fromIndex = null;
      _transition.reset();
    }
    if (widget.revealToken != oldWidget.revealToken && !_userScrolling) {
      _autoScrollToIndex(widget.currentIndex);
    }
  }

  /// Align the transcript so [index] sits ~1/3 from the top.
  ///
  /// 2026-09-22 rework (user report: 定位慢/卡顿/模式切换后定位失效):
  /// the old two-phase estimate-then-ensureVisible failed on large jumps —
  /// the 175px estimate drifts by tens of thousands of px over 1000+
  /// rows, so `animateTo` landed nowhere near the target and the target
  /// row was never mounted, making ensureVisible silently no-op.
  ///
  /// Now: jumpTo the estimate immediately (no long animation), then use
  /// the real rendered offset of any mounted row to correct the estimate
  /// and re-jump — converges within 2-3 frames even across a 1200-row
  /// jump — then fine-align with ensureVisible once the row is mounted.
  void _autoScrollToIndex(int index) {
    _alignToIndex(index, attempt: 0);
  }

  void _alignToIndex(int index, {required int attempt}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        // Controller not attached yet (e.g. right after a mode switch while
        // the crossfade is still settling) — retry for a few frames.
        if (attempt < 8) _alignToIndex(index, attempt: attempt + 1);
        return;
      }
      if (_userScrolling) return;
      final position = _scrollController.position;
      final viewport = position.viewportDimension;
      final headerExtent = widget.header != null ? 120.0 : 0.0;

      // Correction: find any mounted row and compare its real document
      // offset against the estimate; apply the delta to the target.
      double correction = 0;
      for (final key in widget.itemKeys) {
        final ctx = key.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final rowTopInViewport = box.localToGlobal(Offset.zero).dy;
        final i = widget.itemKeys.indexOf(key);
        final rowDocOffset = _scrollController.offset + rowTopInViewport;
        final rowEstimate = i * _estimatedRowHeight + headerExtent;
        correction = rowDocOffset - rowEstimate;
        break;
      }

      // 若目标行已挂载（如逐句自然推进 37→38），直接平滑对齐，绝不触发估算 jumpTo 引起抖动
      final mountedCtx = (index >= 0 && index < widget.itemKeys.length)
          ? widget.itemKeys[index].currentContext
          : null;
      if (mountedCtx != null) {
        Scrollable.ensureVisible(
          mountedCtx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.32,
        );
        return;
      }

      final target =
          ((index * _estimatedRowHeight) + headerExtent + correction - viewport * 0.32)
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      _scrollController.jumpTo(target);

      // Fine alignment once the target row is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _userScrolling) return;
        final ctx = (index >= 0 && index < widget.itemKeys.length)
            ? widget.itemKeys[index].currentContext
            : null;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: 0.32,
          );
        } else if (attempt < 4) {
          _alignToIndex(index, attempt: attempt + 1);
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _transition.addStatusListener(_onTransitionStatus);
    if (widget.currentIndex > 0) {
      _autoScrollToIndex(widget.currentIndex);
    }
  }


  void _onTransitionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _fromIndex = null);
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _scrollController.dispose();
    _transition.dispose();
    super.dispose();
  }

  int _computeVisibleIndex() {
    if (!_scrollController.hasClients) return widget.currentIndex;
    final offset = _scrollController.offset;
    final headerExtent = widget.header != null ? 120.0 : 0.0;
    final viewport = _scrollController.position.viewportDimension;
    final focusY = viewport * 0.32;

    int bestIndex = -1;
    double minDiff = double.infinity;

    for (int i = 0; i < widget.itemKeys.length; i++) {
      final ctx = widget.itemKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      final diff = (dy - focusY).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestIndex = i;
      }
    }

    if (bestIndex != -1) return bestIndex;

    final est =
        ((offset + focusY - headerExtent) / _estimatedRowHeight).round();
    return est.clamp(0, widget.sentences.length - 1);
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _userScrolling = true;
        _resumeTimer?.cancel();
      } else {
        _resumeTimer?.cancel();
        _resumeTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            _userScrolling = false;
          }
        });
      }
    }
    if (notification is ScrollUpdateNotification) {
      widget.onVisibleIndexChanged?.call(_computeVisibleIndex());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final hasHeader = widget.header != null;
    final totalCount = widget.sentences.length + (hasHeader ? 1 : 0) + 1;

    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: totalCount,
        itemBuilder: (context, index) {
          if (hasHeader && index == 0) {
            return widget.header!;
          }
          final lastIndex = totalCount - 1;
          if (index == lastIndex) {
            return const SizedBox(height: LLSpacing.huge);
          }

          final sentenceIndex = hasHeader ? index - 1 : index;
          final sentence = widget.sentences[sentenceIndex];
          final rowWidget = _animatedRow(sentenceIndex, sentence);

          // Check if there is a large gap between this sentence and the next
          if (sentenceIndex < widget.sentences.length - 1) {
            final next = widget.sentences[sentenceIndex + 1];
            final gapMs = next.startMs - sentence.endMs;
            if (gapMs >= 10000) {
              final minutes = (gapMs / 60000).floor();
              final seconds = ((gapMs % 60000) / 1000).round();
              final timeStr = '$minutes:${seconds.toString().padLeft(2, '0')}';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  rowWidget,
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.ll.textPrimary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: context.ll.textPrimary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.music_note_rounded,
                            size: 14,
                            color: context.ll.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '♪ 剧情配乐 / 原声留白 ($timeStr)',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.ll.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
          }

          return rowWidget;
        },
      ),
    );
  }

  /// Wraps the two rows involved in a sentence switch with a smooth vertical
  /// flow transition; every other row renders unchanged.
  Widget _animatedRow(int index, Sentence sentence) {
    Key? rowKey;
    if (index < widget.itemKeys.length) {
      rowKey = widget.itemKeys[index];
    }
    Widget row = _SentenceRow(
      key: rowKey,
      sentence: sentence,
      index: index,
      isCurrent: index == widget.currentIndex,
      showEnglish: widget.showEnglish,
      showChinese: widget.showChinese,
      preferences: widget.preferences,
      palette: context.ll,
      onSentenceTap: widget.onSentenceTap,
    );

    final from = _fromIndex;
    if (from == null || !_transition.isAnimating) return row;
    if (index != from && index != widget.currentIndex) return row;

    final curved = CurvedAnimation(
      parent: _transition,
      curve: Curves.easeOutCubic,
    );
    if (index == from) {
      final slide = Tween<Offset>(
        begin: Offset.zero,
        end: Offset(0, -_direction * 0.02),
      ).animate(curved);
      return SlideTransition(position: slide, child: row);
    }
    final slide = Tween<Offset>(
      begin: Offset(0, _direction * 0.035),
      end: Offset.zero,
    ).animate(curved);
    return SlideTransition(position: slide, child: row);
  }
}

class _SentenceRow extends StatelessWidget {
  const _SentenceRow({
    super.key,
    required this.sentence,
    required this.index,
    required this.isCurrent,
    required this.showEnglish,
    required this.showChinese,
    required this.preferences,
    required this.palette,
    required this.onSentenceTap,
  });

  final Sentence sentence;
  final int index;
  final bool isCurrent;
  final bool showEnglish;
  final bool showChinese;
  final AppPreferences preferences;
  final LLPalette palette;
  final ValueChanged<int> onSentenceTap;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: isCurrent
            ? ll.textPrimary.withValues(alpha: 0.04)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(LLRadius.small),
        border: Border(
          left: BorderSide(
            width: 3,
            color: isCurrent ? ll.textPrimary : Colors.transparent,
          ),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(LLRadius.small),
        onTap: () => onSentenceTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                style: LLText.counter.copyWith(
                  fontSize: 12,
                  color: isCurrent ? ll.textPrimary : ll.textTertiary,
                ),
                child: Text('${index + 1}'),
              ),
              if (showEnglish)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    style: LLLearning.transcriptEnglish(
                      ll,
                      preferences,
                      current: isCurrent,
                    ),
                    child: Text(sentence.english),
                  ),
                ),
              if (showChinese)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    style: LLLearning.transcriptChinese(
                      ll,
                      preferences,
                      current: isCurrent,
                    ),
                    child: Text(sentence.chinese),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
