/// 听写引擎 —— ListenLoop 核心层能力（P1）。
///
/// 设计依据见 `docs/02_工程架构与系统设计/08_核心精听优先_产品优先级定调.md`：
///   * 核心层必须**离线完整可用** → 本文件不依赖网络、不依赖 AI、不依赖 Flutter。
///   * **客观 diff 类型（第一层）与训练原因提示（第二层）必须分开**。
///     第一层可断言（「这里少了一个词」是事实）；第二层只能提示
///     （「可能与弱读有关」是猜测，绝不能说成「这就是弱读吞音」）。
///   * 大小写、标点**默认不计错**；`I'm / I am` 之类等价形式先归一化，
///     否则三色 diff 会制造大量假错误。
///   * 对齐不可靠时**诚实标记 uncertain**，不伪造精确诊断。
library;

// ---------------------------------------------------------------- 枚举定义

/// 第一层：客观 diff 类型。这些是可以断言的**事实**。
enum DictationDiffType {
  /// 完全一致。
  matched,

  /// 漏词：原文有、用户没写。
  missing,

  /// 多写：原文没有、用户写了。
  extra,

  /// 替换：位置对上但词不同，且相似度不足以视为拼写。
  replaced,

  /// 拼写近似：词不同但高度相似（≥ [_spellingThreshold]）。
  spelling,

  /// 词边界——两词被写成了一词（`a lot` → `alot`）。
  merged,

  /// 词边界——一词被写成了两词（`alot` → `a lot`）。
  split,

  /// 词尾形态错误（`walked`/`walk`、`book`/`books`）。
  morphology,
}

/// 第二层：训练原因提示。这些**只是推测**，用于引导回原声重听。
///
/// ⚠️ 严禁在 UI 上把它渲染成确定结论——所有展示都必须带「可能与…有关」。
enum DictationCauseHint {
  /// 功能词被吞：可能与弱读（Weak Form）有关。
  weakForm,

  /// 辅音结尾接元音开头：可能与连读（Liaison）有关。
  liaison,

  /// 塞音结尾接辅音开头：可能与失爆（Incomplete Plosive）有关。
  plosion,

  /// 元音之间的单个 t/d：可能与闪音（Flap T/D）有关。
  flap,
}

// ------------------------------------------------------------------ 结果模型

/// 一个对齐操作（一个 token 位上的差异）。
class DictationOp {
  const DictationOp({
    required this.type,
    this.expected,
    this.actual,
    this.similarity = 0,
    this.expectedIsFunctionWord = false,
    this.causeHints = const <DictationCauseHint>[],
  });

  final DictationDiffType type;

  /// 原文词（[DictationDiffType.extra] 时为 null）。
  final String? expected;

  /// 用户写的词（[DictationDiffType.missing] 时为 null）。
  final String? actual;

  /// 原文词与所写词的相似度（0~1），仅对 replaced/spelling 有意义。
  final double similarity;

  final bool expectedIsFunctionWord;

  /// 训练原因提示（可能为空 = 没有可推测的语音学线索）。
  final List<DictationCauseHint> causeHints;

  bool get isError => type != DictationDiffType.matched;

  /// 提示永远只是提示。
  bool get isHintOnly => causeHints.isNotEmpty;
}

/// 单句听写结果。
class DictationLineResult {
  const DictationLineResult({
    required this.expectedText,
    required this.actualText,
    required this.ops,
    required this.expectedCount,
    required this.matchedCount,
    required this.extraCount,
    required this.uncertain,
  });

  final String expectedText;
  final String actualText;
  final List<DictationOp> ops;

  /// 原文有效词数（归一化后）。
  final int expectedCount;

  /// 正确词数。
  final int matchedCount;

  /// 用户多写、原文没有的词数。
  final int extraCount;

  /// 对齐是否不可靠。
  ///
  /// 为 true 时 UI 应显示「这一段无法精确定位」，只给出整体正误，
  /// **不展示逐词三色标注**——防止伪造精确诊断。
  final bool uncertain;

