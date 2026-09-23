import 'dart:async';
import 'package:flutter/material.dart';

import '../creation/creation_controller.dart';
import '../creation/creation_screen.dart';
import '../creation/lesson_job_stage.dart';
import '../models/lesson.dart';
import '../theme/listenloop_theme.dart';

/// Floating creation semicircle capsule (2026-09-19 用户需求):
/// When leaving the creation screen during or after a job, it collapses into a
/// sleek semicircle docked to the screen's left or right edge.
///
/// Features:
/// 1. Arc progress bar reflecting real-time pipeline completion.
/// 2. Visual glow/pulse when nearly complete (progress >= 85%).
/// 3. Transitions to vibrant emerald green on completion with a checkmark
///    and a floating notification bubble ("课程已制作完成").
/// 4. Clicking the green circle directly launches the lesson player.
class CreationCapsule extends StatefulWidget {
  const CreationCapsule({
    super.key,
    required this.controller,
    required this.onOpen,
    this.onStartListening,
  });

  final CreationController controller;
  final VoidCallback onOpen;
  final ValueChanged<Lesson>? onStartListening;

  @override
  State<CreationCapsule> createState() => _CreationCapsuleState();
}

class _CreationCapsuleState extends State<CreationCapsule>
    with SingleTickerProviderStateMixin {
  static const double _width = 50.0;
  static const double _height = 56.0;

  /// Vertical anchor as a fraction of the free screen height (0..1).
  double _dy = 0.40;
  bool _leftSide = false;
  bool _dragging = false;
  double? _dragLeft;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool _showBubble = false;
  Timer? _bubbleDismissTimer;
  LessonJobStage? _lastStage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bubbleDismissTimer?.cancel();
    super.dispose();
  }

  double _computeOverallProgress(CreationController controller) {
    final stage = controller.stage;
    if (stage == LessonJobStage.completed) return 1.0;
    return switch (stage) {
      LessonJobStage.queued || LessonJobStage.acquiringMedia => 0.05,
      LessonJobStage.preparingAudio => 0.12,
      LessonJobStage.transcribing =>
        0.15 + 0.60 * controller.stageProgress.clamp(0.0, 1.0),
      LessonJobStage.segmenting => 0.78,
      LessonJobStage.translating => 0.88,
      LessonJobStage.packaging => 0.96,
      LessonJobStage.completed => 1.0,
      LessonJobStage.failed || LessonJobStage.cancelled => 0.0,
    };
  }

  void _onStageChanged(LessonJobStage currentStage) {
    if (_lastStage != currentStage) {
      _lastStage = currentStage;
      if (currentStage == LessonJobStage.completed) {
        setState(() => _showBubble = true);
        _bubbleDismissTimer?.cancel();
        _bubbleDismissTimer = Timer(const Duration(seconds: 7), () {
          if (mounted) setState(() => _showBubble = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, creationViewActive]),
      builder: (context, _) {
        final controller = widget.controller;
        final isCompleted = controller.stage == LessonJobStage.completed &&
            controller.result != null;
        final isFailed = controller.stage == LessonJobStage.failed;

        if ((!controller.isBusy && !isCompleted && !isFailed) ||
            creationViewActive.value) {
          return const SizedBox.shrink();
        }

        _onStageChanged(controller.stage);

        final screen = MediaQuery.sizeOf(context);
        final progress = _computeOverallProgress(controller).clamp(0.0, 1.0);
        final percent = (progress * 100).round();
        final isNearlyComplete = progress >= 0.85 && !isCompleted;

        final top = (_dy * (screen.height - _height - 80) + 40).clamp(
          40.0,
          screen.height - _height - 80,
        );
        final dockedX = _leftSide ? 0.0 : screen.width - _width;
        final left = _dragging ? _dragLeft! : dockedX;

        final palette = context.ll;

        return Positioned(
          left: left,
          top: top,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              Color bgColor;
              BorderRadius borderRadius;
              List<BoxShadow> shadows;

              if (_leftSide) {
                borderRadius = const BorderRadius.horizontal(
                  right: Radius.circular(28),
                );
              } else {
                borderRadius = const BorderRadius.horizontal(
                  left: Radius.circular(28),
                );
              }

              if (isCompleted) {
                bgColor = const Color(0xFF2E7D32); // Emerald green
                shadows = [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ];
              } else if (isFailed) {
                bgColor = const Color(0xFFC62828); // Error red
                shadows = [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ];
              } else {
                bgColor = palette.surface;
                if (isNearlyComplete) {
                  final glow = _pulseAnimation.value;
                  shadows = [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: glow * 0.6),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                    const BoxShadow(blurRadius: 8, color: Color(0x60000000)),
                  ];
                } else {
                  shadows = const [
                    BoxShadow(blurRadius: 10, color: Color(0x60000000)),
                  ];
                }
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Semicircle Capsule Body
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _dragging ? null : _handleTap,
                    onPanStart: (_) => setState(() {
                      _dragging = true;
                      _dragLeft = dockedX;
                    }),
                    onPanUpdate: (details) => setState(() {
                      _dragLeft = (_dragLeft! + details.delta.dx).clamp(
                        0.0,
                        screen.width - _width,
                      );
                      _dy = ((top + details.delta.dy - 40) /
                              (screen.height - _height - 80))
                          .clamp(0.0, 1.0);
                    }),
                    onPanEnd: (_) => setState(() {
                      final centre = _dragLeft! + _width / 2;
                      _leftSide = centre < screen.width / 2;
                      _dragging = false;
                      _dragLeft = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: _width,
                      height: _height,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: borderRadius,
                        border: Border.all(
                          color: isCompleted
                              ? Colors.greenAccent
                              : (isNearlyComplete
                                  ? const Color(0xFF00E5FF)
                                  : palette.divider),
                          width: 1.5,
                        ),
                        boxShadow: shadows,
                      ),
                      child: Center(
                        child: _buildCapsuleContent(
                          isCompleted: isCompleted,
                          isFailed: isFailed,
                          progress: progress,
                          percent: percent,
                          palette: palette,
                        ),
                      ),
                    ),
                  ),

                  // Floating Notification Bubble
                  if (_showBubble && !_dragging)
                    Positioned(
                      top: 8,
                      left: _leftSide ? _width + 8 : null,
                      right: !_leftSide ? _width + 8 : null,
                      child: GestureDetector(
                        onTap: _handleTap,
                        child: _buildBubble(isCompleted, palette),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCapsuleContent({
    required bool isCompleted,
    required bool isFailed,
    required double progress,
    required int percent,
    required LLPalette palette,
  }) {
    if (isCompleted) {
      return const Icon(
        Icons.check_rounded,
        color: Colors.white,
        size: 26,
      );
    }
    if (isFailed) {
      return const Icon(
        Icons.priority_high_rounded,
        color: Colors.white,
        size: 22,
      );
    }

    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress <= 0 ? null : progress,
            strokeWidth: 3,
            color: progress >= 0.85 ? const Color(0xFF00E5FF) : palette.textPrimary,
            backgroundColor: palette.divider,
          ),
          Text(
            '$percent',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(bool isCompleted, LLPalette palette) {
    final text = isCompleted ? '课程已制作完成，点击查看' : '制课遇到问题，点击查看';
    final bgColor = isCompleted ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(blurRadius: 10, color: Color(0x60000000)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCompleted ? Icons.check_circle_rounded : Icons.info_rounded,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap() {
    final controller = widget.controller;
    if (controller.stage == LessonJobStage.completed &&
        controller.result != null) {
      final lesson = controller.result!;
      if (widget.onStartListening != null) {
        widget.onStartListening!(lesson);
        controller.resetToIdle();
        setState(() => _showBubble = false);
      } else {
        widget.onOpen();
      }
    } else {
      widget.onOpen();
    }
  }
}
