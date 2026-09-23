import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// Subtitle visibility selector (spec V2 follow-up 中英文切换):
/// HIDE / EN / ZH / EN-ZH, default bilingual. Text-only styling per V2
/// §二十八 — selected = white with a short underline; the rest tertiary
/// grey. No pills.
enum SubtitleMode { hidden, english, chinese, bilingual }

extension SubtitleModeX on SubtitleMode {
  /// Whether the original transcript (English, Japanese, etc.) should be shown.
  bool get showsOriginal => this != SubtitleMode.hidden;

  /// Compatibility alias for [showsOriginal].
  bool get showsEnglish => showsOriginal;

  /// Whether the translation (Chinese, etc.) should be shown.
  bool get showsTranslation =>
      this == SubtitleMode.chinese || this == SubtitleMode.bilingual;

  /// Compatibility alias for [showsTranslation].
  bool get showsChinese => showsTranslation;

  /// Resolves the standard 2-character language uppercase code (e.g. 'JA', 'EN', 'FR').
  static String resolveLanguageCode(String? sourceLanguage) {
    if (sourceLanguage == null || sourceLanguage.trim().isEmpty) return 'EN';
    final tag = sourceLanguage.trim().toLowerCase();
    if (tag.startsWith('ja')) return 'JA';
    if (tag.startsWith('zh')) return 'ZH';
    if (tag.startsWith('fr')) return 'FR';
    if (tag.startsWith('de')) return 'DE';
    if (tag.startsWith('es')) return 'ES';
    if (tag.startsWith('ko')) return 'KO';
    if (tag.startsWith('ru')) return 'RU';
    if (tag.startsWith('it')) return 'IT';
    if (tag.startsWith('en')) return 'EN';
    final clean = tag.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    return clean.length >= 2 ? clean.substring(0, 2).toUpperCase() : 'EN';
  }

  /// Dynamic display label adapting to the course's source language.
  String labelFor([String? sourceLanguage]) {
    final code = resolveLanguageCode(sourceLanguage);
    return switch (this) {
      SubtitleMode.hidden => 'HIDE',
      SubtitleMode.english => code,
      SubtitleMode.chinese => 'ZH',
      SubtitleMode.bilingual => '$code/ZH',
    };
  }

  /// Default label assuming English source.
  String get label => labelFor('en');
}

class SubtitleModeSelector extends StatelessWidget {
  const SubtitleModeSelector({
    super.key,
    required this.mode,
    required this.onChanged,
    this.sourceLanguage,
  });

  final SubtitleMode mode;
  final ValueChanged<SubtitleMode> onChanged;

  /// The source language of the current lesson (e.g. 'ja', 'en', 'fr').
  /// Adapts button labels from default 'EN' to 'JA', 'FR', etc.
  final String? sourceLanguage;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final value in SubtitleMode.values)
          _ModeOption(
            label: value.labelFor(sourceLanguage),
            selected: value == mode,
            onTap: () => onChanged(value),
            palette: ll,
          ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? palette.textPrimary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            letterSpacing: 1.1,
            color: selected ? palette.textPrimary : palette.textTertiary,
          ),
        ),
      ),
    );
  }
}
