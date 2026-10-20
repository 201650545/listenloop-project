import 'package:flutter/material.dart';

import '../models/sentence.dart';
import '../theme/listenloop_theme.dart';
import '../training/continuous_reading_session.dart';
import '../training/reading_alignment.dart';
import 'chinese_textbook_ruby_layout.dart';

/// 整篇课文的阅读承载面（2026-10-20 读页重构）。
///
/// 2026-10-20 郭老师：「以一篇课文为一个流程……把这个课文都读完，然后才结束」
/// 　· 「页面上会显示你要读的东西，你在下方边读，它就边实时识别出内容」
///
/// 所以这里**不再是一句一屏**：整篇课文一次排开，随朗读位置自动滚动，
/// 孩子想往前翻也能翻（识别继续，不抢回滚动位置）。
class LessonReadingDocument extends StatefulWidget {
  const LessonReadingDocument({
    super.key,
    required this.sentences,
    required this.tokens,
    required this.tokenStates,
    required this.visibleToken,
    required this.charSize,
    required this.charStyle,
    required this.pinyinScale,
    required this.chineseFontFamily,
    this.initialSentenceIndex = 0,
  });

  final List<Sentence> sentences;

  /// 整篇 token 索引（与 [ContinuousReadingSession.buildTokens] 同源）。
  final List<ReadingToken> tokens;

  /// 与 [tokens] 等长的逐字状态。
  final List<ReadingTokenStatus> tokenStates;

  /// 当前读到第几个字（全局 token 序号）。
  final int visibleToken;

  final double charSize;

  /// 进入时直接落在第几句（孩子上次读到哪儿）。
  ///
  /// 2026-10-20：目标句离得远时，SliverList 还没铺到它，ensureVisible 找不到
  /// 它 ⇒ 位置一直停在课文开头。改成**列表的初始偏移**就一步到位
  /// （后面 _followVisible 再精调）。
  final int initialSentenceIndex;

  /// 汉字样式（由页面按当前主题/字体/字号算好传进来）。
  final TextStyle charStyle;

  final double pinyinScale;
  final String? chineseFontFamily;

  @override
  State<LessonReadingDocument> createState() => _LessonReadingDocumentState();
}

