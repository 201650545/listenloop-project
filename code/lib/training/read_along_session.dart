/// 跟读验收判分状态机（WP-H 阶段 0：「判分大脑」）。
///
/// 纯逻辑、离线、可单测：不接麦克风、不依赖 Flutter UI 组件、无网络。
/// 录音与权限在 `read_along_recorder.dart`（阶段 1）——本文件只做
/// 「识别文本 → 判定」，外加跨尝试的会话相位管理。
/// 设计依据 `05_任务书\WP-H_跟读验收模式_可执行实现方案_2026-10-10.md`：
///   * §三 行为规则表：读完自动停（门在 WP-B，本文件不管播放）；0.90 过关 /
///     0.95 满星；第 3 次不过停止死循环给出三选；权限被拒降级
///     「仅跟读不评分」；全程没检出语音不算失败、不计重试次数。
///   * §四 判分算法：比音不比字——判定串先归一到拼音再比；判定用
///     **不带声调**拼音（稳），纠错提示另存**带声调**版本（准）；
///     短句容错（≤6 音节错 ≤1 直接放行）；轻声可读可省。
library;

import 'package:flutter/foundation.dart';

import '../creation/asr_engine.dart';
import '../creation/word_timestamp.dart';
import '../utils/chinese_pinyin.dart';
import 'dictation_engine.dart';

/// 会话相位（方案 §六.1）。跨句存活，进下一句由
/// [ReadAlongSession.startSentence] 复位。
enum ReadAlongPhase {
  /// 空闲：一句就绪，尚未开始收音。
  idle,

  /// 收音中：孩子正在跟读。
  listening,

  /// 判分中：wav 已交 [AsrEngine]，等识别结果。
  scoring,

  /// 过关（含满星）：进下一句。
  passed,

  /// 未过关：原声重播，计一次失败。
  failed,

  /// 失败达到 [ReadAlongSession.maxAttempts] 次：停止死循环，由上层给出
  /// 「再听原声 / 看错在哪 / 跳过这句」三选（方案 §三）。
  gaveUp,

  /// 麦克风权限被拒：降级「仅跟读不评分」。粘性态——照读照停不打分，
  /// 直到用户在系统设置里授权后 [ReadAlongSession.resumeScoring]。
  blockedNoMic,
}

/// 单次跟读判定的结论。[giveUp] 只在失败累计达到软上限时出现。
enum ReadAlongVerdict {
  /// 过关但未满星。
  pass,

  /// 满星（必然过关）。
  star,

  /// 未过关，可再来一次。
  retry,

  /// 已到软上限，停止死循环，交上层出三选。
  giveUp,

  /// 识别异常：听到了声音，但有效音节覆盖期望不足三成（v2 真机结论：
  /// 孩子读早了/只蹦出半个字时，ASR 只吐一两个音节）。
  /// 按「没听清」处理——不算失败、不计重试次数、永不给 giveUp。
  unclear,
}

/// 一次跟读判定的完整结果（纯数据）。
class ReadAlongResult {
  const ReadAlongResult({
    required this.passed,
    required this.star,
    required this.score,
    required this.attempt,
    required this.silent,
    required this.coverage,
    required this.matched,
    required this.wrong,
    required this.missing,
    required this.extra,
    required this.ops,
    required this.expectedPinyin,
    required this.actualPinyin,
    required this.verdict,
    this.expectedText = '',
    this.actualText = '',
  });

  /// 是否过关（score ≥ passAt，或命中短句容错豁免）。
  final bool passed;

  /// 是否满星（score ≥ starAt）。满星必然过关。
  final bool star;

  /// 去声调拼音串的 Levenshtein 归一相似度，0~1。
  final double score;

  /// 本次是第几次跟读（1 基）。
  final int attempt;

  /// 全程没检出语音：识别结果归一化为空（方案 §三「噪音/没读」行）。
  /// 不算失败、不计重试次数、永不给 giveUp——把环境静默判成读错会冤枉孩子。
  final bool silent;

  /// 有效音节覆盖率 = 识别音节数 / 期望音节数（0~1）。< 0.30 且非空时
  /// 判 [ReadAlongVerdict.unclear]（没听清，不计失败）——v2 真机结论。
  final double coverage;

  /// 逐音节 diff 计数：匹配。
  final int matched;

