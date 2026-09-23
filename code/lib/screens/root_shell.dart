import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../creation/audio_preprocessor.dart';
import '../creation/creation_controller.dart';
import '../creation/creation_screen.dart';
import '../creation/sherpa_onnx_asr_engine.dart';
import '../creation/translation_service.dart';
import '../creation/youtube_relay.dart';
import '../l10n/ll_strings.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../data/vocabulary_store.dart';
import '../player/audio_player_facade.dart';
import '../player/sentence_player_controller.dart';
import '../preferences/app_preferences.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_brand.dart';
import 'library_screen.dart';
import 'listening_screen.dart';
import 'settings_screen.dart';

/// The lesson currently hosted by the Listen tab. Created when a lesson is
/// opened (from Library) or auto-loaded (most recent, §四); swapped wholesale
/// when a DIFFERENT lesson is opened, and never rebuilt by tab switching
/// (§三十一: navigation must not touch playback state).
@immutable
class ActiveLessonSession {
  const ActiveLessonSession({
    required this.item,
    required this.sentences,
    required this.autoPlay,
    this.startSentenceIndex,
    this.seq = 0,
  });

  final LessonWithProgress item;
  final List<Sentence> sentences;

  /// Library taps keep the existing auto-play behaviour; the Listen tab's
  /// own auto-load stays paused so switching tabs never starts sound.
  final bool autoPlay;

  /// 打开时要求落在的句子下标（生词本「回原声」用）；null 表示沿用进度。
  final int? startSentenceIndex;

  /// 请求序号 —— 每次打开自增。同一个课程的第二次打开（课号不变、只是
  /// 要跳到另一句）不能靠 lesson.id 判断，故用序号区分。
  final int seq;
}

/// Root navigation shell (spec V2 §二–§五, §三十–§三十三): Library / Listen /
/// Settings in an [IndexedStack] so every tab stays alive — switching tabs
/// never disposes the listening session, never recreates the video, and
/// never resets the sentence index. UI navigation ≠ playback rewrite.
class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.repository,
    this.listeningScreenBuilder,

    /// Test seam: injected into the hosted [ListeningScreen] so widget
    /// tests can run without the audio platform channels.
    this.audioFacade,

    /// App-level creation controller (injected when the floating capsule at
    /// the MaterialApp level shares the same instance). Null = the shell
    /// builds and owns its own (default, widget tests).
    this.creationController,

    /// Injected vocabulary store. Null = the shell builds and owns its own
    /// (that is the production path); tests inject one so they can seed
    /// words without touching SharedPreferences.
    this.vocabularyStore,
  });

  final LessonRepository repository;

  /// Test seam (mirrors [LibraryScreen.listeningScreenBuilder]).
  final Widget Function(
    BuildContext context,
    LessonWithProgress item,
    List<Sentence> sentences,
  )?
  listeningScreenBuilder;

  final AudioPlayerFacade? audioFacade;

  final CreationController? creationController;

  /// Injected vocabulary store; null = the shell builds and owns its own
  /// (production). Tests inject one to seed words without disk access.
  final VocabularyStore? vocabularyStore;

  static final GlobalKey<RootShellState> globalKey = GlobalKey<RootShellState>();

  @override
  State<RootShell> createState() => RootShellState();
}

class RootShellState extends State<RootShell> {
  int _index = 0;

  /// Directly opens a lesson in the Listen tab and starts playback.
  Future<void> openLessonDirectly(Lesson lesson) async {
    final data = await widget.repository.getLessonWithSentences(lesson.id);
    if (!mounted || data == null) return;
    await _openLesson(
      LessonWithProgress(lesson: lesson),
      autoPlay: true,
      switchTab: true,
    );
  }
  ActiveLessonSession? _session;
  bool _autoLoadStarted = false;
  final GlobalKey<LibraryScreenState> _libraryKey = GlobalKey();
  final GlobalKey<_ListenTabState> _listenTabKey = GlobalKey();

  /// Read in [didChangeDependencies]; the translation engine looks through it
  /// on every call so a Settings change applies to the next job immediately.
  PreferencesController? _preferences;

  /// 生词本（附属层）—— **全应用共用一个实例**：精听页点词保存、Library
  /// 生词本页管理与「回原声」都读写同一份数据，否则两边会各存一份。
  /// 启动时装载一次存档；断网亦可用（纯本地）。
  late final VocabularyStore _vocabularyStore =
      widget.vocabularyStore ?? VocabularyStore();

  /// 打开课程的请求序号（区分"同一课程跳到另一句"）。
  int _sessionSeq = 0;

