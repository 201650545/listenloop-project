import 'package:flutter/foundation.dart';

import '../models/sentence.dart';
import '../utils/chinese_pinyin.dart';
import 'chinese_word_segmenter.dart';
import 'read_along_session.dart';
import 'reading_alignment.dart';

/// 整课朗读的**朗读模式**（2026-10-21 郭老师定的两种）。
///
/// 两种模式**逐字反馈完全一样**（都是边读边一个一个变色），
/// 区别只在**判定边界**：
///  · [sentence]：**以句为单位**。孩子把这一句读好，才进下一句。
///    读完一句就结算这一句（错词当场可练），反馈快。
///  · [fullText]：**全文为单位**。整篇一口气读完，最后统一处理
///    （错词延后到整课结束再汇总）。适合已经读熟、要连贯背一遍的孩子。
enum ReadingMode {
  /// 以句为单位：一句读好再下一句。
  sentence,

  /// 全文：读完整篇再统一处理。
  fullText,
}

/// 整课朗读的一个**音节**（= 一个汉字）。
///
/// 2026-10-20 郭老师：「以一篇课文为一个流程」——所以索引是**整篇**的，
/// 不是一句一句各建各的。跨句对齐、漏读、重读都发生在这个全局序列上。
class ReadingToken {
  const ReadingToken({
    required this.index,
    required this.sentenceIndex,
    required this.charIndex,
    required this.char,
    required this.pinyin,
    required this.toneless,
    required this.wordKey,
  });

  /// 全篇序号（0 起）。
  final int index;

  /// 属于第几句。
  final int sentenceIndex;

  /// 在本句里的字符序号。
  final int charIndex;

  final String char;

  /// 带调拼音（如 "zhǎo"）。
  final String pinyin;

  /// 去调拼音（比较用）。
  final String toneless;

  /// 所属词组的键（跨句唯一）。
  final String wordKey;
}

/// 整课朗读的**不可变快照** —— 页面只订阅这个，不碰内部状态。
class ReadingSnapshot {
  const ReadingSnapshot({
    required this.tokenStates,
    required this.tokenHeard,
    required this.committedCursor,
    required this.provisionalCursor,
    required this.visibleCursor,
    required this.liveTranscript,
    required this.progress,
    required this.hint,
    required this.listening,
    required this.finished,
    this.wrongTokens = const [],
  });

  /// 与 token 等长：每个音节的状态。
  final List<ReadingTokenStatus> tokenStates;

  /// 与 token 等长：实际听到的音节（没听到为 null）。
  final List<String?> tokenHeard;

  /// 已确认读到的最远位置（**只向前推进**）。
  final int committedCursor;

  /// 最近一次识别推测到的位置（暂定区，可以回退）。
  final int provisionalCursor;

  /// 驱动课文高亮与自动滚动的位置。
  final int visibleCursor;

  /// 底栏实时回显的文字。
  final String liveTranscript;

  /// 朗读进度 0..1（按已确认位置算）。
  final double progress;

  /// 给孩子的提示（可空）。
  final String? hint;

  /// 是否正在收音。
  final bool listening;

  /// 整篇是否读完了。
  final bool finished;

  /// **值得再练**的字词（读成别的 / 没听清）。
  ///
  /// 2026-10-20 读页第 3 步：「阅读时阅读，纠音时纠音」—— 读的过程中**不弹**
  /// 纠错卡，这些字只是安静地记在这儿，等**整课读完**再一次性汇总给孩子。
  final List<ReadingToken> wrongTokens;

  static const ReadingSnapshot empty = ReadingSnapshot(
    tokenStates: [],
    tokenHeard: [],
    committedCursor: 0,
    provisionalCursor: 0,
    visibleCursor: 0,
    liveTranscript: '',
    progress: 0,
    hint: null,
    listening: false,
    finished: false,
  );
}

/// 整课朗读会话 —— 整课状态的**唯一所有者**。
///
/// 2026-10-20 郭老师：
/// 　· 「以一篇课文为一个流程……把这个课文都读完，然后才结束」
/// 　· 「识别是实时的，我边说它就边识别」
///
/// 这一版先落**数据与对齐**（镜像的实施顺序第 1 步）：
/// 　· 整篇 token 索引（跨句稳定编号）；
/// 　· 音节级对齐（[ReadingAligner]）；
/// 　· committed / provisional / visible 三个游标：
///    - committed（已确认前缀）**只向前推进**，是"读到第几个字"的唯一依据；
///    - provisional（暂定尾部）可以随 ASR 修正回退；
///    - visible 驱动课文高亮与自动滚动。
///
/// 麦克风与滑动窗口属于第 2 步（[ContinuousReadingSession.startListening] 先
/// 留好接口，第 2 步接上）。
class ContinuousReadingSession extends ChangeNotifier {
  ContinuousReadingSession({
    required List<Sentence> sentences,
    ReadingAligner aligner = const ReadingAligner(),
    ReadingMode mode = ReadingMode.sentence,
  })  : _tokens = buildTokens(sentences),
        _aligner = aligner,
        _mode = mode {
    _tokenStates = List<ReadingTokenStatus>.filled(
      _tokens.length,
      ReadingTokenStatus.pending,
    );
    _tokenHeard = List<String?>.filled(_tokens.length, null);
  }

