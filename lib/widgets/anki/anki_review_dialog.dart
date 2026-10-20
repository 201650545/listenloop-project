import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/ai_governor_service.dart';
import '../../models/anki_card_model.dart';
import '../../theme/listenloop_theme.dart';
import '../ll_brand.dart';

enum AnkiCardFaceMode {
  cloze, // 填空
  blind, // 盲听
  full,  // 全显
}

/// Interactive Anki Spaced Repetition Flashcard Review Flow.
class AnkiReviewDialog extends StatefulWidget {
  const AnkiReviewDialog({
    super.key,
    required this.cards,
    required this.aiGovernorService,
    this.onPlaySnippet,
  });

  final List<AnkiCard> cards;
  final AiGovernorService aiGovernorService;
  final void Function(int startMs, int endMs)? onPlaySnippet;

  static Future<void> show({
    required BuildContext context,
    required List<AnkiCard> cards,
    required AiGovernorService aiGovernorService,
    void Function(int startMs, int endMs)? onPlaySnippet,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ll.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AnkiReviewDialog(
        cards: cards,
        aiGovernorService: aiGovernorService,
        onPlaySnippet: onPlaySnippet,
      ),
    );
  }

  @override
  State<AnkiReviewDialog> createState() => _AnkiReviewDialogState();
}

