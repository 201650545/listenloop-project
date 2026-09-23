import '../models/vocabulary_model.dart' show normalizeTerm;
import '../training/dictation_engine.dart' show DictationEngine;

/// 字幕里一个**可点击**的词单元，保留它在原句中的字符位置。
///
/// 为什么不能复用听写引擎的分词器：`DictationEngine.tokenize()` 是为**比对**
/// 设计的——它小写化、展开 `I'm → i am`、并把标点当分隔符丢掉，**已经破坏了
/// 原始字符布局**，无法回答「用户点到了屏幕上哪一段字符」。
/// 本分词器只做**命中映射**，不改变字符数，两者职责不同、不可互相替代。
class SubtitleToken {
  const SubtitleToken({
    required this.surface,
    required this.normalized,
    required this.charStart,
    required this.charEnd,
    required this.tokenIndex,
  });

  /// 原句中的原样切片（保留大小写与内部撇号/连字符），例如 `Don't`。
  final String surface;

  /// 归一化形式（小写、撇号统一），用于判重与展示。
  ///
  /// 注意：**这里不展开缩写**。展开会改变词数，破坏字符位置映射——
  /// 需要展开时请用 [expandedForComparison]。
  final String normalized;

  /// 在原句中的起始字符下标（含）。
  final int charStart;

  /// 在原句中的结束字符下标（不含）。
  final int charEnd;

  /// 句内序号（0 基）。
  final int tokenIndex;

  int get length => charEnd - charStart;

  /// 供比对使用的展开形式（`don't` → `do not`）。
  ///
  /// 单独作为方法而不是字段：它是「比对视角」的派生值，不参与命中映射。
  List<String> get expandedForComparison => DictationEngine.tokenize(surface);

  @override
  String toString() => 'SubtitleToken($surface@$charStart-$charEnd)';
}

/// 保留字符位置的字幕分词器。
///
/// 命中规则（与设计文档一致）：
///   * `don't` / `I'm` / `teacher's` → **整个缩写算一个**可点击单元；
///   * `mother-in-law` → 整个连字符词算一个单元；
///   * 标点 `, . ? ! —` 等**不可点击**，仅作分隔；
///   * 多词短语（`take off`）不在这里合并——由长按拖动选取区间后按原样切片。
abstract final class SubtitleTokenizer {
  /// 词单元：字母数字开头，允许内部夹撇号或连字符。
  static final RegExp _wordPattern = RegExp(r"[A-Za-z0-9]+(?:['\u2019\-][A-Za-z0-9]+)*");

  /// 把整句切成可点击的词单元。
  static List<SubtitleToken> tokenize(String sentence) {
    if (sentence.trim().isEmpty) return const <SubtitleToken>[];
    final out = <SubtitleToken>[];
    var index = 0;
    for (final match in _wordPattern.allMatches(sentence)) {
      final surface = match.group(0)!;
      out.add(
        SubtitleToken(
          surface: surface,
          normalized: normalizeTerm(surface),
          charStart: match.start,
          charEnd: match.end,
          tokenIndex: index++,
        ),
      );
    }
    return out;
  }

  /// 按 token 序号区间取短语（长按拖动选 2–5 个词时用）。
  ///
  /// 切片**取自原句原文**而不是用空格拼接 token，这样 `take it off`
  /// 之间的标点与空格原样保留。
  static String phraseFor(
    String sentence,
    List<SubtitleToken> tokens,
    int fromTokenIndex,
    int toTokenIndex,
  ) {
    if (tokens.isEmpty) return '';
    final lo = fromTokenIndex < toTokenIndex ? fromTokenIndex : toTokenIndex;
    final hi = fromTokenIndex < toTokenIndex ? toTokenIndex : fromTokenIndex;
    if (lo < 0 || hi >= tokens.length) return '';
    if (hi - lo + 1 > kMaxPhraseTokens) {
      return ''; // 超过上限一律拒绝，避免误圈整句
    }
    return sentence.substring(tokens[lo].charStart, tokens[hi].charEnd);
  }

  /// 短语的字符区间，供生成 occurrence 使用。
  static (int, int)? phraseSpan(
    List<SubtitleToken> tokens,
    int fromTokenIndex,
    int toTokenIndex,
  ) {
    if (tokens.isEmpty) return null;
    final lo = fromTokenIndex < toTokenIndex ? fromTokenIndex : toTokenIndex;
    final hi = fromTokenIndex < toTokenIndex ? toTokenIndex : fromTokenIndex;
    if (lo < 0 || hi >= tokens.length) return null;
    if (hi - lo + 1 > kMaxPhraseTokens) return null;
    return (tokens[lo].charStart, tokens[hi].charEnd);
  }

  /// 命中测试：给定字符下标，返回覆盖它的词单元（没有则 null）。
  ///
  /// 标点落在词单元之间时返回 null —— 由此天然实现「标点不可点击」。
  static SubtitleToken? tokenAt(List<SubtitleToken> tokens, int charOffset) {
    for (final t in tokens) {
      if (charOffset >= t.charStart && charOffset < t.charEnd) return t;
    }
    return null;
  }
}

/// 短语最多允许圈几个词。
///
/// 上限存在的意义：手机上一次长按拖动很容易连成小半句，
/// 圈进去的就不再是「一个词条」，复习时也无法形成可回答的卡。
const int kMaxPhraseTokens = 5;