class _LessonReadingDocumentState extends State<LessonReadingDocument> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset:
        widget.initialSentenceIndex * _estimatedParagraphHeight,
  );
  final Map<int, GlobalKey> _sentenceKeys = {};

  int _lastVisibleToken = -1;

  /// 微调计数（按比例定位不准时的左右小幅挪动）。
  int _nudgeStep = 0;

  /// 当前句（灰色形状跟着它）。
  int get _currentSentenceIndex {
    final token = widget.visibleToken;
    if (token < 0 || token >= widget.tokens.length) return -1;
    return widget.tokens[token].sentenceIndex;
  }

  /// 估算的段落高度（跳过去用的粗尺）。
  ///
  /// 一段 = 拼音行 + 汉字行 + 段距。汉字 23px、拼音约 12px、行距 16，
  /// 再加每段 18 的段距 ≈ 80；这里给一个偏大的 96，跳粗一点没关系 ——
  /// 下一帧会精确落位。
  static const double _estimatedParagraphHeight = 96;

  /// 当前句落在视口的这个高度比例上（**上三分之一** = 视觉中心区）。
  static const double _focusAlignment = 0.28;

  @override
  void didUpdateWidget(LessonReadingDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visibleToken != oldWidget.visibleToken) {
      _followVisible();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _followVisible());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 自动跟随：只在新句子上滚动（同一句内不反复重启动画）。
  void _followVisible() {
    if (!mounted || !_scroll.hasClients) return;
    final token = widget.visibleToken;
    if (token < 0 || token >= widget.tokens.length) return;
    if (token == _lastVisibleToken) return;
    final sentenceIndex = widget.tokens[token].sentenceIndex;
    final key = _sentenceKeys[sentenceIndex];
    final ctx = key?.currentContext;
    if (ctx != null) {
      // 只有**真的落位了**才记这个 token —— 否则下面的"再跳一次"重试会被
      // 自己挡掉（早先在这里就置位，结果目标句永远铺不到、永远停在开头）。
      _lastVisibleToken = token;
      _nudgeStep = 0;
      // 目标句已经构建：把它对齐到**视口上三分之一**（那里是孩子的视线
      // 落点 —— 郭老师：「人的习惯是自然会聚焦在画面的中上部分」）。
      //
      // 2026-10-20 读页的灰色形状**跟随当前句**（不是听页那种钉在中线的
      // 固定叠层）：所以只要把当前句对齐到上三分之一，形状也就自然待在
      // 视觉中心区附近，读完时自然回到中心。
      Scrollable.ensureVisible(
        ctx,
        alignment: _focusAlignment,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    // 目标句**还没构建**（离得远，SliverList 还没铺到）—— ensureVisible 找不到它。
    // 这时先**按比例**跳过去（把它铺出来），下一帧再精确落位。
    //
    // 为什么按比例而不是"句子序号 × 估高"：段落高度不匀（标点多的句子矮），
    // 估高一大就跳过头（实测 96 vs 实际 64 → 直接跳到文末），而且跳过头
    // 之后只会越跳越远，永远铺不到目标句。
    // 比例法：句子在整篇里的位置比例 × 总滚动范围 —— 只要段落大致均匀就准。
    final position = _scroll.position;
    final total = position.maxScrollExtent;
    final count = widget.sentences.length;
    final base = count == 0
        ? 0.0
        : (sentenceIndex / count).clamp(0.0, 1.0) * total;
    // 还不准就小幅左右微调（段落高度不匀时会差几个）。
    final dir = _nudgeStep.isEven ? 1 : -1;
    final nudge = dir * (_nudgeStep + 1) * 60.0;
    _nudgeStep++;
    final estimate = (base + nudge).clamp(0.0, total);
    _scroll.jumpTo(estimate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _followVisible());
  }

  @override
  Widget build(BuildContext context) {
    // 逐句分组：每个字在句内的位置 + 它的状态。
    final bySentence = <int, List<ReadingToken>>{};
    for (final t in widget.tokens) {
      bySentence.putIfAbsent(t.sentenceIndex, () => []).add(t);
    }

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          sliver: SliverList.builder(
            itemCount: widget.sentences.length,
            itemBuilder: (context, i) {
              final sentence = widget.sentences[i];
              if (sentence.chinese.trim().isEmpty) {
                return const SizedBox(height: 8);
              }
              final key = _sentenceKeys.putIfAbsent(i, GlobalKey.new);
              final tokens = bySentence[i] ?? const <ReadingToken>[];

              // 逐字状态：ruby 排版按**句内字符下标**取，这里把全局 token 的
              // 状态翻译成句内下标。
              final statuses = <int, RubyCharStatus>{};
              for (final t in tokens) {
                final idx = t.index;
                if (idx < 0 || idx >= widget.tokenStates.length) continue;
                final s = widget.tokenStates[idx];
                final mapped = switch (s) {
                  ReadingTokenStatus.matched => RubyCharStatus.correct,
                  ReadingTokenStatus.substituted => RubyCharStatus.wrong,
                  ReadingTokenStatus.missed => RubyCharStatus.wrong,
                  _ => RubyCharStatus.unread,
                };
                statuses[t.charIndex] = mapped;
              }

              // 2026-10-20 郭老师：「读的那个页面字幕，灰色形状改为跟随吧。
              // 但是要改为**之前那种形式**……它不动感觉怪怪的」
              //
              // ⇒ 读页的灰色形状**跟着当前句走**（不再是钉在屏幕中线的固定
              // 叠层）：当前句那一行带浅底 + 左侧强调线，别的句干净。
              // 当前句本身被滚到视口上三分之一（视觉中心区），所以形状也始终
              // 待在"中心"附近，读完时自然回到中心。
              final isCurrent = _currentSentenceIndex == i;

              return Container(
                key: key,
                margin: const EdgeInsets.only(bottom: 18),
                // 左内边距**所有行一致**（2026-10-20 听页踩过的坑：当前句
                // 额外缩进 ⇒ 整列文字横向跳一下）。
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? context.ll.textPrimary.withValues(alpha: 0.055)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  // 左侧强调线：**宽度恒为 2**，只换颜色。
                  //
                  // ⚠️ 不能写成 `width: isCurrent ? 2 : 0` —— width 0 的
                  // BorderSide 是 hairline，而 Flutter 规定 hairline 只能配
                  // 零圆角（有圆角就断言失败）⇒ paint() 抛错 ⇒ 那一行整个
                  // 画不出来。2026-10-20 真机症状：读页只显示当前那一句，
                  // 其余 68 句全空白。
                  border: Border(
                    left: BorderSide(
                      width: 2,
                      color: isCurrent
                          ? context.ll.textPrimary.withValues(alpha: 0.75)
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: ChineseTextbookRubyLayout(
                  text: sentence.chinese,
                  charSize: widget.charSize,
                  charStyle: widget.charStyle,
                  chineseFontFamily: widget.chineseFontFamily,
                  pinyinScale: widget.pinyinScale,
                  textAlign: TextAlign.left,
                  wordSpacing: 6.0,
                  lineSpacing: 16.0,
                  charStatuses: statuses,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
