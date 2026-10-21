/// 整课朗读对齐器（**纯 Dart**：不依赖 Flutter、不碰麦克风）。
///
/// 2026-10-20 郭老师：
/// 　· 「以一篇课文为一个流程……把这个课文都读完，然后才结束」
/// 　· 「识别是实时的，我边说它就边识别」
///
/// 这份文件只解决一件事：**ASR 识别出来的字，怎么和课文对上**。
///
/// 为什么不能"一字对一字往后比"（老做法）：
/// 　· 漏读一个字 → 后面全部错位（"小蝌蚪**找**妈妈"读成"小蝌蚪妈妈"，
///    顺序比较会把"找"判成漏、"妈妈"判成错……全乱）；
/// 　· 课文里两次出现"妈妈" → 只能搜到第一个；
/// 　· ASR 下一次快照修正了文字 → 之前判好的字会反复变色。
///
/// 做法是**音节级序列对齐**（Needleman–Wunsch 变体）：
/// 　· 期望序列 = 课文的音节（去调），识别序列 = ASR 的音节（去调）；
/// 　· 打分：完全相同 3 分；同声母 1.5 分（读音接近，倾向判"可能读成"）；
///    其它 0.75 分（读到了别的音）；跳过（漏/多）各扣 1.2 分；
/// 　· 回溯得到每个课文音节的状态：匹配 / 可能读成 / 漏读。
///
/// 关键性质：**漏读只影响那一个**。回溯时"漏掉的那一格"与"多出来的那一格"
/// 若声母相同，就把"漏读"升级为"可能读成 X"（把听到的音记下来给孩子看）。
library;

/// 一个课文音节的判定结果。
enum ReadingTokenStatus {
  /// 还没读到。
  pending,

  /// 读到了，而且对上了。
  matched,

  /// 读到了，但不是这个音（听到了别的东西）—— 措辞要温和：不是"你错了"，
  /// 是"可能读成了 X"。
  substituted,

  /// 没听到（漏读）。
  missed,

  /// 听到了但还没定（暂定区：ASR 还在修正，不急着判）。
  uncertain,
}

/// 对齐后的一个课文音节。
class AlignedToken {
  const AlignedToken({
    required this.status,
    this.heard,
  });

  final ReadingTokenStatus status;

  /// 实际听到的音节（仅 [ReadingTokenStatus.substituted] / uncertain 有值）。
  final String? heard;

  bool get isSettled =>
      status == ReadingTokenStatus.matched ||
      status == ReadingTokenStatus.substituted ||
      status == ReadingTokenStatus.missed;
}

/// 一次对齐的结果。
class ReadingAlignment {
  const ReadingAlignment({
    required this.statuses,
    required this.heard,
    required this.matchedCount,
    required this.substitutedCount,
    required this.missedCount,
    required this.insertedCount,
    required this.score,
    this.frontier = 0,
  });

  /// 与期望序列等长。
  final List<ReadingTokenStatus> statuses;

  /// 与期望序列等长：听到的音节（没听到为 null）。
  final List<String?> heard;

  final int matchedCount;
  final int substitutedCount;
  final int missedCount;

  /// 识别序列里多出来的音节数（重复读、插话、杂音）。
  final int insertedCount;

  /// 对齐总分（越大越像）。
  final double score;

  /// **识别覆盖到的 expected 下标**（=「读到这儿了」）。
  ///
  /// 2026-10-21（流式实时反馈）：批式识别里，识别完了才判「漏读」；流式下
  /// 尾部那些**还没读到的**字如果也判 missed，孩子会看到满屏红字。
  /// ⇒ 尾部 `[frontier..statuses.length)` 应当保持 pending（还没读到），
  /// 只有真正被跳过的**中间**字才算漏读。
  ///
  /// 语义：[frontier] 是「最后一个 matched/substituted 的位置 + 1」；
  /// 若一个都没匹配上则为 0。
  final int frontier;
}

/// 音节级序列对齐器。
class ReadingAligner {
  const ReadingAligner();

  static const double _matchScore = 3.0;
  static const double _sameInitialScore = 1.5;
  static const double _otherScore = 0.75;
  static const double _gapPenalty = 1.2;

