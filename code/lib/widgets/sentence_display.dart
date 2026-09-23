import 'package:flutter/material.dart';

import '../models/sentence.dart';
import '../models/subtitle_token.dart';
import '../theme/listenloop_theme.dart';
import '../utils/time_format.dart';

/// The visual centre of the listening screen: the current English sentence
/// (first focus), the Chinese translation (second layer) and the sentence's
/// time range on the original media timeline (kept quiet).
///
/// Typography comes from the user's learning preferences (font + text scale)
/// via [styles] — spec V2 §二十七. Visibility of each layer follows the
/// selected subtitle mode — spec V0.1 §6, §7, §15.
class SentenceDisplay extends StatelessWidget {
  const SentenceDisplay({
    super.key,
    required this.sentence,
    required this.currentPosition,
    this.showEnglish = true,
    this.showChinese = true,
    this.styles,
    this.accumulationMode = false,
    this.onTokenTap,
    this.onPhraseSelected,
    this.isTokenSaved,
  });

  final Sentence sentence;
  final Duration currentPosition;
  final bool showEnglish;
  final bool showChinese;

  /// Learning typography resolved by the caller from the user preferences.
  final LLReadLearningStyles? styles;

  /// 生词积累模式：英文句子按词切开、逐词可点。
  ///
  /// **默认关闭**，且入口开在三级（精听页 →「⋯」→ 生词积累）。
  /// 核心是「听」——字幕只在用户主动进入积累模式后才变成可点，
  /// 平时不允许把整句词永久变成按钮（见 10 号文档的红线清单）。
  final bool accumulationMode;

  /// 某个词被点击。仅 [accumulationMode] 为 true 时生效。
  final void Function(SubtitleToken token)? onTokenTap;

  /// 长按拖动圈出一段（2–5 个连续词，`take off` 这类短语）。
  ///
  /// 只圈到 1 个词时也会回调，交给调用方按「单词」处理 —— 避免
  /// 「长按了但什么都没发生」这种哑火。
  final void Function(SubtitleSelection selection)? onPhraseSelected;