  /// 读错（替换类：replaced/spelling/morphology/merged/split）。
  final int wrong;

  /// 漏读。wrong + missing 计入「错字数」（方案 §4.3）。
  final int missing;

  /// 多读。只提示、不判错（方案 §4.3：多写的不算错）。
  final int extra;

  /// 音节级 diff（判定串 = 去声调拼音），供「看错在哪」逐字高亮。
  final List<DictationOp> ops;

  /// 带声调拼音行（§4.2 纠错提示用）：课文期望与识别各一份。
  final String expectedPinyin;
  final String actualPinyin;

  /// 汉字串（2026-10-15 UI 改版用）：期望=课文原句，实际=ASR 识别原文。
  ///
  /// §4.2 判定口径没变（仍比拼音），这里只是把**原文汉字**一并带出来，
  /// 让「应读/读到」对照行以汉字为主、拼音退为小字注解——一二年级
  /// 孩子看不懂纯拼音行，但仍需要拼音来分辨声调错误。
  final String expectedText;
  final String actualText;

  /// 本次判定结论。
  final ReadAlongVerdict verdict;

  /// 错字数 = 读错 + 漏读（多读不算）。
  int get errors => wrong + missing;

  @override
  String toString() =>
      'ReadAlongResult($verdict, score=${score.toStringAsFixed(3)}, '
      'attempt=$attempt, matched=$matched, wrong=$wrong, '
      'missing=$missing, extra=$extra)';
}

/// 跟读验收判分状态机。无状态判定（[judge]）与相位簿记（[phase] /
/// [attempt]）同住一体——上层 UI 只跟这一个对象交互。
class ReadAlongSession extends ChangeNotifier {
  ReadAlongSession({
    required this.engine,
    this.passAt = 0.90,
    this.starAt = 0.95,
    this.maxAttempts = 3,
  })  : assert(passAt > 0 && passAt <= 1, 'passAt 须在 (0, 1]'),
        assert(
          starAt >= passAt && starAt <= 1,
          'starAt 不应低于 passAt，且须 ≤ 1',
        ),
        assert(maxAttempts >= 1, 'maxAttempts 至少为 1');

  /// ASR 引擎。测试注入 [MockAsrEngine]；真机中文档由上层注入
  /// `SherpaOnnxAsrEngine`。只吃 wav **文件路径**，不吃实时流
  /// （方案 §二关键架构洞察）。
  final AsrEngine engine;

  /// 过关阈值（方案 §三：相似度 ≥ 0.90 进下一句）。
  final double passAt;

  /// 满星阈值（方案 §三：≥ 0.95 给满星视觉）。
  final double starAt;

  /// 软上限：失败这么多次就停止死循环，给出三选（方案 §三）。
  final int maxAttempts;

  /// 短句容错（2026-10-17 郭老师与评审红线：彻底废除短句豁免，杜绝读错字依然放行）。
  @Deprecated('Abolished per 2026-10-17 review')
  static const int shortLineMaxChars = 0;

  @Deprecated('Abolished per 2026-10-17 review')
  static const int shortLineMaxErrors = 0;

  /// 识别覆盖率低于此值判 unclear（没听清：只蹦出半个字 / 读早了）。
  /// 覆盖率高得离谱同样判 unclear（读飞了，见 [unclearCoverAbove]）——
  /// 2026-10-15 小米14 实测，4 字初读行录进 14.7 秒，ASR 吐 26 音节。
  static const double unclearCoverBelow = 0.30;

  /// 识别覆盖率高于此值判 unclear（多读成灾）。4 字句只读出 1 个字时
  /// 是 0.25、两个字是 0.50，正常朗读不会到 2 倍；给到 2.0 留足余量，
  /// 只拦「识别音节数是期望两倍以上」这种明显录飞/读飞的情况。
  static const double unclearCoverAbove = 2.0;

  /// 阈值比较 epsilon：只吸收二进制浮点表示误差（如 1−0.05 的尾数抖动；
  /// 真实分差最小也在 1/句长 量级，远大于它），不改变 §三阈值语义。
  static const double _epsilon = 1e-9;

  /// 句末语气词（方案 §4.2「去语气词尾巴」）。只剥句尾，不动句中。
  static const Set<String> _tailParticles = {'啊', '呢', '吧', '吗'};

