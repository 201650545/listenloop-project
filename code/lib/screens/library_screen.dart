import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../anki/apkg_exporter.dart';
import '../anki/apkg_share.dart';
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
import '../models/anki_card_model.dart';
import '../models/lesson.dart';
import '../models/vocabulary_model.dart';
import '../models/sentence.dart';
import '../preferences/app_preferences.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';
import '../training/vocabulary_plan.dart';
import '../widgets/library/lesson_editorial_row.dart';
import '../widgets/library/lesson_language_tabs.dart';
import '../widgets/library/lesson_poster_card.dart';
import '../widgets/ll_brand.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/primary_chinese_curriculum.dart';
import '../widgets/chinese_mind_map_view.dart';
import '../widgets/subtitle_mode_selector.dart' show SubtitleMode, SubtitleModeX;
import 'ai_speaking_sandbox_screen.dart';
import 'listening_screen.dart';
import 'primary_chinese_catalog_screen.dart';
import 'vocabulary_book_screen.dart';
import 'vocabulary_review_screen.dart';
import '../widgets/ll_page.dart';

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
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final Set<String> _expandedSeries = {};
  bool _importing = false;
  String _selectedLanguage = 'EN';
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

  // 中文课程记忆与锁定状态（持久化于 SharedPreferences）
  int _chineseSelectedGrade = 2;
  String _chineseSelectedTerm = '上册';
  bool _isChineseGradeLocked = false;

  late final AiGovernorService _aiGovernorService =
      widget.aiGovernorService ?? AiGovernorService();

  late final VocabularyStore _vocabularyStore =
      widget.vocabularyStore ?? VocabularyStore();

  @override
  void initState() {
    super.initState();
    _reload();
    _loadChineseGradePreferences();
    _vocabularyStore.addListener(_onVocabularyChanged);
    if (widget.vocabularyStore == null) {
      unawaited(_vocabularyStore.load());
    }
    widget.creationController.addListener(_onCreationChanged);
    _aiGovernorService.addListener(_onAiGovernorChanged);
  }

  Future<void> _loadChineseGradePreferences() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _chineseSelectedGrade = sp.getInt('listenloop:chinese_selected_grade') ?? 2;
        _chineseSelectedTerm = sp.getString('listenloop:chinese_selected_term') ?? '上册';
        _isChineseGradeLocked = sp.getBool('listenloop:chinese_grade_locked') ?? false;
      });
    } catch (_) {}
  }

  Future<void> _updateChineseGrade({int? grade, String? term, bool? locked}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (grade != null) {
        _chineseSelectedGrade = grade;
        await sp.setInt('listenloop:chinese_selected_grade', grade);
      }
      if (term != null) {
        _chineseSelectedTerm = term;
        await sp.setString('listenloop:chinese_selected_term', term);
      }
      if (locked != null) {
        _isChineseGradeLocked = locked;
        await sp.setBool('listenloop:chinese_grade_locked', locked);
      }
      if (mounted) setState(() {});
    } catch (_) {}
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
    _searchController.dispose();
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

  Future<void> openCloudCatalog() => _openCloudCatalog();

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
      // 菜单项会随语言/功能开关增减（中文下多出「在线课程库」一项），
      // 固定高度会让 Column 在窄屏/大字号下溢出（实测小米14 报
      // "BOTTOM OVERFLOWED BY 123 PIXELS"）。用可滚动容器兜住，
      // 内容不超高时行为与原来一致。
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _AsrTierSelector(),
                if (_selectedLanguage == 'ZH')
                  ListTile(
                    leading: const Icon(Icons.cloud_download_rounded, color: Colors.blueAccent),
                    title: const Text('在线课程库 (云端下载)'),
                    subtitle: const Text('小学语文 1~6  · 名师原声朗读 · 免数据线'),
                    onTap: () => Navigator.of(sheetContext).pop('cloud'),
                  ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.orange),
                  title: const Text('制作新课程 (二级页面)'),
                  subtitle: const Text('从音视频或链接创建 · ASR识别 · 课文切句'),
                  onTap: () => Navigator.of(sheetContext).pop('create-screen'),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(s.creationMenuImport),
                  subtitle: const Text('导入 .lllesson 课程包'),
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
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'cloud':
        await _openCloudCatalog();
      case 'create-screen':
        await _openCreationScreen();
      case 'import':
        await _onImportPressed();
      case 'create-file':
        await _onCreateFromFile();
      case 'create-link':
        await _onCreateFromLink();
    }
  }

  Future<void> _openCloudCatalog([String? query, int? grade, String? term]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PrimaryChineseCatalogScreen(
          repository: widget.repository,
          initialQuery: query,
          initialGrade: grade ?? _chineseSelectedGrade,
          initialTerm: term ?? _chineseSelectedTerm,
          onLessonImported: (_) async {
            await _reload();
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
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
          onImportLessonPackage: _onImportPressed,
          onOpenCloudCatalog: _openCloudCatalog,
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
      initialPageMode: progress?.displayMode != null
          ? (progress!.displayMode == 'page')
          : null,
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
            initialPageMode: progress?.displayMode != null
                ? (progress!.displayMode == 'page')
                : null,
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
    return LLPage(
      body: items == null
          ? const Center(child: LLInfinityLoader())
          : _buildBody(context, items),
    );
  }

  Widget _buildBody(BuildContext context, List<LessonWithProgress> items) {
    final languages = _extractLanguages(items);
    final isChineseTab = _selectedLanguage == 'ZH';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        // 全局搜索置顶：课程页最顶部，无论是否有课程或课程多少都永久可见
        _buildSearchField(context),
        // 筛选标签栏（[ 英文 | 中文 ] 黑白极简）与中文模式下的正方形课程库入口
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LLSpacing.xl,
            0,
            LLSpacing.xl,
            LLSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: LessonLanguageTabs(
                  languages: languages,
                  selectedLanguage: _selectedLanguage,
                  onSelectLanguage: (lang) =>
                      setState(() => _selectedLanguage = lang),
                  padding: EdgeInsets.zero,
                ),
              ),
              if (isChineseTab) ...[
                const SizedBox(width: LLSpacing.sm),
                _buildSquareOnlineCatalogCard(context),
              ],
            ],
          ),
        ),
        if (isChineseTab) ...[
          if (_searchQuery.trim().isNotEmpty)
            _buildChineseSearchJumpBar(context),
          _buildChineseGradeHeader(context),
          Expanded(
            child: ChineseMindMapView(
              grade: _chineseSelectedGrade,
              term: _chineseSelectedTerm,
              searchQuery: _searchQuery,
              importedLessonTitles:
                  _items?.map((e) => e.lesson.title).toSet() ?? const {},
              onLessonTap: _openChineseLessonFromMindMap,
            ),
          ),
        ] else ...[
          _buildCreationBanner(context),
          _buildAnkiBanner(context),
          _buildVocabularyEntry(context),
          Expanded(
            child: _buildList(context, items),
          ),
        ],
      ],
    );
  }

  /// 语文在线课程库入口（黑白极简正方形按钮，置于标签栏右侧）
  Widget _buildSquareOnlineCatalogCard(BuildContext context) {
    final ll = context.ll;
    return Tooltip(
      message: '语文课程库',
      child: InkWell(
        key: const Key('online-catalog-button'),
        onTap: () =>
            _openCloudCatalog(_searchQuery.isNotEmpty ? _searchQuery : null),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 44,
          height: 36,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          decoration: BoxDecoration(
            color: ll.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: ll.divider.withValues(alpha: 0.8),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories_outlined,
                color: ll.textPrimary,
                size: 16,
              ),
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '课程库',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: ll.textPrimary,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// AI 英语听说实验舱 · 创意区入口横幅（黑白极简风格）
  Widget _buildSpeakingSandboxBanner(BuildContext context) {
    final ll = context.ll;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LLSpacing.xl,
        LLSpacing.xs,
        LLSpacing.xl,
        LLSpacing.sm,
      ),
      child: InkWell(
        key: const Key('ai-speaking-sandbox-banner'),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AiSpeakingSandboxScreen(
                aiGovernorService: _aiGovernorService,
                vocabularyStore: _vocabularyStore,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: ll.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ll.divider, width: 0.9),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ll.textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: ll.textPrimary.withValues(alpha: 0.15),
                    width: 0.8,
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: ll.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'AI 英语听说实验舱',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ll.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: ll.textPrimary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '创意区',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: ll.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AI 生成情境 · 地道母语润色 · 连读失爆深度拆解',
                      style: TextStyle(
                        fontSize: 11,
                        color: ll.textTertiary,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: ll.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 中文导图搜索跨直达药丸栏
  Widget _buildChineseSearchJumpBar(BuildContext context) {
    final ll = context.ll;
    final results = PrimaryChineseCurriculum.search(_searchQuery);
    if (results.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LLSpacing.xl,
        0,
        LLSpacing.xl,
        LLSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ll.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ll.divider, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(Icons.near_me_outlined, size: 14, color: ll.textSecondary),
            const SizedBox(width: 6),
            Text(
              '导图直达 ()：',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ll.textSecondary,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final lesson in results)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () {
                            _updateChineseGrade(
                              grade: lesson.grade,
                              term: lesson.term,
                            );
                            setState(() {
                              _searchQuery = lesson.displayTitle;
                              _searchController.text = lesson.displayTitle;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (_chineseSelectedGrade == lesson.grade &&
                                      _chineseSelectedTerm == lesson.term)
                                  ? ll.textPrimary
                                  : ll.textPrimary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              ' · ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: (_chineseSelectedGrade == lesson.grade &&
                                        _chineseSelectedTerm == lesson.term)
                                    ? ll.bg
                                    : ll.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 中文与分册控制栏（支持记忆选择、一键锁定常用，黑白极简）
  Widget _buildChineseGradeHeader(BuildContext context) {
    final ll = context.ll;
    const grades = [
      (1, '一'),
      (2, '二'),
      (3, '三'),
      (4, '四'),
      (5, '五'),
      (6, '六'),
      (7, '七'),
      (8, '八'),
      (9, '九'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LLSpacing.xl,
        LLSpacing.xs,
        LLSpacing.xl,
        LLSpacing.xs,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: ll.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ll.divider, width: 0.8),
        ),
        child: _isChineseGradeLocked
            ? Row(
                children: [
                  Icon(Icons.push_pin_rounded, size: 14, color: ll.textPrimary),
                  const SizedBox(width: 8),
                  // 360dp 下这一行原本三段都不可缩容，实测内容 302px > 容器 284px
                  // 直接出红条（doc 21 §五）。"我的："与右侧"已锁定"徽标重复，
                  // 去掉前缀后 382dp 真机上标题不再被截成"我的…"。
                  Flexible(
                    child: Text(
                      '$_chineseSelectedGrade  · $_chineseSelectedTerm',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LLText.cardTitle.copyWith(color: ll.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: ll.emphasis,
                      borderRadius: BorderRadius.circular(LLRadius.xsmall),
                    ),
                    child: Text(
                      '已锁定',
                      style: LLText.badge.copyWith(
                        color: ll.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => _updateChineseGrade(locked: false),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 14, color: ll.textSecondary),
                          const SizedBox(width: 3),
                          Text(
                            '更换',
                            style: TextStyle(
                              fontSize: 12,
                              color: ll.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 1 到 9 横向微型药丸选择器
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (g, name) in grades) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => _updateChineseGrade(grade: g),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _chineseSelectedGrade == g
                                      ? ll.textPrimary
                                      : ll.textPrimary.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _chineseSelectedGrade == g
                                        ? ll.textPrimary
                                        : ll.divider,
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _chineseSelectedGrade == g
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: _chineseSelectedGrade == g
                                        ? ll.bg
                                        : ll.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 2. 分册切换与锁定按钮
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ll.textPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '语文',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ll.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 上册 / 下册药丸切换
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: ll.textPrimary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ll.divider, width: 0.6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final term in ['上册', '下册'])
                              GestureDetector(
                                key: Key(term == '上册' ? 'wheel-shangce' : 'wheel-xiace'),
                                onTap: () => _updateChineseGrade(term: term),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _chineseSelectedTerm == term
                                        ? ll.surface
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: _chineseSelectedTerm == term
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.05),
                                              blurRadius: 3,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    term,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: _chineseSelectedTerm == term
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: _chineseSelectedTerm == term
                                          ? ll.textPrimary
                                          : ll.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // 设为我的（锁定）
                      InkWell(
                        onTap: () {
                          _updateChineseGrade(locked: true);
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  '已将 $_chineseSelectedGrade · $_chineseSelectedTerm 设为默认',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.push_pin_outlined,
                                size: 13,
                                color: ll.textPrimary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '锁定为我的',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: ll.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// 点击思维导图上的课文：秒进精听播放
  Future<void> _openChineseLessonFromMindMap(PrimaryChineseLesson lesson) async {
    final clean = lesson.displayTitle;
    final items = _items ?? [];
    LessonWithProgress? match;

    // 1. 若具有确定的 lessonId，必须【绝对优先】且【仅按】lessonId 精确匹配
    if (lesson.lessonId != null) {
      for (final item in items) {
        if (item.lesson.id == lesson.lessonId) {
          match = item;
          break;
        }
      }
    }

    // 2. 仅在未配置 lessonId 时，才退化为标题匹配，但泛用短标题绝不允许跨单元模糊匹配
    if (match == null && lesson.lessonId == null) {
      const genericNames = {'识字加油站', '字词句运用', '日积月累', '我爱阅读', '书写提示', '和大人一起读'};
      for (final item in items) {
        final t = item.lesson.title;
        if (!genericNames.contains(clean)) {
          if (t == lesson.title || t == lesson.fullTitle || t.contains(clean)) {
            match = item;
            break;
          }
        } else {
          if (t == lesson.title || t == lesson.fullTitle) {
            match = item;
            break;
          }
        }
      }
    }

    if (match != null) {
      await _openLesson(match);
      return;
    }

    // 3. 若本地未导入但已配置云端 lessonId：秒速直接从云端下载并立即自动秒进播放！
    if (lesson.lessonId != null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text('正在从云端加载《${lesson.numberedTitle()}》...'),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );

      try {
        final downloadUrl = 'http://123.57.84.97:3100/courses/${lesson.lessonId}.lllesson';
        final res = await http.get(Uri.parse(downloadUrl)).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(p.join(tempDir.path, 'quick_${lesson.lessonId}.lllesson'));
          await tempFile.writeAsBytes(res.bodyBytes);

          final package = await LessonPackageReader.read(tempFile.path);
          final imported = await widget.repository.importPackage(package);
          await _reload();

          messenger.hideCurrentSnackBar();
          if (mounted) {
            await _openLesson(LessonWithProgress(lesson: imported, progress: null));
          }
          return;
        }
      } catch (e) {
        // 下载失败或无网络，平滑降级进入课程库对应分册
      }
    }

    // 4. 若未录入或下载失败，直接定位打开课程库对应年级分册（绝不传 generic 短词做全局搜索）
    _openCloudCatalog(null, lesson.grade, lesson.term);
  }

  /// 全局课程搜索（置于课程页面顶部）。
  /// 按标题/系列名过滤，实时生效。
  Widget _buildSearchField(BuildContext context) {
    final ll = context.ll;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LLSpacing.xl,
        LLSpacing.xs,
        LLSpacing.xl,
        LLSpacing.sm,
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(fontSize: 13, color: ll.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: '', // 2026-10-20 郭老师：搜索框灰色提示字是废话，删掉
          hintStyle: TextStyle(fontSize: 13, color: ll.textTertiary),
          prefixIcon: Icon(Icons.search, size: 18, color: ll.textTertiary),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 16, color: ll.textTertiary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: ll.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: ll.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: ll.divider),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
        onSubmitted: (value) {
          final isZh = _selectedLanguage == 'ZH';
          if (isZh && value.trim().isNotEmpty) {
            final matches = PrimaryChineseCurriculum.search(value);
            if (matches.isNotEmpty) {
              final first = matches.first;
              _updateChineseGrade(grade: first.grade, term: first.term);
              setState(() {
                _searchQuery = first.displayTitle;
                _searchController.text = first.displayTitle;
              });
            }
          }
        },
      ),
    );
  }

  List<String> _extractLanguages(List<LessonWithProgress> items) {
    final langs = <String>{'EN', 'ZH'};
    for (final item in items) {
      final code = SubtitleModeX.resolveLanguageCode(item.lesson.language);
      if (code.isNotEmpty) langs.add(code);
    }
    final others = langs.where((l) => l != 'ZH' && l != 'EN').toList()..sort();
    return ['EN', 'ZH', ...others];
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

  /// 「词汇记忆」双卡区块（14 号 §三）：生词本 | 闪卡复习。
  ///
  /// 只在已有生词时出现。生词本卡给「候选 / 今日待练」计数；闪卡复习卡
  /// 给「待复习 N 张」徽标（与复习页队列同口径：FSRS 到期 + 新卡配额），
  /// 零到期时弱态「今日复习已完成」。两卡路由分离；复习与生词本页内
  /// 快捷入口同一路由（两处都留）。
  Widget _buildVocabularyEntry(BuildContext context) {
    final store = _vocabularyStore;
    if (store.itemCount == 0) return const SizedBox.shrink();
    final plan = const VocabularyPlanner().build(store.items);
    final dueCount = const VocabularyReviewQueue().build(store.items).length;
    final reviewable = store.items.any(
      (it) =>
          it.status == VocabularyStatus.learning ||
          it.status == VocabularyStatus.known,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LLSpacing.xl,
        0,
        LLSpacing.xl,
        LLSpacing.sm,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _vocabEntryCard(
                context,
                key: const Key('vocabulary-entry'),
                icon: Icons.bookmark_border_rounded,
                title: LLStrings.of(context).vocabBook,
                subtitle: plan.isEmpty
                    ? LLStrings.of(
                        context,
                      ).vocabCandidateCount(store.candidateCount)
                    : '${LLStrings.of(context).vocabCandidateCount(store.candidateCount)} · '
                          '${LLStrings.of(context).vocabTodayPlan} ${plan.length}',
                onTap: _openVocabularyBook,
              ),
            ),
            if (reviewable) ...[
              const SizedBox(width: LLSpacing.sm),
              Expanded(
                child: _vocabEntryCard(
                  context,
                  key: const Key('review-entry'),
                  icon: Icons.style_rounded,
                  title: LLStrings.of(context).reviewEntryTitle,
                  subtitle: dueCount > 0
                      ? LLStrings.of(context).reviewEntryDue(dueCount)
                      : LLStrings.of(context).reviewEntryDone,
                  dimmed: dueCount == 0,
                  onTap: _openFlashcardReview,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 「词汇记忆」区块的单张卡片（14 号 §四：紧凑二级区块，
  /// 视觉权重低于「继续精听」核心 CTA）。
  Widget _vocabEntryCard(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    bool dimmed = false,
    required VoidCallback onTap,
  }) {
    final ll = context.ll;
    return InkWell(
      key: key,
      onTap: onTap,
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
              icon,
              size: 17,
              color: dimmed ? ll.textTertiary : ll.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: dimmed ? ll.textSecondary : ll.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: dimmed ? ll.textTertiary : ll.textSecondary,
                    ),
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
    );
  }

  /// 闪卡复习 —— 与生词本页内快捷入口进入**同一个**复习页
  /// （14 号 §三：两入口零语义差异，队列同一份）。
  Future<void> _openFlashcardReview() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VocabularyReviewScreen(
          store: _vocabularyStore,
          onOpenOccurrence: _openVocabularyOccurrence,
          aiGovernorService: _aiGovernorService,
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
          // AI 检查通道（可选）：Library 本来就持有 governor（AI 管家卡）。
          aiGovernorService: _aiGovernorService,
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
          initialPageMode: progress?.displayMode != null
              ? (progress!.displayMode == 'page')
              : null,
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
        onTap: () => _exportLegacyAnkiCards(cards),
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
                      '旧版闪卡 · 导出到 Anki',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ll.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dueCards.isNotEmpty
                          ? '全库 ${cards.length} 句（${
                              dueCards.length
                            } 张到期）· 旧体系已下线，点击导出 .apkg'
                          : '全库已收录 ${cards.length} 句 · 旧体系已下线，点击导出 .apkg',
                      style: TextStyle(fontSize: 11, color: ll.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '导出',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
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

  /// 旧闪卡的出路：转成 .apkg（复用 [buildApkgBytes]，与生词本导出同一
  /// 管线），导出成功后询问是否清除本地旧数据。
  ///
  /// 字段映射：clozeWord → Target_Word，sentenceText → Full_Sentence_EN，
  /// chineseTranslation → Sentence_ZH（03 卡面：中文唯一中文位）。
  Future<void> _exportLegacyAnkiCards(List<AnkiCard> cards) async {
    final s = LLStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final notes = <AnkiExportNote>[
        for (final card in cards)
          AnkiExportNote(
            targetWord: card.clozeWord,
            sentenceCloze: card.clozeWord.isEmpty
                ? card.sentenceText
                : card.sentenceText.replaceFirst(card.clozeWord, '____'),
            fullSentence: card.sentenceText,
            sentenceZh: card.chineseTranslation,
            audioPath: card.audioPath,
          ),
      ];
      final bytes = await buildApkgBytes(
        notes: notes,
        now: DateTime.now(),
        audioFileName: (n) =>
            'legacy_${n.targetWord.hashCode.abs() % 100000000}.mp3',
        audioBytes: (n) {
          final path = n.audioPath;
          if (path == null || path.isEmpty) return null;
          try {
            return File(path).readAsBytesSync();
          } catch (_) {
            return null;
          }
        },
      );
      await shareApkgBytes(
        fileName: 'listenloop_legacy_cards.apkg',
        bytes: Uint8List.fromList(bytes),
        shareSubject: '句读 挖卡卡组',
        shareText: '句读 历史挖卡导出的 .apkg，可导入 Anki 桌面端复习。',
      );
      if (!mounted) return;

      final clear = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final dialogLl = ctx.ll;
          return AlertDialog(
          backgroundColor: dialogLl.surface,
          title: Text(s.legacyCardsClearedTitle,
              style: const TextStyle(fontSize: 16)),
          content: Text(
            s.legacyCardsClearedBody,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: dialogLl.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(s.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(s.legacyCardsClearYes),
            ),
          ],
          );
        },
      );
      if (clear == true) {
        await _aiGovernorService.clearAnkiCards();
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.vocabExportFailed)));
    }
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
          // 产品名 2026-10-10 定为「句读(Phrasing)」。首页 wordmark 与启动页、
          // 设置页卷首保持一致：中文主标「句读」，英文侧（uiLanguage=en）用 Phrasing。
          // （2026-10-16 修：此前首页硬编码 'ListenLoop'，是改名漏网的一处。）
          Text(
            s.appWordmark,
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

    final isChineseTab = _selectedLanguage == 'ZH';

    final continueTarget = continueItem;

    final query = _searchQuery.trim().toLowerCase();
    bool matchesQuery(LessonWithProgress item) {
      if (query.isEmpty) return true;
      return item.lesson.title.toLowerCase().contains(query) ||
          (item.lesson.series ?? '').toLowerCase().contains(query);
    }

    bool isCurriculumLesson(LessonWithProgress item) {
      final s = item.lesson.series ?? '';
      final t = item.lesson.title;
      if (s.contains('统编') || s.contains('语文') || s.contains('小学语文')) return true;
      if (t.contains('统编语文')) return true;
      return false;
    }

    final filteredItems = items.where((item) {
      if (!matchesQuery(item)) return false;
      final langCode = SubtitleModeX.resolveLanguageCode(item.lesson.language);
      if (isChineseTab) {
        // 中文模式：只放用户自己导进去的中文材料，绝对不重复展示统编版教材卡片
        return langCode == 'ZH' && !isCurriculumLesson(item);
      } else if (_selectedLanguage == 'EN') {
        // 英文模式：只放英文课程与用户导进去的英文内容
        return langCode == 'EN';
      } else if (_selectedLanguage == 'ALL') {
        return true;
      } else {
        return langCode == _selectedLanguage;
      }
    }).toList();

    if (filteredItems.isEmpty) {
      if (isChineseTab) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Text(
              '暂无导入的个人中文内容\n上方「语文」中可直接点击收听各课',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: ll.textTertiary,
                height: 1.6,
              ),
            ),
          ),
        );
      }
      return _EmptyLibrary(
        onImport: _onImportPressed,
        onOpenCatalog: () => _openCloudCatalog(),
        onCreate: _openCreationScreen,
      );
    }

    // 系列分组（2026-09-29 课文朗读系列）：同一 series 归组，搜索时全部平铺。
    final seriesGroups = <String, List<LessonWithProgress>>{};
    final loose = <LessonWithProgress>[];
    for (final item in filteredItems) {
      final seriesName = item.lesson.series;
      if (query.isEmpty && seriesName != null && seriesName.isNotEmpty) {
        seriesGroups.putIfAbsent(seriesName, () => []).add(item);
      } else {
        loose.add(item);
      }
    }
    final others = loose;
    final expandedSeries = _expandedSeries;
    List<Widget> seriesSectionWidgets() => [
          for (final entry in seriesGroups.entries)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                LLSpacing.xl, 0, LLSpacing.xl, LLSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () => setState(() {
                        if (!expandedSeries.remove(entry.key)) {
                          expandedSeries.add(entry.key);
                        }
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: ll.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: ll.divider),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.menu_book_outlined, size: 18,
                                color: ll.textPrimary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ll.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              '${entry.value.length} 课',
                              style: TextStyle(
                                fontSize: 12,
                                color: ll.textTertiary,
                              ),
                            ),
                            Icon(
                              expandedSeries.contains(entry.key)
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: ll.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (expandedSeries.contains(entry.key))
                      for (var i = 0; i < entry.value.length; i++)
                        LessonEditorialRow(
                          key: Key(
                              'lesson-card-${entry.value[i].lesson.id}'),
                          index: i,
                          item: entry.value[i],
                          onTap: () => _openLesson(entry.value[i]),
                          onLongPress: () =>
                              _showLessonMenu(entry.value[i]),
                        ),
                  ],
                ),
              ),
            ),
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
        ...seriesSectionWidgets(),
        if (others.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              LLSpacing.xl,
              LLSpacing.lg,
              LLSpacing.xl,
              LLSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    '我的导入与自建',
                    style: LLText.sectionLabel.copyWith(color: ll.textTertiary),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: ll.textPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${others.length}',
                      style: TextStyle(fontSize: 10, color: ll.textTertiary),
                    ),
                  ),
                ],
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
        ] else if (others.isEmpty && seriesGroups.isEmpty) ...[
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
  const _EmptyLibrary({
    required this.onImport,
    this.onOpenCatalog,
    this.onCreate,
  });

  final VoidCallback onImport;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: LLSpacing.xl),
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
            const SizedBox(height: LLSpacing.lg),
            // 2026-10-16 修两处：
            // ① 「制作新课程」此前硬编码中文 → 英文界面下走 i18n（New Lesson）；
            // ② 两个按钮并排，窄屏/大字号下会顶出 Row（实测英文界面报
            //    "RIGHT OVERFLOWED BY 26 PIXELS"）→ 用 Wrap 自动换行，
            //    放得下时行为与原来的 Row 完全一致。
            Wrap(
              alignment: WrapAlignment.center,
              spacing: LLSpacing.sm,
              runSpacing: LLSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: onImport,
                  child: Text(s.importLesson),
                ),
                if (onCreate != null)
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(s.createNewLesson),
                  ),
              ],
            ),
          ],
        ),
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

    // When no weaknesses: return empty widget
    return const SizedBox.shrink();
  }
}