  /// 把 [recognized] 对齐到 [expected]。
  ///
  /// [expected] 与 [recognized] 都是**去调**音节（比较时用去调版；声母比较
  /// 也在去调版上做）。返回的 [ReadingAlignment.statuses] 与 [expected] 等长。
  ReadingAlignment align({
    required List<String> expected,
    required List<String> recognized,
  }) {
    final n = expected.length;
    final m = recognized.length;

    if (n == 0) {
      return ReadingAlignment(
        statuses: const [],
        heard: const [],
        matchedCount: 0,
        substitutedCount: 0,
        missedCount: 0,
        insertedCount: m,
        score: 0,
        frontier: 0,
      );
    }
    if (m == 0) {
      return ReadingAlignment(
        statuses: [for (var i = 0; i < n; i++) ReadingTokenStatus.missed],
        heard: [for (var i = 0; i < n; i++) null],
        matchedCount: 0,
        substitutedCount: 0,
        missedCount: n,
        insertedCount: 0,
        score: 0,
        frontier: 0,
      );
    }

    // dp[i][j] = 期望前 i 个 与 识别前 j 个 的最佳得分
    final dp = List.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, 0),
    );
    for (var i = 1; i <= n; i++) {
      dp[i][0] = dp[i - 1][0] - _gapPenalty;
    }
    for (var j = 1; j <= m; j++) {
      dp[0][j] = dp[0][j - 1] - _gapPenalty;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final diag =
            dp[i - 1][j - 1] + _pairScore(expected[i - 1], recognized[j - 1]);
        final up = dp[i - 1][j] - _gapPenalty; // 期望多一个 → 漏读
        final left = dp[i][j - 1] - _gapPenalty; // 识别多一个 → 多读/插入
        dp[i][j] = _max3(diag, up, left);
      }
    }

    // 回溯
    final statuses = List<ReadingTokenStatus>.filled(n, ReadingTokenStatus.missed);
    final heard = List<String?>.filled(n, null);
    var inserted = 0;
    var i = n;
    var j = m;
    // 识别序列被耗尽的那一刻，expected 还剩 i 个 —— 那就是「读到这儿了」。
    //
    // 2026-10-21：流式识别的实时反馈需要这个。批式识别里，识别完了才判
    // 「漏读」；流式下，尾部那些**还没读到的**字如果也判成 missed，孩子会
    // 看到满屏红字。⇒ 尾部 [frontier..n) 应当保持 pending（还没读到），
    // 只有真正被跳过的**中间**字才算漏读。
    var frontier = n;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0) {
        final diag = dp[i - 1][j - 1] +
            _pairScore(expected[i - 1], recognized[j - 1]);
        if ((dp[i][j] - diag).abs() < 1e-9) {
          final e = expected[i - 1];
          final r = recognized[j - 1];
          if (e == r) {
            statuses[i - 1] = ReadingTokenStatus.matched;
            heard[i - 1] = r;
          } else {
            statuses[i - 1] = ReadingTokenStatus.substituted;
            heard[i - 1] = r;
          }
          i--;
          j--;
          continue;
        }
      }
      if (i > 0 && (dp[i][j] - (dp[i - 1][j] - _gapPenalty)).abs() < 1e-9) {
        // 期望多一个：先记成漏读，等回溯到"识别多出来"的那格时再升级
        statuses[i - 1] = ReadingTokenStatus.missed;
        i--;
        continue;
      }
      // 识别多一个（插入）：如果它和左边刚漏掉的那格声母相同，就把漏读升级
      // 成"可能读成"。
      if (j > 0) {
        inserted++;
        if (i > 0 && statuses[i - 1] == ReadingTokenStatus.missed) {
          final e = expected[i - 1];
          final r = recognized[j - 1];
          if (_sameInitial(e, r)) {
            statuses[i - 1] = ReadingTokenStatus.substituted;
            heard[i - 1] = r;
          }
        }
        j--;
      }
    }
    // 回溯走完时 j==0 ⇒ 识别序列耗尽于 i（若中间没有 gap 消耗，frontier 就是
    // 「识别覆盖到的 expected 长度」）。这里用「最后一次识别被消耗的位置」来
    // 精确计算：重新扫一遍 DP 最优路径不现实，改为用状态分布推断 ——
    // 尾部连续的 missed 就是「还没读到」。
    var covered = 0;
    for (var k = 0; k < n; k++) {
      if (statuses[k] == ReadingTokenStatus.matched ||
          statuses[k] == ReadingTokenStatus.substituted) {
        covered = k + 1;
      }
    }
    frontier = covered;

    var matched = 0;
    var substituted = 0;
    var missed = 0;
    for (final s in statuses) {
      switch (s) {
        case ReadingTokenStatus.matched:
          matched++;
        case ReadingTokenStatus.substituted:
          substituted++;
        case ReadingTokenStatus.missed:
          missed++;
        default:
          break;
      }
    }

    return ReadingAlignment(
      statuses: statuses,
      heard: heard,
      matchedCount: matched,
      substitutedCount: substituted,
      missedCount: missed,
      insertedCount: inserted,
      score: dp[n][m],
      frontier: frontier,
    );
  }

  static double _max3(double a, double b, double c) =>
      a > b ? (a > c ? a : c) : (b > c ? b : c);

  static double _pairScore(String expected, String recognized) {
    if (expected == recognized) return _matchScore;
    if (_sameInitial(expected, recognized)) return _sameInitialScore;
    return _otherScore;
  }

  /// 声母是否相同（"找" vs "爪" 算接近，"找" vs "猫" 不算）。
  static bool _sameInitial(String a, String b) {
    final ia = _initialOf(a);
    final ib = _initialOf(b);
    if (ia.isEmpty || ib.isEmpty) return false;
    if (ia == ib) return true;
    // zh/z、ch/c、sh/s 舌尖音互认（ASR 常见混淆）。
    const near = {
      'zh': 'z',
      'ch': 'c',
      'sh': 's',
    };
    return near[ia] != null && near[ia] == ib;
  }

  static const List<String> _initials = [
    'zh', 'ch', 'sh',
    'b', 'p', 'm', 'f', 'd', 't', 'n', 'l',
    'g', 'k', 'h', 'j', 'q', 'x',
    'r', 'z', 'c', 's', 'y', 'w',
  ];

  static String _initialOf(String syllable) {
    if (syllable.isEmpty) return '';
    for (final ini in _initials) {
      if (syllable.startsWith(ini)) return ini;
    }
    return '';
  }
}
