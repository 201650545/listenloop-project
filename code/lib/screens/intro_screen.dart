import 'package:flutter/material.dart';

import '../creation/creation_controller.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_brand.dart';
import 'root_shell.dart';

/// Brand intro (spec §十–§十一): black canvas → ∞ fades in and scales
/// 0.94→1.0 → "ListenLoop" appears → the whole layer fades out → Library.
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
  });

  final LessonRepository repository;

  /// App-level creation controller (the floating capsule shares it).
  final CreationController? creationController;

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

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
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
                    child: const Text('ListenLoop', style: LLText.appTitle),
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