  /// 轻声字（方案 §4.4，第一版只收设计点名的「们」一类；重叠词尾音节
  /// 在 [_neutralFlags] 里按重复规则另判）。`子/头/儿` 等轻声后缀
  /// 跑通后再精化——别把第一版卡在这上面。
  static const String _neutralToneChar = '们';

  /// 轻声可选位超过这个数就只给「全读 / 全省」两个变体，防止组合爆炸。
  static const int _maxOptionalCombos = 3;

  /// 声调符号 → 无声调字母。
  ///
  /// ǖ/ǘ/ǚ/ǜ/ü 一律归到 v 而不是 u：lǜ（绿）与 lù（路）是不同读音，
  /// 归并会放过真实读音错误。大写形式是兜底（正常管线已先小写化）。
  static const Map<String, String> _toneMarks = {
    'ā': 'a', 'á': 'a', 'ǎ': 'a', 'à': 'a',
    'ē': 'e', 'é': 'e', 'ě': 'e', 'è': 'e',
    'ī': 'i', 'í': 'i', 'ǐ': 'i', 'ì': 'i',
    'ō': 'o', 'ó': 'o', 'ǒ': 'o', 'ò': 'o',
    'ū': 'u', 'ú': 'u', 'ǔ': 'u', 'ù': 'u',
    'ǖ': 'v', 'ǘ': 'v', 'ǚ': 'v', 'ǜ': 'v', 'ü': 'v',
    'ê': 'e', 'ḿ': 'm', 'ń': 'n', 'ň': 'n', 'ǹ': 'n',
    'Ā': 'a', 'Á': 'a', 'Ǎ': 'a', 'À': 'a',
    'Ē': 'e', 'É': 'e', 'Ě': 'e', 'È': 'e',
    'Ī': 'i', 'Í': 'i', 'Ǐ': 'i', 'Ì': 'i',
    'Ō': 'o', 'Ó': 'o', 'Ǒ': 'o', 'Ò': 'o',
    'Ū': 'u', 'Ú': 'u', 'Ǔ': 'u', 'Ù': 'u',
    'Ǖ': 'v', 'Ǘ': 'v', 'Ǚ': 'v', 'Ǜ': 'v', 'Ü': 'v',
  };

  ReadAlongPhase _phase = ReadAlongPhase.idle;

  /// 已失败次数（不是尝试次数：方案 §三只有「不通过」才 +1；
  /// 没检出语音不计）。当前第几次 = [_attempt] + 1。
  int _attempt = 0;

  /// 权限被拒的粘性降级标记（phase 同步打到 blockedNoMic）。
  bool _micBlocked = false;

  /// 熟读档「不拦」（2026-10-15 用户拍板：初读验收 / 熟读不拦）。
  ///
  /// 初读行是 4~8 字的呼吸节拍，过不去就该原声重读；熟读行是十几字的长
  /// 意群，孩子一次读不满是常态，拿同一把 0.90 的尺子卡住进度只会让人放
  /// 弃。打开后判定**照旧**给分、照旧给 pass/star/retry/unclear，只是永远
  /// 不给 [ReadAlongVerdict.giveUp]——没有三选死循环，上层据此把「继续」
  /// 直接摆出来。开与关由上层按当前分段模式（初读 / 熟读）设定。
  bool _lenient = false;

  ReadAlongResult? _lastResult;

  // ------------------------------------------------------------------ 状态

  ReadAlongPhase get phase => _phase;

  /// 已失败次数。
  int get attempt => _attempt;

  /// 评分是否可用。false = 权限被拒的降级态：照读照停，不打分。
  bool get canScore => !_micBlocked;

  /// 最近一次判定结果（没有则为 null）。
  ReadAlongResult? get lastResult => _lastResult;

  /// 熟读「不拦」是否生效：true = 照停照录照给分，但永不卡进度。
  bool get lenient => _lenient;

  /// 切换「不拦」档（初读关、熟读开）。只影响后续判定与相位，不动本次结果——
  /// 中途切档不该把已经摆出来的分数吞掉。
  void setLenient(bool value) {
    if (_lenient == value) return;
    _lenient = value;
    notifyListeners();
  }

  // -------------------------------------------------------------- 生命周期

  /// 一句就绪（进下一句 / 重头）：复位失败计数与结果。
  /// blockedNoMic 是粘性降级态，不受本方法影响——权限没恢复就不评分。
  void startSentence() {
    _attempt = 0;
    _lastResult = null;
    if (!_micBlocked) _phase = ReadAlongPhase.idle;
    notifyListeners();
  }

