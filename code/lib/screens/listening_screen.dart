import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../creation/sherpa_onnx_asr_engine.dart';
import '../data/ai_governor_service.dart';
import '../data/demo_sentences_human.dart';
import '../data/primary_chinese_curriculum.dart';
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
import '../training/read_along_recorder.dart';
import '../training/read_along_session.dart';
import '../training/read_along_speaker.dart';
import '../widgets/ai_tutor_sheet.dart';
import '../widgets/anki/anki_review_dialog.dart';
import '../widgets/listening_top_bar.dart';
import '../widgets/ll_audio_control_bar.dart';
import '../widgets/ll_backdrop.dart';
import '../widgets/ll_icons.dart';
import '../widgets/ll_pill_button.dart';
import '../widgets/ll_read_along_sheet.dart';
import '../widgets/playback_controls.dart';
import '../widgets/sentence_display.dart';
import '../widgets/sentence_page_list.dart';
import '../widgets/speed_selector.dart';
import '../widgets/subtitle_mode_selector.dart';
import '../widgets/video_area.dart';
import 'dictation_screen.dart';
import '../data/vocabulary_store.dart';
import '../models/subtitle_token.dart';
import '../models/vocabulary_model.dart';

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
    this.initialPageMode,
    this.videoSource,
    this.onControllerCreated,
    this.aiGovernorService,
    this.vocabularyStore,
    this.readAlongSessionFactory,
    this.readAlongRecorderFactory,
    this.readAlongSpeakerFactory,
    this.onReadAlongChanged,
    this.onRequestReadAlongTab,
  });

  /// 请求切到底栏的独立跟读一级 Tab（告别弹出式 / Overlay）
  final VoidCallback? onRequestReadAlongTab;

  /// 当跟读模式状态变化（开启/退出）时通知宿主 Shell
  final ValueChanged<bool>? onReadAlongChanged;

  /// WP-H 跟读验收的测试 seam。默认 null = 生产构造（record 包 + sherpa
  /// 中文朗读档）；widget 测试注入假会话/假录音器/假播报器，把「读完停 →
  /// 录 → 判 → 过/重播」跑成确定性的，不碰真麦克风和真 TTS。
  final ReadAlongSession? Function()? readAlongSessionFactory;
  final ReadAlongRecorder? Function()? readAlongRecorderFactory;
  final ReadAlongSpeaker? Function()? readAlongSpeakerFactory;

  /// Optional AI Governor service (injected by caller or tests).
  final AiGovernorService? aiGovernorService;

  /// Optional vocabulary store (injected by caller or tests).
  ///
  /// 生词本两层模型（Item / Occurrence）。见 10 号设计文档 §十三。
  final VocabularyStore? vocabularyStore;

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

  /// Restored display mode: true = 上下流动文本呈现 (SentencePageList), false = 单句呈现 (SentenceDisplay).
  final bool? initialPageMode;

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
enum _ActiveInlineSliderType {
  none,
  speed,
  gap,
  loop,
}

