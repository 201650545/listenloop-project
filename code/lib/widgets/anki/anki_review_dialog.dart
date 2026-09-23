import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/ai_governor_service.dart';
import '../../models/anki_card_model.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF141414) : const Color(0xFFF9F9F8);

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryColor = isDark ? Colors.white70 : Colors.black87;
    final tertiaryColor = isDark ? Colors.white38 : Colors.black45;
    final dividerColor = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E5E5);

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
                color: tertiaryColor,
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
                const Text(
                  'Anki · AI 记忆强化',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (!_completed && _queue.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF282828) : const Color(0xFFEBEBEB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${_queue.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: secondaryColor,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),

          // Content
          Expanded(
            child: _completed ? _buildCompletionView(context, isDark) : _buildReviewView(context, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewView(BuildContext context, bool isDark) {
    if (_queue.isEmpty) {
      return Center(
        child: Text(
          '当前课程暂无待复习闪卡\n点击单句上的「🎴 闪卡」即可加入！',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      );
    }

    final card = _queue[_currentIndex];
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0);

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
                _buildModeChip('🔤 填空', AnkiCardFaceMode.cloze, isDark),
                const SizedBox(width: 8),
                _buildModeChip('🎧 盲听', AnkiCardFaceMode.blind, isDark),
                const SizedBox(width: 8),
                _buildModeChip('📖 全显', AnkiCardFaceMode.full, isDark),
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
                            child: _buildBackCard(card, surfaceColor, borderColor, isDark),
                          )
                        : _buildFrontCard(card, surfaceColor, borderColor, isDark),
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
              label: const Text('翻转查看 AI 详解', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )
          else
            _buildRatingButtons(isDark),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, AnkiCardFaceMode mode, bool isDark) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? const Color(0xFF262626) : const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildFrontCard(
    AnkiCard card,
    Color surfaceColor,
    Color borderColor,
    bool isDark,
  ) {
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
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
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
                  color: Colors.blueAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '正面 · 听感记忆',
                  style: TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _playCurrentSnippet,
                icon: const Icon(Icons.volume_up_rounded, color: Colors.blueAccent, size: 24),
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
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          if (_mode == AnkiCardFaceMode.cloze && !_clozeRevealed) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _clozeRevealed = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFECECEC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '点击揭晓挖空词',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
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
              color: isDark ? const Color(0xFF262626) : const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    card.phoneticClue,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? Colors.white70 : Colors.black87,
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
    AnkiCard card,
    Color surfaceColor,
    Color borderColor,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '背面 · AI 深度复盘',
                    style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _playCurrentSnippet,
                  icon: const Icon(Icons.volume_up_rounded, color: Colors.green, size: 24),
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
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card.chineseTranslation,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
            const SizedBox(height: 14),

            // AI In-Depth Explanation
            Text(
              card.aiExplanation,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingButtons(bool isDark) {
    return Row(
      children: [
        _buildRatingBtn(AnkiRating.again, Colors.redAccent, isDark),
        const SizedBox(width: 8),
        _buildRatingBtn(AnkiRating.hard, Colors.orangeAccent, isDark),
        const SizedBox(width: 8),
        _buildRatingBtn(AnkiRating.good, Colors.green, isDark),
        const SizedBox(width: 8),
        _buildRatingBtn(AnkiRating.easy, Colors.blueAccent, isDark),
      ],
    );
  }

  Widget _buildRatingBtn(AnkiRating rating, Color color, bool isDark) {
    return Expanded(
      child: InkWell(
        onTap: () => _rateCard(rating),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.16 : 0.1),
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

  Widget _buildCompletionView(BuildContext context, bool isDark) {
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
                color: Colors.green.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.check_circle_rounded, size: 44, color: Colors.green),
            ),
            const SizedBox(height: 20),
            const Text(
              '今日复习已完成！',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              '本次共强化练习 $_reviewedCount 张听力闪卡\nSM-2 艾宾浩斯记忆曲线已排期下次复盘。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(160, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('好的，继续精听'),
            ),
          ],
        ),
      ),
    );
  }
}