  /// 该字符区间是否已保存 —— 决定是否给出「已存」轻标记。
  final bool Function(int charStart, int charEnd)? isTokenSaved;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final styles = this.styles;
    // No AnimatedSize here: animating the text block's height is what made a
    // long→short sentence switch look like the previous sentence was still
    // dissolving. The surrounding card owns the footprint; this only paints.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEnglish)
          accumulationMode
              ? _TappableEnglish(
                  text: sentence.originalText,
                  style:
                      styles?.english ??
                      TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        height: 1.32,
                        color: ll.textPrimary,
                      ),
                  savedColor: ll.textTertiary,
                  highlightColor: ll.surfaceHigh,
                  onTokenTap: onTokenTap,
                  onPhraseSelected: onPhraseSelected,
                  isTokenSaved: isTokenSaved,
                )
              : Text(
                  sentence.originalText,
                  textAlign: TextAlign.center,
                  style:
                      styles?.english ??
                      TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        height: 1.32,
                        color: ll.textPrimary,
                      ),
                ),
        if (showChinese)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              sentence.translatedText,
              textAlign: TextAlign.center,
              style:
                  styles?.chinese ??
                  TextStyle(
                    fontSize: 18,
                    height: 1.45,
                    color: ll.textSecondary,
                  ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          '${formatMsAsSeconds(sentence.startMs)} '
          '→ ${formatMsAsSeconds(sentence.endMs)}',
          style: LLText.caption.copyWith(
            color: ll.textTertiary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Resolved learning styles handed to the sentence views.
class LLReadLearningStyles {
  const LLReadLearningStyles({required this.english, required this.chinese});

  final TextStyle english;
  final TextStyle chinese;
}

/// 把整句英文切成可点击的词，**保留原句的空格与标点**。
///
/// 用 [WidgetSpan] 而不是给 TextSpan 挂 `TapGestureRecognizer`：
/// recognizer 必须手动 dispose，而本组件是无状态的，容易泄漏；
/// WidgetSpan 的生命周期由框架管理，更安全。
///
/// 手势分工（两个互不干扰的识别器）：
///   * 子词的 `onTap`      → 存/取消单个词（既有行为）；
///   * 本层的 `onLongPress*` → 长按锚定一个词，横向拖动扩展成短语。
///
/// 两条实现约束：
///   1. **选中高亮不能改布局** —— 走 `TextStyle.backgroundColor`，不用
///      Container 包裹。否则选中瞬间文字会移位，"手指底下的词"会跑掉。
///   2. **命中测试靠每个词的 RenderBox 矩形**，不靠文本偏移 —— 词是
///      WidgetSpan 占位符，段落里的字符下标对不上真实字符位置。
class _TappableEnglish extends StatefulWidget {
  const _TappableEnglish({
    required this.text,
    required this.style,
    required this.savedColor,
    required this.highlightColor,
    this.onTokenTap,
    this.onPhraseSelected,
    this.isTokenSaved,
  });

  final String text;
  final TextStyle style;
  final Color savedColor;
  final Color highlightColor;
  final void Function(SubtitleToken token)? onTokenTap;
  final void Function(SubtitleSelection selection)? onPhraseSelected;
  final bool Function(int charStart, int charEnd)? isTokenSaved;

  @override
  State<_TappableEnglish> createState() => _TappableEnglishState();
}

class _TappableEnglishState extends State<_TappableEnglish> {
  /// 每个词一个 key —— 长按拖动时用来反查手指落在哪个词上。
  List<GlobalKey> _wordKeys = const <GlobalKey>[];

  /// 长按起点锚定的词（选择区间的一端）。
  int? _anchorIndex;

  /// 当前拖到的另一端。
  int? _endIndex;

  int? get _lo {
    final a = _anchorIndex;
    final b = _endIndex;
    if (a == null || b == null) return null;
    return a < b ? a : b;
  }

  int? get _hi {
    final a = _anchorIndex;
    final b = _endIndex;
    if (a == null || b == null) return null;
    return a < b ? b : a;
  }

  int? _tokenIndexAt(Offset globalPosition) {
    for (var i = 0; i < _wordKeys.length; i++) {
      final context = _wordKeys[i].currentContext;
      if (context == null) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      // 词与词之间有空隙（空格），给一点容差，避免拖过空隙时"断档"
      if (rect.inflate(6).contains(globalPosition)) return i;
    }
    return null;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final index = _tokenIndexAt(details.globalPosition);
    if (index == null) return;
    setState(() {
      _anchorIndex = index;
      _endIndex = index;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final anchor = _anchorIndex;
    if (anchor == null) return;
    final index = _tokenIndexAt(details.globalPosition);
    if (index == null || index == _endIndex) return;

    var lo = anchor < index ? anchor : index;
    var hi = anchor < index ? index : anchor;
    if (hi - lo + 1 > kMaxPhraseTokens) {
      // 超上限时**夹紧**而不是整段放弃：手指继续滑不该让选择突然消失。
      if (index >= anchor) {
        hi = anchor + kMaxPhraseTokens - 1;
      } else {
        lo = anchor - kMaxPhraseTokens + 1;
      }
    }
    setState(() => _endIndex = index >= anchor ? hi : lo);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final lo = _lo;
    final hi = _hi;
    _clearSelection();
    if (lo == null || hi == null) return;

    final tokens = SubtitleTokenizer.tokenize(widget.text);
    final selection = SubtitleTokenizer.selectionFor(
      widget.text,
      tokens,
      lo,
      hi,
    );
    if (selection == null) return;
    widget.onPhraseSelected?.call(selection);
  }

  void _clearSelection() {
    if (_anchorIndex == null && _endIndex == null) return;
    setState(() {
      _anchorIndex = null;
      _endIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final tokens = SubtitleTokenizer.tokenize(text);
    // 没有可点词（例如纯中文）时退回普通文本，不要渲染空行
    if (tokens.isEmpty) {
      return Text(text, textAlign: TextAlign.center, style: widget.style);
    }

    if (_wordKeys.length != tokens.length) {
      // 换句后词数会变：重建命中用的 key 列表，并清掉跨句残留的选择。
      _wordKeys = List<GlobalKey>.generate(tokens.length, (_) => GlobalKey());
      _anchorIndex = null;
      _endIndex = null;
    }

    final lo = _lo;
    final hi = _hi;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      // 词与词之间的原始片段（空格、标点）原样保留，保证折行与标点不丢
      if (token.charStart > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, token.charStart)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _TappableWord(
            key: _wordKeys[i],
            token: token,
            saved:
                widget.isTokenSaved?.call(token.charStart, token.charEnd) ??
                false,
            selected: lo != null && hi != null && i >= lo && i <= hi,
            style: widget.style,
            savedColor: widget.savedColor,
            highlightColor: widget.highlightColor,
            onTap: widget.onTokenTap,
          ),
        ),
      );
      cursor = token.charEnd;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    final rich = Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: TextAlign.center,
    );

    if (widget.onPhraseSelected == null) return rich;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _clearSelection,
      child: rich,
    );
  }
}

/// 单个可点词：点击回调 + 已存轻标记 + 拖选高亮（都不弹任何东西）。
class _TappableWord extends StatelessWidget {
  const _TappableWord({
    super.key,
    required this.token,
    required this.saved,
    required this.selected,
    required this.style,
    required this.savedColor,
    required this.highlightColor,
    this.onTap,
  });

  final SubtitleToken token;
  final bool saved;
  final bool selected;
  final TextStyle style;
  final Color savedColor;
  final Color highlightColor;
  final void Function(SubtitleToken token)? onTap;

  @override
  Widget build(BuildContext context) {
    var effective = style;
    if (saved) {
      effective = effective.copyWith(
        color: savedColor,
        decoration: TextDecoration.underline,
        decorationThickness: 1,
      );
    }
    if (selected) {
      // 只改颜色，不动内边距 —— 详见 _TappableEnglish 的说明。
      effective = effective.copyWith(backgroundColor: highlightColor);
    }
    return GestureDetector(
      key: Key('vocab-word-${token.tokenIndex}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap!(token),
      child: Text(token.surface, style: effective),
    );
  }
}