class _AnkiReviewDialogState extends State<AnkiReviewDialog>
    with SingleTickerProviderStateMixin {
  late List<AnkiCard> _queue;
  int _currentIndex = 0;
  bool _isFlipped = false;
  AnkiCardFaceMode _mode = AnkiCardFaceMode.cloze;
  bool _clozeRevealed = false;
  int _reviewedCount = 0;
  bool _completed = false;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _queue = List.of(widget.cards);
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOutCubic),
    );

    // Auto-play first snippet if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playCurrentSnippet();
    });
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _playCurrentSnippet() {
    if (_queue.isEmpty || _currentIndex >= _queue.length) return;
    final card = _queue[_currentIndex];
    widget.onPlaySnippet?.call(card.startMs, card.endMs);
  }

  void _flipCard() {
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  Future<void> _rateCard(AnkiRating rating) async {
    final currentCard = _queue[_currentIndex];
    await widget.aiGovernorService.reviewAnkiCard(currentCard.id, rating);
    _reviewedCount++;

    if (rating == AnkiRating.again) {
      // Re-queue card at the end of the session for immediate re-learning
      _queue.add(currentCard.applyRating(rating));
    }

    if (_currentIndex + 1 < _queue.length) {
      _flipController.reset();
      setState(() {
        _currentIndex++;
        _isFlipped = false;
        _clozeRevealed = false;
      });
      _playCurrentSnippet();
    } else {
      setState(() {
        _completed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final height = MediaQuery.of(context).size.height * 0.88;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ll.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const LLMark(size: 16),
                const SizedBox(width: 8),
                Text(
                  'Anki · AI 记忆强化',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ll.textPrimary,
                  ),
                ),
                const Spacer(),
                if (!_completed && _queue.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: ll.emphasis,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${_queue.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ll.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close, size: 20, color: ll.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          Divider(height: 1, color: ll.divider),

          // Content
          Expanded(
            child: _completed
                ? _buildCompletionView(context)
                : _buildReviewView(context),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewView(BuildContext context) {
    final ll = context.ll;

    if (_queue.isEmpty) {
      return Center(
        child: Text(
          '当前课程暂无待复习闪卡\n点击单句上的「🎴 闪卡」即可加入！',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.6, color: ll.textTertiary),
        ),
      );
    }

    final card = _queue[_currentIndex];
    final surfaceColor = ll.surfaceHigh;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          // Mode toggle row (Cloze / Blind / Full)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModeChip(context, '🔤 填空', AnkiCardFaceMode.cloze),
                const SizedBox(width: 8),
                _buildModeChip(context, '🎧 盲听', AnkiCardFaceMode.blind),
                const SizedBox(width: 8),
                _buildModeChip(context, '📖 全显', AnkiCardFaceMode.full),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3D Flip Card
          Expanded(
            child: GestureDetector(
              onTap: _flipCard,
              child: AnimatedBuilder(
                animation: _flipAnimation,
                builder: (context, child) {
                  final angle = _flipAnimation.value * math.pi;
                  final isBack = _flipAnimation.value >= 0.5;

                  return Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(angle),
                    alignment: Alignment.center,
                    child: isBack
                        ? Transform(
                            transform: Matrix4.identity()..rotateY(math.pi),
                            alignment: Alignment.center,
                            child: _buildBackCard(
                              context,
                              card,
                              surfaceColor,
                            ),
                          )
                        : _buildFrontCard(context, card, surfaceColor),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Controls
          if (!_isFlipped)
            ElevatedButton.icon(
              onPressed: _flipCard,
              icon: const Icon(Icons.flip_to_back_rounded, size: 18),
              label: const Text(
                '翻转查看 AI 详解',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          else
            _buildRatingButtons(context),
        ],
      ),
    );
  }

  Widget _buildModeChip(
    BuildContext context,
    String label,
    AnkiCardFaceMode mode,
  ) {
    final ll = context.ll;
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: LLMotion.normal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? ll.inverseSurface : ll.emphasis,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? ll.onInverseSurface : ll.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildFrontCard(
    BuildContext context,
    AnkiCard card,
    Color surfaceColor,
  ) {
    final ll = context.ll;
    final shape = context.llShape;

    String displayText;
    switch (_mode) {
      case AnkiCardFaceMode.cloze:
        displayText = _clozeRevealed ? card.sentenceText : card.clozeSentence;
        break;
      case AnkiCardFaceMode.blind:
        displayText = '🎧 【盲听磨耳朵中】\n点击播放原声，闭目捕捉每个发音细节';
        break;
      case AnkiCardFaceMode.full:
        displayText = card.sentenceText;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ll.divider, width: 1.2),
        boxShadow: [
          if (shape.shadowOn)
            BoxShadow(
              color: ll.shadow.withValues(alpha: shape.shadowAlpha),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ll.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '正面 · 听感记忆',
                  style: TextStyle(
                    fontSize: 11,
                    color: ll.info,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _playCurrentSnippet,
                icon: Icon(
                  Icons.volume_up_rounded,
                  color: ll.info,
                  size: 24,
                ),
                tooltip: '重听原声片段',
              ),
            ],
          ),
          const Spacer(),

          // Sentence Display
          SelectableText(
            displayText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _mode == AnkiCardFaceMode.blind ? 15 : 20,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: ll.textPrimary,
            ),
          ),
          if (_mode == AnkiCardFaceMode.cloze && !_clozeRevealed) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _clozeRevealed = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: ll.emphasis,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '点击揭晓挖空词',
                  style: TextStyle(fontSize: 11, color: ll.textTertiary),
                ),
              ),
            ),
          ],
          const Spacer(),

          // AI Phonetic Clue
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: ll.emphasis,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 16,
                  color: ll.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    card.phoneticClue,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: ll.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackCard(
    BuildContext context,
    AnkiCard card,
    Color surfaceColor,
  ) {
    final ll = context.ll;
    final shape = context.llShape;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ll.success.withValues(alpha: 0.4), width: 1.4),
        boxShadow: [
          if (shape.shadowOn)
            BoxShadow(
              color: ll.shadow.withValues(alpha: shape.shadowAlpha * 1.2),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ll.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '背面 · AI 深度复盘',
                    style: TextStyle(
                      fontSize: 11,
                      color: ll.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _playCurrentSnippet,
                  icon: Icon(
                    Icons.volume_up_rounded,
                    color: ll.success,
                    size: 24,
                  ),
                  tooltip: '重听原声片段',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Bilingual Original
            Text(
              card.sentenceText,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ll.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card.chineseTranslation,
              style: TextStyle(
                fontSize: 14,
                color: ll.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: ll.divider),
            const SizedBox(height: 14),

            // AI In-Depth Explanation
            Text(
              card.aiExplanation,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: ll.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingButtons(BuildContext context) {
    final ll = context.ll;
    return Row(
      children: [
        _buildRatingBtn(AnkiRating.again, ll.danger),
        const SizedBox(width: 8),
        _buildRatingBtn(AnkiRating.hard, ll.warning),
        const SizedBox(width: 8),
        _buildRatingBtn(AnkiRating.good, ll.success),
        const SizedBox(width: 8),
        _buildRatingBtn(AnkiRating.easy, ll.info),
      ],
    );
  }

  Widget _buildRatingBtn(AnkiRating rating, Color color) {
    return Expanded(
      child: InkWell(
        onTap: () => _rateCard(rating),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rating.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rating.intervalDescription,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionView(BuildContext context) {
    final ll = context.ll;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ll.success.withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: 44,
                color: ll.success,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '今日复习已完成！',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ll.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '本次共强化练习 $_reviewedCount 张听力闪卡\nSM-2 艾宾浩斯记忆曲线已排期下次复盘。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: ll.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(160, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('好的，继续精听'),
            ),
          ],
        ),
      ),
    );
  }
}
