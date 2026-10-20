import 'package:flutter/foundation.dart';

import 'segmentation_service.dart' show DraftSentence;
import 'textbook_index.dart';
import 'word_timestamp.dart';

/// 一次课文对齐的结果。
@immutable
class TextbookAlignResult {
  const TextbookAlignResult({
    required this.track,
    required this.score,
    required this.sentences,
  });

  /// 命中的课文。
  final TextbookTrack track;

  /// 相似度 = 2×LCS / (ASR 字数 + 课文规范化字数)，0..1。
  final double score;

  /// 按课文标准句切好的草稿句（文本取课文原句，时间取 ASR 词边界）。
  final List<DraftSentence> sentences;
}

/// 中文切句新方案的核心（2026-09-29 用户方案四步流的第②③步）：
///
/// ① ASR 全文识别已有（`WordTimestamp` 流）；
/// ② 把 ASR 全文与课文索引逐篇做规范化字符 LCS 对齐，取最匹配的一篇；
/// ③ 按该课文的标准句边界把字幕切开（字幕文本用课文原句）；
/// ④ 时间轴取自 ASR 词边界——句边界落在相邻词的时间中点。
///
/// 对齐是纯本地、确定性的：课文匹配不需要联网，也不需要 AI 生成任何
/// 内容（符合 17 号产品宪法——AI 不生成任意 UI/内容，只做受约束增强）。
abstract final class TextbookSentenceAligner {
  /// 判定「匹配到这篇课文」的最低相似度。0.70 意味着允许相当比例的
  /// ASR 错字（二年级慢速朗读实测错字率约 5-15%），同时避免把无关
  /// 音频误认成课文。
  static const double kMinMatchScore = 0.70;

  /// 规范化后可比较字符的最少数量：太短的文本（如单句格言 8 字）
  /// 偶然撞上高分的概率太高，不值得对齐。
  static const int kMinComparableChars = 12;

  /// DP 矩阵规模上限（约 32 MB Int32List），防御超长音频 × 长课文的
  /// 内存尖峰。正常课文 300-800 字、单次导入音频几千字，远够。
  static const int _maxDpCells = 8 * 1024 * 1024;

  /// 规范化后字符数差异超过 [max(两长度)] 的 60% 直接跳过——长度悬殊
  /// 时不可能匹配，避免对整册音频逐篇跑 DP。
  static const double _maxLenRatioGap = 0.60;

  /// 在整本索引里找最匹配的一篇。都不达标返回 null（调用方回退常规切句）。
  ///
  /// [clauseLevel]（课文朗读模式）：命中课文后再按「逗号/句号」朗读单元
  /// 细分——每行诗、每个逗号短句都是一个可单句循环的单元。
  static TextbookAlignResult? alignToBestTrack(
    List<WordTimestamp> words,
    TextbookIndex index, {
    bool clauseLevel = false,
  }) {
    TextbookAlignResult? best;
    for (final track in index.alignableTracks) {
      final result = alignToTrack(words, track, clauseLevel: clauseLevel);
      if (result != null &&
          (best == null || result.score > best.score)) {
        best = result;
      }
    }
    return best;
  }