  final ReadingAligner _aligner;
  final List<ReadingToken> _tokens;

  /// 朗读模式（句为单位 / 全文）。
  ReadingMode _mode;
  ReadingMode get mode => _mode;

  /// 切换朗读模式。切换会把判定游标重置到当前句开头（状态也重置为 pending）。
  void setMode(ReadingMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _committedCursor = 0;
    _provisionalCursor = 0;
    _carry = const [];
    _tokenStates = List<ReadingTokenStatus>.filled(
      _tokens.length,
      ReadingTokenStatus.pending,
    );
    _tokenHeard = List<String?>.filled(_tokens.length, null);
    notifyListeners();
  }

  late List<ReadingTokenStatus> _tokenStates;
  late List<String?> _tokenHeard;

  int _committedCursor = 0;
  int _provisionalCursor = 0;

  /// 多出来的音节（孩子提前读到下一句去了）—— 留给下一句，别丢掉进度。
  List<String> _carry = const [];

  String _liveTranscript = '';
  String? _hint;
  bool _listening = false;
  bool _finished = false;

  /// 2026-10-20 郭老师定了规则：**一句一句来**，句子按课文的标点（逗号、
  /// 句号）分。所以对齐范围 = **当前句**剩下的音节；读到下一句去的部分
  /// carry 过去下一轮。原先那枚"跨句 30 音节窗口"就此退休（它会把下一句
  /// 也拉进来匹配，规则反而绕）。

  List<ReadingToken> get tokens => List.unmodifiable(_tokens);
  int get tokenCount => _tokens.length;

  ReadingSnapshot get snapshot {
    // 值得再练的字：读成别的 / 没听清（已确认前缀里的）。
    final wrong = <ReadingToken>[];
    for (var i = 0; i < _tokens.length && i < _tokenStates.length; i++) {
      final s = _tokenStates[i];
      if (s == ReadingTokenStatus.substituted || s == ReadingTokenStatus.missed) {
        wrong.add(_tokens[i]);
      }
    }
    return ReadingSnapshot(
      tokenStates: List.unmodifiable(_tokenStates),
      tokenHeard: List.unmodifiable(_tokenHeard),
      committedCursor: _committedCursor,
      provisionalCursor: _provisionalCursor,
      visibleCursor: _committedCursor,
      liveTranscript: _liveTranscript,
      progress: _tokens.isEmpty
          ? 0
          : (_committedCursor / _tokens.length).clamp(0.0, 1.0),
      hint: _hint,
      listening: _listening,
      finished: _finished,
      wrongTokens: List.unmodifiable(wrong),
    );
  }

  /// 建整篇 token 索引。
  ///
  /// 词组归属用 [ChineseWordSegmenter] 的切分结果（它按小学高频词表贪心
  /// 切词），但**判定单位是音节**（一个字一个音节）——与拼音排版的逐字上色
  /// 一致。
  static List<ReadingToken> buildTokens(List<Sentence> sentences) {
    final tokens = <ReadingToken>[];
    var global = 0;
    for (var s = 0; s < sentences.length; s++) {
      final text = sentences[s].chinese;
      if (text.trim().isEmpty) continue;
      final pinyinTokens = ChinesePinyin.format(text);
      final words = ChineseWordSegmenter.segment(text);
      final tokenToWord = <int, int>{};
      for (var w = 0; w < words.length; w++) {
        for (final ci in words[w].charIndices) {
          tokenToWord[ci] = w;
        }
      }
      for (var t = 0; t < pinyinTokens.length; t++) {
        final pt = pinyinTokens[t];
        final py = pt.pinyin;
        if (py == null || py.isEmpty) continue; // 标点：不参与判定
        tokens.add(ReadingToken(
          index: global++,
          sentenceIndex: s,
          charIndex: t,
          char: pt.char,
          pinyin: py,
          toneless: ReadAlongSession.stripTones(py).toLowerCase(),
          wordKey: '${s}#${tokenToWord[t] ?? t}',
        ));
      }
    }
    return tokens;
  }

  /// 把阅读位置直接设到某一句的开头。
  ///
  /// 进入课文时用：孩子上次读到第 73 句，这次就从第 73 句接着读，
  /// 而不是从头开始（整篇是一个流程，位置要接得上）。
  void seekToSentence(int sentenceIndex) {
    var idx = -1;
    for (var i = 0; i < _tokens.length; i++) {
      if (_tokens[i].sentenceIndex >= sentenceIndex) {
        idx = i;
        break;
      }
    }
    if (idx < 0) return;
    _committedCursor = idx;
    _provisionalCursor = idx;
    notifyListeners();
  }

