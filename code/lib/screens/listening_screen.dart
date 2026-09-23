import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ai_governor_service.dart';
import '../data/demo_sentences_human.dart';
import '../l10n/ll_strings.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../models/video_source.dart';
import '../player/audio_player_facade.dart';
import '../player/just_audio_facade.dart';
import '../player/playback_mode.dart';
import '../player/sentence_player_controller.dart';
import '../player/video_playback_facade.dart';
import '../preferences/app_preferences.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ai_tutor_sheet.dart';
import '../widgets/anki/anki_review_dialog.dart';
import '../widgets/listening_top_bar.dart';
import '../widgets/media_area.dart';
import '../widgets/playback_controls.dart';
import '../widgets/sentence_display.dart';
import '../widgets/sentence_page_list.dart';
import '../widgets/speed_selector.dart';
import '../widgets/subtitle_mode_selector.dart';
import '../widgets/video_area.dart';
import 'dictation_screen.dart';

/// The listening screen (Visual Polish V1/V2).
///
/// Black/white minimal, one-sentence focus: the English sentence is the
/// first visual focus, the Chinese translation is a second layer, and the
/// control cluster sits in the lower half for one-hand use. Learning
/// typography follows the user preferences (font + text scale, spec V2
/// §二十七–二十九). Playback behaviour is owned by
/// [SentencePlayerController] — this widget only renders state and
/// forwards intent (spec V0.1 §28).
class ListeningScreen extends StatefulWidget {
  const ListeningScreen({
    super.key,
    this.audioFacade,
    this.videoFacade,
    this.sentences,
    this.audioAsset,
    this.title,
    this.language,
    this.audioIsFile = false,
    this.lessonId,
    this.repository,
    this.coverPath,
    this.initialSentenceIndex = 0,
    this.autoPlay = false,
    this.initialRepeatTarget = 1,
    this.initialPlaybackRate = 1.0,
    this.initialSubtitleMode,
    this.initialPageMode = false,
    this.videoSource,
    this.onControllerCreated,
    this.aiGovernorService,
  });

  /// Optional AI Governor service (injected by caller or tests).
  final AiGovernorService? aiGovernorService;

  /// Overrides the production [JustAudioFacade] (used by tests).
  final AudioPlayerFacade? audioFacade;

  /// Overrides the production [VideoPlaybackFacade] for lessons with a video
  /// source (used by tests; Phase 3C). Without it, a [VideoSource] lesson
  /// gets a real [VideoPlaybackFacade] and audio-only lessons get none.
  final AudioPlayerFacade? videoFacade;

  /// Overrides the bundled demo sentences (used by tests).
  final List<Sentence>? sentences;

  /// Overrides the bundled asset path (used by tests).
  final String? audioAsset;

  /// App bar title; defaults to `ListenLoop` (the bundled demo).
  final String? title;

  /// Source language of the lesson (e.g. 'en', 'ja', 'fr').
  final String? language;

  /// When true, [audioAsset] is an absolute file path instead of a bundled
  /// asset (imported lesson media).
  final bool audioIsFile;

  /// Lesson id for progress persistence; requires [repository].
  final String? lessonId;

  /// Repository used to persist progress on dispose.
  final LessonRepository? repository;

  /// Optional lesson cover shown in the media area.
  final String? coverPath;

  /// Sentence to open (V0.2.1 恢复学习); restore uses startMs, not positionMs.
  final int initialSentenceIndex;

  /// Auto-play on open (V0.2.1 §7).
  final bool autoPlay;

  /// Restored repeat target (0 = infinite).
  final int initialRepeatTarget;

  /// Restored playback rate.
  final double initialPlaybackRate;

  /// Restored subtitle mode name ('hidden'/'english'/'bilingual').
  final String? initialSubtitleMode;

  /// Restored display mode: true = 单页文本, false = 流体文本.
  final bool initialPageMode;

  /// When set, playback is driven by the embedded web video player (Phase 3B)
  /// instead of the local audio file, and the media slot renders the video.
  final VideoSource? videoSource;

  /// Visual Polish V2 §三十二: lets the navigation shell reach the active
  /// controller (to pause when the user opens Settings) without exposing
  /// the player architecture.
  final ValueChanged<SentencePlayerController>? onControllerCreated;

  @override
  State<ListeningScreen> createState() => ListeningScreenState();
}

