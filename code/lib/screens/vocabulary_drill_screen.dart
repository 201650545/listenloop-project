import 'dart:async';

import 'package:flutter/material.dart';

import '../data/vocabulary_store.dart';
import '../l10n/ll_strings.dart';
import '../models/vocabulary_model.dart';
import '../player/audio_player_facade.dart';
import '../player/just_audio_facade.dart';
import '../theme/listenloop_theme.dart';
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

    /// 测试缝：注入一个不触真实音频栈的门面。
    this.autoCreateAudioFacade = true,
  });

  final VocabularyStore store;

  /// 用 id 而不是对象 —— 练习过程中 store 会更新，页面始终读最新值。
  final String itemId;

  /// 本次要执行的组件（来自 [VocabularyPlanEntry.components]）。
  final List<StudyComponent> components;

  final AudioPlayerFacade? audioFacade;

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
      case StudyComponent.srsReview:
        // 不该出现在这里（构造时已过滤）—— 给一句诚实的话而不是空白页
        return Text(
          s.drillNoSteps,
          style: TextStyle(fontSize: 13, color: ll.textTertiary),
        );
    }
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
