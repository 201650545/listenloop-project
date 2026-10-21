/// **口令（唤醒词）检测** —— 2026-10-21。
///
/// 郭老师的需求：
/// > 「给这个按钮增加实时识别功能。但为了避免它一直识别，我们需要设置一个
/// > 识别要求，即录制一个口令（口令可由用户自定义，比如"开始朗读课文"）。
/// > 当用户说出自定义口令，且系统准确识别到之后，才会触发正式测试。」
///
/// 做法：**流式识别 + 文本匹配**。
///
/// 为什么不用 sherpa 的 `KeywordSpotter`：
///   · 它要求 transducer 模型 + 另配一份含关键词的词表 ⇒ 用户每改一次口令
///     就要重生成词表、重新推模型；
///   · 我们已经有流式识别在跑（同一块音频、同一份模型），口令检测只是
///     **在已有的文本上做一次匹配**，零额外成本、零额外模型、任意自定义。
///
/// 归一化：ASR 输出里可能有标点、空白、全角/半角差异 ⇒ 匹配前先洗一遍。
library;

/// 把 ASR 文本归一化成「便于匹配口令」的形态。
///
/// 处理：
///   · 去掉所有标点（中英文）与空白
///   · 全角 → 半角（ＡＢＣ → ABC，数字同理）
///   · 统一小写
String normalizeForWakeMatch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    // 全角 ASCII（！-～）→ 半角
    var c = rune;
    if (c >= 0xFF01 && c <= 0xFF5E) {
      c -= 0xFEE0;
    }
    if (c >= 0x3000 && c <= 0x303F) {
      continue; // CJK 标点
    }
    if (_isAsciiPunct(c)) continue;
    if (_isWhitespace(c)) continue;
    buffer.writeCharCode(c);
  }
  return buffer.toString().toLowerCase();
}

bool _isAsciiPunct(int c) =>
    (c >= 0x21 && c <= 0x2F) ||
    (c >= 0x3A && c <= 0x40) ||
    (c >= 0x5B && c <= 0x60) ||
    (c >= 0x7B && c <= 0x7E);

bool _isWhitespace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0A0;

// ─────────────────────────────────────────────────────────────
// 同音/近音容错表
// ─────────────────────────────────────────────────────────────

/// 口令里常见的**同音字**替换对：ASR 可能把「始」听成「使/市/是」这类。
///
/// 每一项 = [标准写法, 其它读法…, 同音字写法…]（单字候选放在最后）。
const List<List<String>> _homophoneGroups = [
  ['始', 'shi', '使', '市', '是', '驶', '式'],
  ['读', 'du', '独', '度', '渡', '毒'],
  ['课', 'ke', '刻', '科', '颗'],
  ['文', 'wen', '闻', '蚊'],
  ['开', 'kai', '该', '改'],
];

/// 口令判定结果。
enum WakeMatch {
  /// 没匹配上。
  none,

  /// **严格命中**：归一化文本里完整包含口令。
  exact,

  /// **宽松命中**：完整包含 + 允许一处同音字替换。
  loose,
}

/// 口令检测器。
///
/// 用法（流式）：
/// ```dart
/// final detector = WakePhraseDetector(phrase: '开始朗读');
/// stream.listen((text) {
///   final m = detector.check(text);
///   if (m != WakeMatch.none) { /* 触发正式测试 */ }
/// });
/// ```
///
/// 状态机：
///   · [check] 每次喂一段**累积文本**（流式识别吐的是累积结果）；
///   · 命中后 [consume] 把「已用于触发的部分」切掉，避免同一段音频二次触发；
///   · [reset] 换一句/换一次测试时清空。
class WakePhraseDetector {
  WakePhraseDetector({required String phrase})
      : _phrase = phrase,
        _normalized = normalizeForWakeMatch(phrase);

  final String _phrase;

  /// 归一化后的口令（匹配时用它）。
  final String _normalized;

  /// 归一化后的口令（公开给 UI 预览用）。
  String get normalized => _normalized;

  /// 原始口令（给 UI 显示用）。
  String get display => _phrase;

  bool _fired = false;

  /// 已经触发过（本次不再重复触发）。
  bool get fired => _fired;

  /// 累积文本里「已触发过的那一段」的结束位置（用于切掉）。
  int _consumedUpTo = 0;

  /// 待确认的命中**文本**（**稳定性确认**用）。
  ///
  /// 2026-10-21 评审意见：流式识别的中间结果是**会变的**（ASR 会修正前面的
  /// 字）⇒ 只凭一次命中就触发，会被临时的错字骗到。
  /// ⇒ 要求**连续两次**识别更新都命中、且**匹配到的文本一致**，才算真触发。
  ///
  /// ⚠️ 比的是**文本**不是位置：ASR 把「开始使读」修正成「开便朗读」时，
  ///   两者的结束位置相同、但内容不同 ⇒ 只比位置会漏掉这种修正。
  String? _pendingWindow;

