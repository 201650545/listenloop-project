import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/vocabulary_store.dart';
import '../l10n/ll_strings.dart';
import '../models/vocabulary_model.dart';
import '../player/audio_player_facade.dart';
import '../player/just_audio_facade.dart';
import '../theme/listenloop_theme.dart';
import '../training/vocabulary_ai_drill.dart';
import '../training/vocabulary_drill.dart';
import '../training/vocabulary_plan.dart';

/// 学习组件执行页 —— 今日计划里「建议」的**落地页**。
///
/// 设计约束（10 号文档 §十四 + 08 定调）：
///   * **离线可用**：全部判定在本地（[VocabularyDrillJudge]），不调模型；
///   * **只用原片音频**：回听与重听写都播原片句轴切片，**不得用 TTS 合成音**；
///   * **每步完成立刻回写**：中途退出不丢已练的部分（§14.1 硬约束 ③）；
///   * **自评就写自评**：原声回听没有客观对错，界面上明说，不伪装成测量。
class VocabularyDrillScreen extends StatefulWidget {
  const VocabularyDrillScreen({
    super.key,
    required this.store,
    required this.itemId,
    required this.components,
    this.audioFacade,
    this.loadAiQuiz,
    this.judgeAiAnswer,
    this.loadConflictQuiz,

    /// 测试缝：注入一个不触真实音频栈的门面。
    this.autoCreateAudioFacade = true,
  });

  final VocabularyStore store;

  /// 用 id 而不是对象 —— 练习过程中 store 会更新，页面始终读最新值。
  final String itemId;

  /// 本次要执行的组件（来自 [VocabularyPlanEntry.components]）。
  final List<StudyComponent> components;

  final AudioPlayerFacade? audioFacade;

  /// AI 出题的取题回调（10 号 §五）。null = AI 不可用 → 该步显示可跳过，
  /// **不得阻塞其它步骤**（§5.5 离线红线）。由调用方接网关并注入。
  final Future<AiQuiz> Function(VocabularyItem item)? loadAiQuiz;

  /// 开放答案的判卷回调（返回结构化 pass/partial/fail + reasonCode，
  /// §5.4 —— 绝不让 LLM 给「掌握度」数字）。
  final Future<AiAnswerJudgement> Function({
    required AiQuiz quiz,
    required int questionIndex,
    required String answer,
  })? judgeAiAnswer;

  /// 第 3 题（§5.2 冲突消解）的取题回调 —— 两题证据冲突时才调用；
  /// null 或抛异常时冲突场景直接落「半会」（可跳过，不阻塞）。
  final Future<String> Function({
    required AiQuiz quiz,
    required AiAnswerJudgement q1,
    required AiAnswerJudgement q2,
  })? loadConflictQuiz;

  /// false 时不自动创建真实音频门面（widget 测试用）。
  final bool autoCreateAudioFacade;

  @override
  State<VocabularyDrillScreen> createState() => _VocabularyDrillScreenState();
}

class _VocabularyDrillScreenState extends State<VocabularyDrillScreen> {
  /// SRS 复习不在这里做（那是复习页的职责）。
  late final List<StudyComponent> _steps = widget.components
      .where((c) => c != StudyComponent.srsReview)
      .toList(growable: false);

  final TextEditingController _input = TextEditingController();

  AudioPlayerFacade? _audio;
  bool _ownsAudio = false;
  bool _audioReady = false;
  bool _audioFailed = false;
  int _playCount = 0;

  int _step = 0;
  DrillOutcome? _outcome;
  bool _revealed = false;

  // AI 出题（contextTransfer）状态机：
  // loading → q1 → q1 判定 → q2 → q2 判定 → verdict；任何网络/解析失败 → 可跳过。
  AiQuiz? _aiQuiz;
  String? _aiError;
  bool _aiLoading = false;
  int _aiQuestion = 0;
  AiAnswerJudgement? _aiQ1Verdict;
  AiAnswerJudgement? _aiQ2Verdict;
  AiAnswerJudgement? _aiQ3Verdict;
  bool _aiGrading = false;

  // 第 3 题（§5.2 冲突消解）：两题证据冲突时才进入。
  bool _aiConflictMode = false;
  bool _aiConflictLoading = false;
  String? _aiConflictTask;

  @override
  void initState() {
    super.initState();
    _prepareAudio();
  }

