import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../l10n/ll_strings.dart';
import '../models/lesson.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_brand.dart';
import 'bilibili_source.dart';
import 'creation_controller.dart';
import 'lesson_input.dart';
import 'lesson_job_stage.dart';

/// Mobile Creation (spec V1 §十一/§六十一 + follow-up 处理阶段可视化): a
/// quiet black/white page — a stage CHECKLIST (done ✓ / current with
/// pulsing dot / pending faint), the active progress bar, an elapsed timer
/// and cancel. No engineering dashboard.
class CreationScreen extends StatefulWidget {
  const CreationScreen({
    super.key,
    required this.controller,
    this.input,
    required this.onStartListening,
    this.onImportLessonPackage,
    this.embedded = false,
  });

  final CreationController controller;
  final LessonInput? input;
  final Future<void> Function(Lesson lesson) onStartListening;
  final VoidCallback? onImportLessonPackage;
  final bool embedded;

  @override
  State<CreationScreen> createState() => _CreationScreenState();
}

/// True while the full creation screen is on screen. The floating capsule
/// hides itself then — it exists exactly for the moments this screen is NOT.
final ValueNotifier<bool> creationViewActive = ValueNotifier(false);

class _CreationScreenState extends State<CreationScreen> {
  Timer? _elapsedTimer;
  final TextEditingController _urlInputController = TextEditingController();
  String? _selectedLanguage; // null = auto-detect, 'ja', 'en', 'zh'

  @override
  void initState() {
    super.initState();
    // Only standalone full screen locks creationViewActive to true
    if (!widget.embedded) {
      creationViewActive.value = true;
    }
    // Drives the elapsed-time readout while a job is running.
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.isBusy) setState(() {});
    });
  }

  @override
  void dispose() {
    if (!widget.embedded) {
      creationViewActive.value = false;
    }
    _elapsedTimer?.cancel();
    _urlInputController.dispose();
    super.dispose();
  }

  void _openProgressPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CreationProgressPage(
          controller: widget.controller,
          onStartListening: widget.onStartListening,
        ),
      ),
    );
  }

  Future<void> _startFromLink() async {
    final link = _urlInputController.text.trim();
    if (link.isEmpty) return;
    if (extractUrl(link) == null && parseBilibiliUrl(link) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('链接无效：仅支持 B站 / YouTube')),
      );
      return;
    }
    _urlInputController.clear();
    FocusScope.of(context).unfocus();
    final input = LessonInput.link(
      source: link,
      language: _selectedLanguage,
    );
    _openProgressPage();
    await widget.controller.start(input);
  }

  Future<void> _startFromFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;
    final input = LessonInput.localFile(
      path: path,
      titleHint: p.basenameWithoutExtension(path),
      language: _selectedLanguage,
    );
    _openProgressPage();
    await widget.controller.start(input);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.embedded) {
      return CreationProgressPage(
        controller: widget.controller,
        onStartListening: widget.onStartListening,
      );
    }

    final ll = context.ll;
    final s = LLStrings.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: llSystemOverlay(ll.brightness),
      child: Scaffold(
        backgroundColor: ll.bg,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            s.createLesson,
            style: LLText.rowTitle.copyWith(color: ll.textPrimary),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: LLSpacing.xl),
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                return _CreationIdle(
                  controller: widget.controller,
                  urlController: _urlInputController,
                  selectedLanguage: _selectedLanguage,
                  onSelectLanguage: (lang) =>
                      setState(() => _selectedLanguage = lang),
                  onStartFromLink: _startFromLink,
                  onStartFromFile: _startFromFile,
                  onImportPackage: widget.onImportLessonPackage,
                  onOpenProgressPage: _openProgressPage,
                  onStartListening: widget.onStartListening,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Fullscreen detailed progress page when creation is active or opened from capsule/banner.
class CreationProgressPage extends StatefulWidget {
  const CreationProgressPage({
    super.key,
    required this.controller,
    required this.onStartListening,
  });

  final CreationController controller;
  final Future<void> Function(Lesson lesson) onStartListening;

  @override
  State<CreationProgressPage> createState() => _CreationProgressPageState();
}

class _CreationProgressPageState extends State<CreationProgressPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    creationViewActive.value = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.isBusy) setState(() {});
    });
  }

  @override
  void dispose() {
    creationViewActive.value = false;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final controller = widget.controller;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: llSystemOverlay(ll.brightness),
      child: Scaffold(
        backgroundColor: ll.bg,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            tooltip: '收起后台制课',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return Text(
                controller.isReady
                    ? '课程就绪'
                    : (controller.isBusy ? '正在制课中...' : '智能制课'),
                style: LLText.rowTitle.copyWith(color: ll.textPrimary),
              );
            },
          ),
          actions: [
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.isBusy) {
                  return TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text('收起', style: TextStyle(color: ll.textSecondary)),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: LLSpacing.xl),
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.isBusy) {
                  return _CreationRunning(controller: controller, s: s);
                }
                if (controller.isReady && controller.lastLesson != null) {
                  return _LessonReady(
                    lesson: controller.lastLesson!,
                    onStartListening: () async {
                      final lesson = controller.lastLesson!;
                      Navigator.of(context).maybePop();
                      await widget.onStartListening(lesson);
                    },
                    onCreateAnother: controller.reset,
                  );
                }
                if (controller.isFailed) {
                  return _CreationFailed(
                    controller: controller,
                    onRetry: controller.retry,
                    onReset: controller.reset,
                  );
                }
                if (controller.isCancelled) {
                  return _CreationCancelled(
                    controller: controller,
                    onReset: controller.reset,
                  );
                }
                return Center(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('返回'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// §六十一: the pipeline as a checklist — done ✓, current pulsing dot,
/// pending faint. Enough visualisation; no dashboard.
const List<LessonJobStage> _visibleStages = [
  LessonJobStage.preparingAudio,
  LessonJobStage.transcribing,
  LessonJobStage.segmenting,
  LessonJobStage.translating,
  LessonJobStage.packaging,
];

class _CreationRunning extends StatelessWidget {
  const _CreationRunning({required this.controller, required this.s});

  final CreationController controller;
  final LLStrings s;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final stage = controller.stage;
    final currentPos = _visibleStages.indexOf(stage);
    final startedAt = controller.startedAt;
    final elapsed = startedAt == null
        ? const Duration()
        : DateTime.now().difference(startedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: LLSpacing.xl),
        Text(
          inputLabel(controller),
          style: LLText.rowTitle.copyWith(color: ll.textPrimary),
        ),
        const SizedBox(height: LLSpacing.sm),
        Text(
          '${s.elapsed}  '
          '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
          '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
          style: LLText.counter.copyWith(color: ll.textTertiary),
        ),
        const SizedBox(height: LLSpacing.xl),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _visibleStages.length; i++) ...[
                  _StageLine(
                    stage: _visibleStages[i],
                    state: _stageState(currentPos, i, stage),
                    s: s,
                    ll: ll,
                    showProgress:
                        stage == _visibleStages[i] &&
                        (stage == LessonJobStage.transcribing) &&
                        controller.stageProgress > 0,
                    progress: controller.stageProgress,
                  ),
                  const SizedBox(height: LLSpacing.lg),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: LLSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('cancel-creation-button'),
            onPressed: controller.cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: ll.textPrimary,
              side: BorderSide(color: ll.textPrimary),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: LLSpacing.lg),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(s.cancelCreation),
          ),
        ),
        const SizedBox(height: LLSpacing.xl),
      ],
    );
  }

  String inputLabel(CreationController controller) =>
      controller.currentInput?.titleHint ?? '';

  int _stageState(int currentPos, int i, LessonJobStage stage) {
    if (currentPos < 0) return 2;
    if (i < currentPos) return 0;
    if (i == currentPos) return 1;
    return 2;
  }
}