  /// 连续命中同一段文本的次数。
  int _pendingCount = 0;

  /// 检查一段累积文本。
  ///
  /// [text] 是流式识别的**累积**结果（越往后越长）。
  ///
  /// 返回 [WakeMatch.none] 表示"还没确定"（可能是没命中，也可能是命中了但
  /// 还没通过稳定性确认）—— 对调用方来说两者的处理方式相同：再等等。
  WakeMatch check(String text) {
    if (_fired) return WakeMatch.none;
    final norm = normalizeForWakeMatch(text);
    if (norm.isEmpty || _normalized.isEmpty) {
      _pendingWindow = null;
      _pendingCount = 0;
      return WakeMatch.none;
    }

    // 严格包含。
    final idx = norm.indexOf(_normalized);
    if (idx >= 0) {
      // 严格命中（字字相同）**立即触发**：误触发风险很低，
      // 而流式识别每 300~500ms 才来一次更新，等第二次会平白多半天延迟。
      _fired = true;
      _consumedUpTo = idx + _normalized.length;
      _pendingWindow = null;
      _pendingCount = 0;
      return WakeMatch.exact;
    }

    // 宽松：允许一处同音字替换。
    //
    // ⚠️ 2026-10-21 修：原来宽松命中把 `_consumedUpTo` 设成 **norm.length**
    //    ⇒ consume() 会把**口令后面的正文一起切掉**（孩子连着说
    //    「开始朗读池塘里」时，"池塘里"被吃掉）。现在返回**真实匹配窗口的
    //    结束位置**，只切口令那一段。
    //
    //    宽松命中**要连续两次位置一致**才触发：它允许一处同音字替换 ⇒
    //    「开始首读」这种半错的话也会命中 ⇒ 误触发风险明显高于严格匹配。
    //    而流式识别的中间结果**会变**（ASR 会修正前面的字）⇒ 只凭一次
    //    命中就触发，容易被临时的错字骗到。
    final hit = _looseHit(norm);
    if (hit == null) {
      _pendingWindow = null;
      _pendingCount = 0;
      return WakeMatch.none;
    }
    final window = norm.substring(hit.$1, hit.$2);
    if (_pendingWindow == window) {
      _pendingCount++;
    } else {
      _pendingWindow = window;
      _pendingCount = 1;
    }
    if (_pendingCount < 2) {
      return WakeMatch.none; // 第一次只记候选，等下一次识别更新确认
    }
    _fired = true;
    _consumedUpTo = hit.$2;
    return WakeMatch.loose;
  }

  /// 宽松匹配：口令的某个字被换成一个同音字时，返回匹配窗口的 (start, end)。
  ///
  /// 窗口在归一化文本上滑动；恰好一处同音替换才算命中。
  (int, int)? _looseHit(String norm) {
    final chars = _normalized.split('');
    final n = chars.length;
    if (n == 0 || norm.length < n) return null;
    for (var start = 0; start + n <= norm.length; start++) {
      var diffs = 0;
      var ok = true;
      for (var k = 0; k < n; k++) {
        final c = norm[start + k];
        if (c == chars[k]) continue;
        if (_alternativesFor(chars[k]).contains(c)) {
          diffs++;
          continue;
        }
        ok = false;
        break;
      }
      if (ok && diffs == 1) return (start, start + n);
    }
    return null;
  }

  /// 某个字的同音候选。
  List<String> _alternativesFor(String ch) {
    final out = <String>[];
    for (final group in _homophoneGroups) {
      // group = [标准写法, 拼音写法…, 同音字写法…]
      final std = group.first;
      if (!std.contains(ch)) continue;
      for (final alt in group.skip(1)) {
        if (alt.length == 1) out.add(alt);
      }
    }
    return out;
  }

  /// 切掉「已用于触发」的那一段，返回**剩下的**文本（正式朗读的起点）。
  ///
  /// 口令说完之后，孩子接着读课文 ⇒ 识别的累积文本里，口令之后的部分才是
  /// 课文内容。切掉它，正式判定才不会被口令的字污染。
  String consume(String text) {
    if (_consumedUpTo <= 0) return text;
    final norm = normalizeForWakeMatch(text);
    if (_consumedUpTo >= norm.length) return '';
    return norm.substring(_consumedUpTo);
  }

  /// 清空（换一次测试 / 复位 / 判完一句回到"等口令"）。
  void reset() {
    _fired = false;
    _consumedUpTo = 0;
    _pendingWindow = null;
    _pendingCount = 0;
  }
}
