import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../creation/translation_service.dart';
import '../creation/youtube_relay.dart';
import '../l10n/ll_strings.dart';
import '../preferences/app_preferences.dart';
import '../theme/listenloop_theme.dart';

/// Settings: Premium Grouped-Cards layout with modern segmented pills,
/// live typographic canvas, and visual ASR / Translation configuration./// Settings hub.
///
/// Level 1 (this screen) is the whole story for the two things people change
/// most — theme and interface language — which sit at the top as one-tap
/// segmented controls. Everything else is grouped by intent:
/// `AI & models` → `Playback & recognition` → `Connection`, each group a card
/// of rows that show their live value and open a level-2 page.
///
/// It used to be a single long scroll of seven stacked cards, which made the
/// page feel heavy: finding one switch meant swiping past ~1.5 screens of
/// unrelated content. Summaries keep everything glanceable without opening
/// anything.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final controller = PreferencesScope.of(context);
    final prefs = controller.prefs;
    final s = LLStrings.of(context);
    final zh = prefs.uiLanguage == AppLanguage.chinese;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: llSystemOverlay(ll.brightness),
      child: Scaffold(
        backgroundColor: ll.bg,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LLSpacing.lg,
              LLSpacing.xl,
              LLSpacing.lg,
              LLSpacing.huge + LLSpacing.xl,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: LLSpacing.xl),
                child: Text(
                  s.settingsTitle,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: ll.textPrimary,
                  ),
                ),
              ),

              // 外观置顶：主题与语言是最高频的切换项，做成一级页直达的
              // 分段控件，不设二级页。
              _GroupLabel(
                text: zh ? '外观' : 'APPEARANCE',
                palette: ll,
                tracking: zh ? 0.4 : 1.3,
              ),
              const SizedBox(height: 10),
              _SettingsCard(
                palette: ll,
                children: [
                  _FullWidthSegments<ThemeMode>(
                    selected: prefs.themeMode,
                    options: [
                      (ThemeMode.system, s.system),
                      (ThemeMode.light, s.light),
                      (ThemeMode.dark, s.dark),
                    ],
                    onSelect: (mode) => controller.update(themeMode: mode),
                    palette: ll,
                  ),
                  const SizedBox(height: 8),
                  _FullWidthSegments<AppLanguage>(
                    selected: prefs.uiLanguage,
                    options: [
                      for (final language in AppLanguage.values)
                        (language, language.nativeLabel),
                    ],
                    onSelect: (language) => controller.update(uiLanguage: language),
                    palette: ll,
                  ),
                ],
              ),

              for (final group in _SettingsGroup.values) ...[
                const SizedBox(height: 26),
                _GroupLabel(
                  text: group.label(zh),
                  palette: ll,
                  tracking: zh ? 0.4 : 1.3,
                ),
                const SizedBox(height: 10),
                _SettingsCard(
                  palette: ll,
                  children: [
                    for (var i = 0; i < group.sections.length; i++) ...[
                      if (i > 0) _CardDivider(palette: ll, indent: 59),
                      _SettingsNavRow(
                        icon: group.sections[i].icon,
                        title: group.sections[i].title(s, prefs),
                        summary: group.sections[i].summary(s, prefs),
                        palette: ll,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _SettingsDetailPage(
                              section: group.sections[i],
                              controller: controller,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


}

Future<void> _showTextScaleSheet(
    BuildContext context,
    PreferencesController controller,
  ) async {
    final ll = context.ll;
    final s = LLStrings.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ll.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: AnimatedBuilder(
            animation: controller,
            builder: (sheetContext, _) {
              final scale = controller.prefs.textScale;
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          s.textSizeSheet,
                          style: LLText.controlLabel.copyWith(
                            color: ll.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: ll.bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ll.divider),
                          ),
                          child: Text(
                            '${scale.toStringAsFixed(2)}×',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ll.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: ll.textPrimary,
                        inactiveTrackColor: ll.divider,
                        thumbColor: ll.textPrimary,
                        overlayColor: ll.textPrimary.withValues(alpha: 0.12),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        min: kMinTextScale,
                        max: kMaxTextScale,
                        divisions: 24,
                        label: '${scale.toStringAsFixed(2)}×',
                        value: scale.clamp(kMinTextScale, kMaxTextScale),
                        onChanged: (value) => controller.update(textScale: value),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${kMinTextScale.toStringAsFixed(2)}× (小)',
                          style: LLText.caption.copyWith(color: ll.textTertiary),
                        ),
                        Text(
                          '${kMaxTextScale.toStringAsFixed(2)}× (大)',
                          style: LLText.caption.copyWith(color: ll.textTertiary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ll.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ll.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Listen carefully to how the sentence flows.',
                            style: LLLearning.englishSentence(ll, controller.prefs),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '仔细听这句话的声音是怎样流动的。',
                            style: LLLearning.chineseSentence(ll, controller.prefs),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

/// One entry of the settings hub. Order here is the order inside its group.
///
/// APPEARANCE is deliberately absent — theme + language live on the hub itself
/// as one-tap segmented controls, so they never need a level-2 page.
enum _SettingsSection { tutor, translation, typography, asr, scrubber, relay }

/// Groups on the hub, in display order.
enum _SettingsGroup {
  ai([_SettingsSection.tutor, _SettingsSection.translation]),
  playback([
    _SettingsSection.typography,
    _SettingsSection.asr,
    _SettingsSection.scrubber,
  ]),
  connection([_SettingsSection.relay]);

  const _SettingsGroup(this.sections);

  final List<_SettingsSection> sections;

  String label(bool zh) => switch (this) {
    _SettingsGroup.ai => zh ? 'AI 与模型' : 'AI & MODELS',
    _SettingsGroup.playback =>
      zh ? '播放与识别' : 'PLAYBACK & RECOGNITION',
    _SettingsGroup.connection => zh ? '连接' : 'CONNECTION',
  };
}


extension _SettingsSectionX on _SettingsSection {
  IconData get icon => switch (this) {
    _SettingsSection.tutor => Icons.smart_toy_outlined,
    _SettingsSection.typography => Icons.text_fields_rounded,
    _SettingsSection.asr => Icons.graphic_eq_rounded,
    _SettingsSection.scrubber => Icons.linear_scale_rounded,
    _SettingsSection.translation => Icons.translate_rounded,
    _SettingsSection.relay => Icons.router_rounded,
  };

  String title(LLStrings s, AppPreferences prefs) {
    final zh = prefs.uiLanguage == AppLanguage.chinese;
    return switch (this) {
      _SettingsSection.tutor => s.tutorOnlineTitle,
      _SettingsSection.typography => s.typography,
      _SettingsSection.asr => zh ? '语音识别 (ASR)' : 'Speech recognition',
      _SettingsSection.scrubber => zh ? '句跳滑栏' : 'Sentence scrubber',
      _SettingsSection.translation => s.translation,
      _SettingsSection.relay => s.youtubeRelayTitle,
    };
  }

  /// The one-line live value shown under the title on the hub.
  String summary(LLStrings s, AppPreferences prefs) {
    final zh = prefs.uiLanguage == AppLanguage.chinese;
    return switch (this) {
      _SettingsSection.tutor => prefs.hasTutorEndpoint
          ? '${zh ? "在线" : "Online"} · ${prefs.tutorModel}'
          : (zh ? '未配置 · 将退回离线解析' : 'Not set · falls back to offline'),
      _SettingsSection.typography =>
        '${prefs.learningFont.label} · ${prefs.textScale.toStringAsFixed(2)}×',
      _SettingsSection.asr =>
        '${prefs.asrTier == AsrTier.fast ? (zh ? "快速档" : "Fast") : (zh ? "精准档" : "Precise")}'
            ' · ${prefs.asrThreads}${zh ? " 核" : " threads"}',
      _SettingsSection.scrubber => prefs.scrubberHaptics
          ? (zh ? '触感反馈 开' : 'Haptics on')
          : (zh ? '触感反馈 关' : 'Haptics off'),
      _SettingsSection.translation => prefs.translationModel,
      _SettingsSection.relay => prefs.youtubeRelayBaseUrl,
    };
  }

  /// Level-2 content for this group.
  List<Widget> details({
    required BuildContext context,
    required PreferencesController controller,
  }) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final prefs = controller.prefs;
    final zh = prefs.uiLanguage == AppLanguage.chinese;

    return switch (this) {
      _SettingsSection.tutor => [
        _AiTutorSection(controller: controller, palette: ll),
      ],
      _SettingsSection.typography => [
        _SegmentedRow<LearningFont>(
          label: s.font,
          selected: prefs.learningFont,
          options: [
            for (final font in LearningFont.values) (font, font.label),
          ],
          onSelect: (font) => controller.update(learningFont: font),
          palette: ll,
        ),
        _CardDivider(palette: ll),
        GestureDetector(
          onLongPress: () => _showTextScaleSheet(context, controller),
          child: _TextSizeRow(
            selected: prefs.textScale,
            label: s.textSize,
            onSelect: (scale) => controller.update(textScale: scale),
            onOpenSlider: () => _showTextScaleSheet(context, controller),
            palette: ll,
          ),
        ),
        const SizedBox(height: LLSpacing.md),
        _PreviewCanvas(title: s.preview, controller: controller, palette: ll),
      ],
      _SettingsSection.asr => [
        _SegmentedRow<AsrTier>(
          label: zh ? '识别档位' : 'Model Tier',
          selected: prefs.asrTier,
          options: [
            for (final tier in AsrTier.values)
              (
                tier,
                tier == AsrTier.fast
                    ? (zh ? '快速(Base)' : 'Fast(Base)')
                    : (zh ? '精准(Small)' : 'Precise(Small)'),
              ),
          ],
          onSelect: (tier) => controller.update(asrTier: tier),
          palette: ll,
        ),
        _CardDivider(palette: ll),
        _SegmentedRow<int>(
          label: zh ? '解码线程' : 'ASR Threads',
          selected: prefs.asrThreads,
          options: const [(4, '4核'), (6, '6核(推荐)'), (8, '8核全开')],
          onSelect: (threads) => controller.update(asrThreads: threads),
          palette: ll,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.info_outline, size: 13, color: ll.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                zh
                    ? '骁龙 8 Gen 3 建议 6 核，吃满性能集群'
                    : 'Snapdragon 8 Gen 3: 6 threads recommended',
                style: TextStyle(fontSize: 11, color: ll.textTertiary),
              ),
            ),
          ],
        ),
      ],
      _SettingsSection.scrubber => [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zh ? '拖动触感反馈' : 'Haptic feedback',
                    style: TextStyle(fontSize: 14, color: ll.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    zh ? '拖动滑栏时逐档震动' : 'Per-tick vibration while dragging',
                    style: TextStyle(fontSize: 11, color: ll.textTertiary),
                  ),
                ],
              ),
            ),
            Switch(
              value: prefs.scrubberHaptics,
              activeThumbColor: ll.textPrimary,
              onChanged: (value) => controller.update(scrubberHaptics: value),
            ),
          ],
        ),
      ],
      _SettingsSection.translation => [
        _TranslationSection(controller: controller, palette: ll),
      ],
      _SettingsSection.relay => [
        _YouTubeRelaySection(controller: controller, palette: ll),
      ],
    };
  }
}