  /// 开始收音（第 2 步接上麦克风；现在只置状态）。
  void startListening() {
    if (_listening) return;
    _listening = true;
    _hint = null;
    notifyListeners();
  }

  /// 停止收音。
  void stopListening() {
    if (!_listening) return;
    _listening = false;
    notifyListeners();
  }

  /// 喂进一次识别结果（**实时**的那一路）。
  ///
  /// [syllables] 是这次识别到的音节（去调），[text] 是原始文字（给底栏回显）。
  ///
  /// 2026-10-20 郭老师：「肯定是一句一句地来，就按照课文上的标点符号，就是
  /// 逗号跟句号，来划分每一个句子就行了，这样规则简单一些，好弄」
  ///
  /// 2026-10-21（逐句判定的正确逻辑，郭老师：「这一条句子读准了，再下一个
  /// 句子呀，全绿了才下一个」）：
  ///   · **逐句模式**：这一句**全绿**（每个字都对上）才推进到下一句；
  ///     没读准就**停在这一句**，不往下跳。
  ///   · **全文模式**：整篇连续推进（读到哪标到哪）。
  ///
  /// 返回值：当前句是否**刚刚全绿完成**（逐句模式专用 —— 上层据此**重置
  /// 流式识别**，让下一句从干净的音频重新开始）。
  bool applyRecognition({
    required List<String> syllables,
    required String text,
    bool live = false,
    List<String>? chars,
  }) {
    if (_tokens.isEmpty) return false;
    _liveTranscript = text;

    if (_committedCursor >= _tokens.length) {
      _finished = true;
      _hint = '这一课读完啦！读得真棒 🎉';
      notifyListeners();
      return false;
    }

    // 当前句的范围（句子按课文标点分 —— 见 _tokens 的 sentenceIndex）。
    final sentenceIndex = _tokens[_committedCursor].sentenceIndex;
    var sentenceEnd = _committedCursor;
    while (sentenceEnd < _tokens.length &&
        _tokens[sentenceEnd].sentenceIndex == sentenceIndex) {
      sentenceEnd++;
    }

    // 对齐的**基准起点**。
    //
    // ⚠️ 流式（live）与批式的基准不一样，这是 2026-10-21 踩出来的坑：
    //   · 批式：一次喂「这一句剩下的部分」⇒ 基准 = _committedCursor（句中）。
    //   · 流式：每次喂的是**从这一句开头起的累积文本**（'池' → '池塘' →
    //     '池塘里'）⇒ 基准必须是**句首**，否则第二次对齐时 expected 已经被
    //     cursor 截短，识别的累积文本却仍从句首开始 ⇒ 整体错位
    //     （「塘」被配到「chi」上，判成读错）。
    var base = _committedCursor;
    if (live) {
      if (_mode == ReadingMode.fullText) {
        base = 0; // 全文模式：累积文本对应全篇开头。
      } else {
        base = _committedCursor;
        while (base > 0 && _tokens[base - 1].sentenceIndex == sentenceIndex) {
          base--;
        }
      }
    }

    // 期望范围：
    //  · 句为单位 ⇒ 只对齐**当前句**剩下的音节（读完这句再进下一句）。
    //  · 全文     ⇒ 对齐**整篇剩下的**音节（读完整篇再统一处理）。
    final int alignEnd;
    if (_mode == ReadingMode.fullText) {
      alignEnd = _tokens.length;
    } else {
      alignEnd = sentenceEnd;
    }

    final expected = [
      for (var i = base; i < alignEnd; i++) _tokens[i].toneless,
    ];
    // 期望侧的汉字（多音字容错要用）：与 expected 一一对应。
    final expectedChars = [
      for (var i = base; i < alignEnd; i++) _tokens[i].char,
    ];
    // 识别侧：音节 + 对应的汉字（_carry 里是上一轮多出来的，没有字 ⇒ 用空串
    // 占位，判定时按"没有字"处理）。
    final heard = [
      ..._carry,
      for (final s in syllables)
        if (s.isNotEmpty) ReadAlongSession.stripTones(s).toLowerCase(),
    ];
    final heardChars = <String>[
      ...List<String>.filled(_carry.length, ''),
      for (var k = 0; k < syllables.length; k++)
        if (syllables[k].isNotEmpty)
          (chars != null && k < chars.length) ? chars[k] : ''
        else
          '',
    ];
    _carry = const [];

    final result = _aligner.align(
      expected: expected,
      recognized: heard,
      expectedChars: expectedChars,
      recognizedChars: heardChars,
    );

    // 写回状态：只动当前句（已确认的前缀不改 —— 红绿不闪）。
    var contiguous = base;
    for (var k = 0; k < result.statuses.length; k++) {
      final idx = base + k;
      if (idx >= _tokens.length) break;
      var status = result.statuses[k];

      // ⚠️ 流式（live）：尾部那些**还没读到**的字不能判「漏读」。
      //
      // 批式识别是「读完一句再判」，尾部判 missed 是对的（真的漏了）。
      // 流式下只识别到句中，尾部只是**还没读**——判 missed 会让满屏红字。
      // ⇒ 用对齐器的 frontier（识别覆盖到的位置）把尾部还原成 pending。
      if (live && k >= result.frontier) {
        status = ReadingTokenStatus.pending;
      }

      if (idx < _committedCursor) continue;
      _tokenStates[idx] = status;
      if (status != ReadingTokenStatus.pending) {
        _tokenHeard[idx] = result.heard[k];
      }
      // ⚠️ 只有**完全对上**（matched）才推进游标。
      //
      // substituted = 读成了别的字 ⇒ 游标**停在这儿**（那个字标红，等重读），
      // 不能推过去 —— 推过去就等于「读错了也往下走」，正是郭老师说的
      // 「这一句还没读准，它就一直跳」。
      if (status == ReadingTokenStatus.matched && idx == contiguous) {
        contiguous = idx + 1;
      }
    }

    // 多出来的（读到下一句去了）→ 留给下一句，别丢掉孩子的进度。
    if (result.insertedCount > 0) {
      final overflow = result.heard
          .whereType<String>()
          .where((h) => h.isNotEmpty)
          .toList(growable: false);
      if (overflow.isNotEmpty) {
        _carry = overflow.take(8).toList(growable: false);
      }
    }

    // committed：这一句里**连续**确认到的最远位置（只向前推进）。
    //
    // ⚠️ 2026-10-21 逐句判定的关键（郭老师：「这一条句子读准了，再下一个句子呀，
    // 全绿了才下一个」）：
    //
    // 逐句 + 流式（live）模式下，**换句只在整句全绿时发生**。
    // 否则会出现「这一句还没读完，它就一直跳下一句」—— 因为孩子读了一部分，
    // 累积文本里的音节被 NW 对齐到了句尾，contiguous 就冲过去了。
    //
    //   · committed（句内位置）⇒ 仍连续推进，供**逐字高亮**用。
    //   · 换句                ⇒ 必须整句 matched 且无一字 substituted。
    final bool sentenceMode = _mode == ReadingMode.sentence;
    final int sentenceLen = sentenceEnd - base;
    final bool allGreen = sentenceLen > 0 &&
        result.matchedCount >= sentenceLen &&
        result.substitutedCount == 0;

    if (sentenceMode && live) {
      // 句内位置照旧推进（逐字高亮要）。
      if (contiguous > _committedCursor) {
        _committedCursor = contiguous;
        if (contiguous > _provisionalCursor) _provisionalCursor = contiguous;
      }
      // 但**换句**只在全绿时。
      if (allGreen) {
        _committedCursor = sentenceEnd;
        if (sentenceEnd > _provisionalCursor) _provisionalCursor = sentenceEnd;
      }
    } else {
      if (contiguous > _committedCursor) {
        _committedCursor = contiguous;
        if (contiguous > _provisionalCursor) _provisionalCursor = contiguous;
      }
    }

    if (_committedCursor >= _tokens.length) {
      _finished = true;
      _hint = '这一课读完啦！读得真棒 🎉';
    } else if (live) {
      // 流式下 missedCount 里混着「还没读到」的字 ⇒ 不能据此说"没听清"。
      // 只在**已覆盖区**里真漏了字才提示。
      final coveredMissed = result.missedCount -
          (result.statuses.length - result.frontier).clamp(0, result.statuses.length);
      if (coveredMissed > 0 && result.matchedCount > 0) {
        _hint = '有几个字还没听清，继续读就好';
      } else if (sentenceMode && !allGreen && result.matchedCount > 0) {
        // 逐句模式：这一句还没全绿 ⇒ 明确告诉孩子"这句还没读完"。
        _hint = '这一句还没读完，读准了才进下一句';
      } else {
        _hint = null;
      }
    } else if (result.missedCount > 0 && result.matchedCount > 0) {
      _hint = '有几个字还没听清，继续读就好';
    } else {
      _hint = null;
    }

    notifyListeners();

    // 逐句模式：这一句刚全绿 ⇒ 通知上层**重置流式识别**（下一句从干净音频开始）。
    final bool sentenceCompleted = sentenceMode && live && allGreen;
    return sentenceCompleted;
  }

  /// 某一刻的"我在读第几个字"（供页面高亮用）。
  int get visibleCursor => _committedCursor;

  @override
  void dispose() {
    super.dispose();
  }
}
