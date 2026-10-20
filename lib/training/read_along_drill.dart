/// 跟读验收·错字练习队列（WP-H 最小形态 v3）。
///
/// 目的（2026-10-16 郭老师拍板）：学生跟读一句，读不准的字**单独、很大地**
/// 列出来并附拼音，逐个让孩子再读；读准了才收队；全部练完再整句读一遍，
/// 整句也读准了才算这句完成。最多练 [maxRounds] 轮整句重读，超过就放过去
/// ——不把孩子钉死在一个字上。
///
/// 与旧形态的区别：旧形态是「读不准 → 原声重放 → 再读整句」，反复整句，
/// 孩子卡在一两个字上却每次都要重读全句。新形态直接定位到字。
///
/// 纯逻辑：不接麦克风、不依赖 Flutter UI、可单测。
library;

import 'package:flutter/foundation.dart';

import '../utils/chinese_pinyin.dart';
import 'dictation_engine.dart';
import 'read_along_session.dart';

export 'read_along_session.dart' show ReadAlongResult;

/// 队列里一个待练的字。
class DrillTarget {
  const DrillTarget({
    required this.char,
    required this.pinyin,
    required this.missing,
  });

  /// 要练的汉字。
  final String char;

  /// 带声调拼音（单字练习要管声调，2026-10-16 拍板）。
  final String pinyin;

  /// 是不是漏读（漏读也要练，孩子常常是根本没认出这个字）。
  final bool missing;

  @override
  String toString() => 'DrillTarget($char/$pinyin${missing ? ',漏读' : ''})';
}

/// 整句跟读与字词练习的达成状态（落实 2026-10-17 专家评审：两轮放过与教学掌握严格解耦）。
enum ReadAlongDrillResultState {
  /// 正在练习中
  inProgress,

  /// 真实通过（所有字及整句全部准确读准）
  verified,

  /// 轮数用尽放行（流程放行，但明确记录未完全掌握，严禁伪装为 verified）
  roundsExhausted,

  /// 家长/教师一键纠偏放行
  parentConfirmed,
}

/// 一句跟读的练习进度。跨整句重读存活，进下一句时复位。
///
/// 用法（上层 UI）：
/// 1. `record(result)` —— 整句判分结果进来，抽出读不准的字入队
/// 2. `next()` —— 当前字读准了，取下一个
/// 3. `markCurrentMissed()` —— 当前字没读准（不计次、不卡，继续同一个字）
/// 4. `finish()` —— 队列空了且整句重读达标，这句完成
class ReadAlongDrill extends ChangeNotifier {
  ReadAlongDrill({this.maxRounds = 2});

  /// 整句重读最多几轮。超过就放过去（郭老师拍板 A：不把孩子钉死）。
  final int maxRounds;

  /// 待练的字队列（按句中出现顺序）。
  final List<DrillTarget> _queue = [];

  /// 当前练到队列第几个（0 基；== _queue.length 表示队列已空）。
  int _cursor = 0;

  /// 已经练完几个字。
  int _cleared = 0;

  /// 整句重读第几轮（1 基：第 1 轮就是最初那次整句读）。
  int _round = 1;

  /// 这句是否已收队（队列空 + 整句读准，或超过轮数放过去）。
  bool _done = false;

  /// 放过去的标记：轮数用尽仍未读准（区别于真正读准）。
  bool _givenUp = false;

  /// 最终掌握状态（严禁将 roundsExhausted 伪装为 verified）。
  ReadAlongDrillResultState _resultState = ReadAlongDrillResultState.inProgress;

  List<DrillTarget> get queue => List.unmodifiable(_queue);

  /// 当前要练的字；队列已空时返回 null。
  DrillTarget? get current => _cursor < _queue.length ? _queue[_cursor] : null;

  /// 还剩几个字要练。
  int get remaining => _queue.length - _cursor;

  /// 已练完几个字。
  int get cleared => _cleared;

  /// 整句重读第几轮（1 基）。
  int get round => _round;

  /// 这句是否完成。
  bool get done => _done;

  /// 是否因轮数用尽而放过去。
  bool get givenUp => _givenUp;

  /// 教学掌握状态（verified / roundsExhausted / parentConfirmed）。
  ReadAlongDrillResultState get resultState => _resultState;

