import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/sentence.dart';
import '../preferences/app_preferences.dart';
import '../theme/listenloop_theme.dart';
import 'chinese_textbook_ruby_layout.dart';

/// 听页字幕列表。
///
/// 定位规则：当前句所在行的顶部对齐到屏幕高度的 28%。
///
/// 正常切句使用单一 ScrollController 动画。
/// 只有明确要求立即重新定位时，才使用 jumpTo。
///
/// 所有行都保持可变高度；不使用 itemExtent 或 prototypeItem。
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

  /// 可选的外部行 key，保留既有 API。
  /// 未提供的行使用组件内部创建的 GlobalKey。
  final List<GlobalKey> itemKeys;

  final AppPreferences preferences;
  final Widget? header;

  /// 改变此值会要求立即重新对齐当前句。
  final int revealToken;

  /// 当前焦点线附近的可见句子索引。
  final ValueChanged<int>? onVisibleIndexChanged;

  @override
  State<SentencePageList> createState() => _SentencePageListState();
}

class _SentencePageListState extends State<SentencePageList> {
  late final ScrollController _scrollController = ScrollController();

  final GlobalKey _viewportKey =
      GlobalKey(debugLabel: 'SentencePageList.viewport');

  final GlobalKey _headerKey =
      GlobalKey(debugLabel: 'SentencePageList.header');

  /// 内部 key 只用于测量实际挂载的行。
  /// 外部 itemKeys 优先使用，避免改变调用方的 key 语义。
  final List<GlobalKey> _ownedItemKeys = <GlobalKey>[];

  /// 只保存当前已挂载的行索引，避免每帧遍历整篇课文。
  final Set<int> _mountedRowIndices = <int>{};

  bool _userScrolling = false;
  Timer? _resumeTimer;

  /// 每次新定位请求都会递增。
  /// 旧请求的 post-frame 回调和动画完成回调必须通过此检查。
  int _alignmentGeneration = 0;

  /// 布局稳定性复核：每个定位请求最多安排一次。
  Timer? _alignmentCheckTimer;

  int? _lastReportedVisibleIndex;

  /// 当前句落在**列表视口内**的这个高度比例上（上三分之一 = 视觉中心区）。
  ///
  /// ⚠️ 口径必须是**视口相对**，不是屏幕相对（2026-10-21 真机前发现）：
  /// 听页上方还有封面/媒体区，列表视口顶在屏幕 28% 之下 ⇒ 按屏幕 28% 算的
  /// 焦点线落在视口**之外** ⇒ 目标不可达 ⇒ 列表不滚 ⇒ 当前句滚出屏幕。
  /// 读页 `LessonReadingDocument._focusAlignment` 同为 0.28，且是**视口相对**
  /// ⇒ 两页共用同一把尺。
  static const double _focusViewportFraction = 0.28;

  /// 仅在完全没有任何已挂载行可供测量时使用的冷启动估值。
  /// 它不是行高假设；真实行位置挂载后会重新校正。
  static const double _bootstrapRowExtent = 175.0;

  /// 仅供远距离跳转的未挂载间奏徽标估值。
  /// 目标行挂载后会改用真实测量。
  static const double _estimatedInterludeExtent = 44.0;

  static const int _maxAlignmentAttempts = 5;
  static const int _maxAttachAttempts = 8;

  @override
  void initState() {
    super.initState();

    _syncOwnedItemKeys();

    // 第 0 句也必须定位，不能只在 currentIndex > 0 时处理。
    _requestAlignment(widget.currentIndex, animate: false);
  }