  /// 对齐到指定课文；相似度不达标返回 null。
  static TextbookAlignResult? alignToTrack(
    List<WordTimestamp> words,
    TextbookTrack track, {
    bool clauseLevel = false,
  }) {
    if (words.isEmpty || !track.isAlignable) return null;

    final asr = _CharStream.fromWords(words);
    final tbSentences = clauseLevel
        ? [
            for (final sentence in track.sentences)
              ...splitReadingClauses(sentence),
          ]
        : track.sentences;
    final tbNorm = <String>[];
    var tbLength = 0;
    for (final sentence in tbSentences) {
      final normalized = normalizeText(sentence);
      tbNorm.add(normalized);
      tbLength += normalized.length;
    }
    if (asr.chars.length < kMinComparableChars ||
        tbLength < kMinComparableChars) {
      return null;
    }

    final n = asr.chars.length;
    final m = tbLength;
    // 长度悬殊快速排除（例如整册音频对单篇课文）。
    if ((n - m).abs() / (n > m ? n : m) > _maxLenRatioGap) return null;
    if ((n + 1) * (m + 1) > _maxDpCells) return null;

    final matched = _lcsMatches(asr.chars, _flatten(tbNorm));
    final lcs = matched.length;
    final score = 2 * lcs / (n + m);
    if (score < kMinMatchScore) return null;

    // 课文句边界在规范化文本里的偏移：0, len(s0), len(s0)+len(s1), ...
    final boundaries = List<int>.filled(tbSentences.length + 1, 0);
    for (var i = 0; i < tbSentences.length; i++) {
      boundaries[i + 1] = boundaries[i] + tbNorm[i].length;
    }

    final times = <int>[];
    for (final boundary in boundaries) {
      times.add(_splitMs(asrPosForBoundary(matched, boundary, n), asr));
    }
    // 严格递增（§五十四 packaging safety：end > start 且不重叠）。
    for (var i = 1; i < times.length; i++) {
      if (times[i] <= times[i - 1]) times[i] = times[i - 1] + 1;
    }

    final drafts = <DraftSentence>[
      for (var i = 0; i < tbSentences.length; i++)
        DraftSentence(
          startMs: times[i],
          endMs: times[i + 1],
          // 字幕显示课文标准句（含标点），ASR 错字不影响最终字幕。
          text: tbSentences[i],
        ),
    ];
    return TextbookAlignResult(track: track, score: score, sentences: drafts);
  }