  @override
  void dispose() {
    _input.dispose();
    if (_ownsAudio) unawaited(_audio?.dispose());
    super.dispose();
  }

  StudyComponent? get _current =>
      _step < _steps.length ? _steps[_step] : null;

  VocabularyItem? get _item => widget.store.itemById(widget.itemId);

  VocabularyOccurrence? get _occurrence => _item?.latestOccurrence;

  /// 需要放音时按需创建（省得只为看一个 Cloze 也去起一个播放器）。
  void _prepareAudio() {
    if (!needsAudio) return;
    final facade = widget.audioFacade;
    if (facade != null) {
      _audio = facade;
    } else if (widget.autoCreateAudioFacade) {
      _audio = JustAudioFacade();
      _ownsAudio = true;
    } else {
      return;
    }
    unawaited(_loadClip());
  }

  bool get needsAudio => _steps.any(
    (c) =>
        c == StudyComponent.originalRelisten ||
        c == StudyComponent.dictationRetry,
  );

  Future<void> _loadClip() async {
    final audio = _audio;
    final occurrence = _occurrence;
    if (audio == null || occurrence == null || occurrence.audioPath.isEmpty) {
      if (mounted) setState(() => _audioFailed = true);
      return;
    }
    try {
      await audio.loadPlaylist(
        path: occurrence.audioPath,
        // 课程音频在应用目录里是文件路径（精听页同款约定）
        isFile: true,
        clips: <SentenceClip>[
          SentenceClip(
            index: 0,
            start: Duration(milliseconds: occurrence.startMs),
            end: Duration(milliseconds: occurrence.endMs),
          ),
        ],
      );
      if (mounted) setState(() => _audioReady = true);
    } catch (_) {
      if (mounted) setState(() => _audioFailed = true);
    }
  }

  Future<void> _playClip() async {
    final audio = _audio;
    if (audio == null || !_audioReady) return;
    await audio.seek(Duration.zero);
    await audio.play();
    if (mounted) setState(() => _playCount++);
  }

  /// 完成当前步：**立刻落盘**（中途退出不丢），再进入下一步或结束。
  void _complete(DrillOutcome outcome) {
    final component = _current;
    if (component == null) return;
    widget.store.recordDrill(
      itemId: widget.itemId,
      component: component.name,
      passed: outcome.passed,
      detail: outcome.detail,
    );
    _advance();
  }

  /// 只步进不落盘 —— AI 出题的两道题各自落盘，收尾用这个。
  void _advance() {
    if (_step + 1 >= _steps.length) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _step++;
      _outcome = null;
      _revealed = false;
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);