/// Public so the navigation shell can hold a [GlobalKey] to it and ask the
/// transcript to reveal the current sentence when the Listen tab becomes
/// visible (spec V2 §三十一 — the session persists across tab switches, so
/// the one-shot auto-scroll guard must be reset on reveal).
class ListeningScreenState extends State<ListeningScreen>
    with WidgetsBindingObserver {
  late final SentencePlayerController _controller;
  late SubtitleMode _subtitleMode;
  bool _pageMode = false;
  late final List<GlobalKey> _itemKeys;

  /// Bumped to ask SentencePageList to re-align to the current sentence
  /// (tab re-entry via revealCurrentSentence, presentation-mode switch).
  int _revealToken = 0;

  // ---- 句跳滑栏（2026-09-21 用户需求）：长按字幕区呼出，拖动预览、
  // ---- 松手跳转，适合千句级课程快速定位。
  bool _scrubberVisible = false;
  bool _scrubbing = false;
  int _scrubIndex = 0;
  double _subtitleAreaHeight = 0;
  Timer? _scrubberHideTimer;
  Timer? _leftLongPressTimer;
  Offset? _leftPointerDownPos;
  int _transcriptVisibleIndex = 0;
  late final AiGovernorService _aiGovernorService =
      widget.aiGovernorService ?? AiGovernorService();

  /// 核心层 P1：打开听写训练（句级录入 / 段级集中批改）。
  ///
  /// 复用同一个播放控制器 —— 用户听到的必须是原片句轴音频，
  /// 不允许用合成音替代（见 08 定调的交互红线）。
  void _openDictation() {
    _controller.pause();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DictationScreen(controller: _controller),
      ),
    );
  }

  void _openAiTutor() {
    _controller.pause();
    final lesson = Lesson(
      id: widget.lessonId ?? 'demo',
      title: widget.title ?? '精听课程',
      language: widget.language ?? 'en',
      audioPath: widget.audioAsset ?? '',
      sentenceCount: _controller.sentenceCount,
      durationMs: _controller.sentences.isNotEmpty
          ? _controller.sentences.last.endMs
          : 0,
      importedAt: DateTime.now(),
    );
    AiTutorSheet.show(
      context: context,
      lesson: lesson,
      currentSentenceIndex: _controller.currentSentenceIndex,
      sentences: _controller.sentences,
      aiGovernorService: _aiGovernorService,
      onSeekToSentence: (index) {
        _controller.selectSentence(index);
        _controller.playCurrentSentence();
      },
    );
  }

  Future<void> _toggleAnkiCard() async {
    final curIdx = _controller.currentSentenceIndex;
    if (curIdx < 0 || curIdx >= _controller.sentences.length) return;
    final sentence = _controller.sentences[curIdx];
    final lessonId = widget.lessonId ?? 'demo';

    final isAdded = _aiGovernorService.isSentenceInAnki(lessonId, curIdx);
    if (isAdded) {
      final card = _aiGovernorService.getCardForSentence(lessonId, curIdx);
      if (card != null && mounted) {
        AnkiReviewDialog.show(
          context: context,
          cards: [card],
          aiGovernorService: _aiGovernorService,
          onPlaySnippet: (start, end) {
            _controller.selectSentence(curIdx);
            _controller.playCurrentSentence();
          },
        );
      }
    } else {
      final lesson = Lesson(
        id: lessonId,
        title: widget.title ?? '精听课程',
        language: widget.language ?? 'en',
        audioPath: widget.audioAsset ?? '',
        sentenceCount: _controller.sentenceCount,
        durationMs: _controller.sentences.isNotEmpty
            ? _controller.sentences.last.endMs
            : 0,
        importedAt: DateTime.now(),
      );
      await _aiGovernorService.createAnkiCardFromSentence(
        lesson: lesson,
        sentence: sentence,
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ 已加入 Anki 智能闪卡库 (SM-2 艾宾浩斯复习已排期)'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// The video-side facade when the lesson carries a video (Phase 3C); the
  /// controller owns and disposes it. Only a production [VideoPlaybackFacade]
  /// can render [VideoArea]; a test-injected fake falls back to the cover.
  AudioPlayerFacade? _videoFacade;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Phase 3C §2: every lesson enters in audio mode, even when it carries
    // a video. The video facade is constructed up front (cheap — it only
    // configures a WebView) but its page is loaded lazily on the first
    // switch to video mode, inside the controller's setPlaybackMode.
    _videoFacade =
        widget.videoFacade ??
        (widget.videoSource != null
            ? VideoPlaybackFacade(source: widget.videoSource!)
            : null);
    _controller = SentencePlayerController(
      audioFacade: widget.audioFacade ?? JustAudioFacade(),
      videoFacade: _videoFacade,
      sentences: widget.sentences ?? demoSentencesHuman,
      audioAsset: widget.audioAsset ?? demoAudioAssetHuman,
      audioIsFile: widget.audioIsFile,
      initialSentenceIndex: widget.initialSentenceIndex,
      initialPlaybackRate: widget.initialPlaybackRate,
      initialRepeatTarget: widget.initialRepeatTarget,
    );
    _subtitleMode = SubtitleMode.values.firstWhere(
      (m) => m.name == widget.initialSubtitleMode,
      orElse: () => SubtitleMode.bilingual,
    );
    _pageMode = widget.initialPageMode;
    _itemKeys = List.generate(_controller.sentenceCount, (_) => GlobalKey());
    _lastSentenceIndex = widget.initialSentenceIndex;
    _controller.addListener(_onControllerChanged);
    // V2 §三十二: the shell can reach the active controller (pause when the
    // user opens Settings) without exposing the playback architecture.
    widget.onControllerCreated?.call(_controller);
    // Kick off async initialisation; UI reacts via notifyListeners.
    _controller.initialize().then((_) {
      if (!widget.autoPlay || !mounted) return;
      if (_controller.hasError) return;
      _controller.playCurrentSentence();
    });
  }

  /// AI 伴学的在线通道（网关地址 / 密钥 / 模型）由 PreferencesScope 持有，
  /// 每次从设置页返回都要同步一次，否则讨论页仍在打旧模型。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = PreferencesScope.maybeOf(context);
    if (!identical(prefs, _aiGovernorService.appPreferences)) {
      _aiGovernorService.updatePreferences(prefs);
    }
  }

  /// V2 §三十一: the listening session lives inside the navigation shell and
  /// may never be disposed for the whole app session, so progress is also
  /// checkpointed when the app leaves the foreground — same save routine as
  /// dispose, zero algorithm change.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _saveProgressIfPossible();
  }

  int _sentenceDirection = 1;
  int _lastSentenceIndex = 0;

  void _onControllerChanged() {
    if (mounted) {
      final curIdx = _controller.currentSentenceIndex;
      if (curIdx != _lastSentenceIndex) {
        _sentenceDirection = curIdx > _lastSentenceIndex ? 1 : -1;
        _lastSentenceIndex = curIdx;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leftLongPressTimer?.cancel();
    _scrubberHideTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _saveProgressIfPossible();
    _controller.dispose();
    super.dispose();
  }

  // ------------------------------------------------ 句跳滑栏手势处理 ----

  /// 把字幕区内的纵向位置映射为句索引：顶部 = 第 1 句，底部 = 最后一句。
  /// 2026-09-22 优化：精准基于轨道有效范围 (top: 14%, height: 72%) 映射，
  /// 确保手指在轨道顶部精准定位到第 1 句，轨道底部精准定位到末句。
  int _scrubIndexFromLocalY(double dy) {
    final count = _controller.sentenceCount;
    if (count <= 1 || _subtitleAreaHeight <= 0) return 0;
    final topOffset = _subtitleAreaHeight * 0.14;
    final trackHeight = _subtitleAreaHeight * 0.72;
    if (trackHeight <= 0) return 0;
    final t = ((dy - topOffset) / trackHeight).clamp(0.0, 1.0);
    return (t * (count - 1)).round().clamp(0, count - 1);
  }

  /// 滑栏逐档触感反馈（可在设置中关闭：scrubberHaptics）。
  void _scrubHaptic() {
    if (!PreferencesScope.maybeOf(context).scrubberHaptics) return;
    unawaited(HapticFeedback.selectionClick());
  }

  void _startScrubbing(double dy) {
    _scrubberHideTimer?.cancel();
    _subtitleAreaHeight = _subtitleAreaHeight <= 0 ? 1 : _subtitleAreaHeight;
    setState(() {
      _scrubberVisible = true;
      _scrubbing = true;
      _scrubIndex = _scrubIndexFromLocalY(dy);
    });
    if (PreferencesScope.maybeOf(context).scrubberHaptics) {
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  void _updateScrubbing(double dy) {
    final index = _scrubIndexFromLocalY(dy);
    if (index == _scrubIndex) return;
    setState(() => _scrubIndex = index);
    _scrubHaptic();
  }

  void _endScrubbing() {
    if (!_scrubbing) return;
    final target = _scrubIndex;
    setState(() => _scrubbing = false);
    if (target != _controller.currentSentenceIndex) {
      _controller.selectSentence(target);
    }
    _scheduleScrubberHide();
  }

  void _onScrubStart(LongPressStartDetails details) {
    _startScrubbing(details.localPosition.dy);
  }

  void _onScrubUpdate(LongPressMoveUpdateDetails details) {
    _updateScrubbing(details.localPosition.dy);
  }

  void _onScrubEnd(LongPressEndDetails details) {
    _endScrubbing();
  }

  void _scheduleScrubberHide() {
    _scrubberHideTimer?.cancel();
    _scrubberHideTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted && !_scrubbing) {
        setState(() => _scrubberVisible = false);
      }
    });
  }


  /// V2 §三十一: the transcript may have been laid out offstage while the
  /// user was on another tab. Bump the reveal token so SentencePageList
  /// re-aligns to the currently playing sentence on its next build.
  void revealCurrentSentence() {
    if (!mounted) return;
    setState(() => _revealToken++);
  }

  /// Persists where the user left off (spec V0.2 §20) before teardown.
  /// Fire-and-forget: a failed save must never block closing the screen.
  void _saveProgressIfPossible() {
    final lessonId = widget.lessonId;
    final repository = widget.repository;
    if (lessonId == null || repository == null) return;
    if (!_controller.isInitialized || _controller.hasError) return;
    final index = _controller.currentSentenceIndex;
    final positionMs = _controller.currentPosition.inMilliseconds;
    unawaited(
      repository
          .saveProgress(
            lessonId: lessonId,
            lastSentenceIndex: index,
            positionMs: positionMs,
            repeatTarget: _controller.repeatTarget,
            playbackRate: _controller.playbackRate,
            subtitleMode: _subtitleMode.name,
            displayMode: _pageMode ? 'page' : 'fluid',
          )
          .catchError((Object e) {
            debugPrint('[ListenLoop] failed to save progress: $e');
          }),
    );
  }

  void _onPlayPause() {
    if (_controller.isPlaying) {
      _controller.pause();
      // The session may stay mounted inside the shell for a long time —
      // checkpoint on pause as well as on lifecycle changes.
      _saveProgressIfPossible();
    } else {
      _controller.playCurrentSentence();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ll = context.ll;
    final prefs = PreferencesScope.maybeOf(context);
    final learning = LLReadLearningStyles(
      english: LLLearning.englishSentence(ll, prefs),
      chinese: LLLearning.chineseSentence(ll, prefs),
    );
    final loading = !controller.isInitialized && !controller.hasError;

    // （原外层 ensureVisible 跟随路径已移除：懒加载 ListView 下目标行
    // 未挂载时静默失效，且与 SentencePageList 内部定位互相打架。
    // 定位统一由 SentencePageList._alignToIndex 承担。）

    final sentenceChild = AnimatedSwitcher(
      // §三十五 follow-up: fluid ⇄ transcript also crossfades — switching
      // presentation feels like a fade, not a page jump.
      duration: LLMotion.normal,
      switchInCurve: LLMotion.curve,
      child: KeyedSubtree(
        key: ValueKey(_pageMode),
        child: _pageMode
            ? LayoutBuilder(
                builder: (context, constraints) {
                  _subtitleAreaHeight = constraints.maxHeight;
                  // 长按句跳滑栏（用户需求 2026-09-21）：与 Fluid 模式同款，
                  // 挂在整页字幕区，长按呼出、拖动预览、松手跳句。
                  final content = Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: _onScrubStart,
                      onLongPressMoveUpdate: _onScrubUpdate,
                      onLongPressEnd: _onScrubEnd,
                      child: SentencePageList(
                        sentences: controller.sentences,
                        currentIndex: controller.currentSentenceIndex,
                        showEnglish: _subtitleMode.showsEnglish,
                        showChinese: _subtitleMode.showsChinese,
                        onSentenceTap: (index) =>
                            index == _controller.currentSentenceIndex
                            ? _controller.replaySentence()
                            : _controller.selectSentence(index),
                        itemKeys: _itemKeys,
                        preferences: prefs,
                        header: _transcriptHeader(context, controller),
                        revealToken: _revealToken,
                        onVisibleIndexChanged: (idx) =>
                            _transcriptVisibleIndex = idx,
                      ),
                    ),
                  );
                  return Stack(
                    children: [
                      Positioned.fill(child: content),
                      if (_scrubberVisible || _scrubbing)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: _SentenceScrubber(
                            sentenceCount: _controller.sentenceCount,
                            currentIndex: _controller.currentSentenceIndex,
                            scrubIndex: _scrubbing
                                ? _scrubIndex
                                : _controller.currentSentenceIndex,
                            active: _scrubbing,
                            height: constraints.maxHeight,
                            previewSentence: _scrubbing
                                ? _controller.sentences[_scrubIndex]
                                : null,
                            onDragStart: _startScrubbing,
                            onDragUpdate: _updateScrubbing,
                            onDragEnd: _endScrubbing,
                          ),
                        ),
                    ],
                  );
                },
              )
            // Fluid mode (user request 2026-09-17): sentence changes JUMP.
            // The old fade + horizontal drift made a long→short switch look
            // like the previous sentence was still leaving, because both
            // were on screen at once — the "残影" the user reported.
            //
            // The switch is now a plain content swap, and the sentence gets a
            // fixed footprint (one card per sentence) so a long line cannot
            // grow the area and a short line cannot collapse it: switching
            // only repaints, it never re-lays-out. A long sentence scrolls
            // inside its own card instead of pushing the layout around.
            : LayoutBuilder(
                builder: (context, constraints) {
                  _subtitleAreaHeight = constraints.maxHeight;
                  final content = Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: GestureDetector(
                      key: const Key('subtitle-tap'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _controller.replaySentence(),
                      child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                ...previousChildren,
                                ?currentChild,
                              ],
                            );
                          },
                          transitionBuilder: (child, animation) {
                            final isIncoming =
                                (child.key as ValueKey<int>?)?.value ==
                                    controller.currentSentenceIndex;
                            final curved = CurvedAnimation(
                              parent: animation,
                              curve: isIncoming
                                  ? Curves.easeOutCubic
                                  : Curves.easeInCubic,
                            );
                            final offsetTween = isIncoming
                                ? Tween<Offset>(
                                    begin: Offset(0, _sentenceDirection * 0.35),
                                    end: Offset.zero,
                                  )
                                : Tween<Offset>(
                                    begin: Offset(0, -_sentenceDirection * 0.35),
                                    end: Offset.zero,
                                  );
                            return SlideTransition(
                              position: offsetTween.animate(curved),
                              child: FadeTransition(
                                opacity: curved,
                                child: child,
                              ),
                            );
                          },
                          child: Center(
                            key: ValueKey(controller.currentSentenceIndex),
                            child: SentenceDisplay(
                              sentence: controller.currentSentence,
                              currentPosition: controller.currentPosition,
                              showEnglish: _subtitleMode.showsEnglish,
                              showChinese: _subtitleMode.showsChinese,
                              styles: learning,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                  return Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (event) {
                      // 仅在贴紧屏幕最左侧 (dx <= 44.0) 长按 1 秒呼出上下滑动栏
                      if (event.localPosition.dx <= 44.0) {
                        _leftPointerDownPos = event.localPosition;
                        _leftLongPressTimer?.cancel();
                        _leftLongPressTimer = Timer(
                          const Duration(milliseconds: 1000),
                          () {
                            if (!mounted) return;
                            _startScrubbing(event.localPosition.dy);
                          },
                        );
                      }
                    },
                    onPointerMove: (event) {
                      if (_scrubbing) {
                        _updateScrubbing(event.localPosition.dy);
                      } else if (_leftPointerDownPos != null) {
                        final delta = (event.localPosition - _leftPointerDownPos!).distance;
                        if (delta > 20) {
                          _leftLongPressTimer?.cancel();
                          _leftPointerDownPos = null;
                        }
                      }
                    },
                    onPointerUp: (event) {
                      _leftLongPressTimer?.cancel();
                      _leftPointerDownPos = null;
                      if (_scrubbing) {
                        _endScrubbing();
                      }
                    },
                    onPointerCancel: (event) {
                      _leftLongPressTimer?.cancel();
                      _leftPointerDownPos = null;
                      if (_scrubbing) {
                        _endScrubbing();
                      }
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(child: content),
                        // 左侧上下滑动栏（长按左侧 1 秒呼出，支持上下拖动快速定位）
                        if (_scrubberVisible || _scrubbing)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: _SentenceScrubber(
                              sentenceCount: _controller.sentenceCount,
                              currentIndex: _controller.currentSentenceIndex,
                              scrubIndex: _scrubbing
                                  ? _scrubIndex
                                  : _controller.currentSentenceIndex,
                              active: _scrubbing,
                              height: constraints.maxHeight,
                              previewSentence: _scrubbing
                                  ? _controller.sentences[_scrubIndex]
                                  : null,
                              onDragStart: _startScrubbing,
                              onDragUpdate: _updateScrubbing,
                              onDragEnd: _endScrubbing,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: llSystemOverlay(ll.brightness),
      child: Scaffold(
        backgroundColor: ll.bg,
        body: SafeArea(
          // Horizontal swipe anywhere switches sentences: left→right =
          // previous, right→left = next (user request 2026-09-16).
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -200) {
                if (_controller.canGoNext) _controller.nextSentence();
              } else if (velocity > 200) {
                if (_controller.canGoPrevious) {
                  _controller.previousSentence();
                }
              }
            },
            child: Column(
              children: [
                // V2 follow-up: no title up top — the counter and the
                // presentation toggle sit centred, quiet.
                ListeningTopBar(
                  displayIndex: controller.displayIndex,
                  sentenceCount: controller.sentenceCount,
                  leading: IconButton(
                    key: const Key('ai-tutor-button'),
                    tooltip: 'AI 伴学 / 快测 / Anki',
                    icon: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 18,
                    ),
                    color: ll.textSecondary,
                    onPressed: _openAiTutor,
                  ),
                  // 右侧现在有两个图标（听写 + 显示模式），左右槽位成对加宽，
                  // 否则计数器会偏心且 RenderFlex 溢出。
                  slotWidth: 96,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 核心层 P1：听写入口。刻意放在一级页顶栏 —— 听写属于
                      // 「听」的主链路，不允许埋进二级或附属面板。
                      IconButton(
                        key: const Key('dictation-button'),
                        tooltip: LLStrings.of(context).dictation,
                        icon: const Icon(Icons.keyboard_alt_outlined, size: 19),
                        color: ll.textSecondary,
                        onPressed: _openDictation,
                      ),
                      IconButton(
                    key: const Key('view-mode-button'),
                    tooltip: _pageMode
                        ? LLStrings.of(context).fluidText
                        : LLStrings.of(context).singlePageText,
                    icon: Icon(
                      _pageMode ? Icons.subject : Icons.view_day_outlined,
                      size: 20,
                      color: ll.textSecondary,
                    ),
                    onPressed: () => setState(() {
                      if (_pageMode) {
                        // 从单页切回流体时，精准定位到单页中用户浏览的句子
                        if (_transcriptVisibleIndex >= 0 &&
                            _transcriptVisibleIndex <
                                _controller.sentenceCount &&
                            _transcriptVisibleIndex !=
                                _controller.currentSentenceIndex) {
                          _controller.selectSentence(_transcriptVisibleIndex);
                        }
                      }
                      _pageMode = !_pageMode;
                      // 切换后立即请求定位到当前句（2026-09-22 用户反馈：
                      // 模式切回后字幕定位失效，需手动找）。
                      _revealToken++;
                    }),
                  ),
                    ],
                  ),
                ),
                Expanded(
                  // Follow-up: video mode gets a taller stage; audio keeps a
                  // calm, smaller mark.
                  flex: controller.playbackMode == PlaybackMode.video ? 30 : 22,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      // §三十五: the media slot crossfades when the source
                      // changes — the content changed, not the page.
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: KeyedSubtree(
                          key: ValueKey(controller.playbackMode),
                          child: _renderMediaSlot(context, controller, loading),
                        ),
                      ),
                    ),
                  ),
                ),
                // AUDIO|VIDEO typography switch — only for lessons with a
                // video source (spec V2 §二十).
                if (controller.hasVideoSource)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: _modeToggle(context, controller),
                  ),
                Expanded(
                  flex: 44,
                  child: sentenceChild,
                ),
                if (controller.isInGap && controller.currentGapMs >= 8000)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: ll.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: ll.divider.withValues(alpha: 0.6),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          size: 16,
                          color: ll.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          controller.currentGapMs >= 10000
                              ? '♪ 电影原声配乐播放中'
                              : '· · · 剧情留白',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: ll.textSecondary,
                          ),
                        ),
                        if (controller.currentGapMs >= 5000) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => controller.skipGap(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ll.textPrimary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '跳过配乐',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: ll.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.fast_forward_rounded,
                                    size: 13,
                                    color: ll.textPrimary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                // Follow-up: the whole control stack is compressed —
                // tighter paddings and gaps so the sentence keeps the air.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.hasError) ...[
                        _buildErrorBanner(context, controller.errorMessage!),
                        const SizedBox(height: 6),
                      ],
                      PlaybackControls(
                        isPlaying: controller.isPlaying,
                        canGoPrevious: controller.canGoPrevious,
                        canGoNext: controller.canGoNext,
                        onPlayPause: _onPlayPause,
                        onPrevious: controller.previousSentence,
                        onNext: controller.nextSentence,
                        enabled:
                            controller.isInitialized && !controller.hasError,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _loopBadge(context, controller),
                          Container(
                            height: 10,
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            color: ll.divider,
                          ),
                          _silenceModeBadge(context, controller),
                          Container(
                            height: 10,
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            color: ll.divider,
                          ),
                          _ankiBadge(context, controller),
                        ],
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onLongPress: _showSpeedSheet,
                        child: Row(
                          children: [
                            Expanded(
                              child: SpeedSelector(
                                playbackRate: controller.playbackRate,
                                onChanged: controller.setSpeed,
                                enabled:
                                    controller.isInitialized &&
                                    !controller.hasError,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      SubtitleModeSelector(
                        mode: _subtitleMode,
                        sourceLanguage: widget.language,
                        onChanged: (mode) =>
                            setState(() => _subtitleMode = mode),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The transcript opens with the lesson's identity: title + one quiet
  /// meta line (sentences · duration · source), then a hairline (spec V2
  /// follow-up: 在字幕的开头加上视频标题与信息).
  Widget _transcriptHeader(
    BuildContext context,
    SentencePlayerController controller,
  ) {
    final ll = context.ll;
    final sentences = controller.sentences;
    final durationMs = sentences.isEmpty ? 0 : sentences.last.endMs;
    final meta = [
      '${sentences.length} sentences',
      _mmss(durationMs),
      if (widget.videoSource != null)
        '${widget.videoSource!.provider == VideoSource.providerYoutube ? 'YouTube' : 'Bilibili'} ${widget.videoSource!.bvid}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: LLSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title ?? 'ListenLoop',
            style: LLText.pageTitle.copyWith(color: ll.textPrimary),
          ),
          const SizedBox(height: LLSpacing.xs),
          Text(meta, style: LLText.caption.copyWith(color: ll.textTertiary)),
          const SizedBox(height: LLSpacing.lg),
          Divider(color: ll.divider),
        ],
      ),
    );
  }

  String _mmss(int durationMs) {
    final minutes = durationMs ~/ 60000;
    final seconds = (durationMs % 60000) ~/ 1000;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// The media slot: the embedded WebView while the controller is in video
  /// mode, the lesson cover otherwise (Phase 3C §3). Which one is shown
  /// follows `controller.playbackMode`, not the mere presence of a video
  /// source — a lesson with a video still shows its cover in audio mode.
  Widget _renderMediaSlot(
    BuildContext context,
    SentencePlayerController controller,
    bool loading,
  ) {
    final showLoading = loading || controller.isSwitchingSource;
    final videoFacade = _videoFacade;
    if (controller.playbackMode == PlaybackMode.video &&
        videoFacade is VideoPlaybackFacade) {
      return VideoArea(
        controller: videoFacade.controller,
        loading: showLoading,
      );
    }
    return MediaArea(coverPath: widget.coverPath, loading: showLoading);
  }

  /// AUDIO|VIDEO typography switch (spec V2 §二十): quiet text options,
  /// the active one white with a short underline — no pill buttons.
  Widget _modeToggle(
    BuildContext context,
    SentencePlayerController controller,
  ) {
    final ll = context.ll;
    Widget option(PlaybackMode mode, String label, Key key) {
      final selected = controller.playbackMode == mode;
      return GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) _controller.setPlaybackMode(mode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected ? ll.textPrimary : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 1.5,
              color: selected ? ll.textPrimary : ll.textTertiary,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      key: const Key('mode-toggle'),
      children: [
        option(PlaybackMode.audio, 'AUDIO', const Key('mode-option-audio')),
        const SizedBox(width: 16),
        option(PlaybackMode.video, 'VIDEO', const Key('mode-option-video')),
      ],
    );
  }

  /// Long-press the speed selector for continuous 0.5×–2.0× adjustment
  /// (user request 2026-09-16). The three segmented rates stay for quick use.
  Future<void> _showSpeedSheet() async {
    final s = LLStrings.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.ll.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final ll = sheetContext.ll;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.playbackSpeed,
                    style: LLText.controlLabel.copyWith(color: ll.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_controller.playbackRate.toStringAsFixed(2)}×',
                    style: LLText.pageTitle.copyWith(color: ll.textPrimary),
                  ),
                  Slider(
                    min: 0.5,
                    max: 2.0,
                    divisions: 30,
                    label: '${_controller.playbackRate.toStringAsFixed(2)}×',
                    value: _controller.playbackRate.clamp(0.5, 2.0),
                    onChanged: (value) {
                      setSheetState(() {});
                      _controller.setSpeed(value);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0.5×',
                        style: Theme.of(sheetContext).textTheme.labelSmall,
                      ),
                      Text(
                        '2.0×',
                        style: Theme.of(sheetContext).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _loopBadge(BuildContext context, SentencePlayerController controller) {
    final ll = context.ll;
    // §二十四 (V1): a quiet text label — `LOOP ×1` or just `∞` — never a
    // big badge competing with the sentence.
    final label = controller.repeatTarget == 0
        ? '∞'
        : 'LOOP ×${controller.repeatTarget}';
    return InkWell(
      key: const Key('loop-badge'),
      onTap: () => _showLoopSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
            color: ll.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _silenceModeBadge(
    BuildContext context,
    SentencePlayerController controller,
  ) {
    final ll = context.ll;
    final isSkip = controller.skipSilence;
    final label = isSkip ? '⚡ 跳过空白' : '🎬 原声连贯';
    return InkWell(
      key: const Key('silence-mode-badge'),
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          controller.toggleSkipSilence();
        });
        final newMode = controller.skipSilence;
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newMode
                  ? '已开启：⚡ 紧凑精听（自动跳过中间空白）'
                  : '已开启：🎬 原声连贯（电影原声自然播放，字幕稳定保持）',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: isSkip ? ll.textPrimary : ll.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _ankiBadge(
    BuildContext context,
    SentencePlayerController controller,
  ) {
    final ll = context.ll;
    final lessonId = widget.lessonId ?? 'demo';
    final isAdded = _aiGovernorService.isSentenceInAnki(
      lessonId,
      controller.currentSentenceIndex,
    );

    return InkWell(
      key: const Key('anki-badge'),
      borderRadius: BorderRadius.circular(12),
      onTap: _toggleAnkiCard,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAdded ? Icons.style : Icons.style_outlined,
              size: 12,
              color: isAdded ? Colors.green : ll.textSecondary,
            ),
            const SizedBox(width: 3),
            Text(
              isAdded ? '已入闪卡' : '+ 闪卡',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isAdded ? Colors.green : ll.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Loop-count picker: 每句循环 1 / 3 / 5 / 10 次或无限次 (user request
  /// 2026-09-16; default 1 — a sentence plays through once, then advances).
  Future<void> _showLoopSheet(BuildContext context) async {
    final s = LLStrings.of(context);
    final target = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.ll.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(s.loopsPerSentence),
            ),
            for (final (value, label) in [
              (1, s.loopTimes(1)),
              (3, s.loopTimes(3)),
              (5, s.loopTimes(5)),
              (10, s.loopTimes(10)),
              (0, s.loopForever),
            ])
              ListTile(
                key: Key('loop-option-$value'),
                title: Text(label),
                trailing: value == _controller.repeatTarget
                    ? Icon(Icons.check, color: sheetContext.ll.textPrimary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
    if (target != null) {
      await _controller.setRepeatTarget(target);
    }
  }

  /// Non-blocking error strip (§三十八 spirit): monochrome — a failed video
  /// or audio load never turns the whole screen red. The sentence stays
  /// visible; the controls area shows what went wrong plus a retry action.
  Widget _buildErrorBanner(BuildContext context, String message) {
    final ll = context.ll;
    return Material(
      key: const Key('error-banner'),
      color: ll.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: ll.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: TextStyle(color: ll.textPrimary)),
            ),
            TextButton(
              key: const Key('error-retry-button'),
              onPressed: _retry,
              child: Text(
                LLStrings.of(context).retry,
                style: TextStyle(color: ll.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _retry() {
    // Clear the sticky error first so playback methods are no longer gated
    // (covers load failures, async errors and failed mode switches alike).
    _controller.clearError();
    if (_controller.isInitialized) {
      _controller.playCurrentSentence();
    } else {
      _controller.initialize();
    }
  }
}

/// 左侧上下滑动栏（2026-09-22 优化）。
///
/// 平时隐藏不占视野；在流转文本模式下长按左侧 1 秒呼出，或者在单页模式下长按呼出。
/// 拖动过程中滑块跟随手指比例移动，伴随触感反馈并弹出气泡预览目标句，
/// 松手立即跳转到目标句，并在停留 3 秒后平滑淡出。
class _SentenceScrubber extends StatelessWidget {
  const _SentenceScrubber({
    required this.sentenceCount,
    required this.currentIndex,
    required this.scrubIndex,
    required this.active,
    required this.height,
    required this.previewSentence,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final int sentenceCount;
  final int currentIndex;
  final int scrubIndex;
  final bool active;
  final double height;
  final Sentence? previewSentence;
  final ValueChanged<double>? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    if (sentenceCount <= 1 || height <= 0) return const SizedBox.shrink();

    final topOffset = height * 0.14;
    final trackHeight = height * 0.72;

    double fractionOf(int index) =>
        (index / (sentenceCount - 1).clamp(1, 1 << 31)).clamp(0.0, 1.0);

    return SizedBox(
      width: active ? 280 : 44,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: onDragStart != null
            ? (d) => onDragStart!(d.localPosition.dy)
            : null,
        onVerticalDragUpdate: onDragUpdate != null
            ? (d) => onDragUpdate!(d.localPosition.dy)
            : null,
        onVerticalDragEnd: onDragEnd != null ? (_) => onDragEnd!() : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 细长胶囊轨道：紧贴屏幕最左侧 (left: 4)
            Positioned(
              left: 4,
              top: topOffset,
              child: Container(
                width: 3.5,
                height: trackHeight,
                decoration: BoxDecoration(
                  color: ll.textPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 当前播放句位置标记（短横刻度）
            Positioned(
              left: 0,
              top: topOffset + trackHeight * fractionOf(currentIndex) - 1.5,
              child: Container(
                width: 11,
                height: 3,
                decoration: BoxDecoration(
                  color: ll.textPrimary.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            // 拖动 thumb：贴紧屏幕最左侧的胶囊滑块
            Positioned(
              left: 0,
              top: topOffset +
                  trackHeight * fractionOf(scrubIndex) -
                  (active ? 13 : 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: active ? 18 : 14,
                height: active ? 26 : 20,
                decoration: BoxDecoration(
                  color: ll.textPrimary,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: active ? 0.35 : 0.2),
                      blurRadius: active ? 6 : 3,
                      offset: const Offset(1, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.unfold_more_rounded,
                    size: active ? 13 : 10,
                    color: ll.bg,
                  ),
                ),
              ),
            ),
            // 目标句预览气泡（向右展开）
            if (active && previewSentence != null)
              Positioned(
                left: 26,
                top: (topOffset +
                        trackHeight * fractionOf(scrubIndex) -
                        32)
                    .clamp(12.0, (height - 90.0).clamp(12.0, height)),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: ll.textPrimary.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ll.bg.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${scrubIndex + 1} / $sentenceCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: ll.bg,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          previewSentence!.originalText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ll.bg,
                            height: 1.25,
                          ),
                        ),
                        if (previewSentence!.translatedText.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            previewSentence!.translatedText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: ll.bg.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }
