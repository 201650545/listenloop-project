import 'package:flutter/material.dart';

import '../models/sentence.dart';
import '../theme/listenloop_theme.dart';
import '../utils/time_format.dart';

/// The visual centre of the listening screen: the current English sentence
/// (first focus), the Chinese translation (second layer) and the sentence's
/// time range on the original media timeline (kept quiet).
///
/// Typography comes from the user's learning preferences (font + text scale)
/// via [styles] — spec V2 §二十七. Visibility of each layer follows the
/// selected subtitle mode — spec V0.1 §6, §7, §15.
class SentenceDisplay extends StatelessWidget {
  const SentenceDisplay({
    super.key,
    required this.sentence,
    required this.currentPosition,
    this.showEnglish = true,
    this.showChinese = true,
    this.styles,
  });

  final Sentence sentence;
  final Duration currentPosition;
  final bool showEnglish;
  final bool showChinese;

  /// Learning typography resolved by the caller from the user preferences.
  final LLReadLearningStyles? styles;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final styles = this.styles;
    // No AnimatedSize here: animating the text block's height is what made a
    // long→short sentence switch look like the previous sentence was still
    // dissolving. The surrounding card owns the footprint; this only paints.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEnglish)
          Text(
            sentence.originalText,
            textAlign: TextAlign.center,
            style:
                styles?.english ??
                TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                  color: ll.textPrimary,
                ),
          ),
        if (showChinese)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              sentence.translatedText,
              textAlign: TextAlign.center,
              style:
                  styles?.chinese ??
                  TextStyle(
                    fontSize: 18,
                    height: 1.45,
                    color: ll.textSecondary,
                  ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          '${formatMsAsSeconds(sentence.startMs)} '
          '→ ${formatMsAsSeconds(sentence.endMs)}',
          style: LLText.caption.copyWith(
            color: ll.textTertiary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Resolved learning styles handed to the sentence views.
class LLReadLearningStyles {
  const LLReadLearningStyles({required this.english, required this.chinese});

  final TextStyle english;
  final TextStyle chinese;
}