    return Scaffold(
      backgroundColor: ll.bg,
      appBar: AppBar(
        backgroundColor: ll.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: ll.textPrimary),
        titleSpacing: 0,
        title: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _item?.surfaceForm ?? s.drillTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ll.textPrimary,
                ),
              ),
              if (_steps.length > 1)
                Text(
                  s.drillProgress(_step + 1, _steps.length),
                  style: TextStyle(fontSize: 11, color: ll.textTertiary),
                ),
            ],
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final item = _item;
          if (item == null) {
            return Center(
              child: Text(
                s.drillNoSteps,
                style: TextStyle(fontSize: 13, color: ll.textTertiary),
              ),
            );
          }
          final component = _current;
          if (component == null) {
            return Center(
              child: Text(
                s.drillNoSteps,
                style: TextStyle(fontSize: 13, color: ll.textTertiary),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            child: _buildStep(context, s, ll, item, component),
          );
        },
      ),
    );
  }

  Widget _buildStep(
    BuildContext context,
    LLStrings s,
    LLPalette ll,
    VocabularyItem item,
    StudyComponent component,
  ) {
    switch (component) {
      case StudyComponent.originalRelisten:
        return _buildRelisten(s, ll, item);
      case StudyComponent.dictationRetry:
        return _buildDictation(s, ll, item);
      case StudyComponent.clozeRecall:
        return _buildCloze(s, ll, item);
      case StudyComponent.morphologyNote:
        return _buildMorphology(s, ll, item);
      case StudyComponent.contextTransfer:
        return _buildAiQuiz(s, ll, item);
      case StudyComponent.srsReview:
        // 不该出现在这里（构造时已过滤）—— 给一句诚实的话而不是空白页
        return Text(
          s.drillNoSteps,
          style: TextStyle(fontSize: 13, color: ll.textTertiary),
        );
    }
  }

  // ----------------------------------------------------------- AI 出题

  bool _aiKickStarted = false;

  /// 进入该步时发起一次取题（build 中触发但用 flag 防重复）。
  void _kickOffAiQuiz(VocabularyItem item) {
    if (_aiKickStarted) return;
    _aiKickStarted = true;
    final loader = widget.loadAiQuiz;
    if (loader == null) {
      _aiError = LLStrings.of(context).drillAiUnavailable;
      return;
    }
    _aiLoading = true;
    scheduleMicrotask(() async {
      try {
        final quiz = await loader(item);
        if (mounted) {
          setState(() {
            _aiQuiz = quiz;
            _aiLoading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _aiLoading = false;
            _aiError = LLStrings.of(context).drillAiUnavailable;
          });
        }
      }
    });
  }

  /// 听写证据（§5.3 的 listening 维度）：出现过可靠的听写错误即视为未稳。
  bool get _listeningEvidenceFailed => (_item?.occurrences ?? const []).any(
    (o) => o.dictationDiffType != null && !o.uncertain,
  );

  Future<void> _submitAiAnswer(String answer) async {
    final quiz = _aiQuiz;
    final judge = widget.judgeAiAnswer;
    if (quiz == null || judge == null || _aiGrading) return;
    setState(() => _aiGrading = true);
    try {
      final verdict = await judge(
        quiz: quiz,
        questionIndex: _aiQuestion,
        answer: answer,
      );
      final stage = switch (_aiQuestion) {
        0 => 'recognition',
        1 => 'production',
        _ => 'conflict',
      };
      widget.store.recordDrill(
        itemId: widget.itemId,
        component: StudyComponent.contextTransfer.name,
        passed: verdict.verdict == AiVerdict.pass,
        detail: jsonEncode({
          'stage': stage,
          'verdict': verdict.verdict.name,
          'reasonCode': verdict.reasonCode,
          'answer': answer.trim(),
        }),
      );
      if (!mounted) return;
      // q2 判定后：两题证据冲突（一过一不过）且冲突回调可用 → 进第 3 题
      // （§5.2 冲突消解）；否则直接收卷。
      if (_aiQuestion == 1) {
        final q1Pass = _aiQ1Verdict!.verdict == AiVerdict.pass;
        final q2Pass = verdict.verdict == AiVerdict.pass;
        if (q1Pass != q2Pass && widget.loadConflictQuiz != null) {
          setState(() {
            _aiConflictMode = true;
            _aiConflictLoading = true;
            _aiGrading = false;
            _input.clear();
          });
          await _loadConflictTask(quiz, _aiQ1Verdict!, verdict);
          return;
        }
      }
      setState(() {
        if (_aiQuestion == 0) {
          _aiQ1Verdict = verdict;
          _aiQuestion = 1;
        } else if (_aiQuestion == 1) {
          _aiQ2Verdict = verdict;
        } else {
          _aiQ3Verdict = verdict;
        }
        _aiGrading = false;
        _input.clear();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiGrading = false;
          _aiError = LLStrings.of(context).drillAiUnavailable;
        });
      }
    }
  }

  Future<void> _loadConflictTask(
    AiQuiz quiz,
    AiAnswerJudgement q1,
    AiAnswerJudgement q2,
  ) async {
    try {
      final raw = await widget.loadConflictQuiz!(
        quiz: quiz,
        q1: q1,
        q2: q2,
      );
      if (!mounted) return;
      setState(() {
        _aiConflictTask = parseConflictTask(raw);
        _aiConflictLoading = false;
        _aiQuestion = 2;
      });
    } catch (_) {
      // 第 3 题取不到 = 冲突不消解，落「半会」（可跳过语义，§5.5 红线）。
      if (!mounted) return;
      setState(() {
        _aiConflictLoading = false;
        _aiConflictMode = false;
        _aiQ2Verdict = q2;
        _aiQuestion = 1;
      });
    }
  }

  Widget _buildAiQuiz(LLStrings s, LLPalette ll, VocabularyItem item) {
    _kickOffAiQuiz(item);

    final header = _stepHeader(s, ll, s.drillAiTitle, s.drillAiBody);

    // 不可用：如实说明 + 跳过（§5.5 红线——不得阻塞）。
    if (_aiError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Text(
            _aiError!,
            style: TextStyle(fontSize: 13, height: 1.5, color: ll.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: _advance,
            child: Text(s.drillAiSkip),
          ),
        ],
      );
    }

    if (_aiLoading || _aiQuiz == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                s.drillAiLoading,
                style: TextStyle(fontSize: 13, color: ll.textSecondary),
              ),
            ],
          ),
        ],
      );
    }

    final quiz = _aiQuiz!;
    final conflictQuestionPending = _aiConflictMode && _aiQ3Verdict == null;
    final question = switch (_aiQuestion) {
      0 => quiz.contextQuestion,
      1 => quiz.transferPrompt,
      _ => _aiConflictTask ?? '',
    };
    final qLabel = switch (_aiQuestion) {
      0 => s.drillAiQ1,
      1 => s.drillAiQ2,
      _ => s.drillAiQ3,
    };
    final verdict = switch (_aiQuestion) {
      0 => _aiQ1Verdict,
      1 => _aiQ2Verdict,
      _ => _aiQ3Verdict,
    };

    // 收卷：两题都判定完、且（无冲突 或 冲突已消解完）→ 本地映射（§5.3）。
    if (_aiQ2Verdict != null && !(conflictQuestionPending)) {
      final finalVerdict = masteryVerdict(
        listeningPass: !_listeningEvidenceFailed,
        recognitionPass: _aiQ1Verdict!.verdict == AiVerdict.pass,
        productionPass: _aiQ2Verdict!.verdict == AiVerdict.pass,
        conflictResolved:
            _aiConflictMode ? _aiQ3Verdict?.verdict == AiVerdict.pass : null,
      );
      final levelText = switch (finalVerdict.level) {
        MasteryLevel.known => s.drillAiVerdictKnown,
        MasteryLevel.halfKnown => s.drillAiVerdictHalf,
        MasteryLevel.unknown => s.drillAiVerdictUnknown,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          _aiVerdictCard(ll, s.drillAiQ1, _aiQ1Verdict!),
          _aiVerdictCard(ll, s.drillAiQ2, _aiQ2Verdict!),
          if (_aiQ3Verdict != null)
            _aiVerdictCard(ll, s.drillAiQ3, _aiQ3Verdict!),
          const SizedBox(height: 16),
          Text(
            levelText,
            style: TextStyle(fontSize: 14, height: 1.5, color: ll.textPrimary),
          ),
          if (finalVerdict.listeningUnstable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.drillAiListeningNote,
                style: TextStyle(fontSize: 12, height: 1.5, color: ll.textSecondary),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _advance,
            child: Text(s.drillFinish),
          ),
        ],
      );
    }

    // 冲突题加载中。
    if (_aiConflictMode && _aiConflictLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                s.drillAiLoading,
                style: TextStyle(fontSize: 13, color: ll.textSecondary),
              ),
            ],
          ),
        ],
      );
    }

    // 答题中。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Text(
          qLabel,
          style: TextStyle(fontSize: 12, color: ll.textTertiary),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ll.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            question,
            style: TextStyle(fontSize: 16, height: 1.5, color: ll.textPrimary),
          ),
        ),
        if (verdict != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _aiVerdictCard(ll, qLabel, verdict),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _input,
          maxLines: 3,
          enabled: verdict == null && !_aiGrading,
          style: TextStyle(fontSize: 15, height: 1.5, color: ll.textPrimary),
          decoration: InputDecoration(
            hintText: s.drillAiAnswerHere,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              onPressed:
                  (_aiGrading || verdict != null || _input.text.trim().isEmpty)
                  ? null
                  : () => _submitAiAnswer(_input.text),
              child: Text(_aiGrading ? s.drillAiGrading : s.drillAiSubmit),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _aiGrading ? null : _advance,
              child: Text(s.drillAiSkip),
            ),
          ],
        ),
      ],
    );
  }

  Widget _aiVerdictCard(LLPalette ll, String label, AiAnswerJudgement verdict) {
    final text = switch (verdict.verdict) {
      AiVerdict.pass => LLStrings.of(context).drillAiPass,
      AiVerdict.partial => LLStrings.of(context).drillAiPartial,
      AiVerdict.fail => LLStrings.of(context).drillAiFail,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label · $text (${verdict.reasonCode})',
        style: TextStyle(fontSize: 13, height: 1.5, color: ll.textSecondary),
      ),
    );
  }

  // ------------------------------------------------------------- 原声回听

  Widget _buildRelisten(LLStrings s, LLPalette ll, VocabularyItem item) {
    final occurrence = _occurrence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(s, ll, s.drillRelistenTitle, s.drillRelistenBody),
        if (occurrence != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ll.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              occurrence.sentenceText,
              style: TextStyle(fontSize: 17, height: 1.5, color: ll.textPrimary),
            ),
          ),
        _audioButton(s, ll),
        if (_playCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _playCount > 1 ? s.drillReplay : s.drillPlay,
              style: TextStyle(fontSize: 11, color: ll.textTertiary),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          s.drillSelfReported,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            color: ll.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        _PrimaryButton(
          key: const Key('drill-relisten-ok'),
          label: s.drillListenedOk,
          palette: ll,
          onPressed: () =>
              _complete(VocabularyDrillJudge.selfReported(satisfied: true)),
        ),
        const SizedBox(height: 8),
        _GhostButton(
          key: const Key('drill-relisten-partial'),
          label: s.drillNotYet,
          palette: ll,
          onPressed: () =>
              _complete(VocabularyDrillJudge.selfReported(satisfied: false)),
        ),
      ],
    );
  }

  Widget _audioButton(LLStrings s, LLPalette ll) {
    final blocked = _audioFailed || (!_audioReady && needsAudio);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('drill-play'),
        onPressed: blocked ? null : _playClip,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: ll.divider),
          foregroundColor: ll.textPrimary,
        ),
        icon: Icon(Icons.play_arrow_rounded, size: 20, color: ll.textPrimary),
        label: Text(
          _audioFailed
              ? s.drillNoAudio
              : (_playCount == 0 ? s.drillPlay : s.drillReplay),
          style: TextStyle(fontSize: 13.5, color: ll.textPrimary),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- 整句听写

  Widget _buildDictation(LLStrings s, LLPalette ll, VocabularyItem item) {
    final occurrence = _occurrence;
    final expected = occurrence?.sentenceText ?? item.surfaceForm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(s, ll, s.drillDictationTitle, s.drillDictationBody),
        _audioButton(s, ll),
        const SizedBox(height: 16),
        if (_outcome == null) ...[
          TextField(
            key: const Key('drill-dictation-input'),
            controller: _input,
            maxLines: 3,
            minLines: 2,
            style: TextStyle(fontSize: 15, color: ll.textPrimary),
            decoration: InputDecoration(
              hintText: s.drillWriteHere,
              hintStyle: TextStyle(color: ll.textTertiary, fontSize: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: ll.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: ll.divider),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _PrimaryButton(
            key: const Key('drill-submit'),
            label: s.drillSubmit,
            palette: ll,
            onPressed: () => setState(() {
              _outcome = VocabularyDrillJudge.judgeSentenceDictation(
                expected: expected,
                actual: _input.text,
              );
            }),
          ),
        ] else ...[
          // 提交后才揭晓原文 —— 这是"先写完整段再对答案"的最小版本
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ll.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              expected,
              style: TextStyle(fontSize: 15.5, height: 1.5, color: ll.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          _OutcomeBanner(
            key: const Key('drill-outcome'),
            palette: ll,
            strings: s,
            outcome: _outcome!,
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            key: const Key('drill-next'),
            label: _step + 1 >= _steps.length ? s.drillFinish : s.drillNext,
            palette: ll,
            onPressed: () => _complete(_outcome!),
          ),
          const SizedBox(height: 8),
          _GhostButton(
            key: const Key('drill-retry'),
            label: s.drillRetry,
            palette: ll,
            onPressed: () => setState(() {
              _outcome = null;
              _input.clear();
            }),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------- Cloze

  Widget _buildCloze(LLStrings s, LLPalette ll, VocabularyItem item) {
    final occurrence = _occurrence;
    final prompt = occurrence == null
        ? null
        : VocabularyDrillJudge.buildCloze(
            sentenceText: occurrence.sentenceText,
            charStart: occurrence.charStart,
            charEnd: occurrence.charEnd,
          );

    if (prompt == null) {
      // 没有可用上下文时不硬造题 —— 明说做不了，让用户直接跳过
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(s, ll, s.drillClozeTitle, s.drillClozeBody),
          _PrimaryButton(
            key: const Key('drill-next'),
            label: _step + 1 >= _steps.length ? s.drillFinish : s.drillNext,
            palette: ll,
            onPressed: () =>
                _complete(VocabularyDrillJudge.acknowledgeMorphology()),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(s, ll, s.drillClozeTitle, s.drillClozeBody),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ll.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            // 提交后揭晓整句，之前只给挖空版
            _revealed ? prompt.revealed : prompt.blanked,
            key: const Key('drill-cloze-text'),
            style: TextStyle(fontSize: 17, height: 1.5, color: ll.textPrimary),
          ),
        ),
        const SizedBox(height: 16),
        if (_outcome == null) ...[
          TextField(
            key: const Key('drill-cloze-input'),
            controller: _input,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(fontSize: 15, color: ll.textPrimary),
            decoration: InputDecoration(
              hintText: s.drillClozeHere,
              hintStyle: TextStyle(color: ll.textTertiary, fontSize: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: ll.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: ll.divider),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _PrimaryButton(
            key: const Key('drill-submit'),
            label: s.drillSubmit,
            palette: ll,
            onPressed: () => setState(() {
              _outcome = VocabularyDrillJudge.judgeCloze(
                target: prompt.target,
                answer: _input.text,
              );
              _revealed = true;
            }),
          ),
        ] else ...[
          _OutcomeBanner(
            key: const Key('drill-outcome'),
            palette: ll,
            strings: s,
            outcome: _outcome!,
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            key: const Key('drill-next'),
            label: _step + 1 >= _steps.length ? s.drillFinish : s.drillNext,
            palette: ll,
            onPressed: () => _complete(_outcome!),
          ),
          const SizedBox(height: 8),
          _GhostButton(
            key: const Key('drill-retry'),
            label: s.drillRetry,
            palette: ll,
            onPressed: () => setState(() {
              _outcome = null;
              _revealed = false;
              _input.clear();
            }),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------- 形态纠错

  Widget _buildMorphology(LLStrings s, LLPalette ll, VocabularyItem item) {
    // 从听写证据里取「实际写的」与「原文的」—— 这正是形态问题的原始现场
    String? actual;
    String? expected;
    for (final o in item.occurrences) {
      if (o.actual != null && o.actual!.trim().isNotEmpty) {
        actual = o.actual;
        expected = o.expected ?? item.surfaceForm;
      }
    }
    actual ??= item.lastDrill?.detail;
    expected ??= item.surfaceForm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(s, ll, s.drillMorphTitle, s.drillMorphBody),
        _kvRow(ll, s.drillMorphYouWrote, actual ?? '—'),
        const SizedBox(height: 8),
        _kvRow(ll, s.drillMorphCorrect, expected),
        const SizedBox(height: 24),
        _PrimaryButton(
          key: const Key('drill-ack'),
          label: _step + 1 >= _steps.length ? s.drillFinish : s.drillAck,
          palette: ll,
          onPressed: () =>
              _complete(VocabularyDrillJudge.acknowledgeMorphology()),
        ),
      ],
    );
  }

  Widget _kvRow(LLPalette ll, String label, String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: ll.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.1,
            color: ll.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 15.5, color: ll.textPrimary, height: 1.4),
        ),
      ],
    ),
  );

  Widget _stepHeader(
    LLStrings s,
    LLPalette ll,
    String title,
    String body,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            color: ll.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: TextStyle(fontSize: 12.5, height: 1.5, color: ll.textTertiary),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ 小件

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({
    super.key,
    required this.palette,
    required this.strings,
    required this.outcome,
  });

  final LLPalette palette;
  final LLStrings strings;
  final DrillOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final passed = outcome.passed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ll.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                passed
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 17,
                color: passed ? ll.textPrimary : ll.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                strings.drillHint(outcome.hint.name),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: ll.textPrimary,
                ),
              ),
            ],
          ),
          if (!passed) ...[
            const SizedBox(height: 6),
            Text(
              strings.drillAccuracy((outcome.accuracy * 100).round()),
              style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
            ),
          ],
          if (outcome.hint == DrillHint.alignment) ...[
            const SizedBox(height: 6),
            Text(
              strings.drillUncertainNote,
              style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onPressed,
  });

  final String label;
  final LLPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ll.textPrimary,
          foregroundColor: ll.bg,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onPressed,
  });

  final String label;
  final LLPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          foregroundColor: ll.textSecondary,
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13.5, color: ll.textSecondary),
        ),
      ),
    );
  }
}