  /// 队列是否为空（= 该回整句重读了）。
  bool get queueEmpty => _cursor >= _queue.length;

  // ------------------------------------------------------------------ 推进

  /// 整句判分结果进来：抽出读不准的字，按顺序入队。
  ///
  /// [result] 需带 `expectedText`（期望汉字串）、`expectedPinyin`（带声调
  /// 拼音行）与 `ops`（音节级 diff）。读准的字不入队。
  ///
  /// 返回本次入队的字；全读准则返回空表。
  List<DrillTarget> record(ReadAlongResult result) {
    if (_done) return const <DrillTarget>[];
    final targets = <DrillTarget>[];
    final ops = result.ops;
    // 只取期望位有内容的 op（位置轴），按出现顺序。
    final positional = ops.where((op) => op.expected != null).toList(
          growable: false,
        );
    if (positional.isEmpty) return targets;

    final chars = result.expectedText.runes
        .map((r) => String.fromCharCode(r))
        .where(_isHanzi)
        .toList(growable: false);
    final syllables =
        result.expectedPinyin.split(' ').where((t) => t.isNotEmpty).toList();

    for (var i = 0; i < positional.length; i++) {
      final op = positional[i];
      // matched 已读准，不入队。
      if (op.type == DictationDiffType.matched) continue;
      final char = i < chars.length ? chars[i] : '';
      final pinyin = i < syllables.length ? syllables[i] : (op.expected ?? '');
      if (char.isEmpty && pinyin.isEmpty) continue;
      targets.add(DrillTarget(
        char: char.isEmpty ? '?' : char,
        pinyin: pinyin,
        missing: op.type == DictationDiffType.missing,
      ));
    }

    _queue
      ..clear()
      ..addAll(targets);
    _cursor = 0;
    _cleared = 0;
    notifyListeners();
    return targets;
  }

  /// 当前字读准了：收队，光标后移。队列清空时自动判定这句是否完成。
  void markCurrentCleared() {
    if (current == null || _done) return;
    _cursor++;
    _cleared++;
    if (queueEmpty) _settle();
    notifyListeners();
  }

  /// 当前字没读准：不计次、不卡（郭老师拍板 A：读准为止）。
  /// 光标不动，下一次仍练同一个字。
  void markCurrentMissed() {
    if (_done) return;
    notifyListeners();
  }

  /// 手动跳过当前这个字（家长/老师介入）。同样不算失败。
  void skipCurrent() {
    if (current == null || _done) return;
    _cursor++;
    _resultState = ReadAlongDrillResultState.parentConfirmed;
    if (queueEmpty) _settle();
    notifyListeners();
  }

  /// 家长确认该字已掌握或整句放行（家长介入兜底，区别于 verified）。
  void confirmByParent() {
    if (current == null || _done) return;
    _cursor++;
    _cleared++;
    _resultState = ReadAlongDrillResultState.parentConfirmed;
    if (queueEmpty) _settle();
    notifyListeners();
  }

  /// 整句重读完成一轮：轮数 +1；若超过 [maxRounds] 仍未读准则放过去。
  /// （注意：放过去仅代表流程结束，记录为 roundsExhausted，严禁混淆为 verified）
  void advanceRound() {
    if (_done) return;
    _round++;
    if (_round > maxRounds) {
      _done = true;
      _givenUp = true;
      _resultState = ReadAlongDrillResultState.roundsExhausted;
    }
    notifyListeners();
  }

  /// 整句读准：这句完成（无论是否还有轮数）。
  void finish() {
    if (_done) return;
    _done = true;
    _givenUp = false;
    _resultState = ReadAlongDrillResultState.verified;
    notifyListeners();
  }

  /// 复位：进下一句。
  void reset() {
    _queue.clear();
    _cursor = 0;
    _cleared = 0;
    _round = 1;
    _done = false;
    _givenUp = false;
    _resultState = ReadAlongDrillResultState.inProgress;
    notifyListeners();
  }

  void _settle() {
    // 队列清空只代表「字都练过了」，还要整句再读一遍才算完成；
    // 这一句由 UI 在整句重读判准后调 [finish]。
  }
}

bool _isHanzi(String ch) {
  final code = ch.codeUnitAt(0);
  return code >= 0x4E00 && code <= 0x9FA5;
}