/// Uppercase micro-heading that gives the hub its rhythm.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({
    required this.text,
    required this.palette,
    this.tracking = 1.3,
  });

  final String text;
  final LLPalette palette;

  /// Letter-spacing that suits the script: wide tracking is a Latin display
  /// convention and makes CJK look loose, so Chinese labels pass a small value.
  final double tracking;

  /// Latin labels read better in caps; CJK must keep its own case.
  bool get _isLatin => text.codeUnits.every((c) => c < 128);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        _isLatin ? text.toUpperCase() : text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: tracking,
          color: palette.textTertiary,
        ),
      ),
    );
  }
}

/// Full-width segmented control.
///
/// The selection is a raised pill on a recessed track — depth is expressed with
/// the palette's own surface levels ([LLPalette.surface] over
/// [LLPalette.surfaceHigh]) rather than colour, which keeps ListenLoop's
/// black-and-white identity while still reading as a real control.
class _FullWidthSegments<T> extends StatelessWidget {
  const _FullWidthSegments({
    required this.selected,
    required this.options,
    required this.onSelect,
    required this.palette,
  });

  final T selected;
  final List<(T, String)> options;
  final ValueChanged<T> onSelect;
  final LLPalette palette;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final isDark = ll.brightness == Brightness.dark;

    // The thumb must read as raised against its track in BOTH themes.
    // Light: white thumb + hairline + a barely-there lift shadow (the track is
    // deepened to #E9E9E5 so the pure-white thumb separates from the white card
    // behind it — reusing `surface` alone made it invisible on light).
    // Dark: a step *up* from the track; `surface` would be darker and read as
    // recessed.
    final trackColor = isDark ? const Color(0xFF1C1C1C) : const Color(0xFFE9E9E5);
    final thumbColor = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFFFFFFF);
    final thumbBorder = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDADAD6);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (final (value, text) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: value == selected ? thumbColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: value == selected
                          ? thumbBorder
                          : Colors.transparent,
                    ),
                    boxShadow: value == selected && !isDark
                        ? const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          value == selected ? FontWeight.w600 : FontWeight.w500,
                      color: value == selected
                          ? ll.textPrimary
                          : ll.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A hub row: icon, group name, live value, chevron.