  @override
  void didUpdateWidget(covariant SentencePageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    _syncOwnedItemKeys();

    if (widget.onVisibleIndexChanged != oldWidget.onVisibleIndexChanged) {
      _lastReportedVisibleIndex = null;
    }

    final sentencesChanged =
        !listEquals(widget.sentences, oldWidget.sentences);

    final preferencesChanged =
        widget.preferences.textScale != oldWidget.preferences.textScale ||
        widget.preferences.pinyinScale != oldWidget.preferences.pinyinScale ||
        widget.preferences.learningChineseFont.family !=
            oldWidget.preferences.learningChineseFont.family;

    final layoutChanged = sentencesChanged ||
        preferencesChanged ||
        widget.showEnglish != oldWidget.showEnglish ||
        widget.showChinese != oldWidget.showChinese ||
        widget.isChineseMode != oldWidget.isChineseMode;

    final revealChanged = widget.revealToken != oldWidget.revealToken;
    final indexChanged = widget.currentIndex != oldWidget.currentIndex;

    if (layoutChanged || revealChanged) {
      // 数据或显示布局变化时，立即对齐最终布局，而不是动画中途
      // 再用旧的估算结果修正。
      _takeOverScrolling();
      _lastReportedVisibleIndex = null;
      _requestAlignment(widget.currentIndex, animate: false);
    } else if (indexChanged) {
      // 正常逐句推进只发起一项新的平滑定位。
      _takeOverScrolling();
      _requestAlignment(widget.currentIndex, animate: true);
    }
  }

  void _syncOwnedItemKeys() {
    while (_ownedItemKeys.length < widget.sentences.length) {
      final index = _ownedItemKeys.length;
      _ownedItemKeys.add(
        GlobalKey(debugLabel: 'SentencePageList.row.$index'),
      );
    }

    while (_ownedItemKeys.length > widget.sentences.length) {
      _ownedItemKeys.removeLast();
    }
  }

  GlobalKey _keyForSentence(int index) {
    if (index < widget.itemKeys.length) {
      return widget.itemKeys[index];
    }
    return _ownedItemKeys[index];
  }

  void _onRowMounted(int index) {
    _mountedRowIndices.add(index);
  }

  void _onRowUnmounted(int index) {
    _mountedRowIndices.remove(index);
  }

  RenderBox? _renderBoxForContext(BuildContext? context) {
    if (context == null) return null;

    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return object;
  }

  RenderBox? get _viewportBox =>
      _renderBoxForContext(_viewportKey.currentContext);

  /// 焦点线在**屏幕**上的 Y ＝ 视口顶 ＋ 视口高 × 比例。
  double _focusScreenY(RenderBox viewport) {
    return _viewportTop(viewport) + viewport.size.height * _focusViewportFraction;
  }

  double _viewportTop(RenderBox viewport) {
    return viewport.localToGlobal(Offset.zero).dy;
  }

  /// 焦点线是否可用。
  ///
  /// 视口相对的口径下，焦点线**必然落在视口内** ⇒ 只要视口有高度就可达。
  /// （旧实现按屏幕 28% 算，真机上听页的焦点线在视口外 ⇒ 判定不可达
  ///   ⇒ 列表不滚、当前句会滚出屏幕。）
  bool _focusIsReachable(RenderBox viewport) {
    return viewport.size.height > 0;
  }

  /// 列表上下留白：让**第一句/最后一句**也能被滚到焦点线。
  ///
  /// 需要的留白 ＝ 视口高 × (1 − 焦点比例)：当前句要落在焦点线上，
  /// 它上方/下方的内容就得有这么多余量。按视口算（不按屏幕算），
  /// 否则听页上方有封面区时余量不够，首句永远够不到焦点线。
  double _spacerExtent(double viewportHeight) {
    return viewportHeight * (1 - _focusViewportFraction);
  }