  /// 错误处数（按对齐位置计，一处词边界合并算一处）。
  int get errorCount => ops.where((op) => op.isError).length;

  /// 词级准确率 = 正确词 / (原文词 + 多写词)。
  ///
  /// 分母同时惩罚「漏」与「多」：若只算召回率（正确/原文），
  /// 用户随手多写一堆词反而不会被扣分。
  ///
  /// 原文为空且未多写时返回 0。
  double get accuracy {
    final total = expectedCount + extraCount;
    return total == 0 ? 0 : matchedCount / total;
  }

  /// 用户是否明确留空（「没听出来」是合法答案，不是错误行为）。
  bool get isBlank => actualText.trim().isEmpty;

  Map<DictationDiffType, int> get errorCounts {
    final out = <DictationDiffType, int>{};
    for (final op in ops) {
      if (op.isError) {
        out[op.type] = (out[op.type] ?? 0) + 1;
      }
    }
    return out;
  }
}

/// 一段（segment）听写结果 —— 批改以「段」为单位发生。
class DictationSegmentResult {
  const DictationSegmentResult({required this.lines});

  final List<DictationLineResult> lines;

  int get expectedWords =>
      lines.fold(0, (sum, l) => sum + l.expectedCount);

  int get matchedWords => lines.fold(0, (sum, l) => sum + l.matchedCount);

  /// 段内多写词数。
  int get extraWords => lines.fold(0, (sum, l) => sum + l.extraCount);

  /// 段内错误处数（按对齐位置计）。
  int get errorWords => lines.fold(0, (sum, l) => sum + l.errorCount);

  /// 段级准确率，口径与句级一致：正确词 / (原文词 + 多写词)。
  double get accuracy {
    final total = expectedWords + extraWords;
    return total == 0 ? 0 : matchedWords / total;
  }

  int get blankLines => lines.where((l) => l.isBlank).length;

  /// 按客观类型统计错误数（第一层）。
  Map<DictationDiffType, int> get errorCounts {
    final out = <DictationDiffType, int>{};
    for (final line in lines) {
      line.errorCounts.forEach((type, count) {
        out[type] = (out[type] ?? 0) + count;
      });
    }
    return out;
  }

  /// 按训练原因提示统计（第二层）。
  Map<DictationCauseHint, int> get causeCounts {
    final out = <DictationCauseHint, int>{};
    for (final line in lines) {
      for (final op in line.ops) {
        for (final hint in op.causeHints) {
          out[hint] = (out[hint] ?? 0) + 1;
        }
      }
    }
    return out;
  }

  /// 需要回原声重听的高价值句：有错误且对齐可靠。
  List<DictationLineResult> get reviewTargets => lines
      .where((l) => l.errorCount > 0 && !l.uncertain)
      .toList(growable: false);
}

// -------------------------------------------------------------------- 引擎

/// 词级听写比对引擎。全部为静态纯函数，可离线、可单测。
abstract final class DictationEngine {
  /// 相似度高于此值即视为「拼写近似」而非「听错」。
  static const double _spellingThreshold = 0.7;

  /// 错误率超过此值即认为对齐不可靠（防止伪造精确诊断）。
  static const double _uncertainErrorRatio = 0.6;

  /// 词尾形态后缀——用于识别 `walked`/`walk` 这类形态错误。
  static const List<String> _morphSuffixes = <String>[
    's', 'es', 'ed', 'd', 'ing', 'n', 'nt', 'er', 'est', 'ly',
  ];

  /// 塞音（失爆候选）。
  static const Set<String> _stops = <String>{'t', 'd', 'p', 'b', 'k', 'g'};

