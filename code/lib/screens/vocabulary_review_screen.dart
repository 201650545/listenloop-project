import 'dart:async';

import 'package:flutter/material.dart';

import '../data/ai_governor_service.dart';
import '../data/vocabulary_store.dart';
import '../l10n/ll_strings.dart';
import '../models/vocabulary_model.dart';
import '../player/audio_player_facade.dart';
import '../player/just_audio_facade.dart';
import '../theme/listenloop_theme.dart';
import '../training/vocabulary_drill.dart';
import '../training/vocabulary_plan.dart';
import 'ai_quiz_launcher.dart';

/// 闪卡复习 —— **一个词一张卡**（`EPIC-04` 派生规则 3）。
///
/// 与练习页的分工：
///   * 练习页（[StudyComponent]）管"听辨/拼写/形态"的针对性练习；
///   * 本页只管**记忆调度**：正面回想到位没有，然后给四档评级。
///
/// 卡面对齐 03 号 §二 标准的落地状态：
///   * 正面 = 音频 + 英文挖空句，**零中文** ✅（音变提示待 04 的标注管线，
///     无数据就不显示 —— 不伪造）；
///   * 背面 = 目标词 + 完整原句 + 中文释义（唯一中文位）+「AI 考我造句」
///     与「还原原片现场」两个动作（注入才出现）。
///
/// 本页默认离线完整可用：调度（SM-2）、卡面渲染、评级落盘都不碰网络；
/// AI 动作只在注入了网关时出现（§5.5 红线：附属失败不得阻塞核心）。
class VocabularyReviewScreen extends StatefulWidget {
  const VocabularyReviewScreen({
    super.key,
    required this.store,

    /// 指定队列（按 id）；null = 按配额从 store 组装"到期 + 新卡"。
    ///
    /// 从今日计划里单点一张卡进来时用这个，避免被整队拖着走。
    this.queueIds,
    this.audioFacade,
    this.aiGovernorService,
    this.onOpenOccurrence,

    /// 测试缝：注入假门面后不再自建真实播放器。
    this.autoCreateAudioFacade = true,

    /// 测试注入"现在"，让到期判断可控。
    this.now,
  });

  final VocabularyStore store;
  final List<String>? queueIds;
  final AudioPlayerFacade? audioFacade;

  /// 背面「AI 考我造句」的通道 —— 可选注入，null 则不显示该按钮。
  final AiGovernorService? aiGovernorService;

  /// 背面「还原原片现场」—— 由调用方（生词本）负责真正跳转。
  final void Function(VocabularyOccurrence occurrence)? onOpenOccurrence;

  final bool autoCreateAudioFacade;
  final DateTime? now;

  @override
  State<VocabularyReviewScreen> createState() => _VocabularyReviewScreenState();
}

class _VocabularyReviewScreenState extends State<VocabularyReviewScreen> {
  late final List<VocabularyItem> _queue = _buildQueue();

  AudioPlayerFacade? _audio;
  bool _ownsAudio = false;
  bool _audioReady = false;
  bool _audioFailed = false;

  int _index = 0;
  bool _revealed = false;
  int _reviewed = 0;
  bool _finished = false;

  List<VocabularyItem> _buildQueue() {
    final ids = widget.queueIds;
    if (ids != null) {
      return <VocabularyItem>[
        for (final id in ids)
          if (widget.store.itemById(id) != null) widget.store.itemById(id)!,
      ];
    }
    return const VocabularyReviewQueue().build(
      widget.store.items,
      now: widget.now,
    );
  }

  VocabularyItem? get _current =>
      _index < _queue.length ? _queue[_index] : null;

  @override
  void initState() {
    super.initState();
    _prepareAudio();
  }

  @override
  void dispose() {
    if (_ownsAudio) unawaited(_audio?.dispose());
    super.dispose();
  }

