import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/sentence.dart';
import '../preferences/app_preferences.dart';
import '../theme/listenloop_theme.dart';
import 'chinese_textbook_ruby_layout.dart';

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
    this.currentPosition,
    required this.showEnglish,
    required this.showChinese,
    this.isChineseMode = false,
    required this.onSentenceTap,
    this.itemKeys = const [],
    required this.preferences,
    this.header,
    this.revealToken = 0,
    this.onVisibleIndexChanged,
  });
  final List<Sentence> sentences;
  final int currentIndex;
  final Duration? currentPosition;
  final bool showEnglish;
  final bool showChinese;
  final bool isChineseMode;
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

      // 切句发生时，无论之前是否划动过，立即解除阻断让动画跟上新句子
      _userScrolling = false;
      _resumeTimer?.cancel();
      // 2026-10-20 郭老师：「像音乐播放器播放音乐展示歌词一样，显示当前所听
      // 句子的形状，应该**固定**在人看手机的视觉中心区」。
      //
      // 所以每句都要重新锚一次 —— 锚的是**形状的底边**（压在屏幕中线上）：
      // 音频往前走 → 列表往下滚 → 字幕整列向上流过去，而那个"当前句形状"
      // 原地不动地钉在中心区。这就是歌词模式。
      //
      // （我一度改成"形状自己往下走、列表最小滚动"，那是反的：形状会跑偏。）
      _autoScrollToIndex(newIndex);
    } else if (!identical(widget.sentences, oldWidget.sentences)) {
      _fromIndex = null;
      _transition.reset();
      // 2026-10-20 郭老师：「字幕当前播放句子的形状标注位置错了」——
      // 课文数据是**异步**到的：列表先渲染旧句（甚至空），数据到位后句子
      // 列表整体换掉，但 currentIndex 没变 ⇒ 上面那个"索引变了"的分支不会
      // 触发 ⇒ 形状从来没被摆正过，列表停在 PageStorage 恢复出来的旧位置
      // （于是当前句 15 在屏外，只看得见 7~12）。
      // 数据换新 = 必须重新摆一次形状。
      _userScrolling = false;
      _autoScrollToIndex(widget.currentIndex);
    }
    if (widget.revealToken != oldWidget.revealToken) {
      _userScrolling = false;
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
      if (_userScrolling) return;      final position = _scrollController.position;
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
        final rowEstimate =
            i * _estimatedRowHeight + headerExtent + _topSpacerExtent();
        correction = rowDocOffset - rowEstimate;
        break;
      }

      // 若目标行已挂载（如逐句自然推进 37→38），直接平滑对齐，绝不触发估算 jumpTo 引起抖动
      final mountedCtx = (index >= 0 && index < widget.itemKeys.length)
          ? widget.itemKeys[index].currentContext
          : null;
      if (mountedCtx != null) {
        _alignRowIntoShape(mountedCtx);
        _settleOnScreenMiddle(index);
        return;
      }

      // 估算路径：还没挂载，先按"形状底边落屏幕中线"反推目标滚动量。
      final estRowHeight = _estimatedRowHeight;
      final target =
          ((index * estRowHeight) +
                  _topSpacerExtent() +
                  headerExtent +
                  correction -
                  _desiredRowTopInViewport(estRowHeight))
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      _scrollController.jumpTo(target);

      // Fine alignment once the target row is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _userScrolling) return;
        final ctx = (index >= 0 && index < widget.itemKeys.length)
            ? widget.itemKeys[index].currentContext
            : null;
        if (ctx != null) {
          _alignRowIntoShape(ctx);
        } else if (attempt < 4) {
          _alignToIndex(index, attempt: attempt + 1);
        }
      });
    });
  }

  /// 落位自校正：布局稳定后再校准一次。
  ///
  /// 2026-10-20（灰色形状改为跟随当前句后）：目标不再是"对齐到固定形状的
  /// 上沿"，而是"把当前句对齐到屏幕的上三分之一"。
  /// 实测第一版只对齐一次**不够**：对齐之后布局还会变（视频区展开会把
  /// 句子列表整体下推约 200px；模式切换、状态栏显隐同理）⇒ 刚对好的位置
  /// 又偏了。所以这里在动画结束后连续几帧重新量一次，差多少补多少，
  /// 直到落位（最多 4 轮）。
  void _settleOnScreenMiddle(int index) {
    var round = 0;
    void step() {
      if (!mounted || _userScrolling || round >= 4) return;
      round++;
      final ctx = (index >= 0 && index < widget.itemKeys.length)
          ? widget.itemKeys[index].currentContext
          : null;
      if (ctx == null) return;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      if (!_scrollController.hasClients) return;
      // 目标：当前句的上沿落在屏幕的上三分之一。
      final targetTop = _desiredRowTopInViewport(box.size.height);
      final rowTop = box.localToGlobal(Offset.zero).dy;
      final delta = targetTop - (rowTop - _viewportTop());
      if (delta.abs() < 2) return; // 已经落位
      final position = _scrollController.position;
      final target = (position.pixels - delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
      Future<void>.delayed(const Duration(milliseconds: 120), step);
    }

    Future<void>.delayed(const Duration(milliseconds: 260), step);
  }

  /// 列表顶部余量（半屏）—— 让第一句也能滚到上三分之一。
  double _topSpacerExtent() => MediaQuery.sizeOf(context).height * 0.5;

  /// 当前句卡片应该落在什么位置。
  ///
  /// 2026-10-20（灰色形状改为跟随当前句后）：不再有"钉在中线的固定形状"
  /// 可对齐 ⇒ 改为把**当前句本身**对齐到视口的**上三分之一**（与读页
  /// LessonReadingDocument 同一把尺：人的视线习惯落在画面中上部分）。
  ///
  /// 旧算法（对齐到固定形状上沿 / 屏幕中线）已随固定形状一起作废。
  double _desiredRowTopInViewport(double rowHeight) {
    final view = View.of(context);
    final screenHeight = view.physicalSize.height / view.devicePixelRatio;
    // 视口顶边在屏幕坐标里的位置：列表自身的渲染盒（= 可视区域）。
    double viewportTop = 0.0;
    final viewportBox = context.findRenderObject();
    if (viewportBox is RenderBox && viewportBox.attached && viewportBox.hasSize) {
      viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    }
    // 上三分之一：视口高的 28% 处（读页用的是同一个比例）。
    return screenHeight * _focusScreenFraction - viewportTop;
  }

  /// 当前句落在屏幕高度的哪个比例上（上三分之一 = 视觉中心区）。
  static const double _focusScreenFraction = 0.28;

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
    // 焦点线 = **手机屏幕**的中线（与定位对齐同一把尺，见 _desiredRowTopInViewport）。
    // 手指滑动时"当前句"跟着焦点线走，两处必须一致，否则会出现"看着在读
    // 上一句、进度却记到下一句"的错位。
    final focusY = _desiredRowTopInViewport(0).clamp(0.0, double.infinity);

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
        ((offset + focusY - headerExtent - _topSpacerExtent()) /
                _estimatedRowHeight)
            .round();
    return est.clamp(0, widget.sentences.length - 1);
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _userScrolling = true;
        _resumeTimer?.cancel();
      } else {
        _resumeTimer?.cancel();
        _resumeTimer = Timer(const Duration(milliseconds: 600), () {
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

  /// 把某一行的**上沿**对齐到屏幕的上三分之一（当前句的视觉中心位）。
  ///
  /// 2026-10-20（灰色形状改为跟随当前句后）：不再有"固定形状"可对齐 ⇒
  /// 改为把当前句本身滚到上三分之一，形状跟着它走。
  void _alignRowIntoShape(BuildContext rowContext) {
    final box = rowContext.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    if (!_scrollController.hasClients) return;
    final targetTop = _desiredRowTopInViewport(box.size.height);
    final rowTop = box.localToGlobal(Offset.zero).dy;
    final currentInViewport = rowTop - _viewportTop();
    final delta = targetTop - currentInViewport;
    if (delta.abs() < 0.5) return;
    final position = _scrollController.position;
    final target = (position.pixels - delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  double _viewportTop() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      return box.localToGlobal(Offset.zero).dy;
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final hasHeader = widget.header != null;
    // 2026-10-20 郭老师（音乐播放器式歌词）：当前句的**形状**要钉在屏幕
    // 中线上，别的句子在它下面流过去。
    //
    // 要做到"每一句"都能钉在中线上，列表**上下都得留半屏余量**：
    //  · 底部余量：最后一句下面没东西可滚 ⇒ 形状永远停在屏幕下缘；
    //  · 顶部余量：第一句上面没东西可滚 ⇒ 形状永远停在屏幕顶附近。
    // 少了任何一头，被锚定的那句就会差半个屏幕。
    final halfScreen = MediaQuery.sizeOf(context).height * 0.5;
    final totalCount =
        widget.sentences.length + (hasHeader ? 1 : 0) + 2; // +上下余量

    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // ① 当前句的**形状**：2026-10-20 改为**跟随当前句**（原先是钉在
              // 屏幕中线上的固定聚光块，见郭老师「它不动感觉怪怪的」）。
              // ⇒ 形状画在**当前句那一行**里（见 _SentenceRow 的 decoration），
              // 这里不再叠一块固定块。
              //
              // ② 字幕（滚动的）
              ListView.builder(
                controller: _scrollController,
                itemCount: totalCount,
                itemBuilder: (context, index) {
                  // index 0 = 顶部余量
                  if (index == 0) {
                    return SizedBox(height: halfScreen);
                  }
                  if (hasHeader && index == 1) {
                    return widget.header!;
                  }
                  final lastIndex = totalCount - 1;
                  if (index == lastIndex) {
            // 底部余量
            return SizedBox(height: halfScreen);
          }

          final sentenceIndex = hasHeader ? index - 2 : index - 1;
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
            ],
          );
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
      currentPosition: index == widget.currentIndex ? widget.currentPosition : null,
      showEnglish: widget.showEnglish,
      showChinese: widget.showChinese,
      isChineseMode: widget.isChineseMode,
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
    this.currentPosition,
    required this.showEnglish,
    required this.showChinese,
    this.isChineseMode = false,
    required this.preferences,
    required this.palette,
    required this.onSentenceTap,
  });

  final Sentence sentence;
  final int index;
  final bool isCurrent;
  final Duration? currentPosition;
  final bool showEnglish;
  final bool showChinese;
  final bool isChineseMode;
  final AppPreferences preferences;
  final LLPalette palette;
  final ValueChanged<int> onSentenceTap;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      // 2026-10-20（GPT 镜像评审 §四 P2）：**句子不是卡片流，是课文段落**。
      // 未选中的句子不画底、不画框、不画圆角，只靠留白分开。
      //
      // ⚠️ 但**所有行的外边距、左侧留白、边框宽度必须完全一致**：
      // 2026-10-20 郭老师报「字幕当前播放句子的形状标注位置错了」+「音频往
      // 后面走，字幕却往上面走」—— 根因就是这里：当前句原本有**更大的竖向
      // 外边距**（句子之间留白多）和**额外的左内边距**（形状往右挪），
      // 于是"当前态"一变，整列字幕先横向错位、再纵向爬 4~8px。
      //
      // 2026-10-20（郭老师：「读的那个页面字幕，灰色形状改为跟随吧……
      // 它不动感觉怪怪的」）：灰色形状**改为跟随当前句**（不再是钉在屏幕
      // 中线的那块固定聚光块）。做法与读页同一套视觉语言：当前句那行
      // 浅底 + 左侧 2dp 强调线，别的行干净。
      //
      // 为守住"一行都不抖"：**所有行的几何完全一致**——外边距、左内边距、
      // 边框宽度恒定，只换颜色。不换颜色的行画的是**透明**边框（宽度仍是
      // 2dp），绝不能写 `width: 0`（那是 hairline，配圆角会 paint 断言
      // 失败 ⇒ 整行画不出来）。
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: isCurrent
            ? ll.textPrimary.withValues(alpha: 0.055)
            : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border(
          left: BorderSide(
            width: 2,
            color: isCurrent
                ? ll.textPrimary.withValues(alpha: 0.75)
                : Colors.transparent,
          ),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(LLRadius.small),
        onTap: () => onSentenceTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                style: LLText.counter.copyWith(
                  fontSize: 12,
                  color: isCurrent ? ll.textPrimary : ll.textSecondary,
                ),
                child: Text('${index + 1}'),
              ),
              if (isChineseMode) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ChineseTextbookRubyLayout(
                    text: sentence.originalText,
                    charSize: (20 * preferences.textScale).clamp(6.0, 36.0),
                    charStyle: TextStyle(
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                      color: isCurrent ? ll.textPrimary : ll.textSecondary,
                    ),
                    chineseFontFamily: preferences.learningChineseFont.family,
                    pinyinScale: preferences.pinyinScale,
                    textAlign: TextAlign.left,
                    wordSpacing: 6.0,
                    lineSpacing: 10.0,
                    activeCharIndex: isCurrent && currentPosition != null
                        ? sentence.activeCharIndexAt(currentPosition!.inMilliseconds)
                        : null,
                  ),
                ),
              ] else ...[
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
            ],
          ),
        ),
      ),
    );
  }
}