  /// Mobile Lesson Creation (spec V1): one controller for the whole app,
  /// single active job (§四十八). Injected from the app level when the
  /// floating capsule shares it; built here otherwise (tests).
  late final CreationController _creationController =
      widget.creationController ??
      CreationController(
        repository: widget.repository,
        audioPreprocessor: MethodChannelAudioPreprocessor(),
        asrEngine: SherpaOnnxAsrEngine(
          modelDirResolver: () async {
            final docs = await getApplicationDocumentsDirectory();
            return p.join(docs.path, 'models', 'asr');
          },
          tier: () => _preferences?.prefs.asrTier ?? AsrTier.fast,
          threads: () => _preferences?.prefs.asrThreads ?? kDefaultAsrThreads,
        ),
        translationEngine: GatewayTranslationEngine(
          settings: () => _preferences?.prefs ?? AppPreferences.defaults,
        ),
        youtubeRelayBaseUrlResolver: () =>
            _preferences?.prefs.youtubeRelayBaseUrl ??
            YouTubeRelayClient.defaultBaseUrl,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preferences = PreferencesScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    // 生词本存档：启动装载一次（幂等）。失败静默降级为纯内存，
    // 不影响「听」这条主链路。注入的实例由注入方负责装载。
    if (widget.vocabularyStore == null) {
      unawaited(_vocabularyStore.load());
    }
    _autoLoadMostRecent();
  }

  /// §四: Listen always has the most recent lesson ready — restored to its
  /// saved sentence, but paused (tab switches must not start sound).
  Future<void> _autoLoadMostRecent() async {
    if (_autoLoadStarted) return;
    _autoLoadStarted = true;
    final items = await widget.repository.listLessons();
    if (!mounted || items.isEmpty || _session != null) return;
    LessonWithProgress? recent;
    for (final item in items) {
      final progress = item.progress;
      if (progress == null) continue;
      if (recent == null ||
          progress.updatedAt.isAfter(recent.progress!.updatedAt)) {
        recent = item;
      }
    }
    // §四: the Listen tab's session is preloaded, but the app still opens
    // on the Library — switching tabs is always an explicit user action.
    await _openLesson(recent ?? items.first, autoPlay: false, switchTab: false);
  }

  /// Called by the Library tab (and auto-load). Fetching happened upstream
  /// when needed; a session for a DIFFERENT lesson replaces the old one —
  /// the old controller is disposed through the widget's own lifecycle.
  Future<void> _openLesson(
    LessonWithProgress item, {
    required bool autoPlay,
    bool switchTab = true,
    int? startSentenceIndex,
  }) async {
    final data = await widget.repository.getLessonWithSentences(item.lesson.id);
    if (!mounted || data == null) return;
    setState(() {
      _session = ActiveLessonSession(
        item: item,
        sentences: data.sentences,
        autoPlay: autoPlay,
        startSentenceIndex: startSentenceIndex,
        seq: ++_sessionSeq,
      );
      if (switchTab) _index = 1;
    });
  }

  void _onTabChanged(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    // Tab 3: Settings is for adjusting, not listening — pause on the way in.
    if (index == 3) {
      _listenTabKey.currentState?.pausePlayback();
    } else if (index == 1) {
      // Tab 1: reveal the current sentence now that this tab becomes visible.
      _listenTabKey.currentState?.revealCurrentSentence();
    } else if (index == 0) {
      // Tab 0: refresh library so newly completed lessons show up immediately.
      _libraryKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    return Scaffold(
      backgroundColor: ll.bg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: llSystemOverlay(ll.brightness),
        child: IndexedStack(
          index: _index,
          children: [
            LibraryScreen(
              key: _libraryKey,
              repository: widget.repository,
              creationController: _creationController,
              vocabularyStore: _vocabularyStore,
              onOpenLesson: (item, sentences) =>
                  _openLesson(item, autoPlay: true),
              // 生词本「回原声」：落到该证据所在的句子并直接开播。
              onOpenLessonAtSentence: (item, sentences, index) => _openLesson(
                item,
                autoPlay: true,
                startSentenceIndex: index,
              ),
              onOpenCreationTab: () => setState(() => _index = 2),
            ),
            _ListenTab(
              key: _listenTabKey,
              session: _session,
              repository: widget.repository,
              listeningScreenBuilder: widget.listeningScreenBuilder,
              audioFacade: widget.audioFacade,
              vocabularyStore: _vocabularyStore,
            ),
            CreationScreen(
              controller: _creationController,
              embedded: true,
              onStartListening: (lesson) async {
                final data = await widget.repository.getLessonWithSentences(
                  lesson.id,
                );
                if (!mounted || data == null) return;
                await _openLesson(
                  LessonWithProgress(lesson: lesson),
                  autoPlay: true,
                  switchTab: true,
                );
              },
              onImportLessonPackage: () =>
                  _libraryKey.currentState?.importLessonPackage(),
            ),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context, ll, s),
    );
  }

  /// 4 tabs navigation: Library, Listen, Create, Settings.
  Widget _buildBottomNav(BuildContext context, LLPalette ll, LLStrings s) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ll.divider, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: _onTabChanged,
          type: BottomNavigationBarType.fixed,
          backgroundColor: ll.bg,
          elevation: 0,
          selectedItemColor: ll.textPrimary,
          unselectedItemColor: ll.textTertiary,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          iconSize: 22,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.auto_stories_outlined),
              label: s.tabLibrary,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.headphones_outlined),
              label: s.tabListen,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.add_circle_outline),
              label: s.tabCreate,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.tune_outlined),
              label: s.tabSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Listen tab: hosts the active lesson's [ListeningScreen] (or the