  /// 闭类功能词：天然轻读，听不清的概率远高于实词。
  static const Set<String> functionWords = <String>{
    // 冠词 / 限定词
    'a', 'an', 'the', 'this', 'that', 'these', 'those', 'some', 'any',
    'my', 'your', 'his', 'her', 'its', 'our', 'their',
    // 介词
    'of', 'to', 'in', 'on', 'at', 'for', 'from', 'with', 'by', 'as',
    'into', 'onto', 'about', 'over', 'under', 'between', 'through',
    'during', 'before', 'after', 'up', 'down', 'out', 'off', 'than',
    // 代词
    'i', 'me', 'you', 'he', 'him', 'she', 'it', 'we', 'us', 'they',
    'them', 'who', 'whom', 'whose', 'which', 'what',
    // 助动词 / be / have / do
    'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
    'shall', 'should', 'can', 'could', 'may', 'might', 'must',
    // 连词 / 小品词
    'and', 'or', 'but', 'if', 'so', 'because', 'while', 'when',
    'where', 'how', 'not', 'no', 'there', 'here', 'too', 'very',
    'just', 'only', 'also', 'then', 'now',
  };

  /// 常见缩写 → 规范展开。**两侧都要过一遍**，否则 `I'm` 与 `I am` 会被判错。
  static const Map<String, String> _contractions = <String, String>{
    "i'm": 'i am',
    "i've": 'i have',
    "i'll": 'i will',
    "i'd": 'i would',
    "you're": 'you are',
    "you've": 'you have',
    "you'll": 'you will',
    "we're": 'we are',
    "we've": 'we have',
    "they're": 'they are',
    "they've": 'they have',
    "he's": 'he is',
    "she's": 'she is',
    "it's": 'it is',
    "that's": 'that is',
    "there's": 'there is',
    "what's": 'what is',
    "let's": 'let us',
    "don't": 'do not',
    "doesn't": 'does not',
    "didn't": 'did not',
    "isn't": 'is not',
    "aren't": 'are not',
    "wasn't": 'was not',
    "weren't": 'were not',
    "can't": 'can not',
    "cannot": 'can not',
    "couldn't": 'could not',
    "won't": 'will not',
    "wouldn't": 'would not',
    "shouldn't": 'should not',
    "haven't": 'have not',
    "hasn't": 'has not',
    "hadn't": 'had not',
    "mustn't": 'must not',
    "gonna": 'going to',
    "wanna": 'want to',
    "gotta": 'got to',
  };

  /// 归一化并切词：小写、去标点（保留词内撇号）、展开缩写。
  ///
  /// 大小写与标点**不产生错误**——这是刻意为之，见文件头注释。
  static List<String> tokenize(String text) {
    if (text.trim().isEmpty) return const <String>[];

    final cleaned = text
        .toLowerCase()
        // 撇号统一为 ASCII，兼容中文输入法或富文本粘贴带来的变体
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        // 其余标点一律视为分隔符
        .replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) return const <String>[];