class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({
    required this.icon,
    required this.title,
    required this.summary,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final LLPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                // A touch deeper than surfaceHigh on light, and a touch lighter
                // than surfaceHigh on dark — the chip has to stay visible
                // against the card without turning into a coloured badge.
                color: ll.brightness == Brightness.dark
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFFEBEBE7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: ll.textSecondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: ll.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: ll.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: ll.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Level 2 of the settings hierarchy: one group, full width, no long scroll.
class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({required this.section, required this.controller});

  final _SettingsSection section;
  final PreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final prefs = controller.prefs;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: llSystemOverlay(ll.brightness),
      child: Scaffold(
        backgroundColor: ll.bg,
        appBar: AppBar(
          backgroundColor: ll.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          leading: BackButton(color: ll.textPrimary),
          title: Text(
            section.title(s, prefs),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ll.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LLSpacing.xl,
              LLSpacing.lg,
              LLSpacing.xl,
              LLSpacing.huge,
            ),
            children: [
              _SettingsCard(
                palette: ll,
                children: section.details(
                  context: context,
                  controller: controller,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



/// A modern grouped-card container with subtle border and crisp elevation.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children, required this.palette});

  final List<Widget> children;
  final LLPalette palette;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return Container(
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ll.divider, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hairline separator between rows.
///
/// [indent] lets the hub align the line with the row text (past the icon chip)
/// instead of letting it run under the icon — the small alignment detail that
/// separates "a list" from "a designed list".
class _CardDivider extends StatelessWidget {
  const _CardDivider({required this.palette, this.indent = 12});

  final LLPalette palette;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, right: 12),
      child: Divider(
        color: palette.divider.withValues(alpha: 0.7),
        height: 1,
        thickness: 1,
      ),
    );
  }
}

/// A row with a clear title on the left and a modern segmented pill selector on the right.
class _SegmentedRow<T> extends StatelessWidget {
  const _SegmentedRow({
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelect,
    required this.palette,
  });

  final String label;
  final T selected;
  final List<(T, String)> options;
  final ValueChanged<T> onSelect;
  final LLPalette palette;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final isDark = ll.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ll.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEEEEEC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (value, text) in options)
                  _SegmentedItem(
                    label: text,
                    selected: value == selected,
                    onTap: () => onSelect(value),
                    palette: ll,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedItem extends StatelessWidget {
  const _SegmentedItem({
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
    final isDark = ll.brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? const Color(0xFF333333) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? ll.textPrimary : ll.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Text size row with segmented buttons and a subtle slider quick-action.
class _TextSizeRow extends StatelessWidget {
  const _TextSizeRow({
    required this.selected,
    required this.label,
    required this.onSelect,
    required this.onOpenSlider,
    required this.palette,
  });

  final double selected;
  final String label;
  final ValueChanged<double> onSelect;
  final VoidCallback onOpenSlider;
  final LLPalette palette;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final isDark = ll.brightness == Brightness.dark;
    final activePreset = LearningTextSizePreset.fromScale(selected);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ll.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${selected.toStringAsFixed(2)}× · 长按或点右侧滑块',
                  style: TextStyle(fontSize: 11, color: ll.textTertiary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEEEEEC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < LearningTextSizePreset.values.length; i++) ...[
                  _SegmentedItem(
                    label: LearningTextSizePreset.values[i].label,
                    selected: activePreset == LearningTextSizePreset.values[i],
                    onTap: () => onSelect(LearningTextSizePreset.values[i].scale),
                    palette: ll,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 18),
            color: ll.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onOpenSlider,
            tooltip: '微调滑块',
          ),
        ],
      ),
    );
  }
}

/// Live preview card embedded directly inside the settings canvas.
class _PreviewCanvas extends StatelessWidget {
  const _PreviewCanvas({
    required this.title,
    required this.controller,
    required this.palette,
  });

  final String title;
  final PreferencesController controller;
  final LLPalette palette;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final prefs = controller.prefs;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ll.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ll.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.remove_red_eye_outlined, size: 13, color: ll.textTertiary),
              const SizedBox(width: 6),
              Text(
                title,
                style: LLText.sectionLabel.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.0,
                  color: ll.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                '${prefs.learningFont.label} · ${prefs.textScale.toStringAsFixed(2)}×',
                style: TextStyle(fontSize: 10, color: ll.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Listen carefully to\nhow the sentence flows.',
            style: LLLearning.englishSentence(ll, prefs),
          ),
          const SizedBox(height: 8),
          Text(
            '仔细听这句话的声音是怎样流动的。',
            style: LLLearning.chineseSentence(ll, prefs),
          ),
        ],
      ),
    );
  }
}

/// AI Translation configuration items.
class _TranslationSection extends StatefulWidget {
  const _TranslationSection({required this.controller, required this.palette});

  final PreferencesController controller;
  final LLPalette palette;

  @override
  State<_TranslationSection> createState() => _TranslationSectionState();
}

class _TranslationSectionState extends State<_TranslationSection> {
  bool _testing = false;
  String? _testMessage;
  bool _testPassed = false;

  @override
  Widget build(BuildContext context) {
    final s = LLStrings.of(context);
    final ll = widget.palette;
    final prefs = widget.controller.prefs;
    final hasKey = prefs.translationApiKey.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ValueRow(
          label: s.translationBaseUrl,
          value: prefs.translationBaseUrl,
          palette: ll,
          onTap: () => _editValue(
            title: s.translationBaseUrl,
            initial: prefs.translationBaseUrl,
            hint: s.translationBaseUrlHint,
            onSaved: (value) => widget.controller.update(translationBaseUrl: value),
          ),
        ),
        _CardDivider(palette: ll),
        _ValueRow(
          label: s.translationApiKey,
          value: hasKey ? _mask(prefs.translationApiKey) : s.translationApiKeyHint,
          muted: !hasKey,
          hasIndicator: true,
          indicatorActive: hasKey,
          palette: ll,
          onTap: () => _editValue(
            title: s.translationApiKey,
            initial: prefs.translationApiKey,
            hint: s.translationApiKeyHint,
            obscure: true,
            onSaved: (value) => widget.controller.update(translationApiKey: value),
          ),
        ),
        _CardDivider(palette: ll),
        _ValueRow(
          label: s.translationModel,
          value: prefs.translationModel,
          palette: ll,
          hasArrow: true,
          onTap: _pickModel,
        ),
        const SizedBox(height: 8),
        _TestRow(
          label: _testing ? s.translationTesting : s.translationTest,
          busy: _testing,
          message: _testMessage,
          passed: _testPassed,
          palette: ll,
          onTap: _testing ? null : _runTest,
        ),
      ],
    );
  }

  String _mask(String key) {
    final trimmed = key.trim();
    if (trimmed.length <= 4) return '••••';
    return '••••${trimmed.substring(trimmed.length - 4)}';
  }

  Future<void> _editValue({
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSaved,
    bool obscure = false,
  }) async {
    final s = LLStrings.of(context);
    final ll = widget.palette;
    final field = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ll.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: LLText.body.copyWith(color: ll.textPrimary, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: field,
          autofocus: true,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          style: TextStyle(color: ll.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: ll.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            style: FilledButton.styleFrom(
              backgroundColor: ll.textPrimary,
              foregroundColor: ll.bg,
            ),
            child: Text(s.save),
          ),
        ],
      ),
    );
    field.dispose();
    if (value == null) return;
    await onSaved(value.trim());
    if (!mounted) return;
    setState(() => _testMessage = null);
  }

  Future<void> _pickModel() async {
    final prefs = widget.controller.prefs;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: widget.palette.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ModelPickerSheet(
        baseUrl: prefs.translationBaseUrl,
        apiKey: prefs.translationApiKey,
        selected: prefs.translationModel,
        palette: widget.palette,
      ),
    );
    if (chosen == null) return;
    await widget.controller.update(translationModel: chosen);
    if (!mounted) return;
    setState(() => _testMessage = null);
  }

  Future<void> _runTest() async {
    final s = LLStrings.of(context);
    final prefs = widget.controller.prefs;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    String message;
    var passed = false;
    try {
      final result = await translateSentences(
        baseUrl: prefs.translationBaseUrl,
        apiKey: prefs.translationApiKey,
        model: prefs.translationModel,
        english: const ['Listening carefully takes practice.'],
        timeout: const Duration(seconds: 45),
      );
      final text = result.isEmpty ? '' : result.first.trim();
      if (text.isEmpty) {
        message = s.translationFailed('empty translation');
      } else {
        passed = true;
        message = '${s.translationTestOk(prefs.translationModel)} · $text';
      }
    } catch (error) {
      message = s.translationFailed('$error');
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testPassed = passed;
      _testMessage = message;
    });
  }
}

