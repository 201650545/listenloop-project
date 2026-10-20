import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../creation/audio_preprocessor.dart';
import '../widgets/ll_icons.dart';
import '../creation/creation_controller.dart';
import '../creation/creation_screen.dart';
import '../creation/sherpa_onnx_asr_engine.dart';
import '../creation/translation_service.dart';
import '../creation/youtube_relay.dart';
import '../l10n/ll_strings.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../data/vocabulary_store.dart';
import '../data/word_frequency_loader.dart';
import '../player/audio_player_facade.dart';
import '../player/just_audio_facade.dart';
import '../player/sentence_player_controller.dart';
import '../preferences/app_preferences.dart';
import '../storage/lesson_repository.dart';
import '../sync/export_payload.dart' show ExportProgressRecord;
import '../sync/local_snapshot.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_brand.dart';
import '../widgets/ll_page.dart';
import 'chinese_reading_screen.dart';
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
  // 底部导航栏四分位：0: 课程, 1: 听, 2: 跟读, 3: 设置
  int _bottomIndex = 0;

  int get _stackIndex => _bottomIndex;

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
  /// 切换档案后刷新课程库（2026-10-20 离线登录）。
  ///
  /// 进度是按档案存的：换档案 = 换一份"读到第几句"。课程页必须重新拉
  /// 一次，否则还摆着上一个孩子的进度。
  Future<void> reloadForProfileSwitch() async {
    await _libraryKey.currentState?.reload();
  }

  ActiveLessonSession? _session;
  bool _autoLoadStarted = false;
  final GlobalKey<LibraryScreenState> _libraryKey = GlobalKey();
  final GlobalKey<_ListenTabState> _listenTabKey = GlobalKey();
  final GlobalKey<_ReadAlongTabState> _readAlongTabKey = GlobalKey();

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
          modelDirResolver: defaultAsrModelDir,
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
    // 词频表（§20.4 P0）：启动装载一次，失败静默降级为空表。
    // 词频只影响候选池排序，绝不能阻塞生词本主链路。
    unawaited(WordFrequencyHolder.load());
    // L1 本地留存：每天最多一次启动快照，防止换机/误删丢 FSRS 曲线。
    // 全部静默失败（L1 是锦上添花，失败绝不阻塞启动）。
    unawaited(_maybeDailySnapshot());
    _autoLoadMostRecent();
  }

  /// L1 本地快照：**每天最多一次**，靠 SharedPreferences 记 last date。
  /// 快照覆盖生词本（含 FSRS）+ 偏好 + SQLite 备份；governor 数据
  /// 留给 L2 用户主动导出（启动时 governor 尚未创建）。
  Future<void> _maybeDailySnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      if (prefs.getString('listenloop:last_snapshot_date') == todayKey) {
        return; // 今天已快照过
      }

      final manager = LocalSnapshotManager();
      final store = _vocabularyStore;
      final appPrefs = _preferences?.prefs ?? AppPreferences.defaults;
      final progress = await _collectProgress();

      await manager.takeSnapshot(
        store: store,
        governor: null,
        prefs: appPrefs,
        progress: progress,
      );
      // 顺带备份 SQLite（若可访问）。
      try {
        await manager.backupSqlite(
          dbPath: p.join(await getDatabasesPath(), 'listenloop.db'),
        );
      } catch (_) {}

      await prefs.setString('listenloop:last_snapshot_date', todayKey);
    } catch (e) {
      debugPrint('[ListenLoop] daily snapshot skipped: $e');
    }
  }

  /// 收集各课程进度（供快照保存）。失败时返回空列表。
  Future<List<ExportProgressRecord>> _collectProgress() async {
    try {
      final items = await widget.repository.listLessons();
      final out = <ExportProgressRecord>[];
      for (final item in items) {
        final progress = item.progress;
        if (progress == null) continue;
        out.add(
          ExportProgressRecord(
            lessonId: item.lesson.id,
            lastSentenceIndex: progress.lastSentenceIndex,
            positionMs: progress.positionMs,
            subtitleMode: progress.subtitleMode,
            playbackRate: progress.playbackRate,
            repeatTarget: progress.repeatTarget,
            displayMode: progress.displayMode,
            updatedAt: progress.updatedAt,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
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
      if (switchTab) _bottomIndex = 1;
    });
  }

  void _onTabChanged(int index) {
    if (index == _bottomIndex) return;
    setState(() => _bottomIndex = index);

    if (index == 3) {
      // Tab 3: 设置 —— 暂停播放
      _listenTabKey.currentState?.pausePlayback();
      _readAlongTabKey.currentState?.onLeave();
    } else if (index == 1) {
      // Tab 1: 听 —— 暂停跟读收音，回到精听播放
      _readAlongTabKey.currentState?.onLeave();
      _listenTabKey.currentState?.revealCurrentSentence();
    } else if (index == 2) {
      // Tab 2: 跟读 —— 暂停精听播放
      _listenTabKey.currentState?.pausePlayback();
    } else if (index == 0) {
      // Tab 0: 课程 —— 刷新课程库
      _listenTabKey.currentState?.pausePlayback();
      _readAlongTabKey.currentState?.onLeave();
      _libraryKey.currentState?.reload();
    }
  }

  Future<void> _openCreationRoute() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CreationScreen(
          controller: _creationController,
          embedded: true,
          onStartListening: (lesson) async {
            Navigator.of(context).pop();
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
          onImportLessonPackage: () {
            Navigator.of(context).pop();
            _libraryKey.currentState?.importLessonPackage();
          },
          onOpenCloudCatalog: () {
            Navigator.of(context).pop();
            _libraryKey.currentState?.openCloudCatalog();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    return LLPage(
      safeArea: false,
      body: IndexedStack(
        index: _stackIndex,
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
            onOpenCreationTab: _openCreationRoute,
          ),
          _ListenTab(
            key: _listenTabKey,
            session: _session,
            repository: widget.repository,
            listeningScreenBuilder: widget.listeningScreenBuilder,
            audioFacade: widget.audioFacade,
            vocabularyStore: _vocabularyStore,
            onRequestReadAlongTab: () {
              setState(() => _bottomIndex = 2);
            },
          ),
          _ReadAlongTab(
            key: _readAlongTabKey,
            session: _session,
            repository: widget.repository,
            audioFacade: widget.audioFacade,
            controller: _listenTabKey.currentState?.controller,
          ),
          SettingsScreen(repository: widget.repository),
        ],
      ),
      bottomBar: _buildBottomNav(context, ll, s),
    );
  }

  /// 4 tabs navigation: 课程, 听, 跟读, 设置.
  Widget _buildBottomNav(BuildContext context, LLPalette ll, LLStrings s) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ll.divider, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _bottomIndex,
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
              // 2026-10-20 郭老师：底部导航图标定制化（替换 Material 老图标）
              icon: const LLNavCourseIcon(),
              activeIcon: const LLNavCourseIcon(),
              label: s.tabLibrary,
            ),
            BottomNavigationBarItem(
              icon: const LLNavListenIcon(),
              activeIcon: const LLNavListenIcon(),
              label: s.tabListen,
            ),
            BottomNavigationBarItem(
              icon: const LLNavReadIcon(),
              activeIcon: const LLNavReadIcon(),
              label: s.tabReadAlong,
            ),
            BottomNavigationBarItem(
              icon: const LLNavSettingsIcon(),
              activeIcon: const LLNavSettingsIcon(),
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
    this.onRequestReadAlongTab,
  });

  final ActiveLessonSession? session;
  final LessonRepository repository;
  final VoidCallback? onRequestReadAlongTab;

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

  SentencePlayerController? get controller => _boundController;

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

  void enterReadAlong() {
    _screenKey?.currentState?.enterReadAlong();
  }

  void exitReadAlong() {
    _screenKey?.currentState?.exitReadAlong();
  }

  bool get isReadAlongOn => _screenKey?.currentState?.isReadAlongOn ?? false;

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
      initialPageMode: progress?.displayMode != null
          ? (progress!.displayMode == 'page')
          : null,
      onControllerCreated: (controller) => _boundController = controller,
      audioFacade: widget.audioFacade,
      onRequestReadAlongTab: widget.onRequestReadAlongTab,
    );
    // Test seam: observe navigation without the audio stack.
    final builder = widget.listeningScreenBuilder;
    if (builder != null) {
      return builder(context, item, session.sentences);
    }
    return listening;
  }
}