class _StageLine extends StatelessWidget {
  const _StageLine({
    required this.stage,
    required this.state,
    required this.s,
    required this.ll,
    required this.showProgress,
    required this.progress,
  });

  final LessonJobStage stage;
  final int state;
  final LLStrings s;
  final LLPalette ll;
  final bool showProgress;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      0 => ll.textSecondary,
      1 => ll.textPrimary,
      _ => ll.textTertiary,
    };
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: state == 1
              ? const LLInfinityLoader(size: 14)
              : Text(
                  state == 0 ? '✓' : '○',
                  style: TextStyle(
                    fontSize: 13,
                    color: state == 0 ? ll.textSecondary : ll.disabled,
                  ),
                ),
        ),
        const SizedBox(width: LLSpacing.md),
        Text(
          s.stageName(stage),
          style: TextStyle(
            fontSize: 15,
            fontWeight: state == 1 ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
        const Spacer(),
        if (showProgress)
          Text(
            '${(progress * 100).round()}%',
            style: LLText.counter.copyWith(color: ll.textSecondary),
          ),
      ],
    );
  }
}

class _CreationFailed extends StatelessWidget {
  const _CreationFailed({
    required this.controller,
    required this.onRetry,
    required this.onReset,
  });

  final CreationController controller;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LLSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: LLSpacing.lg),
            Text(
              s.stageName(LessonJobStage.failed),
              style: LLText.pageTitle.copyWith(color: ll.textPrimary),
            ),
            const SizedBox(height: LLSpacing.md),
            Text(
              controller.errorCode == null
                  ? (controller.errorMessage ?? '')
                  : s.errorMessage(controller.errorCode!),
              style: LLText.body.copyWith(color: ll.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LLSpacing.xxl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ll.textPrimary,
                      side: BorderSide(color: ll.divider),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: LLSpacing.md),
                    ),
                    child: const Text('返回重选'),
                  ),
                ),
                const SizedBox(width: LLSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: ll.textPrimary,
                      foregroundColor: ll.bg,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: LLSpacing.md),
                    ),
                    child: const Text('重试制课'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreationCancelled extends StatelessWidget {
  const _CreationCancelled({required this.controller, required this.onReset});

  final CreationController controller;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LLMark(size: 40, color: LLColors.textTertiary),
          const SizedBox(height: LLSpacing.lg),
          Text(
            s.stageName(LessonJobStage.cancelled),
            style: LLText.pageTitle.copyWith(color: ll.textPrimary),
          ),
          const SizedBox(height: LLSpacing.sm),
          Text(
            s.listenEmptyBody,
            style: LLText.caption.copyWith(color: ll.textTertiary),
          ),
          const SizedBox(height: LLSpacing.xl),
          OutlinedButton(
            onPressed: onReset,
            style: OutlinedButton.styleFrom(
              foregroundColor: ll.textPrimary,
              side: BorderSide(color: ll.divider),
              shape: const StadiumBorder(),
            ),
            child: const Text('创建新课程'),
          ),
        ],
      ),
    );
  }
}