  /// 一次跟读开始收音。权限被拒的降级态拒绝进入（返回 false）——
  /// 没有权限就不收音，页面也绝不会因此卡死。
  bool beginAttempt() {
    if (_micBlocked) return false;
    _phase = ReadAlongPhase.listening;
    notifyListeners();
    return true;
  }

  /// 本次收音作废（recorder 全程没检出语音，方案 §三「噪音/没读」行）：
  /// 不计入重试次数，phase 回 idle 等孩子再读一次。
  void cancelAttempt() {
    if (_phase == ReadAlongPhase.listening ||
        _phase == ReadAlongPhase.scoring) {
      _phase = ReadAlongPhase.idle;
    }
    notifyListeners();
  }

  /// 提交识别文本判分：phase → passed / failed / gaveUp，
  /// 失败才计数（silent 与 unclear 都不计）。
  ReadAlongResult submit({required String expected, required String actual}) {
    final result = judge(
      expected: expected,
      actual: actual,
      attempt: _attempt + 1,
      lenient: _lenient,
    );
    if (!result.passed &&
        !result.silent &&
        result.verdict != ReadAlongVerdict.unclear) {
      _attempt++;
    }
    _lastResult = result;
    _phase = switch (result.verdict) {
      ReadAlongVerdict.star || ReadAlongVerdict.pass => ReadAlongPhase.passed,
      ReadAlongVerdict.retry || ReadAlongVerdict.unclear =>
        ReadAlongPhase.failed,
      ReadAlongVerdict.giveUp => ReadAlongPhase.gaveUp,
    };
    notifyListeners();
    return result;
  }