/// 一个格子的实时状态（郭老师 2026-10-16：读的过程就要红绿反馈）。
enum LiveSlot {
  /// 还没读到。
  pending,

  /// 读准了。
  hit,

  /// 读错了（识别出的音节与期望不同音）。
  wrong,

  /// 还没读到，但 app 已经听到点东西（半截音）。
  partial,
}

/// 边说边判的实时快照（2026-10-16 郭老师拍板：不能等整句读完再判）。
///
/// 孩子读一句课文要十几秒，等他说完整句再出结果，等待感能把人耗光。
/// 改成录音途中每拍解一次已采集音频，把**已经读到的字**当场标出来。
///
/// [slots] 逐格状态：要读的字在上面一行，实时识别出的字在下面一行，
/// 对的当场绿、错的当场红。孩子读到哪一眼能看到。
///
/// 判定口径与整句判定完全一致（比音不比字、轻声宽松、短句豁免都不碰），
/// 只是输入是「目前为止的音频」而不是完整音频。终判仍走完整 wav，
/// 快照只负责「让孩子立刻看到自己读对了」。
class LiveProgress {
  const LiveProgress({
    required this.slots,
    required this.totalSyllables,
    required this.complete,
    required this.spoken,
  });

  /// 空快照（还没解出东西）：不更新 UI。
  static const LiveProgress empty = LiveProgress(
    slots: <LiveSlot>[],
    totalSyllables: 0,
    complete: false,
    spoken: '',
  );

  bool get isEmpty => spoken.isEmpty;

  /// 逐格状态，长度 = [totalSyllables]。
  final List<LiveSlot> slots;

  /// 期望音节总数。
  final int totalSyllables;

  /// 期望音节是否已全部命中。
  final bool complete;

  /// 目前已识别出的文本（纯展示，不进判分）。
  final String spoken;

  /// 已读准的音节数。
  int get matchedCount => slots.where((s) => s == LiveSlot.hit).length;

  /// 是否检出读错的字。
  bool get wrong => slots.contains(LiveSlot.wrong);

  /// 0~1，用于进度条。
  double get ratio => totalSyllables <= 0
      ? 0
      : (matchedCount / totalSyllables).clamp(0.0, 1.0);
}

/// 实时判分器：从「到目前为止的识别文本」推出 [LiveProgress]。
///
/// 纯函数、可单测。实现走音节对齐：期望音节逐个与识别音节比，命中即算
/// 读准——不要求严格等长（孩子可能中间漏一个），但要求顺序一致。
class ReadAlongLiveJudge {
  const ReadAlongLiveJudge._();

  /// [expectedToned] 课文原句的带声调拼音行（`normalizeWithTones` 的输出）。
  /// [actual] 目前为止的识别文本。
  static LiveProgress progress({
    required String expectedToned,
    required String actual,
  }) {
    final expectedSylls = _syllables(expectedToned);
    if (expectedSylls.isEmpty || actual.trim().isEmpty) {
      return LiveProgress.empty;
    }
    final actualSylls = _syllables(
      ChinesePinyin.toPinyinLine(actual.trim().toLowerCase()),
    );
    if (actualSylls.isEmpty) return LiveProgress.empty;

    // 逐格：前 matched 个命中（hit）；第一个不同的位置记 wrong；
    // 再往后如果识别串更长，说明孩子还在往下读，记 partial。
    final slots = <LiveSlot>[];
    var matched = 0;
    var wrongAt = -1;
    for (var i = 0; i < expectedSylls.length; i++) {
      if (i >= actualSylls.length) {
        slots.add(LiveSlot.pending);
        continue;
      }
      if (_toneless(expectedSylls[i]) == _toneless(actualSylls[i])) {
        slots.add(LiveSlot.hit);
        matched++;
      } else if (wrongAt < 0) {
        wrongAt = i;
        slots.add(LiveSlot.wrong);
      } else {
        slots.add(LiveSlot.partial);
      }
    }

    return LiveProgress(
      slots: slots,
      totalSyllables: expectedSylls.length,
      complete: matched >= expectedSylls.length,
      spoken: actual.trim(),
    );
  }

  static List<String> _syllables(String tonedLine) => tonedLine
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList(growable: false);

  /// 去声调（与整句判定同一套 [_toneMarks]）。
  static String _toneless(String syllable) {
    final sb = StringBuffer();
    for (final r in syllable.runes) {
      final ch = String.fromCharCode(r);
      sb.write(_toneMarks[ch] ?? ch);
    }
    return sb.toString();
  }

  static const Map<String, String> _toneMarks = {
    'ā': 'a', 'á': 'a', 'ǎ': 'a', 'à': 'a',
    'ē': 'e', 'é': 'e', 'ě': 'e', 'è': 'e',
    'ī': 'i', 'í': 'i', 'ǐ': 'i', 'ì': 'i',
    'ō': 'o', 'ó': 'o', 'ǒ': 'o', 'ò': 'o',
    'ū': 'u', 'ú': 'u', 'ǔ': 'u', 'ù': 'u',
    'ǖ': 'v', 'ǘ': 'v', 'ǚ': 'v', 'ǜ': 'v', 'ü': 'v',
    'ê': 'e', 'ḿ': 'm', 'ń': 'n', 'ň': 'n', 'ǹ': 'n',
  };
}

/// 单字判定（2026-10-16 郭老师拍板 B：单字练习要管声调）。
///
/// 与整句判定的区别：整句比**不带声调**拼音（稳），单字比**带声调**——
/// 「霜」读成 shuang3 在整句里算对（比音不比字），在单字练习里不算。
///
/// [actual] 是 ASR 识别文本（可能多字、可能空）。取第一个有效音节与
/// [expectedPinyin] 比；识别为空时返回 [DrillVerdict.unclear]（没听清，
/// 不计失败）。
enum DrillVerdict {
  /// 读准（声调一致）。
  hit,

  /// 声母韵母对、声调不对。
  toneOnly,

  /// 音不对。
  miss,

  /// 没听清（识别为空或明显不是这个字）。
  unclear,
}

class ReadAlongDrillJudge {
  const ReadAlongDrillJudge._();

  static DrillVerdict judgeChar({
    required String char,
    required String expectedPinyin,
    required String actual,
  }) {
    final expected = expectedPinyin.trim();
    if (expected.isEmpty || char.isEmpty) return DrillVerdict.unclear;
    final actualToned = ChinesePinyin.toPinyinLine(
      actual.trim().toLowerCase(),
    ).trim();
    if (actualToned.isEmpty) return DrillVerdict.unclear;

    final actualSylls = actualSyllables(actualToned);
    if (actualSylls.isEmpty) return DrillVerdict.unclear;

    // 单字练习只念这一个字；孩子可能多念（连带上下文），取第一个音节。
    final first = actualSylls.first;
    if (first == expected) return DrillVerdict.hit;

    final wantTone = toneOf(expected);
    final gotTone = toneOf(first);
    // 任一侧没解析出声调（如字典未收录、ASR 吐了非拼音内容），不猜——
    // 判 unclear 让上层「再读一次」，别拿 miss 冤枉孩子。
    if (wantTone == null || gotTone == null) return DrillVerdict.unclear;
    if (wantTone != gotTone) return DrillVerdict.toneOnly;
    return DrillVerdict.miss;
  }

  /// 取拼音行里的音节表。
  static List<String> actualSyllables(String tonedLine) =>
      tonedLine.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  /// 仅调试用：直接看某个汉字的带声调拼音。
  static String debugPinyin(String text) =>
      ChinesePinyin.toPinyinLine(text.toLowerCase()).trim();

  /// 声调号（1~4；无声调符号按 1 声兜底，轻声按 0 处理）。
  static int? toneOf(String syllable) {
    for (final r in syllable.runes) {
      final ch = String.fromCharCode(r);
      final tone = _toneMarks[ch];
      if (tone != null) return tone;
    }
    return null;
  }

  /// 声调符号 → 声调序号。
  static const Map<String, int> _toneMarks = {
    'ā': 1, 'ē': 1, 'ī': 1, 'ō': 1, 'ū': 1,
    'á': 2, 'é': 2, 'í': 2, 'ó': 2, 'ú': 2,
    'ǎ': 3, 'ě': 3, 'ǐ': 3, 'ǒ': 3, 'ǔ': 3,
    'à': 4, 'è': 4, 'ì': 4, 'ò': 4, 'ù': 4,
    'ǖ': 1, 'ǘ': 2, 'ǚ': 3, 'ǜ': 4,
  };
}
