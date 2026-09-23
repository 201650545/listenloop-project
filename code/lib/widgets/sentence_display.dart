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
                  onTokenTap: onTokenTap,
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
class _TappableEnglish extends StatelessWidget {
  const _TappableEnglish({
    required this.text,
    required this.style,
    required this.savedColor,
    this.onTokenTap,
    this.isTokenSaved,
  });

  final String text;
  final TextStyle style;
  final Color savedColor;
  final void Function(SubtitleToken token)? onTokenTap;
  final bool Function(int charStart, int charEnd)? isTokenSaved;

  @override
  Widget build(BuildContext context) {
    final tokens = SubtitleTokenizer.tokenize(text);
    // 没有可点词（例如纯中文）时退回普通文本，不要渲染空行
    if (tokens.isEmpty) {
      return Text(text, textAlign: TextAlign.center, style: style);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final token in tokens) {
      // 词与词之间的原始片段（空格、标点）原样保留，保证折行与标点不丢
      if (token.charStart > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, token.charStart)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _TappableWord(
            token: token,
            saved: isTokenSaved?.call(token.charStart, token.charEnd) ?? false,
            style: style,
            savedColor: savedColor,
            onTap: onTokenTap,
          ),
        ),
      );
      cursor = token.charEnd;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: TextAlign.center,
    );
  }
}

/// 单个可点词：点击回调 + 已存轻标记（下划线 + 降级色，不弹任何东西）。
class _TappableWord extends StatelessWidget {
  const _TappableWord({
    required this.token,
    required this.saved,
    required this.style,
    required this.savedColor,
    this.onTap,
  });

  final SubtitleToken token;
  final bool saved;
  final TextStyle style;
  final Color savedColor;
  final void Function(SubtitleToken token)? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('vocab-word-${token.tokenIndex}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap!(token),
      child: Text(
        token.surface,
        style: saved
            ? style.copyWith(
                color: savedColor,
                decoration: TextDecoration.underline,
                decorationThickness: 1,
              )
            : style,
      ),
    );
  }
}