  /// 一次完整尝试：临时 wav → [engine] 识别 → 判分。
  ///
  /// 录音、权限与临时文件删除都在 `read_along_recorder.dart`（阶段 1），
  /// 本方法只消费 wav 路径（方案 §二：`AsrEngine.transcribe` 吃文件路径，
  /// 所以跟读不需要流式识别）。
  Future<ReadAlongResult> scoreWav({
    required String expected,
    required String wavPath,
    String? language,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _phase = ReadAlongPhase.scoring;
    notifyListeners();
    final List<WordTimestamp> words;
    try {
      words = await engine.transcribe(
        wavPath,
        language: language,
        onProgress: onProgress ?? (_) {},
        isCancelled: isCancelled ?? () => false,
      );
    } catch (_) {
      // 引擎抛错（模型缺文件等）： phase 退回 listening 让孩子能再读一次，
      // 异常继续上抛让上层记录。不假装判过，也不把页面钉死在「判分中」。
      _phase = ReadAlongPhase.listening;
      notifyListeners();
      rethrow;
    }
    // 中文 ASR 的 word 即词片段，无分隔拼接；归一化会剥掉其余字符。
    // 本功能只开中文课时（方案 §六.4 边界），不做拉丁语分词拼接。
    final actual = words.map((w) => w.word).join();
    return submit(expected: expected, actual: actual);
  }

  /// 权限被拒 → 降级「仅跟读不评分」（方案 §三）。粘性，直到
  /// [resumeScoring]；给一次「去开启权限」入口由上层 UI 负责。
  void blockScoringNoMic() {
    _micBlocked = true;
    _phase = ReadAlongPhase.blockedNoMic;
    notifyListeners();
  }

  /// 用户在系统设置里授予麦克风权限后重新启用评分。
  void resumeScoring() {
    if (!_micBlocked) return;
    _micBlocked = false;
    _attempt = 0;
    _lastResult = null;
    _phase = ReadAlongPhase.idle;
    notifyListeners();
  }

  // ------------------------------------------------------------------ 判定

  /// 判定一次跟读（纯函数：同一输入必然同一输出，不碰会话状态）。
  ///
  /// [expected] 为课文原句（中文课取 `Sentence.chinese`，见方案 §九.4），
  /// [actual] 为 ASR 识别文本，[attempt] 为第几次跟读（1 基）——不过且
  /// [attempt] 达到 [maxAttempts] 时结论为 [ReadAlongVerdict.giveUp]。
  ///
  /// [lenient] = 熟读「不拦」档（见 [setLenient]）：判定口径一字不动，只是
  /// 永不给 giveUp。默认 false = 初读档的老行为。
  ReadAlongResult judge({
    required String expected,
    required String actual,
    required int attempt,
    bool lenient = false,
  }) {
    final expectedTonedFull = normalizeWithTones(expected);
    final syllableTotal = syllableCount(stripTones(expectedTonedFull));
    // 判分一律吃**原始** actual：截断会把它砍到 ≤ 期望长度，覆盖率就永远
    // 上不去，`tooMuch`（>2 倍）永远不可达；而且「我家有只小猫。」会被切
    // 成「我家有只小」，把合法的多读一个字砍坏。多读/复读由 _judgeOnce
    // 的 unclear 兜住，截断只服务对照行显示。
    final actualToned = normalizeWithTones(actual);
    final actualNorm = stripTones(actualToned);
    // 对照行用的原文汉字（判定口径不变，仍比拼音）；显示串按期望句长截断，
    // 免得复读时把一整屏都铺满同一句。
    final expectedHanzi = normalizeHanzi(expected);
    final actualHanzi = normalizeHanzi(
      _truncateToSyllables(actual, syllableTotal),
    );

    // 轻声宽松（§4.4）：expected 的轻声音节可读可省，逐变体判定取最优。
    ReadAlongResult? best;
    for (final variantToned in _expectedVariants(expected)) {
      final candidate = _judgeOnce(
        expectedTonedFull: expectedTonedFull,
        variantNorm: stripTones(variantToned),
        actualToned: actualToned,
        actualNorm: actualNorm,
        syllableTotal: syllableTotal,
        attempt: attempt,
        expectedText: expectedHanzi,
        actualText: actualHanzi,
        lenient: lenient,
      );
      if (best == null || _isBetter(candidate, best)) best = candidate;
    }
    return best!;
  }

  ReadAlongResult _judgeOnce({
    required String expectedTonedFull,
    required String variantNorm,
    required String actualToned,
    required String actualNorm,
    required int syllableTotal,
    required int attempt,
    required String expectedText,
    required String actualText,
    required bool lenient,
  }) {
    final hasTarget = syllableTotal > 0;
    final score =
        hasTarget ? DictationEngine.similarity(variantNorm, actualNorm) : 0.0;

    // matched/wrong/missing/extra 按 ops 逐条分类统计，而不是取
    // DictationLineResult.extraCount——后者把「替换」的 actual 侧也算进
    // 多写，替换类错误会被双计。
    var matched = 0, wrong = 0, missing = 0, extra = 0;
    final ops = <DictationOp>[];
    if (hasTarget) {
      final diff =
          DictationEngine.compare(expected: variantNorm, actual: actualNorm);
      for (final op in diff.ops) {
        switch (op.type) {
          case DictationDiffType.matched:
            matched++;
          case DictationDiffType.missing:
            missing++;
          case DictationDiffType.extra:
            extra++;
          case DictationDiffType.replaced:
          case DictationDiffType.spelling:
          case DictationDiffType.morphology:
          case DictationDiffType.merged:
          case DictationDiffType.split:
            wrong++;
        }
      }
      ops.addAll(diff.ops);
    }

    // 有效音节覆盖率 = 识别出的音节数 / 期望音节数。v2 真机结论
    // （2026-10-12 小米14：「有一群小蝌蚪」只吐出 "i"）：
    // 孩子读早了（跟读时音频还在放）或只蹦出半个字时，ASR 输出一两个
    // 音节——这不是「读错」，是「没听清」，必须另判一档，否则 0.05 分
    // 的 retry 会让用户觉得「判分完全不准」。
    final actualSyllables = syllableCount(actualNorm);
    final coverage =
        hasTarget && syllableTotal > 0 ? actualSyllables / syllableTotal : 0.0;
    final silent = hasTarget && actualNorm.trim().isEmpty;
    final tooShort = hasTarget && !silent && coverage < unclearCoverBelow;

    // 多读成灾（2026-10-15 小米14 实测）：4 字初读行读出 14.7 秒，
    // ASR 吐 26 个音节（含孩子前几句的旧内容）。此时短句豁免仍成立、
    // 直接判 pass；而 extra=22 不计错，等于「几乎没读也过关」。
    // 这是「读飞了/录飞了」，不是读错——不给失败计数，只请再读一次。
    final tooMuch = hasTarget && !silent && coverage > unclearCoverAbove;
    final unclear = tooShort || tooMuch;

    // 满星同样要先排除 unclear：覆盖率 2 倍以上说明这段音频根本不是
    // 在念这一句，不能给满星（否则复读/录飞也能拿满分）。
    final star = hasTarget && !unclear && score + _epsilon >= starAt;

    // 判定链（2026-10-17 郭老师与评审红线）：
    // 彻底废除 `字数<=6 && 错<=1` 的短句豁免，杜绝假放行。
    // 只有当实际比对得分 score >= passAt 时才判定 passed。
    final passed = hasTarget && !unclear && (score + _epsilon >= passAt);

    // giveUp 是「停止死循环」的出口，只属于初读档：熟读档（lenient）即使
    // 次数到限也停在 retry，由上层把「继续下一句」直接摆出来。
    final verdict = silent
        ? ReadAlongVerdict.retry
        : star
            ? ReadAlongVerdict.star
            : passed
                ? ReadAlongVerdict.pass
                : unclear
                    ? ReadAlongVerdict.unclear
                    : (!lenient && attempt >= maxAttempts)
                        ? ReadAlongVerdict.giveUp
                        : ReadAlongVerdict.retry;

    return ReadAlongResult(
      passed: passed,
      star: star,
      score: score,
      attempt: attempt,
      silent: silent,
      coverage: coverage,
      matched: matched,
      wrong: wrong,
      missing: missing,
      extra: extra,
      ops: ops,
      expectedPinyin: expectedTonedFull,
      actualPinyin: actualToned,
      verdict: verdict,
      expectedText: expectedText,
      actualText: actualText,
    );
  }

  /// 轻声宽松变体之间取更优：分高者胜；同分取错字少者（并列保持先出现者，
  /// 变体按「全 → 单省 → 多省」生成，即更保守的全读优先）。
  static bool _isBetter(ReadAlongResult candidate, ReadAlongResult best) {
    if (candidate.score != best.score) return candidate.score > best.score;
    return candidate.errors < best.errors;
  }

  // -------------------------------------------------------------- 归一化管线

  /// 归一化（判定用，去声调）：
  /// 去标点/空白/语气词尾巴 → `ChinesePinyin.toPinyinLine()` 转拼音 → 去声调。
  static String normalize(String text) => stripTones(normalizeWithTones(text));

  /// 按期望音节数截断识别串（防 CTC 解码器自我复读）。
  ///
  /// 2026-10-15 小米14 实测：初读行 4 字，孩子读满 14.7 秒（含前面几句
  /// 的回放），ASR 把同一句反复解码出「它在台湾省它在台湾省东部的山区」。
  /// 复读不是读错，却让 extra 暴涨 → 整句判负。
  ///
  /// 截断只做一件事：**超过期望音节数的部分丢掉**。判分仍比拼音，这里的
  /// 截断与归一同轴，不引入第二套口径。不足期望音节数时原样返回。
  static String _truncateToSyllables(String text, int maxSyllables) {
    if (maxSyllables <= 0 || text.trim().isEmpty) return text;
    final normalized = normalizeWithTones(text);
    if (normalized.trim().isEmpty) return text;
    final syllables = normalized
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (syllables.length <= maxSyllables) return text;
    // 从「识别串」里按保留音节数抠字：归一化已去标点，按音节位反查原串。
    return _keepLeadingSyllables(text, maxSyllables);
  }

  /// 保留原串前 [keep] 个汉字音节（非汉字字符原样带上，标点随字走）。
  static String _keepLeadingSyllables(String text, int keep) {
    var count = 0;
    final sb = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final isHanzi = ch.codeUnitAt(0) >= 0x4E00 && ch.codeUnitAt(0) <= 0x9FA5;
      if (isHanzi) {
        if (count >= keep) break;
        count++;
      }
      sb.write(ch);
    }
    return sb.toString();
  }