/// the one-shot auto-scroll guard must be reset on reveal).
class ListeningScreenState extends State<ListeningScreen>
    with WidgetsBindingObserver {
  late final SentencePlayerController _controller;
  late SubtitleMode _subtitleMode;
  bool _pageMode = false;
  /// 字幕行 key 列表。切课（_switchLesson）与初读/熟读切换
  /// （_toggleSegmentationMode）都要按新句子数重建，故不能是 final——
  /// 曾是 late final，第二次赋值即抛 LateInitializationError。
  List<GlobalKey> _itemKeys = const [];

  _ActiveInlineSliderType _activeSliderType = _ActiveInlineSliderType.none;
  double _sliderCurrentValue = 1.0;
  double _sliderDragStartValue = 1.0;

  /// Bumped to ask SentencePageList to re-align to the current sentence
  /// (tab re-entry via revealCurrentSentence, presentation-mode switch).
  int _revealToken = 0;

  /// Whether the current lesson belongs to the Chinese curriculum / language.
  bool get _isChinese {
    final lang = widget.language?.toLowerCase().trim();
    if (lang != null && (lang.startsWith('zh') || lang == 'chinese')) return true;
    final title = widget.title ?? '';
    if (title.contains('统编') ||
        title.contains('语文') ||
        title.contains('识字') ||
        title.contains('课文') ||
        title.contains('年级')) {
      return true;
    }
    final sentences = widget.sentences ?? _primarySentences;
    if (sentences.isNotEmpty) {
      final text = sentences.first.english;
      if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(text)) return true;
    }
    return false;
  }

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

  /// 生词本：核心是「听」，所以积累模式默认关闭，入口在二级菜单里的三级开关。
  late final VocabularyStore _vocabularyStore =
      widget.vocabularyStore ?? VocabularyStore();

  /// 生词积累模式是否开启（三级开关）。
  bool _accumulationMode = false;

  /// WP-H 跟读验收：模式开关 + 会话/录音器 + 浮层面板 + 句末门状态。
  bool _readAlongOn = false;
  ReadAlongSession? _readAlongSession;
  ReadAlongRecorder? _readAlongRecorder;
  ReadAlongSpeaker? _readAlongSpeaker;
  OverlayEntry? _readAlongOverlay;
  final GlobalKey<LlReadAlongSheetState> _readAlongSheetKey = GlobalKey();

  /// 开启跟读前的用户 gap 原值（退出时还原；跟读期间借 gap>0 把句末
  /// 路由到 `_finishCurrentSentence`，见 `_installReadAlongGate`）。
  int? _gapBeforeReadAlong;

  /// 上次触门的句下标：换句才归零重试计数（同句重播保留计数）。
  int? _readAlongGateIndex;

  /// **P2 非破坏式已知词反哺开关**（默认关，08 号红线）。
  ///
  /// 开启后字幕里「已掌握」的词做视觉弱化（只改颜色），**不隐藏、
  /// 不重排、不减少内容**。关掉时完全不参与渲染（`isTokenKnown` 传 null）。
  bool _knownWordsHighlight = false;

  /// 点词保存 / 再点取消 —— 返回 true 表示当前为「已保存」。
  ///
  /// 判重交给 VocabularyStore：Item 层按归一化词形跨课程合并，
  /// Occurrence 层按 (lesson, sentence, 字符区间) 判重，
  /// 所以同一句里的多个词**不会互相覆盖**（现状 AnkiCard 按句判重会覆盖）。
  bool _toggleVocabulary({
    required String surface,
    required VocabularyKind kind,
    required int charStart,
    required int charEnd,
  }) {
    final sentence = _controller.currentSentence;
    return _vocabularyStore.toggleOccurrence(
      surface: surface,
      kind: kind,
      lessonId: widget.lessonId ?? 'demo',
      lessonTitle: widget.title ?? '精听课程',
      sentenceId: sentence.id,
      sentenceIndex: sentence.index,
      sentenceText: sentence.english,
      startMs: sentence.startMs,
      endMs: sentence.endMs,
      audioPath: widget.audioAsset ?? '',
      charStart: charStart,
      charEnd: charEnd,
    );
  }

  bool _toggleWord(SubtitleToken token) => _toggleVocabulary(
    surface: token.surface,
    kind: VocabularyKind.word,
    charStart: token.charStart,
    charEnd: token.charEnd,
  );

  /// 长按拖动圈出的短语（只圈到一个词时按单词处理）。
  ///
  /// 与点词走**同一条存储路径**：判重键是字符区间，所以「先点了 take、
  /// 后来圈出 take off」会得到两条互不覆盖的证据（kind 分别是 word / phrase）。
  void _onPhraseSelected(SubtitleSelection selection) {
    final saved = _toggleVocabulary(
      surface: selection.text,
      kind: selection.isPhrase ? VocabularyKind.phrase : VocabularyKind.word,
      charStart: selection.charStart,
      charEnd: selection.charEnd,
    );
    setState(() {});
    _showVocabFeedback(
      surface: selection.text,
      kind: selection.isPhrase ? VocabularyKind.phrase : VocabularyKind.word,
      charStart: selection.charStart,
      charEnd: selection.charEnd,
      saved: saved,
    );
  }

  /// 点词 / 圈短语之后的统一反馈。
  ///
  /// **只给轻提示与撤销，不弹释义、不暂停音频** ——「存」与「查」必须分开，
  /// 立刻弹释义会把注意力从声音时间轴拉走（见 10 号文档 §四）。
  ///
  /// 区间由调用方显式传入（不用"最近一次"之类的隐式状态），
  /// 这样撤销回滚的一定是刚存的那一处证据。
  void _showVocabFeedback({
    required String surface,
    required VocabularyKind kind,
    required int charStart,
    required int charEnd,
    required bool saved,
  }) {
    final s = LLStrings.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1500),
        content: Text(
          '${saved ? '✓ ${s.vocabSaved}' : '↩ ${s.vocabRemoved}'}  $surface',
        ),
        action: SnackBarAction(
          label: s.cancel,
          onPressed: () {
            _toggleVocabulary(
              surface: surface,
              kind: kind,
              charStart: charStart,
              charEnd: charEnd,
            );
            setState(() {});
          },
        ),
      ),
    );
  }

  /// 点词后的反馈：**只给轻提示与撤销，不弹释义、不暂停音频**。
  ///
  /// 「存」与「查」必须分开：立刻弹释义会把注意力从声音时间轴拉走，
  /// 等于把主任务从「听」切成「读」（见 10 号文档 §四）。
  void _onTokenTap(SubtitleToken token) {
    final saved = _toggleWord(token);
    setState(() {});
    _showVocabFeedback(
      surface: token.surface,
      kind: VocabularyKind.word,
      charStart: token.charStart,
      charEnd: token.charEnd,
      saved: saved,
    );
  }

  /// 二级菜单（精听页 ⋯）—— 三级开关都收在这里。
  Future<void> _openMoreMenu() async {
    final s = LLStrings.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.ll.bg,
      builder: (sheetContext) {
        final ll = sheetContext.ll;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.more,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ll.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('accumulation-toggle'),
                  contentPadding: EdgeInsets.zero,
                  value: _accumulationMode,
                  activeThumbColor: ll.textPrimary,
                  onChanged: (value) {
                    Navigator.of(sheetContext).pop();
                    setState(() => _accumulationMode = value);
                  },
                  title: Text(
                    s.vocabAccumulation,
                    style: TextStyle(fontSize: 14, color: ll.textPrimary),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.vocabAccumulationHint,
                        style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
                      ),
                      const SizedBox(height: 2),
                      // 长按拖动是隐藏手势 —— 不写出来没人会试
                      Text(
                        s.vocabPhraseHint,
                        style: TextStyle(fontSize: 11, color: ll.textTertiary),
                      ),
                    ],
                  ),
                ),
                Divider(color: ll.divider, height: 24),
                // P2 非破坏式已知词反哺（08 号红线）：只弱化视觉，不删内容。
                SwitchListTile(
                  key: const Key('known-words-toggle'),
                  contentPadding: EdgeInsets.zero,
                  value: _knownWordsHighlight,
                  activeThumbColor: ll.textPrimary,
                  onChanged: (value) {
                    Navigator.of(sheetContext).pop();
                    setState(() => _knownWordsHighlight = value);
                  },
                  title: Text(
                    s.vocabKnownWordsHighlight,
                    style: TextStyle(fontSize: 14, color: ll.textPrimary),
                  ),
                  subtitle: Text(
                    s.vocabKnownWordsHighlightHint,
                    style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
                  ),
                ),
                Divider(color: ll.divider, height: 24),
                Text(
                  s.vocabCandidateCount(_vocabularyStore.itemCount),
                  style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 核心层 P1：打开听写训练（句级录入 / 段级集中批改）。
  ///
  /// 复用同一个播放控制器 —— 用户听到的必须是原片句轴音频，
  /// 不允许用合成音替代（见 08 定调的交互红线）。
  void _openDictation() async {
    _controller.pause();
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => DictationScreen(
          controller: _controller,
          // 听写完成流入口：把 AI governor 传下去，批改出的错句可一键
          // 接进「意思回忆」的在线 AI 反馈（未注入时走静态自比兜底）。
          governor: _aiGovernorService,
        ),
      ),
    );
    // ListenRetryTarget 回传：听写页「回原声重听」带句子下标返回，
    // 精听页定位到该句并播放（v0.9.1，17 号路线图双出口之一）。
    if (result != null && result >= 0 && mounted) {
      await _controller.selectSentence(result);
      if (mounted) unawaited(_controller.playCurrentSentence());
    }
  }

  // ------------------------------------------------------ 跟读验收（WP-H）

  /// 判分的期望文本：中文课取 `Sentence.chinese`（方案 §九.4 雷区——中文课
  /// 的正文在 chinese 字段，不是 english）。
  String _readAlongExpectedText(Sentence sentence) =>
      _isChinese ? sentence.chinese : sentence.english;

  bool get isReadAlongOn => _readAlongOn;

  void enterReadAlong() {
    if (!_readAlongOn) {
      _enterReadAlong();
    }
  }

  void exitReadAlong() {
    if (_readAlongOn) {
      unawaited(_exitReadAlong());
    }
  }

  /// 跟读入口（WP-H）。2026-10-20 郭老师：顶栏那枚「跟读验收」图标已撤
  /// ——跟读验收已升为底部一级页（读 tab），顶栏再摆一枚是重复入口。
  /// 切换动作改由 [onRequestReadAlongTab] 回调交给一级页处理；没有回调
  /// 时（单测/独立使用）退回到本屏自己开合跟读。
  void toggleReadAlong() {
    if (widget.onRequestReadAlongTab != null) {
      widget.onRequestReadAlongTab!();
      return;
    }
    if (_readAlongOn) {
      unawaited(_exitReadAlong());
    } else {
      _enterReadAlong();
    }
  }

  void _enterReadAlong() {
    final session = widget.readAlongSessionFactory?.call() ??
        ReadAlongSession(
          // 真机中文朗读档由引擎按语言 hint 自行解析（未装模型则回退设置档，
          // 引擎内部处理，不在这里猜文件系统）。测试走注入的假会话。
          engine: SherpaOnnxAsrEngine(
            modelDirResolver: defaultAsrModelDir,
            threads: () => PreferencesScope.maybeOf(context).asrThreads,
          ),
        );
    final recorder =
        widget.readAlongRecorderFactory?.call() ?? ReadAlongRecorder();
    final speaker =
        widget.readAlongSpeakerFactory?.call() ?? ReadAlongSpeaker();
    _readAlongSession = session;
    _readAlongRecorder = recorder;
    _readAlongSpeaker = speaker;
    _readAlongGateIndex = null;
    // 熟读档「不拦」（2026-10-15 用户拍板）：进跟读时按当前分段模式定档——
    // 初读（呼吸节拍）要过关，熟读（长意群）照给分但不卡进度。
    session.setLenient(_isAlternateMode);
    setState(() => _readAlongOn = true);
    widget.onReadAlongChanged?.call(true);
    _installReadAlongGate();
    _showReadAlongPanel();
    if (!_controller.isPlaying) {
      unawaited(_controller.playCurrentSentence());
    }
  }

  /// 句末路由契约（实测补全，方案 §五未覆盖）：默认「原声连贯」模式下句中
  /// 切换走自然推进分支，不经过 `_finishCurrentSentence`——句末要触发
  /// readAlongGate 需要 `sentenceGapMs > 0`（位置流分支）。跟读期间把 gap
  /// 设为 100ms（门在 gap 逻辑之前收口，无任何可闻效果），退出时还原。
  Future<void> _installReadAlongGate() async {
    if (!mounted) return;
    _gapBeforeReadAlong ??= _controller.sentenceGapMs;
    _controller.readAlongGate = _onReadAlongGate;
    if (_gapBeforeReadAlong == 0) {
      await _controller.setSentenceGap(100);
    }
  }

  Future<void> _exitReadAlong() async {
    // UI 层先拆：门、gap、面板、开关——这些只依赖本地状态，必须立即生
    // 效。绝不允许因为录音器销毁（平台通道无响应、插件缺失）把面板和
    // 句末门钉在屏幕上——那会变成解不开跟读的死锁。
    _controller.readAlongGate = null;
    _readAlongGateIndex = null;
    final gap = _gapBeforeReadAlong;
    _gapBeforeReadAlong = null;
    if (gap != null && _controller.sentenceGapMs != gap) {
      await _controller.setSentenceGap(gap);
    }
    _readAlongOverlay?.remove();
    _readAlongOverlay = null;
    if (mounted) setState(() => _readAlongOn = false);
    widget.onReadAlongChanged?.call(false);

    // 硬件层后拆：录音器/会话的销毁抛错或挂住只记录，不阻断 UI。
    final recorder = _readAlongRecorder;
    final session = _readAlongSession;
    final speaker = _readAlongSpeaker;
    _readAlongRecorder = null;
    _readAlongSession = null;
    _readAlongSpeaker = null;
    unawaited(_teardownReadAlongHardware(recorder, session));
    // 播报器无硬件资源：退出即停播报，不等待。
    unawaited(speaker?.stop());
  }

  Future<void> _teardownReadAlongHardware(
    ReadAlongRecorder? recorder,
    ReadAlongSession? session,
  ) async {
    try {
      await recorder?.abort();
      await recorder?.dispose();
    } catch (error, stackTrace) {
      debugPrint(
        '[ListenLoop][read-along] recorder teardown failed: $error\n$stackTrace',
      );
    }
    session?.dispose();
  }

  /// 句末门回调：读完一句停住 → 开一次跟读收音。
  ///
  /// 换句才归零重试计数——同句原声重播也会再次触门，计数必须留下，
  /// 否则 3 次软上限永远不触发（方案 §三）。
  Future<void> _onReadAlongGate(int index) async {
    if (!_readAlongOn || !mounted) return;
    final session = _readAlongSession;
    final recorder = _readAlongRecorder;
    if (session == null || recorder == null) return;
    if (_readAlongGateIndex != index) {
      session.startSentence();
      _readAlongGateIndex = index;
    }
    // 录音兜底上限：该句音频时长 × 3 + 2000ms（方案 §三）。
    final maxMs = _controller.currentSentence.durationMs * 3 + 2000;
    final state = _readAlongSheetKey.currentState;
    if (state != null) {
      await state.startAttempt(maxDurationMs: maxMs);
    } else {
      _showReadAlongPanel(autoStart: true, maxDurationMs: maxMs);
    }
  }

  void _showReadAlongPanel({bool autoStart = false, int maxDurationMs = 0}) {
    final session = _readAlongSession;
    final recorder = _readAlongRecorder;
    if (session == null || recorder == null) return;
    if (_readAlongOverlay != null) {
      if (autoStart) {
        _readAlongSheetKey.currentState
            ?.startAttempt(maxDurationMs: maxDurationMs);
      }
      return;
    }
    final overlay = Overlay.of(context);
    _readAlongOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        top: 0,
        bottom: 0,
        child: LlReadAlongSheet(
          key: _readAlongSheetKey,
          session: session,
          recorder: recorder,
          controller: _controller,
          expectedTextOf: _readAlongExpectedText,
          speaker: _readAlongSpeaker,
          autoStartAttempt: autoStart,
          attemptMaxDurationMs: maxDurationMs,
          onExit: () => unawaited(_exitReadAlong()),
        ),
      ),
    );
    overlay.insert(_readAlongOverlay!);
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
  AudioPlayerFacade? _videoFacade;
  List<Sentence> _primarySentences = const [];
  List<Sentence>? _alternateSentences;
  bool _isAlternateMode = false;

  late String _currentLessonId = widget.lessonId ?? 'demo';
  late String _currentTitle = widget.title ?? '精听课程';

  /// 二年级上册（或当前课包）的单元层级树（支持 8 个单元下滑栏 + 语文园地下滑栏）
  List<PrimaryChineseLesson> _curriculumUnits = const [];

  /// 当前播放列表对应的年级与册，用于切课后判断是否需要重载列表。
  int _playlistGrade = 2;
  String _playlistTerm = '上册';

  /// 播放列表所属年级的中文标签（如「三年级」），供目录抽屉标题等处使用。
  String get _playlistGradeLabel {
    const labels = {
      1: '一年级',
      2: '二年级',
      3: '三年级',
      4: '四年级',
      5: '五年级',
      6: '六年级',
      7: '七年级',
      8: '八年级',
      9: '九年级',
    };
    return labels[_playlistGrade] ?? '$_playlistGrade年级';
  }

  void _loadPlaylistLessons() {
    if (widget.repository == null) return;

    // 2026-10-14 修复：原写死 l.grade == 2 && l.term == '上册'，导致只有
    // 二年级上册能切课，三年级/四年级的「上一课/下一课」静默失效。
    // 改为按当前 lessonId 反查年级册，全年级通用。
    final located = PrimaryChineseCurriculum.locateGradeTerm(_currentLessonId);
    final grade = located?.grade ?? 2;
    final term = located?.term ?? '上册';

    final tree = <PrimaryChineseLesson>[];
    for (final l in PrimaryChineseCurriculum.allLessons) {
      if (l.grade == grade && l.term == term) {
        tree.add(l);
      }
    }
    if (tree.isNotEmpty) {
      setState(() {
        _curriculumUnits = tree;
        _playlistGrade = grade;
        _playlistTerm = term;
      });
    } else {
      widget.repository!.listLessons().then((all) {
        if (!mounted) return;
        final flat = all.map((item) {
          return PrimaryChineseLesson(
            grade: grade,
            term: term,
            unit: item.lesson.series ?? '全部课程',
            title: item.lesson.title,
            lessonId: item.lesson.id,
            isDualMode: true,
          );
        }).toList();
        setState(() {
          _curriculumUnits = flat;
          _playlistGrade = grade;
          _playlistTerm = term;
        });
      }).catchError((_) {});
    }
  }

  /// 展开二年级上册全部课件为线性播放列表（按教材顺序依次展开单课与语文园地子栏目）
  List<PrimaryChineseLesson> get _orderedLessons {
    final list = <PrimaryChineseLesson>[];
    for (final u in _curriculumUnits) {
      // 课文自身有课包即入列；语文园地等容器自身无课包，则展开其下有课包的子栏目
      if (u.lessonId != null) list.add(u);
      for (final sub in u.subLessons) {
        if (sub.lessonId != null) list.add(sub);
      }
    }
    return list;
  }

  bool get _hasNextLesson {
    final list = _orderedLessons;
    final idx = list.indexWhere((l) => l.lessonId == _currentLessonId);
    return idx != -1 && idx < list.length - 1;
  }

  bool get _hasPreviousLesson {
    final list = _orderedLessons;
    final idx = list.indexWhere((l) => l.lessonId == _currentLessonId);
    return idx > 0;
  }

  void _switchToNextLesson() {
    final list = _orderedLessons;
    final idx = list.indexWhere((l) => l.lessonId == _currentLessonId);
    if (idx != -1 && idx < list.length - 1) {
      final next = list[idx + 1];
      _switchLesson(
        lessonId: next.lessonId!,
        title: next.numberedTitle(),
      );
    }
  }

  void _switchToPreviousLesson() {
    final list = _orderedLessons;
    final idx = list.indexWhere((l) => l.lessonId == _currentLessonId);
    if (idx > 0) {
      final prev = list[idx - 1];
      _switchLesson(
        lessonId: prev.lessonId!,
        title: prev.numberedTitle(),
      );
    }
  }

  Future<void> _switchLesson({
    required String lessonId,
    required String title,
  }) async {
    if (widget.repository == null) return;
    if (_currentLessonId == lessonId) return;

    // 1. 存档当前课进度
    _saveProgressIfPossible();

    // 2. 暂停当前音频
    await _controller.pause();

    // 3. 异步拉取目标课程数据
    final data = await widget.repository!.getLessonWithSentences(lessonId);
    if (!mounted || data == null || data.sentences.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('课件 $title 数据未就绪'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final newSentences = data.sentences;
    final newAudioPath = data.lesson.audioPath;
    final alt = await widget.repository!.getAlternateSentences(lessonId);

    if (!mounted) return;

    setState(() {
      _currentLessonId = lessonId;
      _currentTitle = title;
      _primarySentences = newSentences;
      _alternateSentences = alt;
      _isAlternateMode = false;
      _itemKeys = List.generate(newSentences.length, (_) => GlobalKey());
      _lastSentenceIndex = 0;
      _revealToken++;
    });

    // 换课即回初读档：新课的句子是初读行，跟读验收要恢复过关口径，
    // 别把上一课熟读档的「不拦」带过来（跟读没开时是空操作）。
    _readAlongSession?.setLenient(false);

    // 4. 原地平滑重载音轨与字幕
    await _controller.replaceAudioSource(
      audioAsset: newAudioPath,
      isFile: true,
      sentences: newSentences,
      initialIndex: 0,
      autoPlay: true,
    );

    // 5. 若目标课所属年级册与当前播放列表不同（跨册切入），重载播放列表，
    //    否则「下一课」仍按旧册的教材顺序推进。
    final newLocated =
        PrimaryChineseCurriculum.locateGradeTerm(_currentLessonId);
    if (newLocated != null &&
        (newLocated.grade != _playlistGrade || newLocated.term != _playlistTerm)) {
      _loadPlaylistLessons();
    }
  }

  void _openPlaylistSheet() {
    final ll = context.ll;
    // 按单元将课文树进行分组
    final unitMap = <String, List<PrimaryChineseLesson>>{};
    for (final item in _curriculumUnits) {
      unitMap.putIfAbsent(item.unit, () => []).add(item);
    }

    // 2026-10-20 郭老师（自动定位）：每个单元一枚 key + 当前单元序号。
    // 打开目录时：当前单元自动展开，列表自动滚到它眼前，标题栏直接写明
    // 「当前：第 N 单元」。语文园地二级栏**不自动展开**。
    final unitKeys = List.generate(unitMap.length, (_) => GlobalKey());
    final unitNames = unitMap.keys.toList(growable: false);
    var currentUnitIndex = -1;
    for (var i = 0; i < unitNames.length; i++) {
      final items = unitMap[unitNames[i]] ?? [];
      final hit = items.any((it) {
        if (it.lessonId == _currentLessonId) return true;
        return it.subLessons.any((sub) => sub.lessonId == _currentLessonId);
      });
      if (hit) {
        currentUnitIndex = i;
        break;
      }
    }
    // 粗定位：每个收起单元的头条约 58dp。先按估算滚过去，目标单元多半
    // 已经在构建范围内，随后的 ensureVisible 再精确落位。
    final initialOffset = currentUnitIndex <= 0
        ? 0.0
        : (currentUnitIndex * 58.0).toDouble();
    final sheetScroll = ScrollController(initialScrollOffset: initialOffset);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ll.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部标题与关闭按钮
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.format_list_bulleted_rounded,
                        size: 19,
                        color: ll.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$_playlistGradeLabel$_playlistTerm 课文目录',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: ll.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ll.surfaceHigh,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${unitMap.length} 个单元',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: ll.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: ll.textSecondary, size: 20),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                // 2026-10-20 郭老师（自动定位）：标题栏直接写明"现在在听第几
                // 单元"，不必自己数。
                if (currentUnitIndex >= 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          size: 14,
                          color: ll.accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '当前：第 ${currentUnitIndex + 1} 单元 · '
                            '${unitNames[currentUnitIndex]}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: ll.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Divider(color: ll.divider, height: 1),

                // 8 个单元的下滑栏（一级 ExpansionTile）。
                //
                // 2026-10-20 郭老师（自动定位）：当前正在听的单元**自动展开**，
                // 打开目录就直接滚到它眼前；「语文园地」二级栏保持收起
                // （它下面挂着 4~5 个子栏目，展开会把整屏撑成目录墙）。
                Expanded(
                  child: ListView.builder(
                    controller: sheetScroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: unitMap.length,
                    itemBuilder: (_, uIdx) {
                      final unitName = unitMap.keys.elementAt(uIdx);
                      final unitItems = unitMap[unitName] ?? [];

                      // 检查当前播放课文是否属于该单元
                      final unitHasCurrent = unitItems.any((it) {
                        if (it.lessonId == _currentLessonId) return true;
                        return it.subLessons.any((sub) => sub.lessonId == _currentLessonId);
                      });

                      return Container(
                        key: unitKeys[uIdx],
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        decoration: BoxDecoration(
                          color: ll.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: unitHasCurrent
                                ? ll.accent.withValues(alpha: 0.35)
                                : ll.divider.withValues(alpha: 0.5),
                            width: unitHasCurrent ? 1.0 : 0.6,
                          ),
                        ),
                        child: Theme(
                          data: Theme.of(sheetContext).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: ExpansionTile(
                            // 2026-10-20 郭老师（自动定位）：当前正在听的
                            // 单元**自动展开**，其余单元仍收起。
                            // 「语文园地」那一层（二级 ExpansionTile）保持
                            // 收起——它下面 4~5 个子栏目全展开就没有课文了。
                            initiallyExpanded: unitHasCurrent,
                            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            childrenPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: unitHasCurrent
                                    ? ll.accent.withValues(alpha: 0.16)
                                    : ll.surfaceHigh,
                              ),
                              child: Text(
                                '${uIdx + 1}',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: unitHasCurrent ? ll.accent : ll.textTertiary,
                                ),
                              ),
                            ),
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    unitName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: unitHasCurrent
                                          ? ll.accent
                                          : ll.textPrimary,
                                    ),
                                  ),
                                ),
                                if (unitHasCurrent) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ll.accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '当前',
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: ll.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            children: [
                              Divider(color: ll.divider.withValues(alpha: 0.4), height: 1),
                              ...unitItems.map((item) {
                                // 如果是语文园地（自身无课包、含 subLessons），展示为二级下滑栏
                                if (item.isContainerOnly) {
                                  final yuandiHasCurrent = item.subLessons.any(
                                    (s) => s.lessonId == _currentLessonId,
                                  );
                                  return Container(
                                    margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                                    decoration: BoxDecoration(
                                      color: ll.surfaceHigh.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: yuandiHasCurrent
                                            ? ll.accent.withValues(alpha: 0.3)
                                            : ll.divider.withValues(alpha: 0.4),
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: ExpansionTile(
                                      // 语文园地二级下滑栏，默认收起
                                      initiallyExpanded: false,
                                      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                      childrenPadding: const EdgeInsets.only(bottom: 6),
                                      leading: Icon(
                                        Icons.collections_bookmark_rounded,
                                        size: 18,
                                        color: yuandiHasCurrent ? ll.accent : ll.textSecondary,
                                      ),
                                      title: Text(
                                        item.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: yuandiHasCurrent ? ll.accent : ll.textPrimary,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '共 ${item.subLessons.length} 栏目',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: ll.textTertiary,
                                        ),
                                      ),
                                      children: item.subLessons.map((sub) {
                                        final isCurrentSub = sub.lessonId == _currentLessonId;
                                        return ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.only(left: 36, right: 14),
                                          leading: Icon(
                                            isCurrentSub
                                                ? Icons.graphic_eq_rounded
                                                : Icons.radio_button_unchecked,
                                            size: 15,
                                            color: isCurrentSub ? ll.accent : ll.textTertiary,
                                          ),
                                          title: Text(
                                            sub.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isCurrentSub ? FontWeight.w700 : FontWeight.w500,
                                              color: isCurrentSub ? ll.accent : ll.textPrimary,
                                            ),
                                          ),
                                          trailing: isCurrentSub
                                              ? Text(
                                                  '当前播放',
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: ll.accent,
                                                  ),
                                                )
                                              : null,
                                          onTap: () {
                                            Navigator.of(sheetContext).pop();
                                            if (!isCurrentSub && sub.lessonId != null) {
                                              _switchLesson(
                                                lessonId: sub.lessonId!,
                                                title: sub.numberedTitle(),
                                              );
                                            }
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                );
                              }

                              // 普通课文
                              final isCurrent = item.lessonId == _currentLessonId;
                              return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
                                  leading: Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isCurrent
                                          ? ll.accent.withValues(alpha: 0.16)
                                          : ll.surfaceHigh,
                                    ),
                                    child: isCurrent
                                        ? Icon(
                                            Icons.graphic_eq_rounded,
                                            size: 14,
                                            color: ll.accent,
                                          )
                                        : Icon(
                                            Icons.article_outlined,
                                            size: 13,
                                            color: ll.textTertiary,
                                          ),
                                  ),
                                  title: Text(
                                    item.numberedTitle(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                      color: isCurrent ? ll.accent : ll.textPrimary,
                                    ),
                                  ),
                                  trailing: isCurrent
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: ll.accent.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '当前播放',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: ll.accent,
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    if (!isCurrent && item.lessonId != null) {
                                      _switchLesson(
                                        lessonId: item.lessonId!,
                                        title: item.numberedTitle(),
                                      );
                                    }
                                  },
                                );
                              }),
                            ],
                          ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      sheetScroll.dispose();
    });

    // 2026-10-20 郭老师（自动定位）：弹层入场后把当前单元精确滚到视口
    // 上部——前面的 initialScrollOffset 只是粗定位，这一手才是落位。
    if (currentUnitIndex >= 0) {
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (!context.mounted) return;
        final target = unitKeys[currentUnitIndex].currentContext;
        if (target == null) return;
        Scrollable.ensureVisible(
          target,
          alignment: 0.12,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  void _toggleSegmentationMode() {
    if (_alternateSentences == null) return;
    final toAlternate = !_isAlternateMode;
    final targetList = toAlternate ? _alternateSentences! : _primarySentences;
    _controller.switchSentenceList(targetList);
    // 熟读档「不拦」：切到熟读就放开进度，切回初读立刻恢复过关口径。
    // 跟读没开时只是空操作（session 为 null）。
    _readAlongSession?.setLenient(toAlternate);
    setState(() {
      _isAlternateMode = toAlternate;
      _itemKeys = List.generate(_controller.sentenceCount, (_) => GlobalKey());
    });
  }

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
    final initialSentences = widget.sentences ?? demoSentencesHuman;
    _primarySentences = initialSentences;
    _controller = SentencePlayerController(
      audioFacade: widget.audioFacade ?? JustAudioFacade(),
      videoFacade: _videoFacade,
      sentences: initialSentences,
      audioAsset: widget.audioAsset ?? demoAudioAssetHuman,
      audioIsFile: widget.audioIsFile,
      initialSentenceIndex: widget.initialSentenceIndex,
      initialPlaybackRate: widget.initialPlaybackRate,
      initialRepeatTarget: widget.initialRepeatTarget,
    );
    _controller.onNextLessonRequested = _switchToNextLesson;
    _controller.onPreviousLessonRequested = _switchToPreviousLesson;
    _subtitleMode = SubtitleMode.values.firstWhere(
      (m) => m.name == widget.initialSubtitleMode,
      orElse: () => SubtitleMode.bilingual,
    );
    // 2026-10-10 用户需求：无论是从课程库还是从思维导图点进精听页面，
    // 在中文模式下，字幕的呈现形式默认是上下流动的文本呈现 (SentencePageList, _pageMode = true)；
    // 而英文则默认是单句呈现 (SentenceDisplay, _pageMode = false)。
    _pageMode = _isChinese ? true : (widget.initialPageMode ?? false);
    _itemKeys = List.generate(_controller.sentenceCount, (_) => GlobalKey());
    _lastSentenceIndex = widget.initialSentenceIndex;
    // 自动点词的存档跨启动存活：只有自建（无人注入共享实例）时才需要装载，
    // 共享实例由上层（RootShell）负责装载，避免重复读盘。
    if (widget.vocabularyStore == null) {
      unawaited(_vocabularyStore.load());
    }
    if (widget.lessonId != null && widget.repository != null) {
      widget.repository!.getAlternateSentences(widget.lessonId!).then((alt) {
        if (mounted && alt != null && alt.isNotEmpty) {
          setState(() {
            _alternateSentences = alt;
          });
        }
      });
    }
    _loadPlaylistLessons();
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
    // 整课循环是持久偏好（2026-10-17 郭老师：课文播完别自动切下一课）。
    // 只在首次依赖变化时套用一次——之后用户在本页的开关由他自己掌握，
    // 不能被偏好回写覆盖。
    if (!_lessonLoopSynced) {
      _lessonLoopSynced = true;
      _controller.setLessonLoop(prefs.lessonLoop);
    }
  }

  /// 整课循环偏好是否已套用到当前控制器（见 [didChangeDependencies]）。
  bool _lessonLoopSynced = false;

  /// V2 §三十一: the listening session lives inside the navigation shell and
  /// may never be disposed for the whole app session, so progress is also
  /// checkpointed when the app leaves the foreground — same save routine as
  /// dispose, zero algorithm change.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _saveProgressIfPossible();
  }

  int _lastSentenceIndex = 0;

  /// 上一次已知的播放模式 —— 用于在听读 ⇄ 视听 切换时更新屏幕方向。
  PlaybackMode? _lastPlaybackMode;

  /// 屏幕方向策略（2026-10-15 郭老师）：常态竖屏，只有视听看视频才放开。
  ///
  /// 竖屏是这一页的阅读节奏；横屏 382dp 高时顶栏 + 听读/视听 + 控制条
  /// 就把可用高度吃满，句子区被压没、控制条下缘溢出（当天实测）。
  /// 视听模式要全屏看视频，所以那时放开旋转；切回听读立刻收回。
  void _syncOrientation() {
    final mode = _controller.playbackMode;
    if (mode == _lastPlaybackMode) return;
    _lastPlaybackMode = mode;
    SystemChrome.setPreferredOrientations(
      mode == PlaybackMode.video
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
              DeviceOrientation.portraitUp,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  void _onControllerChanged() {
    if (mounted) {
      final curIdx = _controller.currentSentenceIndex;
      if (curIdx != _lastSentenceIndex) {
        _lastSentenceIndex = curIdx;
      }
      _syncOrientation();
      setState(() {});
    }
  }

  @override
  void dispose() {
    // WP-H：跟读会话与页面同生命周期。异步清理 fire-and-forget——进程要没了
    // 时麦克风由系统回收，同步 await 在 dispose 里也等不到。
    _controller.readAlongGate = null;
    _readAlongOverlay?.remove();
    _readAlongOverlay = null;
    if (_readAlongRecorder != null) {
      unawaited(_readAlongRecorder!.dispose());
      _readAlongRecorder = null;
    }
    _readAlongSession?.dispose();
    _readAlongSession = null;
    if (widget.vocabularyStore == null) _vocabularyStore.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _leftLongPressTimer?.cancel();
    _scrubberHideTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    // 视听模式放开过旋转，别把它带出这一页 —— 离开精听页收回竖屏。
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
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

  /// 附属层「回原声」入口：跳到指定句（生词本证据里的句子）。
  ///
  /// 播的必须是**原片句轴音频**（08 定调红线：不得用合成音替代）。
  /// 越界或尚未初始化时静默忽略 —— 附属功能失败不得阻塞核心。
  void jumpToSentence(int index, {bool autoplay = true}) {
    if (!mounted || !_controller.isInitialized) return;
    if (index < 0 || index >= _controller.sentenceCount) return;
    unawaited(_controller.selectSentence(index));
    if (autoplay) unawaited(_controller.playCurrentSentence());
    setState(() => _revealToken++);
  }

  /// Persists where the user left off (spec V0.2 §20) before teardown.
  /// Fire-and-forget: a failed save must never block closing the screen.
  void _saveProgressIfPossible() {
    final lessonId = _currentLessonId;
    final repository = widget.repository;
    if (repository == null) return;
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
      chineseMain: LLLearning.chineseMainSentence(ll, prefs),
    );
    final loading = !controller.isInitialized && !controller.hasError;

    // 矮视口（横屏 / 分屏）：见 LLAudioControlBar.compact 的说明。
    // 用屏幕高度而不是 Orientation —— 平板横过来高度依然充裕，
    // 那种情况不该走紧凑布局。
    final shortViewport = MediaQuery.sizeOf(context).height < 420;

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
                    padding: const EdgeInsets.symmetric(
                      horizontal: LLSpacing.xl,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: _onScrubStart,
                      onLongPressMoveUpdate: _onScrubUpdate,
                      onLongPressEnd: _onScrubEnd,
                      child: SentencePageList(
                        sentences: controller.sentences,
                        currentIndex: controller.currentSentenceIndex,
                        currentPosition: controller.currentPosition,
                        showEnglish: _subtitleMode.showsEnglish,
                        showChinese: _isChinese ? false : _subtitleMode.showsChinese,
                        isChineseMode: _isChinese,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: LLSpacing.xl,
                    ),
                    child: GestureDetector(
                      key: const Key('subtitle-tap'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _controller.replaySentence(),
                      child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          key: ValueKey(controller.currentSentenceIndex),
                          child: SentenceDisplay(
                            sentence: controller.currentSentence,
                            currentPosition: controller.currentPosition,
                            showEnglish: _subtitleMode.showsEnglish,
                            showChinese: _isChinese ? false : _subtitleMode.showsChinese,
                            isChineseMode: _isChinese,
                            styles: learning,
                              // 只在一级精听页、且用户主动开启积累模式后
                              // 字幕才变成可点 —— 平时不允许把词变成按钮。
                              accumulationMode: _accumulationMode,
                              onTokenTap: _onTokenTap,
                              onPhraseSelected: _onPhraseSelected,
                              isTokenSaved: (start, end) =>
                                  _vocabularyStore.isSaved(
                                    lessonId: widget.lessonId ?? 'demo',
                                    sentenceId: controller.currentSentence.id,
                                    charStart: start,
                                    charEnd: end,
                                  ),
                              // P2 非破坏式已知词反哺：已掌握词做视觉弱化，
                              // 只改颜色、不隐藏不重排不删内容（08 号红线）。
                              isTokenKnown: _knownWordsHighlight
                                  ? _vocabularyStore.isKnownSurface
                                  : null,
                              knownColor: _knownWordsHighlight
                                  ? context.ll.textTertiary.withValues(
                                      alpha: 0.75,
                                    )
                                  : null,
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
        body: LLBackdrop(child: SafeArea(
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
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isChinese)
                        IconButton(
                          key: const Key('ai-tutor-button'),
                          tooltip: 'AI 伴学 / 快测 / Anki',
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 18,
                          ),
                          color: ll.textSecondary,
                          // WP-G 终审：去掉 compact —— 它把热区压到 40×32dp。
                          // 顶栏已抬到 48 高，这里放手让 IconButton 用满
                          // 48×48 的默认热区。
                          onPressed: _openAiTutor,
                        ),
                      if (_alternateSentences != null) ...[
                        const SizedBox(width: 4),
                        // 2026-10-20 郭老师：初读/熟读**图标化**——去掉"读"字，
                        // 只留「初」「熟」两枚圆钮。原因：顶栏中栏是"02 / 69"
                        // 句数，左右两槽必须配重，「初读|熟读」四个字的药丸
                        // 太宽（124dp），把中栏挤到换行。两个字 = 2×28dp。
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SegmentationDot(
                              key: const Key('segmentation-mode-chudu'),
                              glyph: '初',
                              active: !_isAlternateMode,
                              onTap: _isAlternateMode ? _toggleSegmentationMode : null,
                            ),
                            const SizedBox(width: 4),
                            _SegmentationDot(
                              key: const Key('segmentation-mode-shudu'),
                              glyph: '熟',
                              active: _isAlternateMode,
                              onTap: !_isAlternateMode ? _toggleSegmentationMode : null,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  // 右侧现有三个图标（听写 + more + 显示模式），左右槽位成对
                  // 加宽且图标紧凑化（3×48 正好顶满 144 —— 不紧凑化则字体
                  // 缩放下挤压中栏计数器，曾致「总句数」换行被裁）。
                  // 左右槽宽独立计算：中文课时右槽 3 枚（跟读验收/课文目录/
                  // 显示模式）、左槽 1 枚分段器；英文课时右槽 4 枚（听写/more/
                  // 课文目录/显示模式）、左槽 1 枚 AI 伴学。原先两侧共用
                  // slotWidth 且取较大值，会把一侧顶出屏幕（溢出 48/56px）。
                  leadingSlotWidth: _isChinese ? 132 : 48,
                  trailingSlotWidth: _isChinese ? 144 : 192,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isChinese && controller.hasVideoSource)
                        // 2026-10-20 郭老师：「试听」不再是一行「听读|视听」
                        // 的文字切换，改成顶栏一枚**视频播放标志**：点一下就
                        // 进视频（视听页保留），视频态下同一枚钮变成「退出
                        // 视频」回到听读。没有原片的课不摆这枚钮——绝不摆
                        // 点了没反应的死按钮。
                        IconButton(
                          key: const Key('video-button'),
                          tooltip: controller.playbackMode == PlaybackMode.video
                              ? '退出视频'
                              : '看视频',
                          icon: Icon(
                            controller.playbackMode == PlaybackMode.video
                                ? Icons.close_fullscreen_rounded
                                : Icons.play_circle_outline_rounded,
                            size: 22,
                          ),
                          color: ll.textSecondary,
                          onPressed: () {
                            _controller.setPlaybackMode(
                              controller.playbackMode == PlaybackMode.video
                                  ? PlaybackMode.audio
                                  : PlaybackMode.video,
                            );
                          },
                        ),
                      if (!_isChinese) ...[
                        // 核心层 P1：听写入口。刻意放在一级页顶栏 —— 听写属于
                        // 「听」的主链路，不允许埋进二级或附属面板。
                        IconButton(
                          key: const Key('dictation-button'),
                          tooltip: LLStrings.of(context).dictation,
                          icon: const Icon(Icons.keyboard_alt_outlined, size: 19),
                          color: ll.textSecondary,
                          onPressed: _openDictation,
                        ),
                        // 二级菜单：三级开关（生词积累）都收在这里，
                        // 不与核心操作抢顶栏位置。
                        IconButton(
                          key: const Key('more-button'),
                          tooltip: LLStrings.of(context).more,
                          icon: const Icon(Icons.more_horiz_rounded, size: 20),
                          color: ll.textSecondary,
                          onPressed: _openMoreMenu,
                        ),
                      ],
                      IconButton(
                        key: const Key('playlist-button'),
                        tooltip: '课文目录',
                        icon: const Icon(
                          Icons.playlist_play_rounded,
                          size: 22,
                        ),
                        color: ll.textSecondary,
                        onPressed: _openPlaylistSheet,
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
                // 2026-10-20 郭老师：删掉听读页的封面。音频模式不再保留媒体区
                // （原来那块是"封面 + ∞ 标记"，纯标识，却吃掉近 1/4 竖屏，
                // 把课文句子挤到下面）；现在这段高度整块归课文句子。
                // 视频模式必须保留 —— 那时媒体区就是内容本身。
                if (controller.playbackMode == PlaybackMode.video)
                Expanded(
                  // 视频模式给一块更高的舞台；音频模式已无媒体区。
                  flex: 30,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      LLSpacing.lg,
                      LLSpacing.sm,
                      LLSpacing.lg,
                      0,
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            // WP-G 终审：圆角改吃风格令牌。原先写死 16，等于四套
                            // 风格里只有基础那一套的形状语言生效——学堂(card 4)、
                            // 书院(card 6)、都市(card 4) 的最大一块画面一直跟着
                            // 基础走，风格切换在这个槽位上看不出来。
                            borderRadius:
                                BorderRadius.circular(context.llShape.card),
                            // §三十五: the media slot crossfades when the source
                            // changes — the content changed, not the page.
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: KeyedSubtree(
                                key: ValueKey(
                                  '${controller.playbackMode}_$_currentLessonId',
                                ),
                                child: _renderMediaSlot(
                                  context,
                                  controller,
                                  loading,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 2026-10-20 郭老师：原来这里的「听读 | 视听」文字切换已撤。
                // 「试听」改成了顶栏那枚视频播放标志（见 video-button）：
                // 文字切换要占一整行、还要点两次才看得到视频，而一枚 ▶
                // 一次点击直接进视频页，位置固定在右手第一个。
                // 没有原片的课不摆那枚钮——绝不摆点了没反应的死按钮。
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
                // WP-G 前端视觉：原先四层散件（播放钮 / dock / 倍速行 /
                // 字幕选择器）收敛为一个底座 LLAudioControlBar。回调全部
                // 透传既有 controller 方法与 Sheet，播放/断句逻辑零改动；
                // 顶部细线为当前句进度（控制器无公开 seek，故仅展示）。
                Padding(
                  // 2026-10-20（GPT 镜像评审 §四 P2）：底座**铺满整宽**，
                  // 外面不再用左右留边把它塑造成一张独立卡片 —— 它应该是
                  // 书页下方自然延伸的操作区，而不是悬在纸面中间的一台机器。
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.hasError) ...[
                        _buildErrorBanner(context, controller.errorMessage!),
                        const SizedBox(height: 6),
                      ],
                      LLAudioControlBar(
                        key: const Key('control-dock'),
                        compact: shortViewport,
                        progress: _sentenceProgress(controller),
                        playback: PlaybackControls(
                          isPlaying: controller.isPlaying,
                          canGoPrevious: controller.canGoPrevious || _hasPreviousLesson,
                          canGoNext: controller.canGoNext || _hasNextLesson,
                          onPlayPause: _onPlayPause,
                          onPrevious: controller.previousSentence,
                          onNext: controller.nextSentence,
                          enabled:
                              controller.isInitialized && !controller.hasError,
                        ),
                        inlineSlider:
                            _activeSliderType != _ActiveInlineSliderType.none
                                ? _buildInlineSliderCard(context, controller)
                                : null,
                        pills: _controlPills(context, controller),
                        speedRow: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPressStart: (details) =>
                              _onSpeedLongPressStart(context, details),
                          onLongPressMoveUpdate: _onSpeedLongPressMoveUpdate,
                          onLongPressEnd: _onSpeedLongPressEnd,
                          child: SpeedSelector(
                            playbackRate: controller.playbackRate,
                            onChanged: controller.setSpeed,
                            onLongPressStart: (details) =>
                                _onSpeedLongPressStart(context, details),
                            onLongPressMoveUpdate:
                                _onSpeedLongPressMoveUpdate,
                            onLongPressEnd: _onSpeedLongPressEnd,
                            enabled: controller.isInitialized &&
                                !controller.hasError,
                          ),
                        ),
                        subtitleRow: _isChinese
                            ? null
                            : SubtitleModeSelector(
                                mode: _subtitleMode,
                                sourceLanguage: widget.language,
                                onChanged: (mode) =>
                                    setState(() => _subtitleMode = mode),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )),
      ),
    );
  }

  /// The transcript opens with the lesson's identity: title + one quiet
  /// meta line (sentences · duration · source), then a hairline (spec V2
  /// follow-up: 在字幕的开头加上视频标题与信息).
  String get _displayTitle {
    final raw = _currentTitle;
    return raw
        .replaceAll(RegExp(r'^(课文\d+|识字\d+|示范课例)\s*'), '')
        .replaceAll(RegExp(r'[（\(]双模[板版].*?[）\)]'), '')
        .replaceAll(RegExp(r'双模[板版]'), '')
        .trim();
  }

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
            _displayTitle,
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
    // 2026-10-20 郭老师：封面已删，音频模式没有媒体区。这里只在视频模式
    // 被调用（媒体区 = 视频本身）；真到了没有视频 facade 的异常态，就留空，
    // 绝不回退到"封面"那张图——那正是这次要删掉的东西。
    return const SizedBox.shrink();
  }

  void _onSpeedLongPressStart(BuildContext context, LongPressStartDetails details) {
    final cur = _controller.playbackRate.clamp(0.5, 2.0);
    HapticFeedback.mediumImpact();
    setState(() {
      _activeSliderType = _ActiveInlineSliderType.speed;
      _sliderCurrentValue = cur;
      _sliderDragStartValue = cur;
    });
  }

  void _onSpeedLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_activeSliderType == _ActiveInlineSliderType.speed) {
      final dx = details.offsetFromOrigin.dx;
      final delta = dx * (1.5 / 220.0);
      final raw = (_sliderDragStartValue + delta).clamp(0.5, 2.0);
      final stepped = (raw * 20).round() / 20.0;
      if (stepped != _sliderCurrentValue) {
        _sliderCurrentValue = stepped.clamp(0.5, 2.0);
        _controller.setSpeed(_sliderCurrentValue);
        HapticFeedback.selectionClick();
        setState(() {});
      }
    }
  }

  void _onSpeedLongPressEnd(LongPressEndDetails details) {
    HapticFeedback.lightImpact();
  }

  /// 滑动的横轴控制面板（用户长按后不松手直接滑动调节，最后点确认确定）
  Widget _buildInlineSliderCard(
    BuildContext context,
    SentencePlayerController controller,
  ) {
    if (_activeSliderType == _ActiveInlineSliderType.none) {
      return const SizedBox.shrink();
    }
    final ll = context.ll;

    final String title;
    final String valueText;
    final double min;
    final double max;
    final int divisions;
    final Key sliderKey;
    final List<(double, String)> ticks;

    switch (_activeSliderType) {
      case _ActiveInlineSliderType.speed:
        title = _isChinese ? '播放倍速' : 'Playback Speed';
        valueText = '${_sliderCurrentValue.toStringAsFixed(2)}×';
        min = 0.5;
        max = 2.0;
        divisions = 30;
        sliderKey = const Key('speed-slider');
        ticks = [
          (0.5, '0.5×'),
          (0.75, '0.75×'),
          (1.0, '1.0×'),
          (1.25, '1.25×'),
          (1.5, '1.5×'),
          (2.0, '2.0×'),
        ];
        break;

      case _ActiveInlineSliderType.gap:
        final s = _sliderCurrentValue.toInt();
        title = _isChinese ? '两句话停顿间隔' : 'Sentence Gap';
        valueText = s <= 0 ? '0秒（不停顿）' : '${(s / 1000).toStringAsFixed(s % 1000 == 0 ? 0 : 1)}秒';
        min = 0.0;
        max = 15000.0;
        divisions = 30;
        sliderKey = const Key('gap-slider');
        ticks = [
          (0.0, '0秒'),
          (1000.0, '1秒'),
          (2000.0, '2秒'),
          (3000.0, '3秒'),
          (5000.0, '5秒'),
          (8000.0, '8秒'),
          (10000.0, '10秒'),
          (15000.0, '15秒'),
        ];
        break;

      case _ActiveInlineSliderType.loop:
        final stepInt = _sliderCurrentValue.round().clamp(1, 7);
        title = _isChinese ? '每句循环读调节' : 'Loop Count';
        valueText = stepInt == 7
            ? (_isChinese ? '无限（一直读）' : '无限')
            : '$stepInt 次';
        min = 1.0;
        max = 7.0;
        divisions = 6;
        sliderKey = const Key('loop-slider');
        ticks = [
          (1.0, '1遍'),
          (2.0, '2遍'),
          (3.0, '3遍'),
          (4.0, '4遍'),
          (5.0, '5遍'),
          (6.0, '6遍'),
          (7.0, '无限'),
        ];
        break;

      case _ActiveInlineSliderType.none:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: ll.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ll.accent.withValues(alpha: 0.6),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部栏：标题、当前数值与确认按钮
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ll.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ll.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _activeSliderType == _ActiveInlineSliderType.loop
                      ? (_sliderCurrentValue.round() == 7
                          ? (_isChinese ? '每句循环次数：无限（一直读）' : '每句循环次数：无限')
                          : '每句循环次数：${_sliderCurrentValue.round()} 次')
                      : (_activeSliderType == _ActiveInlineSliderType.gap
                          ? '停顿：$valueText'
                          : '倍速：$valueText'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ll.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 确定确认按钮（用户需求：最后点确认确定）
              FilledButton(
                key: const Key('confirm-button'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  backgroundColor: ll.textPrimary,
                  foregroundColor: ll.surface,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _activeSliderType = _ActiveInlineSliderType.none;
                  });
                },
                child: const Text(
                  '确定',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          // 滑动的横轴（长按后用户不松手即可直接调节滑动）
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              activeTrackColor: ll.textPrimary,
              inactiveTrackColor: ll.divider,
              thumbColor: ll.textPrimary,
              overlayColor: ll.textPrimary.withValues(alpha: 0.15),
            ),
            child: Slider(
              key: sliderKey,
              min: min,
              max: max,
              divisions: divisions,
              value: _sliderCurrentValue.clamp(min, max),
              onChanged: (v) {
                _sliderCurrentValue = v;
                if (_activeSliderType == _ActiveInlineSliderType.speed) {
                  final stepped = (v * 20).round() / 20.0;
                  _controller.setSpeed(stepped);
                } else if (_activeSliderType == _ActiveInlineSliderType.gap) {
                  final stepped = (v / 500.0).round() * 500.0;
                  _controller.setSentenceGap(stepped.toInt());
                } else if (_activeSliderType == _ActiveInlineSliderType.loop) {
                  final stepInt = v.round().clamp(1, 7);
                  _controller.setRepeatTarget(stepInt == 7 ? 0 : stepInt);
                }
                setState(() {});
              },
            ),
          ),
          // 快捷可选参数横向刻度标签
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final t in ticks)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _sliderCurrentValue = t.$1;
                    if (_activeSliderType == _ActiveInlineSliderType.speed) {
                      _controller.setSpeed(t.$1);
                    } else if (_activeSliderType == _ActiveInlineSliderType.gap) {
                      _controller.setSentenceGap(t.$1.toInt());
                    } else if (_activeSliderType == _ActiveInlineSliderType.loop) {
                      final stepInt = t.$1.round().clamp(1, 7);
                      _controller.setRepeatTarget(stepInt == 7 ? 0 : stepInt);
                    }
                    setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    child: Text(
                      t.$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: (_sliderCurrentValue - t.$1).abs() < 0.01
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: (_sliderCurrentValue - t.$1).abs() < 0.01
                            ? ll.textPrimary
                            : ll.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }


  /// 当前句内进度（0–1）。控制器没有公开 seek，所以底座顶部的细线
  /// 只展示、不支持拖拽——拖拽定位仍由左侧句跳滑栏承担。
  double _sentenceProgress(SentencePlayerController controller) {
    final sentence = controller.currentSentence;
    final spanMs = sentence.endMs - sentence.startMs;
    if (spanMs <= 0) return 0;
    return ((controller.currentPosition.inMilliseconds - sentence.startMs) /
            spanMs)
        .clamp(0.0, 1.0);
  }

  /// 底座胶囊排：整课循环 / 循环 / 间隔 / 连读模式 /（非中文）闪卡。
  /// 每个胶囊只是把旧 dock badge 换成统一的胶囊语言——Key、文案、
  /// 点击进 Sheet、长按横轴精调的行为全部原样保留。
  List<Widget> _controlPills(
    BuildContext context,
    SentencePlayerController controller,
  ) {
    final ll = context.ll;
    final lessonLoop = controller.lessonLoop;
    // 2026-10-20 郭老师：控制条全面图标化——中文标签全部删除，
    // 数值以小徽标挂在图标上（信息不丢，语言中立）。
    final gapMs = controller.sentenceGapMs;
    final isSkip = controller.skipSilence;
    final lessonId = widget.lessonId ?? 'demo';
    final isAdded = _aiGovernorService.isSentenceInAnki(
      lessonId,
      controller.currentSentenceIndex,
    );
    return [
      LLPillButton(
        key: const Key('lesson-loop-badge'),
        label: '',
        leading: LLLessonLoopIcon(
          size: 14,
          color: lessonLoop ? ll.textPrimary : ll.textSecondary,
        ),
        active: lessonLoop,
        onTap: () {
          final next = !lessonLoop;
          _controller.setLessonLoop(next);
          // 记住这次选择：下一课打开时自动沿用（否则课文一播完又会
          // 切到下一课）。
          unawaited(
            PreferencesScope.of(context).update(lessonLoop: next),
          );
          setState(() {});
          // 图标化之后没有文字标签了 → 切换时弹一小段说明，告诉用户这个按钮的区别。
          _showLessonLoopHint(next);
        },
      ),
      LLPillButton(
        key: const Key('loop-badge'),
        label: '',
        leading: LLLoopCountIcon(
          size: 14,
          color: controller.repeatTarget != 1
              ? ll.textPrimary
              : ll.textSecondary,
          count: controller.repeatTarget == 0 ? null : controller.repeatTarget,
        ),
        active: controller.repeatTarget != 1,
        onTap: () => _showLoopSheet(context),
        onLongPressStart: (details) => _onLoopLongPressStart(context, details),
        onLongPressMoveUpdate: _onLoopLongPressMoveUpdate,
        onLongPressEnd: _onLoopLongPressEnd,
      ),
      LLPillButton(
        key: const Key('gap-badge'),
        label: '',
        leading: LLLoopGapIcon(
          size: 14,
          color: gapMs > 0 ? ll.textPrimary : ll.textSecondary,
          badge: gapMs <= 0
              ? null
              : '${(gapMs / 1000).toStringAsFixed(gapMs % 1000 == 0 ? 0 : 1)}s',
        ),
        active: gapMs > 0,
        onTap: () => _showGapSheet(context),
        onLongPressStart: (details) => _onGapLongPressStart(context, details),
        onLongPressMoveUpdate: _onGapLongPressMoveUpdate,
        onLongPressEnd: _onGapLongPressEnd,
      ),
      LLPillButton(
        key: const Key('silence-mode-badge'),
        leading: isSkip
            ? LLSentencePauseIcon(
                size: 13,
                color: isSkip ? ll.textPrimary : ll.textSecondary,
              )
            : LLContinuousPlayIcon(
                size: 13,
                color: isSkip ? ll.textPrimary : ll.textSecondary,
              ),
        label: '',
        active: isSkip,
        onTap: () => _toggleSilenceMode(controller),
      ),
      if (!_isChinese)
        LLPillButton(
          key: const Key('anki-badge'),
          label: isAdded ? '★ 已入闪卡' : '+ 闪卡',
          active: isAdded,
          onTap: _toggleAnkiCard,
        ),
    ];
  }

  /// 2026-10-20 郭老师：整课图标化之后没有文字标签了，
  /// 切换时弹一小段文字，说明这个按钮到底切了什么。
  void _showLessonLoopHint(bool enabled) {
    final ll = context.ll;
    final message = _isChinese
        ? (enabled
            ? '整课循环：整本课文播完再从头循环'
            : '关掉整课循环：播完本课即止，不回头重播')
        : (enabled
            ? 'Lesson loop: replay the whole lesson'
            : 'Lesson loop off: stop at the end');
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 140, left: 24, right: 24),
        padding: EdgeInsets.zero,
        content: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: (ll.brightness == Brightness.light
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFF2C2C2C))
                  .withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }

  /// 连读/逐句切换（轻量磨砂胶囊浮动提示，精炼文案讲透概念）
  void _toggleSilenceMode(SentencePlayerController controller) {
    setState(() {
      controller.toggleSkipSilence();
    });
    final newMode = controller.skipSilence;
    final ll = context.ll;
    final message = newMode
        ? (_isChinese
            ? '逐句：每句播完停顿，适合跟读精听'
            : '逐句精听：句末停顿，适合跟读消化')
        : (_isChinese
            ? '连读：整篇原声连贯，不打断节奏'
            : '原声连读：整篇自然连贯播放');

    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 140, left: 24, right: 24),
        padding: EdgeInsets.zero,
        content: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: (ll.brightness == Brightness.light
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFF2C2C2C))
                  .withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onLoopLongPressStart(BuildContext context, LongPressStartDetails details) {
    final cur = _controller.repeatTarget == 0
        ? 7.0
        : _controller.repeatTarget.clamp(1, 6).toDouble();
    HapticFeedback.mediumImpact();
    setState(() {
      _activeSliderType = _ActiveInlineSliderType.loop;
      _sliderCurrentValue = cur;
      _sliderDragStartValue = cur;
    });
  }

  void _onLoopLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_activeSliderType == _ActiveInlineSliderType.loop) {
      final dx = details.offsetFromOrigin.dx;
      final delta = dx * (6.0 / 220.0);
      final raw = (_sliderDragStartValue + delta).clamp(1.0, 7.0);
      final stepped = raw.roundToDouble();
      if (stepped != _sliderCurrentValue) {
        _sliderCurrentValue = stepped.clamp(1.0, 7.0);
        final target = _sliderCurrentValue == 7.0 ? 0 : _sliderCurrentValue.toInt();
        _controller.setRepeatTarget(target);
        HapticFeedback.selectionClick();
        setState(() {});
      }
    }
  }

  void _onLoopLongPressEnd(LongPressEndDetails details) {
    HapticFeedback.lightImpact();
  }

  void _onGapLongPressStart(BuildContext context, LongPressStartDetails details) {
    final cur = _controller.sentenceGapMs.toDouble().clamp(0.0, 15000.0);
    HapticFeedback.mediumImpact();
    setState(() {
      _activeSliderType = _ActiveInlineSliderType.gap;
      _sliderCurrentValue = cur;
      _sliderDragStartValue = cur;
    });
  }

  void _onGapLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_activeSliderType == _ActiveInlineSliderType.gap) {
      final dx = details.offsetFromOrigin.dx;
      final delta = dx * (15000.0 / 220.0);
      final raw = (_sliderDragStartValue + delta).clamp(0.0, 15000.0);
      final stepped = (raw / 500.0).round() * 500.0;
      if (stepped != _sliderCurrentValue) {
        _sliderCurrentValue = stepped.clamp(0.0, 15000.0);
        _controller.setSentenceGap(_sliderCurrentValue.toInt());
        HapticFeedback.selectionClick();
        setState(() {});
      }
    }
  }

  void _onGapLongPressEnd(LongPressEndDetails details) {
    HapticFeedback.lightImpact();
  }

  /// 句间间隔快选：0 / 1 / 2 / 3 / 5 / 8 / 10 / 15 秒。
  Future<void> _showGapSheet(BuildContext context) async {
    final current = _controller.sentenceGapMs;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ll.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _isChinese ? '两句话之间的停顿间隔' : '两句话之间的循环间隔',
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
              ),
              for (final (value, label) in [
                (0, _isChinese ? '0秒（不停顿）' : '无间隔（连续播放）'),
                (1000, _isChinese ? '1秒' : '1 秒'),
                (2000, _isChinese ? '2秒' : '2 秒'),
                (3000, _isChinese ? '3秒' : '3 秒'),
                (5000, _isChinese ? '5秒' : '5 秒'),
                (8000, _isChinese ? '8秒' : '8 秒'),
                (10000, _isChinese ? '10秒' : '10 秒'),
                (15000, _isChinese ? '15秒' : '15 秒'),
              ])
                ListTile(
                  key: Key('gap-option-$value'),
                  title: Text(label),
                  trailing: value == current
                      ? Icon(Icons.check, color: sheetContext.ll.textPrimary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(value),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                child: Text(
                  _isChinese ? '长按停顿按键可直接滑动精调 (0-15 秒)' : '长按「间隔」可直接滑动精调 (0-15s)',
                  style: Theme.of(sheetContext).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await _controller.setSentenceGap(picked);
    }
  }




  /// Loop-count picker: 1-2-3-4-5-6-无限 (直接显示的可调节参数)
  Future<void> _showLoopSheet(BuildContext context) async {
    final s = LLStrings.of(context);
    final target = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ll.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _isChinese ? '每句循环读次数' : s.loopsPerSentence,
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
              ),
              for (final (value, label) in [
                (1, _isChinese ? '1 遍' : s.loopTimes(1)),
                (2, _isChinese ? '2 遍' : s.loopTimes(2)),
                (3, _isChinese ? '3 遍' : s.loopTimes(3)),
                (4, _isChinese ? '4 遍' : s.loopTimes(4)),
                (5, _isChinese ? '5 遍' : s.loopTimes(5)),
                (6, _isChinese ? '6 遍' : s.loopTimes(6)),
                (0, _isChinese ? '无限（一直读）' : s.loopForever),
              ])
                ListTile(
                  key: Key('loop-option-$value'),
                  title: Text(label),
                  trailing: value == _controller.repeatTarget
                      ? Icon(Icons.check, color: sheetContext.ll.textPrimary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(value),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                child: Text(
                  _isChinese ? '长按循环按键可直接滑动精调 (1-6-无限)' : '长按「LOOP」可直接滑动精调 (1-6-∞)',
                  style: Theme.of(sheetContext).textTheme.labelSmall,
                ),
              ),
            ],
          ),
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

/// 初读 / 熟读 的单字圆钮（2026-10-20 郭老师：顶栏分段器图标化）。
///
/// 原先是「初读 | 熟读」四个字的药丸，占 124dp，把中栏句数挤到换行；
/// 现在只剩「初」「熟」两枚 28dp 圆钮——一眼可辨，宽度减半。
class _SegmentationDot extends StatelessWidget {
  const _SegmentationDot({
    super.key,
    required this.glyph,
    required this.active,
    required this.onTap,
  });

  /// 单字标记：「初」或「熟」。
  final String glyph;

  /// 当前选中态（选中 = 实心底 + 粗字）。
  final bool active;

  /// null = 不可点（另一个档位正生效时，点了也不会切）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Semantics(
      button: true,
      selected: active,
      label: glyph == '初' ? '初读' : '熟读',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? ll.textPrimary.withValues(alpha: 0.12)
                : ll.surfaceHigh,
            border: Border.all(
              color: active ? ll.textPrimary.withValues(alpha: 0.28) : ll.divider,
              width: 0.8,
            ),
          ),
          child: Text(
            glyph,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? ll.textPrimary : ll.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
