import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../creation/creation_controller.dart';
import '../creation/bilibili_source.dart';
import '../creation/creation_screen.dart';
import '../creation/lesson_input.dart';
import '../creation/lesson_job_stage.dart';
import '../data/ai_governor_service.dart';
import '../data/vocabulary_store.dart';
import '../l10n/ll_strings.dart';
import '../lesson/lesson_package_exception.dart';
import '../lesson/lesson_package_reader.dart';
import '../models/ai_governor_model.dart';
import '../models/lesson.dart';
import '../models/vocabulary_model.dart';
import '../models/sentence.dart';
import '../preferences/app_preferences.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';
import '../training/vocabulary_plan.dart';
import '../widgets/anki/anki_review_dialog.dart';
import '../widgets/library/lesson_continue_card.dart';
import '../widgets/library/lesson_editorial_row.dart';
import '../widgets/library/lesson_language_tabs.dart';
import '../widgets/library/lesson_poster_card.dart';
import '../widgets/ll_brand.dart';
import '../widgets/subtitle_mode_selector.dart' show SubtitleMode, SubtitleModeX;
import 'listening_screen.dart';
import 'vocabulary_book_screen.dart';

const String _httpUserAgent = 'Mozilla/5.0 (Linux; Android 14) ListenLoop/1.0';