class _LessonReady extends StatelessWidget {
  const _LessonReady({
    required this.lesson,
    required this.onStartListening,
    required this.onCreateAnother,
  });

  final Lesson lesson;
  final Future<void> Function() onStartListening;
  final VoidCallback onCreateAnother;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: LLSpacing.xxl),
        const LLMark(size: 40, color: LLColors.textPrimary),
        const SizedBox(height: LLSpacing.lg),
        Text(
          s.lessonReady,
          style: LLText.pageTitle.copyWith(color: ll.textPrimary),
        ),
        const SizedBox(height: LLSpacing.xl),
        Text(
          lesson.title,
          style: LLText.rowTitle.copyWith(color: ll.textPrimary),
        ),
        const SizedBox(height: LLSpacing.sm),
        Text(
          s.sentencesReady(lesson.sentenceCount),
          style: LLText.caption.copyWith(color: ll.textTertiary),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('start-listening-button'),
            onPressed: onStartListening,
            style: FilledButton.styleFrom(
              backgroundColor: ll.textPrimary,
              foregroundColor: ll.bg,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: LLSpacing.lg),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(s.startListening),
          ),
        ),
        const SizedBox(height: LLSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onCreateAnother,
            style: OutlinedButton.styleFrom(
              foregroundColor: ll.textSecondary,
              side: BorderSide(color: ll.divider),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: LLSpacing.md),
            ),
            child: const Text('制作下一课'),
          ),
        ),
        const SizedBox(height: LLSpacing.xl),
      ],
    );
  }
}

class _CreationIdle extends StatelessWidget {
  const _CreationIdle({
    required this.controller,
    required this.urlController,
    required this.selectedLanguage,
    required this.onSelectLanguage,
    required this.onStartFromLink,
    required this.onStartFromFile,
    this.onImportPackage,
    required this.onOpenProgressPage,
    required this.onStartListening,
  });

