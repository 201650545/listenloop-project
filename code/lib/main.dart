import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'creation/audio_preprocessor.dart';
import 'creation/creation_controller.dart';
import 'creation/creation_screen.dart';
import 'creation/lesson_input.dart';
import 'creation/sherpa_onnx_asr_engine.dart';
import 'creation/translation_service.dart';
import 'preferences/app_preferences.dart';
import 'screens/intro_screen.dart';
import 'screens/root_shell.dart';
import 'storage/in_memory_lesson_repository.dart';
import 'storage/lesson_repository.dart';
import 'theme/listenloop_theme.dart';
import 'widgets/creation_capsule.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LessonRepository repository;
  try {
    repository = await SqfliteLessonRepository.open();
  } catch (error, stackTrace) {
    // Degrade gracefully: the app stays usable for this session (lessons
    // simply won't persist across restarts) instead of crash-looping.
    debugPrint(
      '[ListenLoop] opening lesson database failed: '
      '$error\n$stackTrace',
    );
    repository = InMemoryLessonRepository();
  }

  // Personal reading preferences (Visual Polish V2 §二十三–§二十五) load
  // before the first frame so there is no theme flash after the intro.
  final preferences = PreferencesController(
    store: SharedPrefsAppPreferencesStore(),
  );
  await preferences.load();

  runApp(ListenLoopApp(repository: repository, preferences: preferences));
}

/// Root widget of ListenLoop.
class ListenLoopApp extends StatefulWidget {
  const ListenLoopApp({
    super.key,
    required this.repository,
    required this.preferences,
  });

  final LessonRepository repository;
  final PreferencesController preferences;

  @override
  State<ListenLoopApp> createState() => _ListenLoopAppState();
}

class _ListenLoopAppState extends State<ListenLoopApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// One creation controller for the whole app: the shell's Library tab and
  /// the floating capsule above every route share this single instance
  /// (§四十八 single active job).
  late final CreationController _creationController = CreationController(
    repository: widget.repository,
    audioPreprocessor: MethodChannelAudioPreprocessor(),
    asrEngine: SherpaOnnxAsrEngine(
      modelDirResolver: () async {
        final docs = await getApplicationDocumentsDirectory();
        return p.join(docs.path, 'models', 'asr');
      },
      tier: () => widget.preferences.prefs.asrTier,
      threads: () => widget.preferences.prefs.asrThreads,
    ),
    translationEngine: GatewayTranslationEngine(
      settings: () => widget.preferences.prefs,
    ),
    youtubeRelayBaseUrlResolver: () => widget.preferences.prefs.youtubeRelayBaseUrl,
  );

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
    return PreferencesScope(
      controller: widget.preferences,
      child: AnimatedBuilder(
        animation: widget.preferences,
        builder: (context, _) {
          return MaterialApp(
            title: 'ListenLoop',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            builder: (context, child) => Stack(
              children: [
                ?child,
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
            // §八: Dark is the default identity; System and Light are
            // first-class options (§九–§十二).
            theme: buildListenLoopTheme(Brightness.light),
            darkTheme: buildListenLoopTheme(Brightness.dark),
            themeMode: widget.preferences.prefs.themeMode,
            home: IntroScreen(
              repository: widget.repository,
              creationController: _creationController,
            ),
          );
        },
      ),
    );
  }
}