  /// 归一化到**汉字串**（2026-10-15 对照行 UI 用）：只剥标点/空白/句尾
  /// 语气词，保留汉字本体。判定链不走这条（判定仍比拼音，见
  /// [normalizeWithTones]），它只负责让「应读/读到」行以汉字为主呈现。
  static String normalizeHanzi(String text) {
    if (text.trim().isEmpty) return '';
    var s = text.toLowerCase().replaceAll(
          RegExp(r'[^一-龥a-z0-9\s]'),
          '',
        );
    s = _stripTailParticles(s);
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 归一化到**带声调**拼音行（纠错提示用，§4.2）。
  ///
  /// 管线：小写化 → 去标点符号（只留汉字/字母/数字/空白）→ 去句尾语气词
  /// → 转拼音 → 折叠多余空白。`toPinyinLine` 的输出格式是「音节空格分隔、
  /// 带声调符号、非标点字符原样透传」（如「小蝌蚪找妈妈」→
  /// 「xiǎo kē dǒu zhǎo mā mā」）。
  static String normalizeWithTones(String text) {
    if (text.trim().isEmpty) return '';
    var s = text.toLowerCase().replaceAll(
          RegExp(r'[^一-龥a-z0-9\s]'),
          '',
        );
    s = _stripTailParticles(s);
    s = ChinesePinyin.toPinyinLine(s);
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 剥离拼音行里的声调符号（逐字查 [_toneMarks]，非声调字符原样保留）。
  static String stripTones(String pinyinLine) {
    final sb = StringBuffer();
    for (final r in pinyinLine.runes) {
      final ch = String.fromCharCode(r);
      sb.write(_toneMarks[ch] ?? ch);
    }
    return sb.toString();
  }

  /// 归一化拼音行的音节数（= 参与比对的「句字数」）。
  static int syllableCount(String normalizedLine) => normalizedLine
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .length;

  /// 只剥句尾的语气词（连同其后的尾部空白）。
  static String _stripTailParticles(String s) {
    var end = s.length;
    while (end > 0) {
      final ch = s[end - 1];
      if (ch == ' ' || _tailParticles.contains(ch)) {
        end--;
      } else {
        break;
      }
    }
    return s.substring(0, end);
  }

  // ------------------------------------------------------------ 轻声宽松

  /// expected 的合法带声调拼音变体（§4.4 轻声可读可省）：轻声位可整音节
  /// 省略，任一变体命中即算对。第一版轻声集 = `们` + 重叠词尾音节
  /// （妈妈/哥哥/奶奶，识别端常丢第二个轻声音节）。
  static List<String> _expectedVariants(String expected) {
    final full = normalizeWithTones(expected);
    final tokens = full
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    final neutral = _neutralFlags(expected);
    // 纯汉字句子才 1:1 对齐；混入字母/数字会破坏对齐，此时放弃轻声宽松
    // （只判全读变体）——宁可漏放，不可错放。
    if (neutral.length != tokens.length) return <String>[full];

    final optionalAt = <int>[];
    for (var i = 0; i < neutral.length; i++) {
      if (neutral[i]) optionalAt.add(i);
    }
    if (optionalAt.isEmpty) return <String>[full];

    final List<List<int>> omitSets;
    if (optionalAt.length <= _maxOptionalCombos) {
      omitSets = [
        for (var mask = 0; mask < (1 << optionalAt.length); mask++)
          [
            for (var b = 0; b < optionalAt.length; b++)
              if (mask & (1 << b) != 0) optionalAt[b],
          ],
      ];
    } else {
      omitSets = [const <int>[], optionalAt];
    }

    final seen = <String>{full};
    final out = <String>[full];
    for (final omit in omitSets) {
      final variant = <String>[];
      for (var i = 0; i < tokens.length; i++) {
        if (omit.contains(i)) continue;
        variant.add(tokens[i]);
      }
      final joined = variant.join(' ');
      if (seen.add(joined)) out.add(joined);
    }
    return out;
  }

  /// 归一化后每个汉字是否轻声（与 `toPinyinLine` 的音节一一对应）。
  static List<bool> _neutralFlags(String text) {
    final s = _stripTailParticles(
      text.toLowerCase().replaceAll(RegExp(r'[^一-龥a-z0-9\s]'), ''),
    );
    final chars = s.runes.map(String.fromCharCode).toList(growable: false);
    final flags = <bool>[];
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      if (!_isCjk(ch)) continue; // 字母/数字不产音节
      flags.add(
        ch == _neutralToneChar || (i > 0 && chars[i - 1] == ch),
      );
    }
    return flags;
  }

  static bool _isCjk(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 0x4E00 && code <= 0x9FA5;
  }
}