class _YouTubeRelaySection extends StatefulWidget {
  const _YouTubeRelaySection({required this.controller, required this.palette});

  final PreferencesController controller;
  final LLPalette palette;

  @override
  State<_YouTubeRelaySection> createState() => _YouTubeRelaySectionState();
}

class _YouTubeRelaySectionState extends State<_YouTubeRelaySection> {
  bool _testing = false;
  String? _testMessage;
  bool _testPassed = false;

  @override
  Widget build(BuildContext context) {
    final s = LLStrings.of(context);
    final ll = widget.palette;
    final prefs = widget.controller.prefs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ValueRow(
          label: s.youtubeRelayBaseUrl,
          value: prefs.youtubeRelayBaseUrl,
          palette: ll,
          onTap: () => _editValue(
            title: s.youtubeRelayBaseUrl,
            initial: prefs.youtubeRelayBaseUrl,
            hint: s.youtubeRelayBaseUrlHint,
            onSaved: (value) => widget.controller.update(youtubeRelayBaseUrl: value),
          ),
        ),
        _CardDivider(palette: ll),
        const SizedBox(height: 4),
        _TestRow(
          label: _testing ? s.youtubeRelayTesting : s.youtubeRelayTest,
          busy: _testing,
          message: _testMessage,
          passed: _testPassed,
          palette: ll,
          onTap: _testing ? null : _runRelayTest,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 13, color: ll.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.youtubeRelayTip,
                style: TextStyle(fontSize: 11, color: ll.textTertiary, height: 1.3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editValue({
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSaved,
  }) async {
    final s = LLStrings.of(context);
    final ll = widget.palette;
    final field = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ll.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: LLText.body.copyWith(color: ll.textPrimary, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: field,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          style: TextStyle(color: ll.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: ll.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            style: FilledButton.styleFrom(
              backgroundColor: ll.textPrimary,
              foregroundColor: ll.bg,
            ),
            child: Text(s.save),
          ),
        ],
      ),
    );
    field.dispose();
    if (value == null) return;
    await onSaved(value.trim());
    if (!mounted) return;
    setState(() => _testMessage = null);
  }

  Future<void> _runRelayTest() async {
    final s = LLStrings.of(context);
    final prefs = widget.controller.prefs;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final client = YouTubeRelayClient(baseUrl: prefs.youtubeRelayBaseUrl);
      final ok = await client.checkHealth();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testPassed = ok;
        _testMessage = ok ? s.youtubeRelayTestOk : s.youtubeRelayTestFailed('HTTP != 200');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testPassed = false;
        _testMessage = s.youtubeRelayTestFailed('$error');
      });
    }
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.palette,
    this.muted = false,
    this.hasIndicator = false,
    this.indicatorActive = false,
    this.hasArrow = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final LLPalette palette;
  final bool muted;
  final bool hasIndicator;
  final bool indicatorActive;
  final bool hasArrow;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (hasIndicator) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: indicatorActive ? const Color(0xFF10B981) : ll.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ll.textPrimary,
              ),
            ),
            const SizedBox(width: LLSpacing.md),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: muted ? ll.textTertiary : ll.textSecondary,
                ),
              ),
            ),
            if (hasArrow) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: ll.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  const _TestRow({
    required this.label,
    required this.busy,
    required this.message,
    required this.passed,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final String? message;
  final bool passed;
  final LLPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: ll.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ll.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(Icons.network_ping, size: 16, color: ll.textSecondary),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ll.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: passed ? const Color(0x1510B981) : const Color(0x15EF4444),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: passed ? const Color(0x4010B981) : const Color(0x40EF4444),
              ),
            ),
            child: Text(
              message!,
              style: TextStyle(
                fontSize: 12,
                color: passed ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// AI 伴学的在线通道配置：网关地址 / 密钥 / 模型 + 一键填充 + 连通自检。
///
/// 与翻译服务共用同一套 OpenAI 兼容语义（base URL 含 `/v1`），只是默认值
/// 指向本机 :3100 网关的免费线路。
/// One-line channel summary: online vs missing, and which route answers.
class _TutorStatusRow extends StatelessWidget {
  const _TutorStatusRow({
    required this.palette,
    required this.online,
    required this.model,
    required this.chinese,
  });

  final LLPalette palette;
  final bool online;
  final String model;

  /// Mirrors the hub summary wording, which is language-aware.
  final bool chinese;

  @override
  Widget build(BuildContext context) {
    final ll = palette;
    final dotColor = online ? const Color(0xFF10B981) : ll.disabled;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            online
                ? '${chinese ? '在线' : 'Online'} · $model'
                : (chinese ? '未配置 · 将退回离线解析' : 'Not set · falls back to offline'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: online ? ll.textPrimary : ll.textTertiary,
            ),
          ),
        ),
        if (online && model.toLowerCase().contains('mimo'))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: ll.textPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'MiMo',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: ll.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _AiTutorSection extends StatefulWidget {
  const _AiTutorSection({required this.controller, required this.palette});

  final PreferencesController controller;
  final LLPalette palette;

  @override
  State<_AiTutorSection> createState() => _AiTutorSectionState();
}

class _AiTutorSectionState extends State<_AiTutorSection> {
  bool _testing = false;
  String? _testMessage;
  bool _testPassed = false;

  @override
  Widget build(BuildContext context) {
    final s = LLStrings.of(context);
    final ll = widget.palette;
    final prefs = widget.controller.prefs;
    final hasKey = prefs.tutorApiKey.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TutorStatusRow(
          palette: ll,
          online: prefs.hasTutorEndpoint,
          model: prefs.tutorModel,
          chinese: prefs.uiLanguage == AppLanguage.chinese,
        ),
        const SizedBox(height: 10),
        _ValueRow(
          label: s.tutorBaseUrl,
          value: prefs.tutorBaseUrl,
          palette: ll,
          onTap: () => _editValue(
            title: s.tutorBaseUrl,
            initial: prefs.tutorBaseUrl,
            hint: s.tutorBaseUrlHint,
            onSaved: (value) => widget.controller.update(tutorBaseUrl: value),
          ),
        ),
        _CardDivider(palette: ll),
        _ValueRow(
          label: s.tutorApiKey,
          value: hasKey ? _mask(prefs.tutorApiKey) : s.tutorApiKeyHint,
          muted: !hasKey,
          hasIndicator: true,
          indicatorActive: hasKey,
          palette: ll,
          onTap: () => _editValue(
            title: s.tutorApiKey,
            initial: prefs.tutorApiKey,
            hint: s.tutorApiKeyHint,
            obscure: true,
            onSaved: (value) => widget.controller.update(tutorApiKey: value),
          ),
        ),
        _CardDivider(palette: ll),
        _ValueRow(
          label: s.tutorModel,
          value: prefs.tutorModel,
          palette: ll,
          hasArrow: true,
          onTap: _pickModel,
        ),
        const SizedBox(height: 8),
        _TestRow(
          label: _testing ? s.tutorTesting : s.tutorTest,
          busy: _testing,
          message: _testMessage,
          passed: _testPassed,
          palette: ll,
          onTap: _testing ? null : _runTest,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: InkWell(
            onTap: _resetToMimoDefaults,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: ll.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ll.divider),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: ll.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    s.tutorPrefillFree,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ll.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          s.tutorFreeTip,
          style: LLText.caption.copyWith(color: ll.textTertiary, height: 1.45),
        ),
      ],
    );
  }

  String _mask(String key) {
    final trimmed = key.trim();
    if (trimmed.length <= 4) return '••••';
    return '••••${trimmed.substring(trimmed.length - 4)}';
  }

  Future<void> _editValue({
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSaved,
    bool obscure = false,
  }) async {
    final s = LLStrings.of(context);
    final ll = widget.palette;
    final field = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ll.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: LLText.body.copyWith(
                color: ll.textPrimary, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: field,
          autofocus: true,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          style: TextStyle(color: ll.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: ll.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            style: FilledButton.styleFrom(
              backgroundColor: ll.textPrimary,
              foregroundColor: ll.bg,
            ),
            child: Text(s.save),
          ),
        ],
      ),
    );
    field.dispose();
    if (value == null) return;
    await onSaved(value.trim());
    if (!mounted) return;
    setState(() => _testMessage = null);
  }

  Future<void> _pickModel() async {
    final prefs = widget.controller.prefs;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: widget.palette.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ModelPickerSheet(
        baseUrl: prefs.tutorBaseUrl,
        apiKey: prefs.tutorApiKey,
        selected: prefs.tutorModel,
        palette: widget.palette,
        fallbackIds: kTutorFallbackModels,
      ),
    );
    if (chosen == null) return;
    await widget.controller.update(tutorModel: chosen);
    if (!mounted) return;
    setState(() => _testMessage = null);
  }

  /// 把三项配置一键恢复成随包预置的 MiMo 默认值。
  Future<void> _resetToMimoDefaults() async {
    final s = LLStrings.of(context);
    await widget.controller.update(
      tutorBaseUrl: kDefaultTutorBaseUrl,
      tutorApiKey: kDefaultTutorApiKey,
      tutorModel: kDefaultTutorModel,
    );
    if (!mounted) return;
    setState(() {
      _testMessage = s.tutorPrefilled;
      _testPassed = true;
    });
  }

  /// 真实发一轮短问答，验证「网关鉴权 + 模型可用 + 返回可解析」整链路。
  Future<void> _runTest() async {
    final s = LLStrings.of(context);
    final prefs = widget.controller.prefs;
    setState(() {
      _testing = true;
      _testMessage = null;
    });

    var passed = false;
    late String message;
    final stopwatch = Stopwatch()..start();
    try {
      final reply = await probeTutorChat(
        baseUrl: prefs.tutorBaseUrl,
        apiKey: prefs.tutorApiKey,
        models: <String>[
          prefs.tutorModel,
          ...kTutorFallbackModels,
        ],
      );
      stopwatch.stop();
      passed = reply.reply.trim().isNotEmpty;
      message = passed
          ? '${s.tutorTestOk(reply.model)} · ${stopwatch.elapsed.inMilliseconds}ms'
          : s.tutorTestFailed('empty reply from ${reply.model}');
    } catch (error) {
      message = s.tutorTestFailed('$error');
    }

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testPassed = passed;
      _testMessage = message;
    });
  }
}