  final CreationController controller;
  final TextEditingController urlController;
  final String? selectedLanguage;
  final ValueChanged<String?> onSelectLanguage;
  final VoidCallback onStartFromLink;
  final VoidCallback onStartFromFile;
  final VoidCallback? onImportPackage;
  final VoidCallback onOpenProgressPage;
  final Future<void> Function(Lesson lesson) onStartListening;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final hasActiveJob = controller.isBusy ||
        (controller.isReady && controller.lastLesson != null);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: LLSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasActiveJob) ...[
            _ActiveJobBanner(
              controller: controller,
              onTap: onOpenProgressPage,
              onStartListening: () {
                if (controller.lastLesson != null) {
                  onStartListening(controller.lastLesson!);
                }
              },
            ),
            const SizedBox(height: LLSpacing.xl),
          ],
          Text(
            '从链接创建课程',
            style: LLText.pageTitle.copyWith(color: ll.textPrimary),
          ),
          const SizedBox(height: LLSpacing.xs),
          Text(
            'B站 / YouTube 链接',
            style: LLText.caption.copyWith(color: ll.textTertiary),
          ),
          const SizedBox(height: LLSpacing.xl),
          Container(
            padding: const EdgeInsets.all(LLSpacing.md),
            decoration: BoxDecoration(
              color: ll.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ll.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  style: TextStyle(color: ll.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '粘贴链接或 BV 号',
                    hintStyle: TextStyle(color: ll.textTertiary, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: urlController,
                      builder: (context, value, _) {
                        if (value.text.isNotEmpty) {
                          return IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            tooltip: '清空',
                            onPressed: () => urlController.clear(),
                          );
                        }
                        return IconButton(
                          icon: const Icon(Icons.paste_rounded, size: 18),
                          tooltip: '粘贴剪贴板',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null && data!.text!.trim().isNotEmpty) {
                              urlController.text = data.text!.trim();
                            }
                          },
                        );
                      },
                    ),
                  ),
                  onSubmitted: (_) => onStartFromLink(),
                ),
                const SizedBox(height: LLSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      urlController.text = 'BV1xE5d6BEZ5';
                      onSelectLanguage('en');
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 13, color: ll.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            '示例：英语 Vlog',
                            style: TextStyle(fontSize: 11, color: ll.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: LLSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        '语种:',
                        style: TextStyle(fontSize: 12, color: ll.textTertiary, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 8),
                      _LanguagePill(
                        label: '英语 (EN)',
                        selected: selectedLanguage == 'en',
                        onTap: () => onSelectLanguage('en'),
                        palette: ll,
                      ),
                      const SizedBox(width: 6),
                      _LanguagePill(
                        label: '日语 (JA)',
                        selected: selectedLanguage == 'ja',
                        onTap: () => onSelectLanguage('ja'),
                        palette: ll,
                      ),
                      const SizedBox(width: 6),
                      _LanguagePill(
                        label: '中文 (ZH)',
                        selected: selectedLanguage == 'zh',
                        onTap: () => onSelectLanguage('zh'),
                        palette: ll,
                      ),
                      const SizedBox(width: 6),
                      _LanguagePill(
                        label: '自动检测',
                        selected: selectedLanguage == null,
                        onTap: () => onSelectLanguage(null),
                        palette: ll,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: LLSpacing.md),
                FilledButton.icon(
                  onPressed: onStartFromLink,
                  style: FilledButton.styleFrom(
                    backgroundColor: ll.textPrimary,
                    foregroundColor: ll.bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: LLSpacing.md),
                  ),
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text('开始制课', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: LLSpacing.xxl),
          Text(
            '其他方式',
            style: LLText.sectionLabel.copyWith(color: ll.textTertiary),
          ),
          const SizedBox(height: LLSpacing.md),
          _ActionCard(
            icon: Icons.audio_file_outlined,
            title: '本地音视频文件',
            onTap: onStartFromFile,
          ),
          if (onImportPackage != null) ...[
            const SizedBox(height: LLSpacing.md),
            _ActionCard(
              icon: Icons.folder_zip_outlined,
              title: '导入 .lllesson 课程包',
              onTap: onImportPackage!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveJobBanner extends StatelessWidget {
  const _ActiveJobBanner({
    required this.controller,
    required this.onTap,
    required this.onStartListening,
  });

  final CreationController controller;
  final VoidCallback onTap;
  final VoidCallback onStartListening;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final isReady = controller.isReady && controller.lastLesson != null;
    final stage = controller.stage;
    final stageText = isReady ? '课程已就绪' : s.stageName(stage);
    final title = controller.currentInput?.titleHint ??
        (isReady ? controller.lastLesson!.title : '正在制作课程');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isReady ? onStartListening : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(LLSpacing.md),
          decoration: BoxDecoration(
            color: isReady
                ? const Color(0xFF1B3B2B)
                : ll.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isReady
                  ? const Color(0xFF2E7D32)
                  : ll.textPrimary.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: isReady
                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 30)
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: controller.stageProgress > 0 ? controller.stageProgress : null,
                            strokeWidth: 3,
                            color: ll.textPrimary,
                            backgroundColor: ll.divider,
                          ),
                          const Icon(Icons.flash_on, size: 16),
                        ],
                      ),
              ),
              const SizedBox(width: LLSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isReady ? Colors.white : ll.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isReady ? '点击立即开始精听' : '状态: $stageText (点击展开详情)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isReady ? const Color(0xFFA5D6A7) : ll.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LLSpacing.sm),
              Icon(
                isReady ? Icons.play_arrow_rounded : Icons.chevron_right_rounded,
                color: isReady ? Colors.white : ll.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(LLSpacing.lg),
        decoration: BoxDecoration(
          color: ll.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ll.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: ll.textPrimary),
            const SizedBox(width: LLSpacing.lg),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ll.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: ll.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final LLPalette palette;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? ll.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? ll.textPrimary : ll.divider,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? ll.bg : ll.textSecondary,
          ),
        ),
      ),
    );
  }
}
