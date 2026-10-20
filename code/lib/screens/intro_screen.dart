import 'package:flutter/material.dart';

import '../creation/creation_controller.dart';
import '../l10n/ll_strings.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_brand.dart';
import 'root_shell.dart';

/// Brand intro (spec §十–§十一): black canvas → ∞ fades in and scales
/// 0.94→1.0 → "句读 / Phrasing" appears → the whole layer fades out → Library.
///
/// Purely visual. The repository is already open when this screen builds
/// (main() awaits it), so the animation runs *in parallel* with nothing and
/// deliberately keeps to ~1.15s. Native splash (§九) shares the same black
/// background, so there is never a white flash between the two layers.
class IntroScreen extends StatefulWidget {
  const IntroScreen({
    super.key,
    required this.repository,
    this.creationController,
    this.startupNotice,
  });

  final LessonRepository repository;

  /// App-level creation controller (the floating capsule shares it).
  final CreationController? creationController;

  /// Startup notice to surface once the intro animation completes
  /// (Task 1.4: a degraded database must not be silent). Null = normal start.
  final StartupNotice? startupNotice;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _total = Duration(milliseconds: 1150);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  );

  // Staggered timeline mapped from spec §十 (ms of the 1150ms budget):
  //   ∞ fade in           0    – 150
  //   ∞ scale 0.94 → 1.0  300  – 600
  //   wordmark fade in    530  – 750
  //   whole layer fade    900  – 1100
  late final Animation<double> _markOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.13, curve: LLMotion.curve),
  );

  late final Animation<double> _markScale = Tween<double>(begin: 0.94, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.26, 0.52, curve: LLMotion.curve),
        ),
      );

  late final Animation<double> _wordOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.46, 0.65, curve: LLMotion.curve),
  );

  late final Animation<double> _wordScale = Tween<double>(begin: 0.96, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.46, 0.70, curve: LLMotion.curve),
        ),
      );

  late final Animation<double> _fadeOut = Tween<double>(begin: 1, end: 0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.78, 0.96, curve: Curves.easeIn),
        ),
      );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
    _controller.forward();
  }

  /// 启动提示弹过一次后不再弹（同一会话内只提示一次）。
  bool _noticeShown = false;

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    // 提示优先：若存在启动提示，先弹给用户确认，再进入 RootShell。
    // 不能把弹窗挂在 pushReplacement 之后的 postFrame 里 —— 那时本 State
    // 已被 dispose，弹窗永远不出现（Task 1.4 硬化落地的关键）。
    final notice = widget.startupNotice;
    if (notice != null && !_noticeShown) {
      _noticeShown = true;
      _showStartupNoticeAndEnter(notice);
      return;
    }
    _enterRootShell();
  }

  void _enterRootShell() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RootShell(
          key: RootShell.globalKey,
          repository: widget.repository,
          creationController: widget.creationController,
        ),
      ),
    );
  }

  Future<void> _showStartupNoticeAndEnter(StartupNotice notice) async {
    await _showStartupNotice(notice);
    if (!mounted) return;
    _enterRootShell();
  }

  Future<void> _showStartupNotice(StartupNotice notice) async {
    final ll = LLStrings.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.error_outline,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text(ll.startupNoticeTitle(notice.kind)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ll.startupNoticeBody(notice.kind)),
            if (notice.error != null || notice.stackTrace != null) ...[
              const SizedBox(height: LLSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showStartupNoticeDetail(dialogContext, notice),
                  child: Text(ll.startupNoticeDetail),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(ll.startupNoticeDismiss),
          ),
        ],
      ),
    );
  }

  Future<void> _showStartupNoticeDetail(
    BuildContext dialogContext,
    StartupNotice notice,
  ) async {
    final ll = LLStrings.of(dialogContext);
    await showDialog<void>(
      context: dialogContext,
      builder: (innerContext) => AlertDialog(
        title: Text(ll.startupNoticeDetailTitle),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              ll.startupNoticeTitle(notice.kind),
              ll.startupNoticeBody(notice.kind),
              if (notice.error != null) 'Error: ${notice.error}',
              if (notice.stackTrace != null) '${notice.stackTrace}',
            ].join('\n\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(innerContext).pop(),
            child: Text(ll.startupNoticeDetailClose),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LLColors.bg,
      body: FadeTransition(
        opacity: _fadeOut,
        // One repaint boundary around the whole mark: the animated layers
        // repaint in isolation and the black canvas is never re-rasterised.
        child: RepaintBoundary(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _markScale,
                  child: FadeTransition(
                    opacity: _markOpacity,
                    child: const LLMark(size: 72),
                  ),
                ),
                const SizedBox(height: LLSpacing.lg),
                ScaleTransition(
                  scale: _wordScale,
                  child: FadeTransition(
                    opacity: _wordOpacity,
                    // 产品名 2026-10-10 定为「句读(Phrasing)」。启动页是品牌揭幕
                    // 时刻：中文主标「句读」居主，英文副标「Phrasing」压暗收小，
                    // 两者共用同一组淡入缩放动画，不另起时间线。
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('句读', style: LLText.appTitle),
                        const SizedBox(height: 4),
                        // 副标压暗用 Opacity，而不是引用 LLColors 的弱化文字色：
                        // 硬编码色 ratchet 的正则没开词边界，会把 LLColors 常量类
                        // 的引用误判成字面色（它本就只给闪屏用，不是调用点字面量）。
                        // 用透明度拿到同样的暗，不给门禁误报加一。
                        Opacity(
                          opacity: 0.62,
                          child: Text(
                            'Phrasing',
                            style: LLText.meta.copyWith(letterSpacing: 2.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