  /// 规范化：只保留可比字符（汉字 / ASCII 字母数字），全角转半角、
  /// 大写转小写，丢弃所有标点与空白。简繁体按 [_tradToSimp] 折叠——
  /// whisper 中文输出偶发繁体，不折叠会把整篇得分拉到阈值以下。
  static String normalizeText(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF)) {
        final simplified = _tradToSimp[String.fromCharCode(rune)];
        buffer.write(simplified ?? String.fromCharCode(rune));
      } else if (rune >= 0x30 && rune <= 0x39) {
        buffer.writeCharCode(rune); // 0-9
      } else if (rune >= 0x41 && rune <= 0x5A) {
        buffer.writeCharCode(rune + 32); // A-Z -> a-z
      } else if (rune >= 0x61 && rune <= 0x7A) {
        buffer.writeCharCode(rune); // a-z
      } else if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.writeCharCode(rune - 0xFF10 + 0x30); // 全角数字
      } else if (rune >= 0xFF21 && rune <= 0xFF3A) {
        buffer.writeCharCode(rune - 0xFF21 + 0x61); // 全角大写
      } else if (rune >= 0xFF41 && rune <= 0xFF5A) {
        buffer.writeCharCode(rune - 0xFF41 + 0x61); // 全角小写
      }
      // 其余（标点/空白/假名）一律丢弃。
    }
    return buffer.toString();
  }

  /// 给定课文规范化偏移 [tbPos]（句边界），求它在 ASR 规范化字符流里的
  /// 位置：边界 = 前缀里最后一个匹配字符的下一个位置；前缀没有任何
  /// 匹配时退到后缀里第一个匹配字符的位置。
  static int asrPosForBoundary(
    List<(int, int)> matches,
    int tbPos,
    int asrLength,
  ) {
    var pos = -1;
    for (final (tbIndex, asrIndex) in matches) {
      if (tbIndex < tbPos) {
        if (asrIndex > pos) pos = asrIndex;
      } else {
        break; // matches 按 tbIndex 升序
      }
    }
    if (pos >= 0) return pos + 1;
    for (final (tbIndex, asrIndex) in matches) {
      if (tbIndex >= tbPos) return asrIndex;
    }
    return asrLength;
  }

  /// 课文朗读模式的单元边界标点（与 SegmentationService 的朗读模式一致）：
  /// 逗号/句号/分号/冒号/问叹号后切开；顿号（、）不切。
  static const String _clauseEndChars = '，,。！？；：…—';

  /// 把一句课文按朗读单元切开（句末标点随前一个单元带走）。
  ///
  /// 「山上山下有吃的、玩的，还有看的。」→
  /// 「山上山下有吃的、玩的，」「还有看的。」
  /// 「床前明月光，」→「床前明月光，」（整行一个单元）。
  static List<String> splitReadingClauses(String sentence) {
    final clauses = <String>[];
    final buffer = StringBuffer();
    for (final rune in sentence.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(ch);
      if (_clauseEndChars.contains(ch)) {
        clauses.add(buffer.toString());
        buffer.clear();
      }
    }
    final tail = buffer.toString();
    if (tail.isNotEmpty) {
      // 无标点的尾巴：并入最后一个单元（避免只剩一两个字的碎单元）。
      if (clauses.isEmpty) {
        clauses.add(tail);
      } else {
        clauses[clauses.length - 1] += tail;
      }
    }
    return clauses;
  }

  /// ASR 规范化字符位置 → 媒体时间：落在相邻词的时间中点（天然吸掉
  /// 词间停顿）；边界落在同一个词内部时取该词的 endMs。
  static int _splitMs(int asrPos, _CharStream asr) {
    if (asrPos <= 0) return asr.words.first.startMs;
    if (asrPos >= asr.chars.length) return asr.words.last.endMs;
    final prevWord = asr.charWord[asrPos - 1];
    final nextWord = asr.charWord[asrPos];
    if (nextWord > prevWord) {
      final prevEnd = asr.words[prevWord].endMs;
      final nextStart = asr.words[nextWord].startMs;
      // 词重叠（窗口接缝抖动）时退到 prevEnd，保证不重叠。
      return nextStart > prevEnd ? (prevEnd + nextStart) ~/ 2 : prevEnd;
    }
    return asr.words[prevWord].endMs;
  }

  /// LCS 全矩阵 + 回溯，返回匹配对列表 (tbIndex, asrIndex)，均严格升序。
  static List<(int, int)> _lcsMatches(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    final dp = Int32List((n + 1) * (m + 1));
    int at(int i, int j) => i * (m + 1) + j;
    for (var i = 1; i <= n; i++) {
      final ai = a[i - 1];
      for (var j = 1; j <= m; j++) {
        dp[at(i, j)] = ai == b[j - 1]
            ? dp[at(i - 1, j - 1)] + 1
            : (dp[at(i - 1, j)] >= dp[at(i, j - 1)]
                ? dp[at(i - 1, j)]
                : dp[at(i, j - 1)]);
      }
    }
    final pairs = <(int, int)>[];
    var i = n;
    var j = m;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        pairs.add((j - 1, i - 1));
        i--;
        j--;
      } else if (dp[at(i - 1, j)] >= dp[at(i, j - 1)]) {
        i--;
      } else {
        j--;
      }
    }
    return pairs.reversed.toList(growable: false);
  }

  static List<String> _flatten(List<String> parts) {
    if (parts.length == 1) return parts[0].split('');
    final all = <String>[];
    for (final part in parts) {
      all.addAll(part.split(''));
    }
    return all;
  }
}

/// ASR 词流的规范化字符展开：每个规范化字符都能回答「我属于第几个词」，
/// 句边界因此能落到词时间轴上。
class _CharStream {
  _CharStream.fromWords(List<WordTimestamp> inputWords) {
    final chars = <String>[];
    final charWord = <int>[];
    for (var w = 0; w < inputWords.length; w++) {
      for (final ch in TextbookSentenceAligner.normalizeText(inputWords[w].word)
          .split('')) {
        chars.add(ch);
        charWord.add(w);
      }
    }
    this.chars = chars;
    this.charWord = charWord;
    words = inputWords;
  }

  late final List<String> chars;
  late final List<int> charWord;
  late final List<WordTimestamp> words;
}

