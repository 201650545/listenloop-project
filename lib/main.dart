
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'creation/audio_preprocessor.dart';
import 'creation/creation_controller.dart';
import 'creation/creation_screen.dart';
import 'creation/lesson_input.dart';
import 'creation/sherpa_onnx_asr_engine.dart';
import 'creation/translation_service.dart';
import 'data/profile_store.dart';
import 'l10n/ll_strings.dart';
import 'preferences/app_preferences.dart';
import 'screens/intro_screen.dart';
import 'screens/profile_lock_screen.dart';
import 'screens/root_shell.dart';
import 'storage/in_memory_lesson_repository.dart';
import 'storage/lesson_repository.dart';
import 'theme/listenloop_theme.dart';
import 'theme/ll_style.dart';
import 'widgets/creation_capsule.dart';
import 'widgets/ll_daynight_veil.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 屏幕方向：常态锁竖屏（2026-10-15 郭老师定）。
  //
  // 这个 App 的阅读节奏是按竖屏排的——课文、控制条、设置页都是。跟着
  // 手机转来转去只会把版式挤坏：横屏 382dp 高时，顶栏 + 听读/视听 +
  // 控制条三件固定高度子件就把可用高度吃满，句子区被压成 0、控制条下缘
  // 还溢出 2.4px（当天实测）。
  //
  // 唯一需要横屏的是**视听模式看视频**：那才需要全屏。放开旋转的时机由
  // ListeningScreen._syncOrientation 在听读 ⇄ 视听 切换时掌握，切回听读
  // 或离开精听页都会立刻收回竖屏。
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  // 离线登录（2026-10-20）：档案表先起来 —— 学习进度与阅读偏好都按档案
  // 分开存，课件库打不开时它也得能用（降级成内存库也不该把登录一起废掉）。
  final profiles = ProfileStore();
  try {
    await profiles.load();
  } catch (error) {
    debugPrint('[ListenLoop] loading profiles failed: $error');
  }

  LessonRepository repository;
  StartupNotice? startupNotice;
  try {
    repository = await SqfliteLessonRepository.open(
      // 现取当前档案：切换档案后进度立刻跟着走，不必重开数据库。
      profileId: () => profiles.activeId,
    );
  } catch (error, stackTrace) {
    // Degrade gracefully: the app stays usable for this session (lessons
    // simply won't persist across restarts) instead of crash-looping. BUT
    // the degradation is no longer silent — the reason is surfaced once
    // (Task 1.4): a wiped library is far worse than a crash.
    debugPrint(
      '[ListenLoop] opening lesson database failed: '
      '$error\n$stackTrace',
    );
    repository = InMemoryLessonRepository();
    startupNotice = StartupNotice(
      StartupNoticeKind.dbOpenFailed,
      error: error,
      stackTrace: stackTrace,
    );
  }

  // Personal reading preferences (Visual Polish V2 §二十三–§二十五) load
  // before the first frame so there is no theme flash after the intro.
  // 字号/字体/语言等跟人走的偏好按**当前档案**存（离线登录）。
  final preferences = PreferencesController(
    store: SharedPrefsAppPreferencesStore(
      profileId: () => profiles.activeId,
    ),
  );
  await preferences.load();

  runApp(ListenLoopApp(
    repository: repository,
    preferences: preferences,
    profiles: profiles,
    startupNotice: startupNotice,
  ));
}

/// Root widget of ListenLoop.
class ListenLoopApp extends StatefulWidget {
  const ListenLoopApp({
    super.key,
    required this.repository,
    required this.preferences,
    required this.profiles,
    this.startupNotice,
  });

  final LessonRepository repository;
  final PreferencesController preferences;

  /// 本地档案表（离线登录）。
  final ProfileStore profiles;

  /// 启动期一次性提示（本地库打开失败等），首屏会弹出一次；null = 正常启动。
  final StartupNotice? startupNotice;

  @override
  State<ListenLoopApp> createState() => _ListenLoopAppState();
}