/// The ReadAlong tab: hosts the active lesson's [ChineseReadingScreen] (or the
/// quiet empty state). It is an independent first-class tab in [IndexedStack].
class _ReadAlongTab extends StatefulWidget {
  const _ReadAlongTab({
    super.key,
    required this.session,
    required this.repository,
    required this.audioFacade,
    this.controller,
  });

  final ActiveLessonSession? session;
  final LessonRepository repository;
  final AudioPlayerFacade? audioFacade;
  final SentencePlayerController? controller;

  @override
  State<_ReadAlongTab> createState() => _ReadAlongTabState();
}

class _ReadAlongTabState extends State<_ReadAlongTab> {
  SentencePlayerController? _ownedController;
  String? _ownedLessonId;

  void onLeave() {
    final c = widget.controller ?? _ownedController;
    c?.pause();
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) {
      final s = LLStrings.of(context);
      return Center(
        child: Column(
          key: const Key('read-along-empty'),
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
    final controller = widget.controller ?? _getOrCreateController(session);

    return ChineseReadingScreen(
      key: ValueKey('read-along-${lesson.id}'),
      lesson: lesson,
      sentences: session.sentences,
      controller: controller,
      onSelectSentence: (index) {
        controller.selectSentence(index);
      },
    );
  }

  SentencePlayerController _getOrCreateController(ActiveLessonSession session) {
    final lid = session.item.lesson.id;
    if (_ownedController != null && _ownedLessonId == lid) {
      return _ownedController!;
    }
    _ownedController?.dispose();
    _ownedLessonId = lid;
    _ownedController = SentencePlayerController(
      audioFacade: widget.audioFacade ?? JustAudioFacade(),
      sentences: session.sentences,
      audioAsset: session.item.lesson.audioPath,
      audioIsFile: true,
      initialSentenceIndex: session.startSentenceIndex ?? 0,
    );
    unawaited(_ownedController!.initialize());
    return _ownedController!;
  }
}