    final out = <String>[];
    for (final raw in cleaned.split(' ')) {
      final token = raw.replaceAll(RegExp(r"^'+|'+$"), '');
      if (token.isEmpty) continue;
      final expanded = _contractions[token];
      if (expanded != null) {
        out.addAll(expanded.split(' '));
      } else if (token.endsWith("n't") && token.length > 4) {
        // 兜底：未登记的 n't 缩写，按「词干 + not」展开
        out..add(token.substring(0, token.length - 3))..add('not');
      } else {
        out.add(token);
      }
    }
    return out;
  }

  /// Levenshtein 相似度（0~1，1 = 完全相同）。
  static double similarity(String a, String b) {
    if (a == b) return 1;
    final la = a.length, lb = b.length;
    if (la == 0 || lb == 0) return 0;
    var prev = List<int>.generate(lb + 1, (j) => j);
    var curr = List<int>.filled(lb + 1, 0);
    for (var i = 1; i <= la; i++) {
      curr[0] = i;
      for (var j = 1; j <= lb; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final swap = prev;
      prev = curr;
      curr = swap;
    }
    final distance = prev[lb];
    return 1 - distance / (la > lb ? la : lb);
  }

  /// 比对一句：原文 [expected] 对用户所写 [actual]，产出可解释的 diff。
  static DictationLineResult compare({
    required String expected,
    required String actual,
  }) {
    final expTokens = tokenize(expected);
    final actTokens = tokenize(actual);

    if (expTokens.isEmpty) {
      return DictationLineResult(
        expectedText: expected,
        actualText: actual,
        ops: const <DictationOp>[],
        expectedCount: 0,
        matchedCount: 0,
        extraCount: actTokens.length,
        uncertain: false,
      );
    }

    final ops = _align(expTokens, actTokens);
    final refined = _refine(ops, expTokens);

    var matched = 0;
    for (final op in refined) {
      if (op.type == DictationDiffType.matched) matched++;
    }

    // 多写的词 = 用户所写词数 - 命中词数（命中词必然两侧共有）。
    final extraCount = actTokens.length - matched;
    final totalWords = expTokens.length + extraCount;
    final errorSpots = refined.where((op) => op.isError).length;
    final errorRatio = totalWords == 0 ? 0.0 : errorSpots / totalWords;

    return DictationLineResult(
      expectedText: expected,
      actualText: actual,
      ops: refined,
      expectedCount: expTokens.length,
      matchedCount: matched,
      extraCount: extraCount,
      // 整体错得太多时，逐词对齐已经没有解释力——诚实降级。
      // 但「整句留空」是合法答案（听不出就先空着），不算对齐混乱。
      uncertain: actTokens.isNotEmpty && errorRatio > _uncertainErrorRatio,
    );
  }

  /// 段级比对：把每句原文与用户所写逐一对齐，再聚合。
  static DictationSegmentResult compareSegment({
    required List<String> expectedLines,
    required List<String> actualLines,
  }) {
    final lines = <DictationLineResult>[];
    for (var i = 0; i < expectedLines.length; i++) {
      lines.add(
        compare(
          expected: expectedLines[i],
          actual: i < actualLines.length ? actualLines[i] : '',
        ),
      );
    }
    return DictationSegmentResult(lines: lines);
  }

  // ------------------------------------------------------------ 内部实现

  /// 最长公共子序列对齐，产出 matched / missing / extra 三种原子操作。
  static List<DictationOp> _align(List<String> a, List<String> b) {
    final n = a.length, m = b.length;

    // dp[i][j] = LCS(a[i:], b[j:])
    final dp = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
    );
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j]
            ? dp[i + 1][j + 1] + 1
            : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }

    final ops = <DictationOp>[];
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        ops.add(DictationOp(
          type: DictationDiffType.matched,
          expected: a[i],
          actual: b[j],
          similarity: 1,
          expectedIsFunctionWord: functionWords.contains(a[i]),
        ));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        ops.add(DictationOp(
          type: DictationDiffType.missing,
          expected: a[i],
          expectedIsFunctionWord: functionWords.contains(a[i]),
        ));
        i++;
      } else {
        ops.add(DictationOp(type: DictationDiffType.extra, actual: b[j]));
        j++;
      }
    }
    while (i < n) {
      ops.add(DictationOp(
        type: DictationDiffType.missing,
        expected: a[i],
        expectedIsFunctionWord: functionWords.contains(a[i]),
      ));
      i++;
    }
    while (j < m) {
      ops.add(DictationOp(type: DictationDiffType.extra, actual: b[j]));
      j++;
    }
    return ops;
  }

  /// 把原子操作精炼成可解释的错误类型，并挂上训练原因提示。
  ///
  /// 相邻的「漏 + 多」会配对成替换，再进一步识别拼写近似 / 词尾形态 /
  /// 词边界合并与拆分。
  static List<DictationOp> _refine(List<DictationOp> ops, List<String> expected) {
    final out = <DictationOp>[];
    var k = 0;
    while (k < ops.length) {
      final op = ops[k];
      if (op.type != DictationDiffType.missing) {
        out.add(op);
        k++;
        continue;
      }

      // 收集连续的 missing 与紧随其后的连续 extra
      var mi = k;
      while (mi < ops.length && ops[mi].type == DictationDiffType.missing) {
        mi++;
      }
      var ei = mi;
      while (ei < ops.length && ops[ei].type == DictationDiffType.extra) {
        ei++;
      }

      final missingCount = mi - k;
      final extraCount = ei - mi;
      final missingTokens = ops
          .sublist(k, mi)
          .map((o) => o.expected!)
          .toList(growable: false);
      final extraTokens = ops
          .sublist(mi, ei)
          .map((o) => o.actual!)
          .toList(growable: false);

      final replacedCount =
          missingCount < extraCount ? missingCount : extraCount;

      for (var p = 0; p < replacedCount; p++) {
        final exp = missingTokens[p];
        final act = extraTokens[p];
        final sim = similarity(exp, act);

        // 词边界：两词写成一词
        if (missingCount == 2 && extraCount == 1 && act == '${missingTokens[0]}${missingTokens[1]}') {
          out.add(DictationOp(
            type: DictationDiffType.merged,
            expected: '${missingTokens[0]} ${missingTokens[1]}',
            actual: act,
            similarity: sim,
          ));
          continue;
        }
        // 词边界：一词写成两词
        if (missingCount == 1 && extraCount == 2 && exp == '${extraTokens[0]}${extraTokens[1]}') {
          out.add(DictationOp(
            type: DictationDiffType.split,
            expected: exp,
            actual: '${extraTokens[0]} ${extraTokens[1]}',
            similarity: sim,
          ));
          continue;
        }

        final type = _classifyReplacement(exp, act, sim);
        out.add(DictationOp(
          type: type,
          expected: exp,
          actual: act,
          similarity: sim,
          expectedIsFunctionWord: functionWords.contains(exp),
          causeHints: _hints(exp, expected),
        ));
      }

      // 剩余的漏词
      for (var p = replacedCount; p < missingCount; p++) {
        final exp = missingTokens[p];
        out.add(DictationOp(
          type: DictationDiffType.missing,
          expected: exp,
          expectedIsFunctionWord: functionWords.contains(exp),
          causeHints: _hints(exp, expected),
        ));
      }
      // 剩余的多写
      for (var p = replacedCount; p < extraCount; p++) {
        out.add(DictationOp(
          type: DictationDiffType.extra,
          actual: extraTokens[p],
        ));
      }

      k = ei;
    }
    return out;
  }

  static DictationDiffType _classifyReplacement(
    String expected,
    String actual,
    double similarity,
  ) {
    if (similarity >= _spellingThreshold) {
      return DictationDiffType.spelling;
    }
    // 词尾形态：一方是另一方的词干
    if (_sharesStem(expected, actual)) {
      return DictationDiffType.morphology;
    }
    return DictationDiffType.replaced;
  }

  /// 判断两个词是否只差一个词尾（`walked` vs `walk`）。
  static bool _sharesStem(String a, String b) {
    final short = a.length <= b.length ? a : b;
    final long = a.length <= b.length ? b : a;
    if (short.length < 3 || !long.startsWith(short)) return false;
    return _morphSuffixes.contains(long.substring(short.length));
  }

  /// 生成训练原因**提示**。永远只是线索，不是结论。
  static List<DictationCauseHint> _hints(
    String word,
    List<String> expected,
  ) {
    final hints = <DictationCauseHint>[];
    if (functionWords.contains(word)) {
      hints.add(DictationCauseHint.weakForm);
    }

    final idx = expected.indexOf(word);
    final next = (idx >= 0 && idx + 1 < expected.length) ? expected[idx + 1] : '';

    // 连读：辅音结尾 + 元音开头
    if (word.isNotEmpty && _isConsonant(word[word.length - 1]) &&
        next.isNotEmpty && _isVowel(next[0])) {
      hints.add(DictationCauseHint.liaison);
    }
    // 失爆：塞音结尾 + 辅音开头
    if (word.isNotEmpty &&
        _stops.contains(word[word.length - 1]) &&
        next.isNotEmpty && _isConsonant(next[0])) {
      hints.add(DictationCauseHint.plosion);
    }
    // 闪音：元音之间的单个 t/d
    if (RegExp(r'^[a-z]*[aeiou][td][aeiou][a-z]*$').hasMatch(word)) {
      hints.add(DictationCauseHint.flap);
    }
    return hints;
  }

  static bool _isVowel(String c) => 'aeiou'.contains(c);

  static bool _isConsonant(String c) => !_isVowel(c);
}