class _ListenLoopAppState extends State<ListenLoopApp>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// The look fully on screen when no transition is running.
  late _ThemeLook _shown;

  /// The look being animated towards; non-null only mid-transition.
  _ThemeLook? _pending;

  bool _transitioning = false;

  /// 0 → 1 across [LLMotion.themeDepth]; feeds `LLPalette.staggerTo`.
  late final AnimationController _depth = AnimationController(
    vsync: this,
    value: 0,
  );

  /// One creation controller for the whole app: the shell's Library tab and
  /// the floating capsule above every route share this single instance
  /// (§四十八 single active job).
  late final CreationController _creationController = CreationController(
    repository: widget.repository,
    audioPreprocessor: MethodChannelAudioPreprocessor(),
    asrEngine: SherpaOnnxAsrEngine(
      modelDirResolver: defaultAsrModelDir,
      tier: () => widget.preferences.prefs.asrTier,
      threads: () => widget.preferences.prefs.asrThreads,
    ),
    translationEngine: GatewayTranslationEngine(
      settings: () => widget.preferences.prefs,
    ),
    youtubeRelayBaseUrlResolver: () => widget.preferences.prefs.youtubeRelayBaseUrl,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.preferences.addListener(_stageLook);
    _shown = _requestedLook();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.preferences.removeListener(_stageLook);
    _depth.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _stageLook();

  /// Brightness the prefs ask for right now — `system` follows the OS.
  Brightness _resolvedBrightness(ThemeMode mode) => switch (mode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };

  _ThemeLook _requestedLook() {
    final prefs = widget.preferences.prefs;
    return (
      brightness: _resolvedBrightness(prefs.themeMode),
      style: prefs.style,
    );
  }

  /// Called on every prefs change and on every OS brightness change. Only
  /// brightness and style animate; the reading prefs (type size, fonts) keep
  /// repainting instantly so a slider drag never starts a transition.
  ///
  /// A request that arrives mid-transition is dropped here: [_runBeats]
  /// re-reads the prefs once it lands, so the screen converges on what prefs
  /// actually say instead of on a stale request — a double tap (黑夜 then
  /// 白昼) ends on 白昼.
  void _stageLook() {
    if (!mounted || _transitioning) return;
    if (_requestedLook() == _shown) return;
    _transitioning = true;
    _runBeats();
  }

  /// The day/night and style change, in three beats with silence between them
  /// (doc 21 §十六): 背景与主墨 → 形状 → 彩度与字距. The holds are what make it
  /// read as three layers instead of one wash; the beats themselves are short
  /// because a luminance-inverted pair must cross the equal-luminance instant
  /// and the only knob is how briefly it is spent there (§十四).
  ///
  /// A snapshot-ring reveal was tried and rejected on sight (2026-10-08 用户：
  /// 「直接一块黑布，把所有动画都做了」) — a wipe reads as a cloth no matter how
  /// the edge is feathered, so the layering lives in time again.
  Future<void> _runBeats() async {
    while (mounted) {
      final target = _requestedLook();
      if (target == _shown) {
        _transitioning = false;
        return;
      }
      setState(() => _pending = target);
      _depth.value = 0;
      // Linear master progress on purpose: the beat windows inside
      // `LLPalette.staggerTo` carry the easing, so curving t as well would
      // distort where they sit.
      await _depth.animateTo(
        1,
        duration: LLMotion.themeDepth,
        curve: Curves.linear,
      );
      if (!mounted) break;
      // At t = 1 the blend *is* the target palette, so handing over from
      // `_pending` back to `_shown` cannot pop.
      setState(() {
        _shown = target;
        _pending = null;
      });
      _depth.value = 0;
    }
    _transitioning = false;
  }

  /// 这一次过渡该往哪个方向走光（WP-G §二.2）。
  ///
  /// 明暗变了就是「开灯 / 熄灯」；明暗没变（只换风格）就是一层极轻的光尘——
  /// 不假装天亮，但给「换了一张纸」一个来处。
  LLVeilMode _veilMode(Brightness target) {
    if (target == _shown.brightness) return LLVeilMode.shift;
    return target == Brightness.light ? LLVeilMode.dawn : LLVeilMode.dusk;
  }

  void _openCreationFromCapsule() {
    final input = _creationController.currentInput ??
        const LessonInput.localFile(path: '');
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => CreationScreen(
          controller: _creationController,
          input: input,
          // The capsule has no Listen-tab machinery; the finished lesson
          // lands on the Library shelf like any other.
          onStartListening: (lesson) async {
            _navigatorKey.currentState?.pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProfileScope(
      store: widget.profiles,
      child: PreferencesScope(
        controller: widget.preferences,
        // The theme is a function of `_depth`, so every tick has to rebuild the
        // app; prefs changes have to as well. Nested rather than merged — a
        // `Listenable.merge` result has no dispose of its own to call.
        child: AnimatedBuilder(
          animation: _depth,
          builder: (context, _) => AnimatedBuilder(
            animation: widget.preferences,
            builder: (context, _) => _app(),
          ),
        ),
      ),
    );
  }

  Widget _app() {
    // §八: Dark is the default identity; System and Light are first-class
    // options (§九–§十二). `style` (doc 21) picks which of the four visual
    // styles those two brightnesses render.
    //
    // During a transition the look on screen is neither `_shown` nor
    // [_pending] but the blend between them, so brightness is resolved here
    // rather than by MaterialApp, and the built-in colour tween is switched
    // off — it would fight the layer windows and drag every `isDark ? …`
    // widget along at its own pace.
    final pending = _pending;
    final Brightness reported;
    final LLStyle style;
    LLPalette? blend;
    if (pending == null) {
      reported = _shown.brightness;
      style = _shown.style;
    } else {
      final t = _depth.value;
      reported = t >= LLMotion.depthBoolFlip
          ? pending.brightness
          : _shown.brightness;
      style = pending.style;
      blend = _shown.style
          .paletteFor(_shown.brightness)
          .staggerTo(pending.style.paletteFor(pending.brightness), t);
    }
    // One blended ThemeData in both slots: `themeMode` is explicit below, so
    // only one is ever read, and during a blend the two must not differ.
    final theme = buildListenLoopTheme(reported, style: style, paletteOverride: blend);
    return MaterialApp(
      // 任务切换器/桌面多任务里显示的产品名：句读。包名与引擎名仍是
      // ListenLoop（applicationId com.listenloop.listenloop，应用更新与本地
      // 数据都锚在它身上），那部分不动。
      title: '句读',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      builder: (context, child) => Stack(
        children: [
          ?child,
          // 昼夜 / 风格过渡的那点「光」（WP-G §二.2）：一层从顶部中心漫开的
          // 径向光晕，盖在过渡期的根页面之上、浮层胶囊之下。只在过渡中挂载——
          // `pending == null` 时它根本不在树上，静止页面不为它付任何代价。
          if (pending != null)
            Positioned.fill(
              child: LLDaynightVeil(
                progress: _depth.value,
                mode: _veilMode(pending.brightness),
              ),
            ),
          // Floating creation capsule: floats above every route while
          // a job runs, so leaving the creation screen never hides the
          // progress (2026-09-18 用户需求).
          CreationCapsule(
            controller: _creationController,
            onOpen: _openCreationFromCapsule,
            onStartListening: (lesson) {
              _navigatorKey.currentState?.popUntil((route) => route.isFirst);
              RootShell.globalKey.currentState?.openLessonDirectly(lesson);
            },
          ),
        ],
      ),
      theme: theme,
      darkTheme: theme,
      themeMode: reported == Brightness.light
          ? ThemeMode.light
          : ThemeMode.dark,
      themeAnimationDuration: Duration.zero,
      home: ProfileGate(
        store: widget.profiles,
        child: IntroScreen(
          repository: widget.repository,
          creationController: _creationController,
          startupNotice: widget.startupNotice,
        ),
      ),
    );
  }
}

/// A rendered look: which brightness is showing and which of the four styles
/// it is wearing (doc 21).
typedef _ThemeLook = ({Brightness brightness, LLStyle style});