/// The app home (Visual Polish V1 §十二–§十七): a quiet bookshelf, not a
/// dashboard. "Continue" is the first visual focus, followed by an editorial
/// lesson list — hairlines and whitespace instead of card stacks.
///
/// All business logic (import / open / menu / delete) is unchanged; the
/// visual rounds moved visuals and surface copy onto the design tokens and
/// the UI language table.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.creationController,
    this.listeningScreenBuilder,
    this.onOpenLesson,
    this.onOpenCreationTab,
    this.aiGovernorService,
    this.vocabularyStore,
    this.onOpenLessonAtSentence,
  });

  final LessonRepository repository;

  /// Mobile Lesson Creation (spec V1): app-level single-job controller.
  final CreationController creationController;

  /// Builds the screen pushed when a lesson is tapped. Injectable so
  /// widget tests can observe navigation without the real audio stack.
  final Widget Function(
    BuildContext context,
    LessonWithProgress item,
    List<Sentence> sentences,
  )?
  listeningScreenBuilder;

  /// Visual Polish V2 §四: when running inside the navigation shell,
  /// opening a lesson swaps the Listen tab's session instead of pushing a
  /// route — that is what keeps the player alive across tab switches.
  final void Function(LessonWithProgress item, List<Sentence> sentences)?
  onOpenLesson;

  /// Invoked to navigate to the bottom nav "Create" tab.
  final VoidCallback? onOpenCreationTab;

  /// AI Governor service for managing weaknesses and quizzes.
  final AiGovernorService? aiGovernorService;

  /// 生词本存储（通常由 RootShell 注入共享实例；测试可自建）。
  final VocabularyStore? vocabularyStore;

  /// 打开课程并直接落在指定句子 —— 生词本「回原声」用。
  ///
  /// 为什么单开一个回调而不是复用 [onOpenLesson]：回原声必须**精确落到
  /// 那句**（证据所在句），而 onOpenLesson 只表达"打开这门课"。
  final void Function(
    LessonWithProgress item,
    List<Sentence> sentences,
    int sentenceIndex,
  )?
  onOpenLessonAtSentence;

  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen> {
  List<LessonWithProgress>? _items;
  bool _importing = false;
  String _selectedLanguage = 'ALL';
  bool _isGridView = true;

  bool _effectiveGridView(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PreferencesScope>();
    if (scope != null) {
      return scope.notifier?.prefs.libraryGridView ?? _isGridView;
    }
    return _isGridView;
  }

  void _toggleView() {
    final isGrid = _effectiveGridView(context);
    final next = !isGrid;
    setState(() => _isGridView = next);
    final scope = context.dependOnInheritedWidgetOfExactType<PreferencesScope>();
    scope?.notifier?.update(libraryGridView: next);
  }

  /// One fetch attempt per lesson per session — a failed fetch is silent
  /// (the ∞ mark stays) and is retried on the next app start.
  final Set<String> _coverFetchTried = {};

  late final AiGovernorService _aiGovernorService =
      widget.aiGovernorService ?? AiGovernorService();

  late final VocabularyStore _vocabularyStore =
      widget.vocabularyStore ?? VocabularyStore();

  @override
  void initState() {
    super.initState();
    _reload();
    _vocabularyStore.addListener(_onVocabularyChanged);
    if (widget.vocabularyStore == null) {
      unawaited(_vocabularyStore.load());
    }
    widget.creationController.addListener(_onCreationChanged);
    _aiGovernorService.addListener(_onAiGovernorChanged);
  }

  void _onAiGovernorChanged() {
    if (mounted) setState(() {});
  }

  /// 生词本变化（精听页点词、生词本页里的增删）→ 刷新入口上的计数。
  void _onVocabularyChanged() {
    if (mounted) setState(() {});
  }

  /// AI 伴学的在线通道（网关地址 / 密钥 / 模型）存在 PreferencesScope 里，
  /// 设置页改完返回必须重新灌给服务，否则讨论页还会用旧模型发请求。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = PreferencesScope.maybeOf(context);
    if (!identical(prefs, _aiGovernorService.appPreferences)) {
      _aiGovernorService.updatePreferences(prefs);
    }
  }

  @override
  void dispose() {
    widget.creationController.removeListener(_onCreationChanged);
    _vocabularyStore.removeListener(_onVocabularyChanged);
    _aiGovernorService.removeListener(_onAiGovernorChanged);
    super.dispose();
  }

  void _onCreationChanged() {
    if (!mounted) return;
    if (widget.creationController.stage == LessonJobStage.completed) {
      _reload();
    } else {
      setState(() {});
    }
  }

  Future<void> reload() => _reload();

  Future<void> importLessonPackage() => _onImportPressed();

  Future<void> _reload() async {
    final items = await widget.repository.listLessons();
    if (!mounted) return;
    setState(() => _items = items);
    _fetchMissingVideoCovers(items);
  }

  /// Visual Polish V2 follow-up: video lessons whose `.lllesson` predates
  /// the cover pipeline get their B站 cover fetched once and persisted via
  /// [LessonRepository.updateCoverPath]. Audio-only lessons keep the brand
  /// mark (§十六). Silent on any failure — covers are decoration.
  void _fetchMissingVideoCovers(List<LessonWithProgress> items) {
    for (final item in items) {
      final lesson = item.lesson;
      if (lesson.video == null || lesson.coverPath != null) continue;
      if (!_coverFetchTried.add(lesson.id)) continue;
      unawaited(_fetchVideoCover(lesson));
    }
  }

  Future<void> _fetchVideoCover(Lesson lesson) async {
    final source = lesson.video!;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final viewReq = await client.getUrl(
        Uri.parse(
          'https://api.bilibili.com/x/web-interface/view?bvid=${source.bvid}',
        ),
      );
      viewReq.headers.set(HttpHeaders.userAgentHeader, _httpUserAgent);
      final viewRes = await viewReq.close();
      if (viewRes.statusCode != 200) return;
      final body = await viewRes.transform(utf8.decoder).join();
      final pic =
          ((jsonDecode(body) as Map?)?['data'] as Map?)?['pic'] as String?;
      if (pic == null || pic.isEmpty) return;

      final imgReq = await client.getUrl(
        Uri.parse(pic.replaceFirst('http://', 'https://')),
      );
      imgReq.headers.set(HttpHeaders.userAgentHeader, _httpUserAgent);
      imgReq.headers.set(HttpHeaders.refererHeader, 'https://www.bilibili.com');
      final imgRes = await imgReq.close();
      if (imgRes.statusCode != 200) return;
      final bytes = <int>[];
      await for (final chunk in imgRes) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) return;

      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, 'lessons', lesson.id, 'cover.jpg'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);

      await widget.repository.updateCoverPath(lesson.id, file.path);
      if (mounted) await _reload();
    } catch (error) {
      debugPrint('[ListenLoop] fetching cover for ${lesson.id} failed: $error');
    } finally {
      client?.close();
    }
  }

  // -------------------------------------------------------------- import --

  /// §十: the add button opens the creation menu — Import Lesson (existing
  /// `.lllesson` flow), Create from File (Mobile M1), Create from Link (M3).
  Future<void> _onAddPressed() async {
    final s = LLStrings.of(context);
    if (widget.creationController.isBusy) {
      // §四十八: one active job — offer progress instead of a second task.
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: context.ll.surface,
        builder: (sheetContext) => SafeArea(
          child: ListTile(
            title: Text(s.creationBusy),
            subtitle: Text(s.viewProgress),
            onTap: () => Navigator.of(sheetContext).pop('progress'),
          ),
        ),
      );
      if (!mounted) return;
      if (action == 'progress') {
        await _openCreationScreen();
      }
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.ll.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AsrTierSelector(),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(s.creationMenuImport),
              onTap: () => Navigator.of(sheetContext).pop('import'),
            ),
            ListTile(
              leading: const Icon(Icons.mic_none_outlined),
              title: Text(s.creationMenuFromFile),
              subtitle: Text(s.createLesson),
              onTap: () => Navigator.of(sheetContext).pop('create-file'),
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text(s.creationMenuFromLink),
              subtitle: const Text('bilibili / YouTube'),
              onTap: () => Navigator.of(sheetContext).pop('create-link'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'import':
        await _onImportPressed();
      case 'create-file':
        await _onCreateFromFile();
      case 'create-link':
        await _onCreateFromLink();
    }
  }

  /// M3 从链接创建 (2026-09-18): paste a bilibili link, the job downloads the
  /// audio and rides the regular pipeline; the lesson carries the WebView
  /// video source.
  Future<void> _onCreateFromLink() async {
    final controller = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.ll.surface,
        title: const Text('从链接创建'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: '粘贴 bilibili 视频链接或 BV 号',
              ),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '支持 bilibili.com / b23.tv 链接和 BV 号；多 P 视频带 ?p=N。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (link == null || link.isEmpty) return; // cancelled
    // Short links (b23.tv) and share blobs carry no BV — those resolve over
    // the network inside the job; only reject input with nothing URL-like.
    if (extractUrl(link) == null && parseBilibiliUrl(link) == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法识别链接——请粘贴 bilibili 或 YouTube 链接')),
      );
      return;
    }
    final input = LessonInput.link(source: link);
    unawaited(widget.creationController.start(input));
    await _openCreationScreen();
  }

  /// Mobile M1 (§十四): pick a local media file and run the creation job.
  Future<void> _onCreateFromFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return; // user cancelled
    final input = LessonInput.localFile(
      path: path,
      titleHint: p.basenameWithoutExtension(path),
    );
    // Fire the job; the screen observes the controller.
    unawaited(widget.creationController.start(input));
    await _openCreationScreen();
  }

  Future<void> _openCreationScreen() async {
    if (widget.onOpenCreationTab != null) {
      widget.onOpenCreationTab!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CreationScreen(
          controller: widget.creationController,
          input:
              widget.creationController.currentInput ??
              const LessonInput.localFile(path: ''),
          onStartListening: (lesson) async {
            Navigator.of(context).pop(); // close the creation screen
            final data = await widget.repository.getLessonWithSentences(
              lesson.id,
            );
            if (!mounted || data == null) return;
            widget.onOpenLesson!(
              LessonWithProgress(lesson: lesson),
              data.sentences,
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  /// Existing `.lllesson` import flow (Milestone 2A) — unchanged.
  Future<void> _onImportPressed() async {
    if (_importing) return;
    final s = LLStrings.of(context);
    // FileType.any is deliberate: `.lllesson` is an unknown extension, and
    // MIUI's 安全访问 picker hides application/octet-stream files entirely
    // when a custom extension filter is set. Wrong picks are rejected later
    // by LessonPackageReader with a friendly message.
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return; // user cancelled

    setState(() => _importing = true);
    _showImportingDialog();

    Lesson? imported;
    String? failureText;
    try {
      final package = await LessonPackageReader.read(path);
      imported = await widget.repository.importPackage(package);
    } on LessonPackageException catch (e) {
      failureText = s.errorText(e.code);
    } catch (e) {
      failureText = s.importFailed;
    }

    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) navigator.pop(); // close the progress dialog
    setState(() => _importing = false);

    if (imported != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.imported(imported.title))));
      await _reload();
    } else {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: dialogContext.ll.surface,
          title: Text(s.cannotImportTitle),
          content: Text(failureText ?? s.importFailed),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(s.know),
            ),
          ],
        ),
      );
    }
  }

  void _showImportingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: dialogContext.ll.surface,
          content: Row(
            children: [
              const LLInfinityLoader(size: 26),
              const SizedBox(width: 20),
              Expanded(child: Text(LLStrings.of(dialogContext).importing)),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- opening --

  Future<void> _openLesson(LessonWithProgress item) async {
    final data = await widget.repository.getLessonWithSentences(item.lesson.id);
    if (!mounted) return;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LLStrings.of(context).lessonMissing)),
      );
      await _reload();
      return;
    }
    if (widget.onOpenLesson != null) {
      // Shell navigation (V2 §四): hand the lesson to the Listen tab. The
      // shell owns the session so switching tabs never rebuilds it.
      widget.onOpenLesson!(item, data.sentences);
      return;
    }
    final builder =
        widget.listeningScreenBuilder ?? _defaultListeningScreenBuilder;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => builder(context, item, data.sentences),
      ),
    );
    // Returning from the listening screen may have advanced the progress.
    await _reload();
  }

  Widget _defaultListeningScreenBuilder(
    BuildContext context,
    LessonWithProgress item,
    List<Sentence> sentences,
  ) {
    final progress = item.progress;
    SubtitleMode? restoredSubtitleMode;
    if (progress != null) {
      for (final mode in SubtitleMode.values) {
        if (mode.name == progress.subtitleMode) restoredSubtitleMode = mode;
      }
    }
    return ListeningScreen(
      title: item.lesson.title,
      language: item.lesson.language,
      sentences: sentences,
      audioAsset: item.lesson.audioPath,
      audioIsFile: true,
      lessonId: item.lesson.id,
      repository: widget.repository,
      coverPath: item.lesson.coverPath,
      // Phase 3B: lessons that carry a video source play in the embedded
      // web player; the rest keep the audio-only path unchanged.
      videoSource: item.lesson.video,
      // V0.2.1 恢复学习：回到上次句子 + 自动播放 + 恢复各偏好。
      initialSentenceIndex: progress?.lastSentenceIndex ?? 0,
      autoPlay: true,
      initialRepeatTarget: progress?.repeatTarget ?? 1,
      initialPlaybackRate: progress?.playbackRate ?? 1.0,
      initialSubtitleMode: restoredSubtitleMode?.name,
      initialPageMode: progress?.displayMode == 'page',
    );
  }

  Future<void> _openWeaknessTarget(WeaknessRecord record) async {
    final items = _items ?? [];
    if (items.isEmpty) return;
    final targetItem = items.firstWhere(
      (item) => item.lesson.id == record.lessonId,
      orElse: () => items.first,
    );
    final data = await widget.repository.getLessonWithSentences(targetItem.lesson.id);
    if (!mounted || data == null) return;

    if (widget.onOpenLesson != null) {
      widget.onOpenLesson!(targetItem, data.sentences);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          final progress = targetItem.progress;
          return ListeningScreen(
            title: targetItem.lesson.title,
            language: targetItem.lesson.language,
            sentences: data.sentences,
            audioAsset: targetItem.lesson.audioPath,
            audioIsFile: true,
            lessonId: targetItem.lesson.id,
            repository: widget.repository,
            coverPath: targetItem.lesson.coverPath,
            videoSource: targetItem.lesson.video,
            initialSentenceIndex: record.sentenceIndex,
            autoPlay: true,
            initialRepeatTarget: progress?.repeatTarget ?? 1,
            initialPlaybackRate: progress?.playbackRate ?? 1.0,
            initialSubtitleMode: progress?.subtitleMode,
            initialPageMode: progress?.displayMode == 'page',
            aiGovernorService: _aiGovernorService,
          );
        },
      ),
    );
    await _reload();
  }

  // --------------------------------------------------- long-press menu --

  Future<void> _showLessonMenu(LessonWithProgress item) async {
    final s = LLStrings.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.ll.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(s.info),
              onTap: () => Navigator.of(sheetContext).pop('info'),
            ),
            ListTile(
              title: Text(s.deleteLessonMenu),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'info') {
      _showLessonInfo(item);
    } else if (action == 'delete') {
      await _confirmDelete(item);
    }
  }

  void _showLessonInfo(LessonWithProgress item) {
    final lesson = item.lesson;
    final s = LLStrings.of(context);
    final minutes = lesson.durationMs ~/ 60000;
    final seconds = (lesson.durationMs % 60000) ~/ 1000;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.ll.surface,
        title: Text(lesson.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.lessonIdLabel}: ${lesson.id}'),
            Text('${s.sentenceCountLabel}: ${lesson.sentenceCount}'),
            Text(
              '${s.audioDurationLabel}: '
              '${s.audioDurationMinSec(minutes, seconds)}',
            ),
            Text(
              '${s.importedAtLabel}: '
              '${lesson.importedAt.year}-${lesson.importedAt.month}-${lesson.importedAt.day}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(LessonWithProgress item) async {
    // §三十九: quiet, monochrome, honest about the consequence.
    final s = LLStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.ll.surface,
        title: Text(s.deleteTitle),
        content: Text(s.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.ll.textPrimary,
              foregroundColor: dialogContext.ll.bg,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteLesson(item.lesson.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(LLStrings.of(context).deleted(item.lesson.title))),
    );
    await _reload();
  }

  // -------------------------------------------------------------- build ----

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final ll = context.ll;
    return Scaffold(
      backgroundColor: ll.bg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: llSystemOverlay(ll.brightness),
        child: SafeArea(
          child: items == null
              ? const Center(child: LLInfinityLoader())
              : _buildBody(context, items),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<LessonWithProgress> items) {
    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          _buildCreationBanner(context),
          _buildAnkiBanner(context),
        _buildVocabularyEntry(context),
          Expanded(child: _EmptyLibrary(onImport: _onImportPressed)),
        ],
      );
    }

    final languages = _extractLanguages(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        _buildCreationBanner(context),
        _buildAnkiBanner(context),
        _buildVocabularyEntry(context),
        if (languages.length >= 2) ...[
          LessonLanguageTabs(
            languages: languages,
            selectedLanguage: _selectedLanguage,
            onSelectLanguage: (lang) => setState(() => _selectedLanguage = lang),
          ),
          const SizedBox(height: LLSpacing.xs),
        ],
        Expanded(child: _buildList(context, items)),
      ],
    );
  }

  List<String> _extractLanguages(List<LessonWithProgress> items) {
    final langs = <String>{};
    for (final item in items) {
      langs.add(SubtitleModeX.resolveLanguageCode(item.lesson.language));
    }
    final sorted = langs.toList()..sort();
    return ['ALL', ...sorted];
  }

  Widget _buildCreationBanner(BuildContext context) {
    final c = widget.creationController;
    if (!c.hasActiveOrRecentJob) return const SizedBox.shrink();
    final ll = context.ll;
    final s = LLStrings.of(context);

    if (c.isBusy) {
      final inputName =
          c.currentInput?.source ?? c.currentInput?.titleHint ?? '';
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          LLSpacing.xl,
          0,
          LLSpacing.xl,
          LLSpacing.sm,
        ),
        child: InkWell(
          onTap: () {
            if (widget.onOpenCreationTab != null) {
              widget.onOpenCreationTab!();
            } else {
              _openCreationScreen();
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: ll.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ll.divider),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: LLInfinityLoader(size: 14),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '正在制作课程 · ${s.stageName(c.stage)} (${(c.stageProgress * 100).round()}%)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ll.textPrimary,
                        ),
                      ),
                      if (inputName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          inputName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: ll.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '查看进度',
                  style: TextStyle(fontSize: 12, color: ll.textSecondary),
                ),
                Icon(Icons.chevron_right, size: 16, color: ll.textTertiary),
              ],
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// 生词本入口（Library 二级）。
  ///
  /// 只在**已有生词**时出现：空生词本不该在课程列表上占一行
  /// （新用户的第一条引导在积累模式的提示里）。行上直接给出
  /// 「候选 / 今日待练」两个数字，不必点进去才能看出有没有事要做。
  Widget _buildVocabularyEntry(BuildContext context) {
    final store = _vocabularyStore;
    if (store.itemCount == 0) return const SizedBox.shrink();
    final ll = context.ll;
    final s = LLStrings.of(context);
    final plan = const VocabularyPlanner().build(store.items);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LLSpacing.xl,
        0,
        LLSpacing.xl,
        LLSpacing.sm,
      ),
      child: InkWell(
        key: const Key('vocabulary-entry'),
        onTap: _openVocabularyBook,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ll.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ll.divider),
          ),
          child: Row(
            children: [
              Icon(
                Icons.bookmark_border_rounded,
                size: 17,
                color: ll.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.vocabBook,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ll.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.isEmpty
                          ? s.vocabCandidateCount(store.candidateCount)
                          : '${s.vocabCandidateCount(store.candidateCount)} · '
                                '${s.vocabTodayPlan} ${plan.length}',
                      style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: ll.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openVocabularyBook() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VocabularyBookScreen(
          store: _vocabularyStore,
          onOpenOccurrence: _openVocabularyOccurrence,
        ),
      ),
    );
  }

  /// 「回原声」：定位到该证据所在的课程与句子。
  ///
  /// 附属功能的失败路径必须安静收场（08 红线：附属失败不得阻塞核心）——
  /// 课程已被删除时只给一句提示，不抛异常、不弹错误框。
  Future<void> _openVocabularyOccurrence(VocabularyOccurrence occurrence) async {
    final items = _items ?? const <LessonWithProgress>[];
    LessonWithProgress? target;
    for (final item in items) {
      if (item.lesson.id == occurrence.lessonId) {
        target = item;
        break;
      }
    }
    if (target == null) {
      _toast(LLStrings.of(context).vocabLessonMissing);
      return;
    }

    final data = await widget.repository.getLessonWithSentences(
      target.lesson.id,
    );
    if (!mounted || data == null) return;
    if (data.sentences.isEmpty) return;

    // 句子下标以存档为准，越界时夹到合法范围（课程被重新导入过的情况）。
    final index = occurrence.sentenceIndex.clamp(0, data.sentences.length - 1);

    if (widget.onOpenLessonAtSentence != null) {
      widget.onOpenLessonAtSentence!(target, data.sentences, index);
      return;
    }

    final builder = widget.listeningScreenBuilder;
    if (builder != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => builder(context, target!, data.sentences),
        ),
      );
      return;
    }

    final progress = target.progress;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ListeningScreen(
          title: target!.lesson.title,
          language: target.lesson.language,
          sentences: data.sentences,
          audioAsset: target.lesson.audioPath,
          audioIsFile: true,
          lessonId: target.lesson.id,
          repository: widget.repository,
          coverPath: target.lesson.coverPath,
          videoSource: target.lesson.video,
          initialSentenceIndex: index,
          autoPlay: true,
          initialRepeatTarget: progress?.repeatTarget ?? 1,
          initialPlaybackRate: progress?.playbackRate ?? 1.0,
          initialSubtitleMode: progress?.subtitleMode,
          initialPageMode: progress?.displayMode == 'page',
        ),
      ),
    );
    await _reload();
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildAnkiBanner(BuildContext context) {
    final cards = _aiGovernorService.ankiCards;
    if (cards.isEmpty) return const SizedBox.shrink();
    final dueCards = _aiGovernorService.dueAnkiCards;
    final ll = context.ll;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LLSpacing.xl,
        0,
        LLSpacing.xl,
        LLSpacing.sm,
      ),
      child: InkWell(
        onTap: () {
          final queue = dueCards.isNotEmpty ? dueCards : cards;
          AnkiReviewDialog.show(
            context: context,
            cards: queue,
            aiGovernorService: _aiGovernorService,
            onPlaySnippet: (start, end) async {
              if (queue.isNotEmpty) {
                final card = queue.first;
                final items = _items ?? [];
                final target = items.firstWhere(
                  (it) => it.lesson.id == card.lessonId,
                  orElse: () => items.first,
                );
                final data = await widget.repository.getLessonWithSentences(target.lesson.id);
                if (data != null && widget.onOpenLesson != null) {
                  widget.onOpenLesson!(target, data.sentences);
                }
              }
            },
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ll.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ll.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.style_outlined, size: 16, color: Colors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Anki · AI 艾宾浩斯复习',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ll.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dueCards.isNotEmpty
                          ? '今日待复习 ${dueCards.length} 句 · 点击开启强化'
                          : '全库已收录 ${cards.length} 句 · 记忆曲线保持良好',
                      style: TextStyle(fontSize: 11, color: ll.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (dueCards.isNotEmpty ? Colors.orangeAccent : Colors.green)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  dueCards.isNotEmpty ? '待复习' : '已就绪',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: dueCards.isNotEmpty ? Colors.orangeAccent : Colors.green,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: ll.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  /// §十三: wordmark, view toggle, and import button.
  Widget _buildHeader(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final isGridView = _effectiveGridView(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LLSpacing.xl,
        LLSpacing.lg,
        LLSpacing.xl,
        LLSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            'ListenLoop',
            style: LLText.appTitle.copyWith(color: ll.textPrimary),
          ),
          const Spacer(),
          IconButton(
            key: const Key('view-toggle-button'),
            onPressed: _toggleView,
            tooltip: isGridView ? s.viewList : s.viewGrid,
            icon: Icon(
              isGridView
                  ? Icons.view_headline_outlined
                  : Icons.grid_view_outlined,
              size: 20,
              color: ll.textSecondary,
            ),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: LLSpacing.xs),
          TextButton(
            key: const Key('import-button'),
            onPressed: _onAddPressed,
            style: TextButton.styleFrom(
              foregroundColor: ll.textPrimary,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('＋'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<LessonWithProgress> items) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final isGridView = _effectiveGridView(context);
    LessonWithProgress? continueItem;
    for (final item in items) {
      final progress = item.progress;
      if (progress == null) continue;
      if (continueItem == null ||
          progress.updatedAt.isAfter(continueItem.progress!.updatedAt)) {
        continueItem = item;
      }
    }

    final continueTarget = continueItem;
    final showContinue =
        continueTarget != null &&
        (_selectedLanguage == 'ALL' ||
            SubtitleModeX.resolveLanguageCode(continueTarget.lesson.language) ==
                _selectedLanguage);

    final filteredItems = [
      for (final item in items)
        if (_selectedLanguage == 'ALL' ||
            SubtitleModeX.resolveLanguageCode(item.lesson.language) ==
                _selectedLanguage)
          item,
    ];

    final others = [
      for (final item in filteredItems)
        if (!showContinue || item != continueTarget) item,
    ];

    return CustomScrollView(
      slivers: [
        // 🎯 智能管家动态插槽卡片 (AI Governor Dynamic Slot)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            LLSpacing.xl,
            LLSpacing.md,
            LLSpacing.xl,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _DynamicAiGovernorCard(
              aiGovernorService: _aiGovernorService,
              onTapWeakness: (record) => _openWeaknessTarget(record),
              onStartChallenge: () {
                if (continueTarget != null) {
                  _openLesson(continueTarget);
                } else if (items.isNotEmpty) {
                  _openLesson(items.first);
                }
              },
            ),
          ),
        ),
        if (showContinue) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              LLSpacing.xl,
              LLSpacing.xl,
              LLSpacing.xl,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.continueLearning,
                    style: LLText.sectionLabel.copyWith(color: ll.textTertiary),
                  ),
                  const SizedBox(height: LLSpacing.md),
                  LessonContinueCard(
                    key: const Key('continue-card'),
                    item: continueTarget,
                    onTap: () => _openLesson(continueTarget),
                    onLongPress: () => _showLessonMenu(continueTarget),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (others.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              LLSpacing.xl,
              LLSpacing.xxl,
              LLSpacing.xl,
              LLSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                s.allLessons,
                style: LLText.sectionLabel.copyWith(color: ll.textTertiary),
              ),
            ),
          ),
          if (isGridView)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: LLSpacing.xl),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: LLSpacing.md,
                  mainAxisSpacing: LLSpacing.lg,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => LessonPosterCard(
                    key: Key('lesson-card-${others[i].lesson.id}'),
                    item: others[i],
                    onTap: () => _openLesson(others[i]),
                    onLongPress: () => _showLessonMenu(others[i]),
                  ),
                  childCount: others.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: LLSpacing.xl),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final itemIndex = i ~/ 2;
                    if (i.isOdd) {
                      return Divider(color: ll.divider);
                    }
                    final item = others[itemIndex];
                    return LessonEditorialRow(
                      key: Key('lesson-card-${item.lesson.id}'),
                      index: itemIndex,
                      item: item,
                      onTap: () => _openLesson(item),
                      onLongPress: () => _showLessonMenu(item),
                    );
                  },
                  childCount: others.length * 2 - 1,
                ),
              ),
            ),
        ] else if (!showContinue) ...[
          SliverPadding(
            padding: const EdgeInsets.all(LLSpacing.xxl),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: Text(
                  s.noLessonsInLanguage,
                  style: TextStyle(color: ll.textTertiary, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
        const SliverPadding(
          padding: EdgeInsets.only(bottom: LLSpacing.huge + LLSpacing.xl),
        ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    return Center(
      child: Column(
        key: const Key('empty-state'),
        mainAxisSize: MainAxisSize.min,
        children: [
          LLMark(size: 56, color: ll.textTertiary),
          const SizedBox(height: LLSpacing.lg),
          Text(
            s.noLessonsTitle,
            style: LLText.rowTitle.copyWith(color: ll.textPrimary),
          ),
          const SizedBox(height: LLSpacing.sm),
          Text(
            s.noLessonsBody,
            style: LLText.caption.copyWith(color: ll.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LLSpacing.xl),
          OutlinedButton(
            onPressed: onImport,
            style: OutlinedButton.styleFrom(
              foregroundColor: ll.textPrimary,
              side: BorderSide(color: ll.textPrimary),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(
                horizontal: LLSpacing.xl,
                vertical: LLSpacing.md,
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(s.importLesson),
          ),
        ],
      ),
    );
  }
}

/// 转写档位选择（2026-09-18 用户拍板：Whisper 双档，多语言模型）。
/// 快速档 = base（快），精确档 = small（高精度）。选择即时持久化，
/// 对下一次制课生效；运行中的任务不受影响。
class _AsrTierSelector extends StatelessWidget {
  const _AsrTierSelector();

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesScope.maybeOf(context);
    final controller = PreferencesScope.of(context);
    final current = prefs.asrTier;
    final subtitle = current == AsrTier.fast
        ? 'Whisper base · 速度快，日常使用'
        : 'Whisper small · 更高的转写精度';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('转写档位', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SegmentedButton<AsrTier>(
            segments: const [
              ButtonSegment(
                value: AsrTier.fast,
                icon: Icon(Icons.bolt_outlined),
                label: Text('快速档'),
              ),
              ButtonSegment(
                value: AsrTier.precise,
                icon: Icon(Icons.auto_awesome_outlined),
                label: Text('精确档'),
              ),
            ],
            selected: {current},
            onSelectionChanged: (selection) {
              controller.update(asrTier: selection.first);
            },
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

class _DynamicAiGovernorCard extends StatelessWidget {
  const _DynamicAiGovernorCard({
    required this.aiGovernorService,
    required this.onTapWeakness,
    required this.onStartChallenge,
  });

  final AiGovernorService aiGovernorService;
  final void Function(WeaknessRecord record) onTapWeakness;
  final VoidCallback onStartChallenge;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final weaknesses = aiGovernorService.unresolvedWeaknesses;

    if (weaknesses.isNotEmpty) {
      final latest = weaknesses.first;
      return Container(
        margin: const EdgeInsets.only(bottom: LLSpacing.md),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ll.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ll.divider, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const LLMark(size: 14),
                const SizedBox(width: 8),
                Text(
                  '智能管家 · 今日精听弱点',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ll.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${weaknesses.length} 处待巩固',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '「${latest.sentenceText}」',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ll.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              latest.reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: ll.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: ll.textPrimary.withValues(alpha: 0.08),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 14),
                  label: const Text('🔥 针对性重听原声 →', style: TextStyle(fontSize: 12)),
                  onPressed: () => onTapWeakness(latest),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // When no weaknesses: show 尚雯婕 3-minute sprint card
    return Container(
      margin: const EdgeInsets.only(bottom: LLSpacing.md),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ll.divider, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ll.textPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flash_on, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '尚雯婕 3 分钟限时精听法',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ll.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '学完即测 3 题，以测代练，专克听力盲区。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ll.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onStartChallenge,
            child: const Text('开始 →', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}