/// Result of a single tutor probe — which model actually answered.
class TutorProbeResult {
  const TutorProbeResult({required this.model, required this.reply});

  final String model;
  final String reply;
}

/// Sends one tiny chat turn through the gateway, walking the free fallback
/// chain until a model answers. Used by Settings only — it never touches a
/// paid route and always keeps `max_tokens` small.
Future<TutorProbeResult> probeTutorChat({
  required String baseUrl,
  required String apiKey,
  required List<String> models,
  http.Client? client,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final base = baseUrl.trim();
  if (base.isEmpty) throw const FormatException('empty tutor endpoint');
  final endpoint = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (apiKey.trim().isNotEmpty) {
    headers['Authorization'] = 'Bearer ${apiKey.trim()}';
  }

  final owned = client == null;
  final effectiveClient = client ?? http.Client();
  String? lastError;
  try {
    for (final model in models) {
      try {
        final response = await effectiveClient
            .post(
              endpoint,
              headers: headers,
              body: jsonEncode({
                'model': model,
                'messages': <Map<String, String>>[
                  {
                    'role': 'user',
                    'content': 'Reply with a single word: ready.',
                  },
                ],
                'max_tokens': 64,
                'temperature': 0.2,
              }),
            )
            .timeout(timeout);

        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode} ($model)';
          if (response.statusCode == 401 || response.statusCode == 403) {
            throw lastError;
          }
          continue;
        }

        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          lastError = 'no choices ($model)';
          continue;
        }
        final message =
            (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
        final content = (message?['content'] as String?)?.trim() ?? '';
        final reasoning = (message?['reasoning'] as String?)?.trim() ?? '';
        final answer = content.isNotEmpty ? content : reasoning;
        if (answer.isEmpty) {
          lastError = 'empty content ($model)';
          continue;
        }
        return TutorProbeResult(model: model, reply: answer);
      } catch (error) {
        lastError = '$error';
      }
    }
  } finally {
    if (owned) effectiveClient.close();
  }
  throw FormatException(lastError ?? 'no tutor route available');
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.baseUrl,
    required this.apiKey,
    required this.selected,
    required this.palette,
    this.fallbackIds = const <String>[],
  });

  final String baseUrl;
  final String apiKey;
  final String selected;
  final LLPalette palette;

  /// Model ids in the tutor fallback chain; they carry a badge in the list so
  /// the user can see which tiers a failure will roll through.
  final List<String> fallbackIds;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  late Future<List<String>> _models = _fetch();
  final TextEditingController _search = TextEditingController();

  Future<List<String>> _fetch() => fetchTranslationModels(
        baseUrl: widget.baseUrl,
        apiKey: widget.apiKey,
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ll = widget.palette;
    final s = LLStrings.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Text(
                  s.translationModelSheet,
                  style: LLText.controlLabel.copyWith(
                    color: ll.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: ll.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ll.divider),
                  ),
                  child: TextField(
                    controller: _search,
                    autocorrect: false,
                    style: TextStyle(color: ll.textPrimary, fontSize: 14),
                    onChanged: (value) => setState(() {}),
                    decoration: InputDecoration(
                      icon: Icon(Icons.search, size: 18, color: ll.textTertiary),
                      hintText: s.translationModelSearch,
                      hintStyle: TextStyle(color: ll.textTertiary, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: _models,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Center(
                        child: Text(
                          s.translationModelLoading,
                          style: LLText.caption.copyWith(color: ll.textTertiary),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.translationFailed('${snapshot.error}'),
                                textAlign: TextAlign.center,
                                style: LLText.caption.copyWith(color: ll.textTertiary),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => setState(() => _models = _fetch()),
                                child: Text(s.translationModelRetry),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final query = _search.text.trim().toLowerCase();
                    final all = snapshot.data ?? const <String>[];
                    final shown = query.isEmpty
                        ? all
                        : [
                            for (final id in all)
                              if (id.toLowerCase().contains(query)) id,
                          ];
                    if (shown.isEmpty) {
                      return Center(
                        child: Text(
                          s.translationFailed('no model matches "$query"'),
                          style: LLText.caption.copyWith(color: ll.textTertiary),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => Divider(color: ll.divider.withValues(alpha: 0.4), height: 1),
                      itemBuilder: (context, index) {
                        final id = shown[index];
                        final isSelected = id == widget.selected;
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          id,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isSelected ? ll.textPrimary : ll.textSecondary,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (widget.fallbackIds.contains(id)) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: ll.textPrimary
                                                .withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '回退',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.6,
                                              color: ll.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check, size: 18, color: ll.textPrimary),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