/// 高频简繁异体字折叠表（只收录课文常用字；未收录的繁体字按原样保留，
/// 由 0.70 的阈值容忍）。
const Map<String, String> _tradToSimp = {
  '個': '个', '們': '们', '來': '来', '對': '对', '時': '时', '會': '会',
  '說': '说', '話': '话', '學': '学', '開': '开', '關': '关', '門': '门',
  '問': '问', '間': '间', '兒': '儿', '東': '东', '車': '车', '馬': '马',
  '鳥': '鸟', '語': '语', '讀': '读', '書': '书', '筆': '笔', '紙': '纸',
  '詩': '诗', '觀': '观', '聽': '听', '邊': '边', '還': '还', '這': '这',
  '裡': '里', '裏': '里', '後': '后', '發': '发', '見': '见', '貝': '贝',
  '現': '现', '長': '长', '麼': '么', '為': '为', '經': '经', '動': '动',
  '雲': '云', '電': '电', '聲': '声', '農': '农', '樹': '树', '葉': '叶',
  '風': '风', '萬': '万', '與': '与', '義': '义', '樂': '乐', '機': '机', '權': '权',
  '歷': '历', '廠': '厂', '廣': '广', '慶': '庆', '導': '导', '層': '层',
  '歲': '岁', '從': '从', '復': '复', '應': '应', '懷': '怀', '戶': '户',
  '護': '护', '報': '报', '親': '亲', '億': '亿', '點': '点', '熱': '热',
  '無': '无', '藝': '艺', '買': '买', '賣': '卖', '頭': '头', '實': '实',
  '寫': '写', '軍': '军', '興': '兴', '舉': '举', '濟': '济', '於': '于',
  '單': '单', '嚴': '严', '羅': '罗', '職': '职', '聯': '联', '運': '运',
  '進': '进', '遠': '远', '過': '过', '達': '达', '選': '选', '錢': '钱',
  '鐘': '钟', '錯': '错', '陽': '阳', '際': '际', '難': '难', '響': '响',
  '顧': '顾', '飛': '飞', '館': '馆', '驚': '惊', '鮮': '鲜', '龍': '龙',
  '劃': '划', '講': '讲', '論': '论', '記': '记', '許': '许', '詞': '词',
  '課': '课', '誰': '谁', '調': '调', '談': '谈', '請': '请', '識': '识',
  '議': '议', '讓': '让', '變': '变', '貧': '贫', '貴': '贵', '費': '费',
  '質': '质', '較': '较', '輕': '轻', '輛': '辆', '遲': '迟', '辦': '办',
  '醫': '医', '鋼': '钢', '錄': '录', '險': '险', '雙': '双', '離': '离',
  '靈': '灵', '靜': '静', '頂': '顶', '項': '项', '順': '顺', '須': '须',
  '願': '愿', '顏': '颜', '類': '类', '飯': '饭', '養': '养', '驗': '验',
  '體': '体', '專': '专', '業': '业', '叢': '丛', '絲': '丝', '兩': '两',
  '亞': '亚', '產': '产', '亂': '乱', '爭': '争', '傳': '传', '價': '价',
  '儀': '仪', '蘭': '兰', '則': '则', '剛': '刚', '創': '创', '決': '决',
  '況': '况', '溫': '温', '測': '测', '湯': '汤', '準': '准', '滿': '满',
  '潤': '润', '漢': '汉', '營': '营', '爺': '爷', '狀': '状', '猶': '犹',
  '貓': '猫', '黃': '黄', '給': '给', '緊': '紧', '縣': '县', '級': '级',
  '紅': '红', '綠': '绿', '線': '线', '壞': '坏', '堅': '坚',
  '備': '备', '夢': '梦', '處': '处', '務': '务', '勝': '胜', '勞': '劳',
  '區': '区', '醜': '丑', '餓': '饿', '驅': '驱',
  '龜': '龟', '婦': '妇', '媽': '妈', '嬰': '婴', '孫': '孙', '寶': '宝',
  '將': '将', '屬': '属', '峽': '峡', '嶺': '岭', '幫': '帮', '幹': '干',
  '庫': '库', '廳': '厅', '強': '强', '彈': '弹', '徵': '征', '憶': '忆',
  '掛': '挂', '擔': '担', '擊': '击', '據': '据', '擁': '拥', '撲': '扑',
  '敵': '敌', '斷': '断', '舊': '旧',
};