  /// 根据已挂载目标行的真实全局位置计算滚动偏移。
  ///
  /// 正常切句不使用行高估算。
  double? _scrollOffsetForRow(
    RenderBox rowBox,
    RenderBox viewport,
  ) {
    if (!_focusIsReachable(viewport)) return null;
    if (!_scrollController.hasClients) return null;

    final position = _scrollController.position;
    final rowTopGlobal = rowBox.localToGlobal(Offset.zero).dy;

    // 向下滚动 delta 时，行的全局 Y 坐标会减少 delta。
    // 因此：目标偏移 = 当前偏移 + 行顶部 Y - 焦点线 Y。
    final target =
        position.pixels + rowTopGlobal - _focusScreenY(viewport);

    return target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  /// 请求一次新的定位。新请求会使旧请求的异步回调失效。
  void _requestAlignment(
    int requestedIndex, {
    required bool animate,
  }) {
    final generation = ++_alignmentGeneration;

    _alignmentCheckTimer?.cancel();
    _alignmentCheckTimer = null;

    if (widget.sentences.isEmpty) {
      _cancelActiveScrollAtCurrentOffset();
      return;
    }

    final index = requestedIndex
        .clamp(0, widget.sentences.length - 1)
        .toInt();

    _scheduleAlignment(
      index,
      generation: generation,
      animate: animate,
      attempt: 0,
    );
  }

  void _takeOverScrolling() {
    _userScrolling = false;
    _resumeTimer?.cancel();
    _resumeTimer = null;

    _alignmentCheckTimer?.cancel();
    _alignmentCheckTimer = null;
  }

  /// 使旧的滚动活动停止，但不改变当前像素位置。
  ///
  /// 特别是目标已经对齐时，也必须防止旧动画继续向旧目标移动。
  void _cancelActiveScrollAtCurrentOffset() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.isScrollingNotifier.value) {
      _scrollController.jumpTo(position.pixels);
    }
  }

  /// 平滑滚动使用与位移成比例的时长，避免大跨度时移动过快。
  ///
  /// 线性曲线用于歌词式流动：每次切句时从当前位置重新计算目标，
  /// 而不是每次都从 ease-out 曲线的高速段重新开始。
  Future<void> _moveToOffset(
    double target, {
    required bool animate,
  }) {
    if (!_scrollController.hasClients) {
      return Future<void>.value();
    }

    final position = _scrollController.position;

    final clampedTarget = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    final distance = (clampedTarget - position.pixels).abs();

    if (distance < 0.75) {
      _cancelActiveScrollAtCurrentOffset();
      return Future<void>.value();
    }

    if (!animate) {
      _scrollController.jumpTo(clampedTarget);
      return Future<void>.value();
    }

    final milliseconds =
        (distance / 0.75).round().clamp(160, 420).toInt();

    return _scrollController.animateTo(
      clampedTarget,
      duration: Duration(milliseconds: milliseconds),
      curve: Curves.linear,
    );
  }

  void _scheduleAlignment(
    int index, {
    required int generation,
    required bool animate,
    required int attempt,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _alignmentGeneration) return;
      if (_userScrolling) return;

      if (!_scrollController.hasClients) {
        if (attempt < _maxAttachAttempts) {
          _scheduleAlignment(
            index,
            generation: generation,
            animate: animate,
            attempt: attempt + 1,
          );
        }
        return;
      }

      final viewport = _viewportBox;
      if (viewport == null) {
        if (attempt < _maxAttachAttempts) {
          _scheduleAlignment(
            index,
            generation: generation,
            animate: animate,
            attempt: attempt + 1,
          );
        }
        return;
      }

      if (!_focusIsReachable(viewport)) {
        _cancelActiveScrollAtCurrentOffset();
        return;
      }

      final rowBox = _renderBoxForContext(
        _keyForSentence(index).currentContext,
      );

      if (rowBox != null) {
        final target = _scrollOffsetForRow(rowBox, viewport);

        if (target == null) {
          _cancelActiveScrollAtCurrentOffset();
          return;
        }

        final movement = _moveToOffset(target, animate: animate);

        // 只复核一次。若父布局在滚动后发生变化，进行平滑校正；
        // 不再运行多轮延迟 jumpTo。
        unawaited(
          movement.then((_) {
            if (!mounted || generation != _alignmentGeneration) return;
            _scheduleAlignmentCheck(index, generation);
          }),
        );
        return;
      }

      // 目标行尚未挂载。只能用估算把列表移到目标附近，
      // 随后等待实际行挂载，再用真实坐标对齐。
      if (attempt >= _maxAlignmentAttempts) return;

      final estimate = _estimateTargetOffset(index, viewport);
      final movement = _moveToOffset(estimate, animate: animate);

      if (animate) {
        unawaited(
          movement.then((_) {
            if (!mounted || generation != _alignmentGeneration) return;

            _scheduleAlignment(
              index,
              generation: generation,
              animate: true,
              attempt: attempt + 1,
            );
          }),
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _alignmentGeneration) return;

          _scheduleAlignment(
            index,
            generation: generation,
            animate: false,
            attempt: attempt + 1,
          );
        });
      }
    });
  }

  /// 对齐动画完成后的单次复核。
  ///
  /// 如果视口因父组件布局变化而移动，才重新计算目标。
  /// 新切句、手指滚动或新定位请求都会取消这次复核。
  void _scheduleAlignmentCheck(int index, int generation) {
    _alignmentCheckTimer?.cancel();

    _alignmentCheckTimer = Timer(
      const Duration(milliseconds: 260),
      () {
        if (!mounted || generation != _alignmentGeneration) return;
        if (_userScrolling || !_scrollController.hasClients) return;
        if (index < 0 || index >= widget.sentences.length) return;

        final viewport = _viewportBox;
        final rowBox = _renderBoxForContext(
          _keyForSentence(index).currentContext,
        );

        if (viewport == null || rowBox == null) return;

        final target = _scrollOffsetForRow(rowBox, viewport);

        if (target == null) {
          _cancelActiveScrollAtCurrentOffset();
          return;
        }

        if ((target - _scrollController.position.pixels).abs() >= 2.0) {
          // 复核只在检测到真实偏差时触发，而且仍然是平滑移动。
          unawaited(_moveToOffset(target, animate: true));
        }
      },
    );
  }

  bool _hasInterludeAfter(int index) {
    if (index < 0 || index + 1 >= widget.sentences.length) {
      return false;
    }

    final sentence = widget.sentences[index];
    final next = widget.sentences[index + 1];

    return next.startMs - sentence.endMs >= 10000;
  }

  List<_MeasuredRow> _measureMountedRows() {
    final rows = <_MeasuredRow>[];

    for (final index in _mountedRowIndices) {
      if (index < 0 || index >= widget.sentences.length) continue;

      final box = _renderBoxForContext(
        _keyForSentence(index).currentContext,
      );

      if (box == null) continue;

      rows.add(
        _MeasuredRow(
          index: index,
          top: box.localToGlobal(Offset.zero).dy,
          height: box.size.height,
        ),
      );
    }

    rows.sort((a, b) => a.index.compareTo(b.index));
    return rows;
  }

  double _measuredHeaderHeight() {
    final box = _renderBoxForContext(_headerKey.currentContext);
    return box?.size.height ?? 0.0;
  }

  /// 只用于目标行尚未挂载的跳转路径。
  ///
  /// 优先使用最近的已挂载行作为锚点，并使用当前挂载行的平均高度。
  /// 对尚未测量的行和间奏徽标使用估值；真实目标挂载后会再对齐。
  double _estimateTargetOffset(int targetIndex, RenderBox viewport) {
    final position = _scrollController.position;
    final viewportTop = _viewportTop(viewport);
    // 焦点线在**视口内**的位置（视口局部坐标）。
    final desiredLocalTop = viewport.size.height * _focusViewportFraction;

    final measured = _measureMountedRows();

    double averageHeight = _bootstrapRowExtent;

    if (measured.isNotEmpty) {
      var totalHeight = 0.0;

      for (final row in measured) {
        totalHeight += row.height;
      }

      averageHeight = totalHeight / measured.length;
    }

    final measuredByIndex = <int, _MeasuredRow>{
      for (final row in measured) row.index: row,
    };

    double extentAfter(int index) {
      final rowHeight = measuredByIndex[index]?.height ?? averageHeight;
      final interludeHeight =
          _hasInterludeAfter(index) ? _estimatedInterludeExtent : 0.0;

      return rowHeight + interludeHeight;
    }

    double targetDocumentTop;

    if (measured.isNotEmpty) {
      // 选离目标索引最近的真实挂载行作为锚点。
      var anchor = measured.first;

      for (final row in measured.skip(1)) {
        if ((row.index - targetIndex).abs() <
            (anchor.index - targetIndex).abs()) {
          anchor = row;
        }
      }

      // 内容文档坐标 = 当前滚动偏移 + 行在视口中的局部坐标。
      final anchorDocumentTop =
          position.pixels + anchor.top - viewportTop;

      targetDocumentTop = anchorDocumentTop;

      if (targetIndex > anchor.index) {
        for (var i = anchor.index; i < targetIndex; i++) {
          targetDocumentTop += extentAfter(i);
        }
      } else {
        for (var i = targetIndex; i < anchor.index; i++) {
          targetDocumentTop -= extentAfter(i);
        }
      }
    } else {
      // 极端冷启动：连一行字幕都尚未挂载。
      // 标题优先使用真实高度；暂时无法测量时只作为初始估值。
      targetDocumentTop = _spacerExtent(viewport.size.height) + _measuredHeaderHeight();

      for (var i = 0; i < targetIndex; i++) {
        targetDocumentTop += extentAfter(i);
      }
    }

    final target = targetDocumentTop - desiredLocalTop;

    return target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  int _safeCurrentIndex() {
    if (widget.sentences.isEmpty) return widget.currentIndex;

    return widget.currentIndex
        .clamp(0, widget.sentences.length - 1)
        .toInt();
  }

  int _computeVisibleIndex() {
    if (widget.sentences.isEmpty) return widget.currentIndex;

    final viewport = _viewportBox;
    if (viewport == null || !_focusIsReachable(viewport)) {
      return _safeCurrentIndex();
    }

    final focusY = _focusScreenY(viewport);

    var bestIndex = -1;
    var minDiff = double.infinity;

    // 只遍历已经挂载的行，不扫描整篇课文。
    for (final index in _mountedRowIndices) {
      if (index < 0 || index >= widget.sentences.length) continue;

      final box = _renderBoxForContext(
        _keyForSentence(index).currentContext,
      );

      if (box == null) continue;

      final rowTopGlobal = box.localToGlobal(Offset.zero).dy;
      final diff = (rowTopGlobal - focusY).abs();

      if (diff < minDiff) {
        minDiff = diff;
        bestIndex = index;
      }
    }

    return bestIndex >= 0 ? bestIndex : _safeCurrentIndex();
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _userScrolling = true;
        _resumeTimer?.cancel();
        _alignmentCheckTimer?.cancel();
      } else {
        _resumeTimer?.cancel();

        _resumeTimer = Timer(
          const Duration(milliseconds: 600),
          () {
            if (mounted) {
              _userScrolling = false;
            }
          },
        );
      }
    }

    if (notification is ScrollUpdateNotification) {
      final index = _computeVisibleIndex();

      // 回调仍然表示焦点线对应的可见句子，只过滤重复的同一索引。
      if (index != _lastReportedVisibleIndex) {
        _lastReportedVisibleIndex = index;
        widget.onVisibleIndexChanged?.call(index);
      }
    }

    return false;
  }

  Widget _buildSentenceRow(int index, Sentence sentence) {
    final row = _SentenceRow(
      key: _keyForSentence(index),
      sentence: sentence,
      index: index,
      isCurrent: index == widget.currentIndex,
      currentPosition:
          index == widget.currentIndex ? widget.currentPosition : null,
      showEnglish: widget.showEnglish,
      showChinese: widget.showChinese,
      isChineseMode: widget.isChineseMode,
      preferences: widget.preferences,
      palette: context.ll,
      onSentenceTap: widget.onSentenceTap,
    );

    return _RowMountTracker(
      index: index,
      onMounted: _onRowMounted,
      onUnmounted: _onRowUnmounted,
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 焦点线与上下留白都按**视口**算（听页上方有封面/媒体区，按屏幕算会算错），
    // 所以先拿到视口高度再构建列表。
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return _buildViewport(context, viewportHeight);
      },
    );
  }

  Widget _buildViewport(BuildContext context, double viewportHeight) {
    final hasHeader = widget.header != null;
    final spacer = _spacerExtent(viewportHeight);

    final totalCount =
        widget.sentences.length + (hasHeader ? 1 : 0) + 2;

    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: Stack(
        key: _viewportKey,
        children: [
          ListView.builder(
            controller: _scrollController,

            // 坐标由本组件统一计算，避免 ListView 自动添加安全区 padding。
            padding: EdgeInsets.zero,

            itemCount: totalCount,
            itemBuilder: (context, index) {
              // 顶部留白：允许第一句向上滚到 28% 焦点线。
              if (index == 0) {
                return SizedBox(height: spacer);
              }

              if (hasHeader && index == 1) {
                return KeyedSubtree(
                  key: _headerKey,
                  child: widget.header!,
                );
              }

              // 最后一个 item 是底部留白。
              final lastIndex = totalCount - 1;

              if (index == lastIndex) {
                return SizedBox(height: spacer);
              }

              final sentenceIndex = hasHeader ? index - 2 : index - 1;

              if (sentenceIndex < 0 ||
                  sentenceIndex >= widget.sentences.length) {
                return const SizedBox.shrink();
              }

              final sentence = widget.sentences[sentenceIndex];
              final rowWidget = _buildSentenceRow(
                sentenceIndex,
                sentence,
              );

              // 保留原有的长间奏提示。
              if (sentenceIndex < widget.sentences.length - 1) {
                final next = widget.sentences[sentenceIndex + 1];
                final gapMs = next.startMs - sentence.endMs;

                if (gapMs >= 10000) {
                  final minutes = (gapMs / 60000).floor();
                  final seconds = ((gapMs % 60000) / 1000).round();
                  final timeStr =
                      '$minutes:${seconds.toString().padLeft(2, '0')}';

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
                            color: context.ll.textPrimary.withValues(
                              alpha: 0.05,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: context.ll.textPrimary.withValues(
                                alpha: 0.1,
                              ),
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
      ),
    );
  }

  @override
  void dispose() {
    // 使尚未执行的异步定位任务全部失效。
    _alignmentGeneration++;

    _resumeTimer?.cancel();
    _alignmentCheckTimer?.cancel();

    _scrollController.dispose();

    super.dispose();
  }
}

/// 一行字幕当前是否挂载的轻量跟踪器。
///
/// 这不是额外的动画控制器，也不会触发父组件 setState。
class _RowMountTracker extends StatefulWidget {
  const _RowMountTracker({
    required this.index,
    required this.onMounted,
    required this.onUnmounted,
    required this.child,
  });

  final int index;
  final ValueChanged<int> onMounted;
  final ValueChanged<int> onUnmounted;
  final Widget child;

  @override
  State<_RowMountTracker> createState() => _RowMountTrackerState();
}

class _RowMountTrackerState extends State<_RowMountTracker> {
  @override
  void initState() {
    super.initState();
    widget.onMounted(widget.index);
  }

  @override
  void didUpdateWidget(covariant _RowMountTracker oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.index != widget.index) {
      oldWidget.onUnmounted(oldWidget.index);
      widget.onMounted(widget.index);
    }
  }

  @override
  void dispose() {
    widget.onUnmounted(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MeasuredRow {
  const _MeasuredRow({
    required this.index,
    required this.top,
    required this.height,
  });

  final int index;
  final double top;
  final double height;
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
      // 只动画背景色与强调线颜色。
      // 外边距、内边距、边框宽度始终不变。
      duration: const Duration(milliseconds: 180),
      curve: Curves.linear,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: isCurrent
            ? ll.textPrimary.withValues(alpha: 0.055)
            : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border(
          left: BorderSide(
            // 必须恒为 2dp，只改变颜色。
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
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 文字使用目标状态的最终样式，不再逐帧插值字体度量。
              Text(
                '${index + 1}',
                style: LLText.counter.copyWith(
                  fontSize: 12,
                  color: isCurrent ? ll.textPrimary : ll.textSecondary,
                ),
              ),
              if (isChineseMode) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ChineseTextbookRubyLayout(
                    text: sentence.originalText,
                    charSize: (20 * preferences.textScale).clamp(
                      6.0,
                      36.0,
                    ),
                    charStyle: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.w400,
                      color:
                          isCurrent ? ll.textPrimary : ll.textSecondary,
                    ),
                    chineseFontFamily:
                        preferences.learningChineseFont.family,
                    pinyinScale: preferences.pinyinScale,
                    textAlign: TextAlign.left,
                    wordSpacing: 6.0,
                    lineSpacing: 10.0,
                    activeCharIndex:
                        isCurrent && currentPosition != null
                            ? sentence.activeCharIndexAt(
                                currentPosition!.inMilliseconds,
                              )
                            : null,
                  ),
                ),
              ] else ...[
                if (showEnglish)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      sentence.english,
                      style: LLLearning.transcriptEnglish(
                        ll,
                        preferences,
                        current: isCurrent,
                      ),
                    ),
                  ),
                if (showChinese)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      sentence.chinese,
                      style: LLLearning.transcriptChinese(
                        ll,
                        preferences,
                        current: isCurrent,
                      ),
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