  void _prepareAudio() {
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

  Future<void> _loadClip() async {
    final audio = _audio;
    final occurrence = _current?.latestOccurrence;
    if (audio == null || occurrence == null || occurrence.audioPath.isEmpty) {
      if (mounted) setState(() => _audioFailed = true);
      return;
    }
    try {
      await audio.loadPlaylist(
        path: occurrence.audioPath,
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
    if (!_audioReady || _audio == null) return;
    await _audio!.seek(Duration.zero);
    await _audio!.play();
  }

  void _rate(ReviewRating rating) {
    final item = _current;
    if (item == null) return;
    widget.store.recordReview(itemId: item.id, rating: rating, now: widget.now);
    _reviewed++;

    if (_index + 1 >= _queue.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
      _audioReady = false;
      _audioFailed = false;
    });
    unawaited(_loadClip());
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
        title: Text(
          s.reviewTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: ll.textPrimary,
          ),
        ),
        actions: [
          if (!_finished && _queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  s.reviewProgress(_index + 1, _queue.length),
                  style: TextStyle(
                    fontSize: 12,
                    color: ll.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(context, s, ll)),
    );
  }

  Widget _buildBody(BuildContext context, LLStrings s, LLPalette ll) {
    if (_queue.isEmpty) {
      return _centered(
        ll,
        title: s.reviewEmptyTitle,
        body: s.reviewEmptyBody,
        key: const Key('review-empty'),
      );
    }
    if (_finished) {
      return _centered(
        ll,
        title: s.reviewDone,
        body: s.reviewSummary(_reviewed),
        key: const Key('review-summary'),
      );
    }

    final item = _current;
    if (item == null) {
      return _centered(ll, title: s.reviewEmptyTitle, body: s.reviewEmptyBody);
    }

    final occurrence = item.latestOccurrence;
    final cloze = occurrence == null
        ? null
        : VocabularyDrillJudge.buildCloze(
            sentenceText: occurrence.sentenceText,
            charStart: occurrence.charStart,
            charEnd: occurrence.charEnd,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.srs == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                s.reviewNewCard,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: ll.textTertiary,
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (occurrence != null && !_audioFailed)
                    OutlinedButton.icon(
                      key: const Key('review-play'),
                      onPressed: _audioReady ? _playClip : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: ll.divider),
                        foregroundColor: ll.textPrimary,
                      ),
                      icon: Icon(
                        Icons.play_arrow_rounded,
                        size: 20,
                        color: ll.textPrimary,
                      ),
                      label: Text(
                        s.drillPlay,
                        style: TextStyle(fontSize: 13.5, color: ll.textPrimary),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: ll.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      // 正面只给挖空句；背面才给完整原句
                      _revealed
                          ? (occurrence?.sentenceText ?? item.surfaceForm)
                          : (cloze?.blanked ?? s.reviewNoContext),
                      key: const Key('review-card-text'),
                      style: TextStyle(
                        fontSize: 19,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: ll.textPrimary,
                      ),
                    ),
                  ),
                  if (_revealed) ...[
                    const SizedBox(height: 16),
                    Text(
                      item.surfaceForm,
                      key: const Key('review-answer'),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: ll.textPrimary,
                      ),
                    ),
                    if (item.chineseGloss != null ||
                        item.englishDefinition != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.chineseGloss ?? item.englishDefinition!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: ll.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    ListenableBuilder(
                      listenable: widget.store,
                      builder: (context, _) {
                        final srs = widget.store.itemById(item.id)?.srs;
                        if (srs == null) return const SizedBox.shrink();
                        final days =
                            srs.dueAt
                                .difference(widget.now ?? DateTime.now())
                                .inHours /
                            24;
                        return Text(
                          s.reviewNextDue(days.round()),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: ll.textTertiary,
                          ),
                        );
                      },
                    ),
                    // 03 号 §二 背面的两个动作（注入才出现，缺省无按钮 ——
                    // 附属动作不阻塞评级主流程）。
                    if (widget.aiGovernorService != null ||
                        (widget.onOpenOccurrence != null &&
                            occurrence != null)) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (widget.aiGovernorService != null)
                            TextButton.icon(
                              key: Key('review-ai-quiz-${item.id}'),
                              onPressed: () => _openAiQuiz(item),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(
                                Icons.auto_awesome_outlined,
                                size: 15,
                                color: ll.textPrimary,
                              ),
                              label: Text(
                                s.reviewAiQuizAction,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: ll.textPrimary,
                                ),
                              ),
                            ),
                          if (widget.onOpenOccurrence != null &&
                              occurrence != null) ...[
                            const SizedBox(width: 10),
                            TextButton.icon(
                              key: Key('review-open-scene-${item.id}'),
                              onPressed: () =>
                                  widget.onOpenOccurrence!(occurrence),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(
                                Icons.movie_outlined,
                                size: 15,
                                color: ll.textPrimary,
                              ),
                              label: Text(
                                s.reviewOpenSceneAction,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: ll.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_revealed) ...[
            Text(
              s.reviewFrontHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: const Key('review-reveal'),
              onPressed: () => setState(() => _revealed = true),
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
                s.reviewReveal,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else
            Row(
              children: [
                _ratingButton(ll, s.reviewAgain, ReviewRating.again,
                    const Key('review-again')),
                const SizedBox(width: 8),
                _ratingButton(ll, s.reviewHard, ReviewRating.hard,
                    const Key('review-hard')),
                const SizedBox(width: 8),
                _ratingButton(ll, s.reviewGood, ReviewRating.good,
                    const Key('review-good'), emphasised: true),
                const SizedBox(width: 8),
                _ratingButton(ll, s.reviewEasy, ReviewRating.easy,
                    const Key('review-easy')),
              ],
            ),
        ],
      ),
    );
  }

  /// 背面「AI 考我造句」（03 号 §二 ai-actions）—— 打开单卷 AI 检查。
  Future<void> _openAiQuiz(VocabularyItem item) async {
    final governor = widget.aiGovernorService;
    if (governor == null) return;
    await openAiQuizScreen(
      context: context,
      store: widget.store,
      item: item,
      governor: governor,
      audioFacade: widget.audioFacade,
      autoCreateAudioFacade: widget.audioFacade == null,
    );
    if (mounted) setState(() {}); // 回来后刷新 SRS 行（检查可能新增了 drill 记录）
  }

  Widget _ratingButton(
    LLPalette ll,
    String label,
    ReviewRating rating,
    Key key, {
    bool emphasised = false,
  }) => Expanded(
    child: OutlinedButton(
      key: key,
      onPressed: () => _rate(rating),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        backgroundColor: emphasised ? ll.surfaceHigh : null,
        side: BorderSide(color: ll.divider),
        foregroundColor: ll.textPrimary,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: emphasised ? FontWeight.w600 : FontWeight.w500,
          color: emphasised ? ll.textPrimary : ll.textSecondary,
        ),
      ),
    ),
  );

  Widget _centered(
    LLPalette ll, {
    required String title,
    required String body,
    Key? key,
  }) => Center(
    key: key,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.style_outlined, size: 32, color: ll.textTertiary),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ll.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.6, color: ll.textTertiary),
          ),
        ],
      ),
    ),
  );
}