/// quiet empty state). Its state stays mounted inside the [IndexedStack]
/// while other tabs are shown — that is the whole lifecycle guarantee.
class _ListenTab extends StatefulWidget {
  const _ListenTab({
    super.key,
    required this.session,
    required this.repository,
    required this.listeningScreenBuilder,
    required this.audioFacade,
    required this.vocabularyStore,
  });

  final ActiveLessonSession? session;
  final LessonRepository repository;

  final Widget Function(
    BuildContext context,
    LessonWithProgress item,
    List<Sentence> sentences,
  )?
  listeningScreenBuilder;

  final AudioPlayerFacade? audioFacade;

  /// 全应用共享的生词本（精听页点词与生词本页共用同一份）。
  final VocabularyStore vocabularyStore;

  @override
  State<_ListenTab> createState() => _ListenTabState();
}

class _ListenTabState extends State<_ListenTab> {
  SentencePlayerController? _boundController;

  /// Points at the hosted [ListeningScreen] so the shell can pause it
  /// (Settings) or reveal the current sentence (returning to Listen).
  /// Recreated whenever the session switches to a different lesson, which
  /// is exactly how the old screen gets disposed.
  GlobalKey<ListeningScreenState>? _screenKey;

  @override
  void initState() {
    super.initState();
    _syncScreenKey();
  }

  @override
  void didUpdateWidget(_ListenTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.session?.item.lesson.id;
    final newId = widget.session?.item.lesson.id;
    if (oldId != newId) {
      _syncScreenKey();
      return;
    }
    // 同一个课程被再次打开（生词本「回原声」点到本课的另一句）：
    // lesson.id 没变，GlobalKey 也不会重建，所以必须显式跳转 ——
    // initialSentenceIndex 只在 initState 里读一次。
    final oldSeq = oldWidget.session?.seq;
    final newSeq = widget.session?.seq;
    final target = widget.session?.startSentenceIndex;
    if (target != null && oldSeq != newSeq) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _screenKey?.currentState?.jumpToSentence(target);
      });
    }
  }

  void _syncScreenKey() {
    _boundController = null;
    _screenKey = widget.session == null
        ? null
        : GlobalKey<ListeningScreenState>(
            debugLabel: 'listen-session-${widget.session!.item.lesson.id}',
          );
  }

  void pausePlayback() {
    _boundController?.pause();
  }

  void revealCurrentSentence() {
    _screenKey?.currentState?.revealCurrentSentence();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) {
      // §四: no lesson yet — do NOT build a second lesson list here.
      final s = LLStrings.of(context);
      return Center(
        child: Column(
          key: const Key('listen-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const LLMark(size: 48, color: LLColors.textTertiary),
            const SizedBox(height: LLSpacing.lg),
            Text(s.listenEmptyTitle, style: LLText.rowTitle),
            const SizedBox(height: LLSpacing.sm),
            Text(s.listenEmptyBody, style: LLText.caption),
          ],
        ),
      );
    }
    final item = session.item;
    final lesson = item.lesson;
    final progress = item.progress;
    final listening = ListeningScreen(
      key: _screenKey,
      title: lesson.title,
      language: lesson.language,
      sentences: session.sentences,
      audioAsset: lesson.audioPath,
      audioIsFile: true,
      lessonId: lesson.id,
      repository: widget.repository,
      coverPath: lesson.coverPath,
      videoSource: lesson.video,
      initialSentenceIndex:
          session.startSentenceIndex ?? progress?.lastSentenceIndex ?? 0,
      autoPlay: session.autoPlay,
      vocabularyStore: widget.vocabularyStore,
      initialRepeatTarget: progress?.repeatTarget ?? 1,
      initialPlaybackRate: progress?.playbackRate ?? 1.0,
      initialSubtitleMode: progress?.subtitleMode,
      initialPageMode: progress?.displayMode == 'page',
      onControllerCreated: (controller) => _boundController = controller,
      audioFacade: widget.audioFacade,
    );
    // Test seam: observe navigation without the audio stack.
    final builder = widget.listeningScreenBuilder;
    if (builder != null) {
      return builder(context, item, session.sentences);
    }
    return listening;
  }
}
