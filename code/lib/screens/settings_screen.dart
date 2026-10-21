import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../creation/translation_service.dart';
import '../creation/youtube_relay.dart';
import '../data/profile_store.dart';
import '../l10n/ll_strings.dart';
import '../preferences/app_preferences.dart';
import '../storage/lesson_repository.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/chinese_textbook_ruby_layout.dart';
import '../widgets/ll_colophon.dart';
import '../widgets/ll_lamp_bar.dart';
import '../widgets/ll_page.dart';
import '../widgets/ll_primitives.dart';
import '../widgets/ll_profile_entry_card.dart';
import '../widgets/ll_style_rack.dart';
import 'cloud_catalog_sheet.dart';
import 'profile_screen.dart';

/// Settings — redesigned as the **版权页 of the book** (WP-I, 2026-10-13).
///
/// The page used to be an iOS grouped list: equal-weight rows, rounded white
/// cards, grey section labels. That is the grammar of a system control panel,
/// and it is what 郭老师 rejected outright — swapping only the style picker
/// left the skeleton intact, so the page read as "same as before".
///
/// Structure now, top to bottom:
///
/// 1. **天头** — a quiet `sectionLabel` head + a UI-language toggle + the guest
///    door. The 30sp「设置」title wall is gone.
/// 2. **卷首 · 书名页** — the book names itself (「句读」 + the colophon line),
///    then the honest 访客 profile card, demoted from first screen hero.
/// 3. **一 · 纸与光** — the page's one big thing: a rack of four 扉页 (each
///    self-themed, each with its name) and a 灯绳 for brightness.
/// 4. **二 · 读** — the reading knobs, all operable in place: text size steps,
///    both fonts, and the live preview canvas that proves the change landed.
/// 5. **三 · 跟读** — read-along calibration and haptics, also in place.
/// 6. **四 · 高级** — folded by default: model / network / thread entries, so the
///    dev hot-sync note never appears on the main path again.
/// 7. **版权页** — two lines of colophon instead of an "About" card.
///
/// Level-2 pages still exist, but only for the three genuinely heavy forms
/// (AI tutor / translation / relay). Everything you touch daily is inline.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.repository});

  final LessonRepository? repository;

  @override
  Widget build(BuildContext context) {
    final controller = PreferencesScope.of(context);
    final prefs = controller.prefs;
    final zh = prefs.uiLanguage == AppLanguage.chinese;
    // 离线登录：档案表。没挂 ProfileScope 的场合（单测）就不摆这张卡，
    // 免得点进去是空页。
    final profileStore = ProfileScope.maybeOf(context);

    return LLPage(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LLSpacing.lg,
          LLSpacing.xl,
          LLSpacing.lg,
          LLSpacing.huge + LLSpacing.xl,
        ),
        children: [
          // ① 天头：不再做 30sp 的「设置」大字。书的页面顶部是天头。
          _Masthead(
            zh: zh,
            language: prefs.uiLanguage,
            onLanguage: (language) => controller.update(uiLanguage: language),
          ),
          const SizedBox(height: LLSpacing.xxl),

          // ② 卷首 · 书名页：先让书自报姓名，档案卡退到书名下面。
          //
          // 2026-10-20 离线登录：这一张卡就是**档案入口**（头像 + 当前档案
          // 名字 + 是否设了密码），点进去就是档案页。原来它摆的是"访客 ·
          // 未登录"的假身份，与真的档案系统自相矛盾 —— 现在换掉。
          _TitlePage(
            zh: zh,
            fontFamily: context.llStyle.headingFont,
            child: LLProfileEntryCard(
              zh: zh,
              profileName: profileStore?.active.name,
              profileEmoji: profileStore?.active.emoji,
              profileHasPin: profileStore?.active.hasPin ?? false,
              onTap: profileStore == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfileScreen(
                            store: profileStore,
                            preferences: controller,
                          ),
                        ),
                      ),
            ),
          ),
          const SizedBox(height: LLSpacing.xxl),

          // ③ 功能目录
          //
          // 2026-10-20（GPT 镜像评审 §四 P3）：设置首页应当像**目录**，不像
          // 一列互相分离的海报。原来每个功能各自一张卡（同样的重量、同样的
          // 圆角、同样的阴影），于是"组件形状不协调"。现在：功能项收进
          // **同一张卡**，组内用发丝线分隔；进二级页后才用卡片去装真正需要
          // 实体容器的内容（风格预览、字体样张……）。
          _SettingsHubGroup(
            items: [
              (
                icon: Icons.auto_stories_outlined,
                title: zh ? '纸与光' : 'Paper & Light',
                summary: zh
                    ? '${prefs.style.label(zh)} · ${switch (prefs.themeMode) {
                        ThemeMode.system => '跟随系统',
                        ThemeMode.light => '白昼',
                        ThemeMode.dark => '黑夜',
                      }}'
                    : '${prefs.style.label(zh)} · ${switch (prefs.themeMode) {
                        ThemeMode.system => 'System',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      }}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PreferencesScope(
                      controller: controller,
                      child: _PaperAndLightDetailPage(
                        controller: controller,
                        zh: zh,
                      ),
                    ),
                  ),
                ),
              ),
              (
                icon: Icons.format_size_rounded,
                title: zh ? '字与读' : 'Typography & Reading',
                summary: zh
                    ? '字号 ${(prefs.textScale * 100).round()}% · 中文 ${prefs.learningChineseFont.label} · 英文 ${prefs.learningFont.label}'
                    : 'Size ${(prefs.textScale * 100).round()}% · ${prefs.learningChineseFont.label} · ${prefs.learningFont.label}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PreferencesScope(
                      controller: controller,
                      child: _TypographyDetailPage(
                        controller: controller,
                        zh: zh,
                      ),
                    ),
                  ),
                ),
              ),
              (
                icon: Icons.record_voice_over_outlined,
                title: zh ? '跟读与纠音' : 'Read-Along & Speech',
                summary: zh
                    ? '识别 ${prefs.asrTier == AsrTier.precise ? "精准" : "快速"} · 触感 ${prefs.scrubberHaptics ? "开启" : "关闭"}'
                    : 'ASR ${prefs.asrTier == AsrTier.precise ? "Precise" : "Fast"} · Haptics ${prefs.scrubberHaptics ? "On" : "Off"}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PreferencesScope(
                      controller: controller,
                      child: _ReadAlongDetailPage(
                        controller: controller,
                        zh: zh,
                      ),
                    ),
                  ),
                ),
              ),
              (
                icon: Icons.inventory_2_outlined,
                title: zh ? '课件与存储' : 'Courseware & Storage',
                summary: zh ? '管理本地缓存与课件空间' : 'Manage local cache & storage',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PreferencesScope(
                      controller: controller,
                      child: _StorageDetailPage(
                        repository: repository,
                        zh: zh,
                      ),
                    ),
                  ),
                ),
              ),
              (
                icon: Icons.hub_outlined,
                title: zh ? '网络与模型' : 'Network & Models',
                summary: zh
                    ? 'AI 伴学 · 翻译 · 解码 ${prefs.asrThreads}核'
                    : 'AI Tutor · Translation · ${prefs.asrThreads} threads',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PreferencesScope(
                      controller: controller,
                      child: _AdvancedNetworkDetailPage(
                        controller: controller,
                        zh: zh,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LLSpacing.xxl),

          // ⑧ 版权页：两行小字，安静优雅。
          LLColophon(
            lines: [
              zh
                  ? '句读 (Phrasing) · 小学语文英语精听跟读'
                  : 'Phrasing (句读) · elementary bilingual listening',
              zh ? '引擎 ListenLoop v0.9.3' : 'Core ListenLoop v0.9.3',
            ],
          ),
        ],
      ),
    );
  }
}

/// 一级总览的**功能目录**：所有功能收进同一张卡，组内用发丝线分隔。
///
/// 2026-10-20（GPT 镜像评审 §四 P3）：原来每个功能各自一张卡，于是首页
/// 变成一列等重的"海报"，看着像一排互不相干的东西 —— 这就是老板说的
/// "组件的形状设置得不太协调"。一张卡 + 发丝线 = 一份目录。
class _SettingsHubGroup extends StatelessWidget {
  const _SettingsHubGroup({required this.items});

  final List<({IconData icon, String title, String summary, VoidCallback onTap})>
  items;

  @override
  Widget build(BuildContext context) {
    return LLCard(
      padding: EdgeInsets.zero,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const LLHairline(),
          LLNavRow(
            icon: items[i].icon,
            title: items[i].title,
            summary: items[i].summary,
            onTap: items[i].onTap,
          ),
        ],
      ],
    );
  }
}

/// 二级页：纸与光
class _PaperAndLightDetailPage extends StatelessWidget {
  const _PaperAndLightDetailPage({
    required this.controller,
    required this.zh,
  });

  final PreferencesController controller;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final prefs = controller.prefs;
    final s = LLStrings.of(context);

    return LLPage(
      title: Text(
        zh ? '纸与光' : 'Paper & Light',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ll.textPrimary,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LLSpacing.xl,
          LLSpacing.lg,
          LLSpacing.xl,
          LLSpacing.huge,
        ),
        children: [
          _BlockLabel(
            ruleColor: ll.accent,
            label: zh ? '纸 · 界面风格' : 'PAPER · STYLE',
          ),
          const SizedBox(height: LLSpacing.md),
          LLCard(
            padding: const EdgeInsets.all(LLSpacing.lg),
            children: [
              LLStyleRack(
                selected: prefs.style,
                brightness: ll.brightness,
                zh: zh,
                onSelect: (style) => controller.update(style: style),
              ),
            ],
          ),
          const SizedBox(height: LLSpacing.xxl),
          _BlockLabel(
            ruleColor: ll.accent,
            label: zh ? '光 · 日夜光线' : 'LIGHT · BRIGHTNESS',
          ),
          const SizedBox(height: LLSpacing.md),
          LLCard(
            padding: const EdgeInsets.all(LLSpacing.lg),
            children: [
              LLLampBar<ThemeMode>(
                selected: prefs.themeMode,
                options: [
                  (
                    value: ThemeMode.system,
                    icon: Icons.brightness_auto_outlined,
                    label: s.system,
                  ),
                  (
                    value: ThemeMode.light,
                    icon: Icons.wb_sunny_outlined,
                    label: s.light,
                  ),
                  (
                    value: ThemeMode.dark,
                    icon: Icons.nightlight_round,
                    label: s.dark,
                  ),
                ],
                onSelect: (mode) => controller.update(themeMode: mode),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 二级页：字与读
class _TypographyDetailPage extends StatelessWidget {
  const _TypographyDetailPage({
    required this.controller,
    required this.zh,
  });

  final PreferencesController controller;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final prefs = controller.prefs;
    final s = LLStrings.of(context);

    return LLPage(
      title: Text(
        zh ? '字与读' : 'Typography & Reading',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ll.textPrimary,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LLSpacing.xl,
          LLSpacing.lg,
          LLSpacing.xl,
          LLSpacing.huge,
        ),
        children: [
          LLCard(
            children: [
              _TextSizeSection(
                selected: prefs.textScale,
                pinyinScale: prefs.pinyinScale,
                zh: zh,
                onChange: (scale) => controller.update(textScale: scale),
                onPinyinChange: (scale) =>
                    controller.update(pinyinScale: scale),
              ),
              const LLHairline(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zh ? '中文字体' : 'Chinese font',
                      style: LLText.rowLabel.copyWith(color: ll.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    _FontGallery(
                      options: [
                        for (final f in LearningChineseFont.values)
                          (label: f.label, family: f.family),
                      ],
                      selectedLabel: prefs.learningChineseFont.label,
                      sample: '字',
                      onSelect: (label) {
                        final picked = LearningChineseFont.values.firstWhere(
                          (e) => e.label == label,
                        );
                        controller.update(learningChineseFont: picked);
                      },
                    ),
                  ],
                ),
              ),
              const LLHairline(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zh ? '英文字体' : 'English font',
                      style: LLText.rowLabel.copyWith(color: ll.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    _FontGallery(
                      options: [
                        for (final f in LearningFont.values)
                          (label: f.label, family: f.family),
                      ],
                      selectedLabel: prefs.learningFont.label,
                      sample: 'Aa',
                      onSelect: (label) {
                        final picked = LearningFont.values.firstWhere(
                          (e) => e.label == label,
                        );
                        controller.update(learningFont: picked);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LLSpacing.md),
              _PreviewCanvas(
                title: s.preview,
                controller: controller,
                palette: ll,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 二级页：跟读与纠音
class _ReadAlongDetailPage extends StatelessWidget {
  const _ReadAlongDetailPage({
    required this.controller,
    required this.zh,
  });

  final PreferencesController controller;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final prefs = controller.prefs;

    return LLPage(
      title: Text(
        zh ? '跟读与纠音' : 'Read-Along & Speech',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ll.textPrimary,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LLSpacing.xl,
          LLSpacing.lg,
          LLSpacing.xl,
          LLSpacing.huge,
        ),
        children: [
          LLCard(
            children: [
              LLRow(
                label: zh ? '识别档位' : 'Model tier',
                vertical: 10,
                trailing: LLSegmented<AsrTier>(
                  selected: prefs.asrTier,
                  options: [
                    (AsrTier.fast, zh ? '快速' : 'Fast'),
                    (AsrTier.precise, zh ? '精准' : 'Precise'),
                  ],
                  onSelect: (tier) => controller.update(asrTier: tier),
                  variant: LLSegmentVariant.dense,
                ),
              ),
              const LLHairline(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            zh ? '拖动触感反馈' : 'Haptic feedback',
                            style: LLText.rowLabel.copyWith(
                              color: ll.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            zh ? '拖动滑栏时逐档震动' : 'Per-tick vibration while dragging',
                            style: LLText.itemSummary.copyWith(
                              color: ll.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: prefs.scrubberHaptics,
                      activeThumbColor: ll.textPrimary,
                      onChanged: (value) =>
                          controller.update(scrubberHaptics: value),
                    ),
                  ],
                ),
              ),
              const LLHairline(),
              // 2026-10-21：读页口令（可自定义）。
              // 「说出口令才开始正式判读」——郭老师要的。
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      zh ? '读页口令' : 'Read-along wake phrase',
                      style: LLText.rowLabel.copyWith(color: ll.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      zh
                          ? '说出这句才开始正式判读；留空 = 点开就直接判读'
                          : 'Say this to start judging; empty = judge immediately',
                      style: LLText.itemSummary.copyWith(color: ll.textTertiary),
                    ),
                    const SizedBox(height: 8),
                    // 2026-10-21 郭老师：「能在设置中切换启动命令」⇒ 预设一键切换；
                    // 自定义输入框照旧（口令判定走归一化文本匹配，任意口令都能用）。
                    _WakePhrasePresets(
                      value: prefs.readWakePhrase,
                      presets: zh
                          ? kReadWakePhrasePresetsZh
                          : kReadWakePhrasePresetsEn,
                      offLabel: zh ? '不用口令' : 'No phrase',
                      onSelected: (phrase) =>
                          controller.update(readWakePhrase: phrase),
                    ),
                    const SizedBox(height: 8),
                    _WakePhraseField(
                      value: prefs.readWakePhrase,
                      hint: zh ? kDefaultReadWakePhrase : 'Start reading',
                      onChanged: (value) =>
                          controller.update(readWakePhrase: value),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 口令预设（一键切换）—— 2026-10-21 郭老师：「把启动命令改为『开始朗读』，
/// 同时能在设置中切换启动命令的自定义词语」。
///
/// 预设只是快捷方式：点一下就把输入框填成它；想写别的就自己打字，
/// 判定逻辑（归一化文本匹配）不挑口令。
class _WakePhrasePresets extends StatelessWidget {
  const _WakePhrasePresets({
    required this.value,
    required this.presets,
    required this.offLabel,
    required this.onSelected,
  });

  final String value;
  final List<String> presets;
  final String offLabel;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final phrase in presets)
          _WakePhrasePill(
            label: phrase,
            selected: phrase == value,
            onTap: () => onSelected(phrase),
          ),
        // 留空 = 不等口令（点开就直接判读），也给一个显式入口。
        _WakePhrasePill(
          label: offLabel,
          selected: value.trim().isEmpty,
          onTap: () => onSelected(''),
        ),
      ],
    );
  }
}

/// 预设口令的小药丸。
class _WakePhrasePill extends StatelessWidget {
  const _WakePhrasePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? ll.controlThumb : ll.surface,
          borderRadius: BorderRadius.circular(shape.chip),
          border: Border.all(
            color: selected ? ll.controlThumbBorder : ll.divider,
          ),
        ),
        child: Text(
          label,
          style: LLText.controlLabel.copyWith(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? ll.textPrimary : ll.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 口令输入框（2026-10-21）。
class _WakePhraseField extends StatefulWidget {
  const _WakePhraseField({
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_WakePhraseField> createState() => _WakePhraseFieldState();
}

class _WakePhraseFieldState extends State<_WakePhraseField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_WakePhraseField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return TextField(
      key: const Key('wake-phrase-field'),
      controller: _controller,
      onChanged: widget.onChanged,
      style: TextStyle(fontSize: 14, color: ll.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: 14, color: ll.textTertiary),
        filled: true,
        fillColor: ll.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: ll.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: ll.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: ll.textPrimary.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

/// 二级页：课件与存储
class _StorageDetailPage extends StatelessWidget {
  const _StorageDetailPage({
    required this.repository,
    required this.zh,
  });

  final LessonRepository? repository;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;

    return LLPage(
      title: Text(
        zh ? '课件与存储' : 'Courseware & Storage',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ll.textPrimary,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LLSpacing.xl,
          LLSpacing.lg,
          LLSpacing.xl,
          LLSpacing.huge,
        ),
        children: [
          _StorageManagementFoldedCard(
            repository: repository,
            zh: zh,
          ),
        ],
      ),
    );
  }
}

/// 二级页：网络与模型
class _AdvancedNetworkDetailPage extends StatelessWidget {
  const _AdvancedNetworkDetailPage({
    required this.controller,
    required this.zh,
  });

  final PreferencesController controller;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final prefs = controller.prefs;
    final s = LLStrings.of(context);

    return LLPage(
      title: Text(
        zh ? '网络与模型' : 'Network & Models',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ll.textPrimary,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LLSpacing.xl,
          LLSpacing.lg,
          LLSpacing.xl,
          LLSpacing.huge,
        ),
        children: [
          LLCard(
            children: [
              for (final section in const [
                _SettingsSection.tutor,
                _SettingsSection.translation,
                _SettingsSection.relay,
              ]) ...[
                if (section != _SettingsSection.tutor) const LLHairline(indent: 59),
                LLNavRow(
                  icon: section.icon,
                  title: section.title(s, prefs),
                  summary: section.summary(s, prefs),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _SettingsDetailPage(
                        section: section,
                        controller: controller,
                      ),
                    ),
                  ),
                ),
              ],
              const LLHairline(),
              LLRow(
                label: zh ? '解码线程' : 'ASR threads',
                vertical: 10,
                trailing: LLSegmented<int>(
                  selected: prefs.asrThreads,
                  options: const [(4, '4核'), (6, '6核(推荐)'), (8, '8核全开')],
                  onSelect: (threads) => controller.update(asrThreads: threads),
                  variant: LLSegmentVariant.dense,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 天头（WP-I §三.1）：「设置」不再是 30sp 的大字墙，是一行安静的天头。
///
/// 界面语言放在天头右边——它是"界面层"的开关，混在「纸与光」里会让人以为
/// 换语言会换风格。两个原生标签（English / 中文），永远用自己的文字写自己。
class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.zh,
    required this.language,
    required this.onLanguage,
  });

  final bool zh;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguage;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                zh ? '设置' : 'SETTINGS',
                style: LLText.sectionLabel.copyWith(
                  fontSize: 12,
                  letterSpacing: zh ? LLTracking.wide : LLTracking.label,
                  color: ll.textTertiary,
                ),
              ),
            ),
            _SquareLanguageToggle(
              language: language,
              onLanguage: onLanguage,
            ),
          ],
        ),
        const SizedBox(height: LLSpacing.sm),
        Container(height: shape.hairline, color: ll.divider),
      ],
    );
  }
}

/// 方形中英文对切语言切换器（左侧 EN 缩写，右侧 中，工整微矩形高级质感）
class _SquareLanguageToggle extends StatelessWidget {
  const _SquareLanguageToggle({
    required this.language,
    required this.onLanguage,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguage;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final isEn = language == AppLanguage.english;

    return Semantics(
      button: true,
      label: isEn ? 'Switch to Chinese' : '切换为英文',
      child: Container(
        width: 62.0,
        height: 28.0,
        padding: const EdgeInsets.all(2.0),
        decoration: BoxDecoration(
          color: ll.controlTrack,
          borderRadius: BorderRadius.circular(6.0),
          border: Border.all(
            color: ll.divider,
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            // 左边：EN
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onLanguage(AppLanguage.english),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isEn ? ll.textPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    'EN',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isEn ? FontWeight.w700 : FontWeight.w500,
                      color: isEn ? ll.bg : ll.textSecondary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2.0),
            // 右边：中
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onLanguage(AppLanguage.chinese),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: !isEn ? ll.textPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    '中',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: !isEn ? FontWeight.w700 : FontWeight.w500,
                      color: !isEn ? ll.bg : ll.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卷首 · 书名页（WP-I §三.2）：先让书自报姓名，再把访客门退到书名下面。
///
/// 原来第一屏最显眼的是「访客 未登录 · 终身会员 敬请期待」一张系统空卡，
/// 整个产品的气质从第一屏就没了。现在先看「句读」和它的副题，
/// `LLProfileEntryCard`（有独立测试，原样保留）退成书名页的下半。
class _TitlePage extends StatelessWidget {
  const _TitlePage({
    required this.zh,
    required this.fontFamily,
    required this.child,
  });

  final bool zh;

  /// 风格的标题字体（`LLStyle.headingFont`）：换风格时扉页标题一起换脸。
  final String? fontFamily;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          zh ? '句读' : 'Phrasing',
          style: LLText.appTitle.copyWith(
            fontFamily: fontFamily,
            fontSize: 34,
            color: ll.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          zh ? '授之书而习其句读，开口把书读进去' : 'Read it aloud, and it stays in.',
          style: LLText.itemSummary.copyWith(color: ll.textSecondary),
        ),
        const SizedBox(height: LLSpacing.lg),
        LLCard(children: [child]),
      ],
    );
  }
}

/// 界栏式分区块题（WP-I §三.7）：一道短竖线 + 小字，取代飘在卡上方的灰色标签。
class _BlockLabel extends StatelessWidget {
  const _BlockLabel({required this.ruleColor, required this.label});

  final Color ruleColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Row(
      children: [
        Container(width: 2, height: 11, color: ruleColor),
        const SizedBox(width: LLSpacing.sm),
        Text(
          label,
          style: LLText.groupLabel.copyWith(color: ll.textTertiary),
        ),
      ],
    );
  }
}

/// 折叠卡（WP-I §三.5）：「高级」默认收起，折叠态的头一行显示实时状态。
class _FoldedCard extends StatefulWidget {
  const _FoldedCard({
    required this.title,
    required this.summary,
    required this.children,
  });

  final String title;
  final String summary;
  final List<Widget> children;

  @override
  State<_FoldedCard> createState() => _FoldedCardState();
}

class _FoldedCardState extends State<_FoldedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fold = AnimationController(
    vsync: this,
    duration: LLMotion.slow,
    value: 0,
  )..addStatusListener((status) {
      // 动画一结束就把正文从树里摘掉。AnimatedCrossFade 做不到：它只用
      // FadeTransition + ExcludeSemantics 包着隐去的那一帧，子树照样 mounted
      // ——收起的「高级」会在每次进设置页时构建三份重表单，`find` 也照样命中，
      // 「默认收起，主路径上看不到」就成了一句空话。
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        setState(() {});
      }
    });
  late final CurvedAnimation _foldFactor = CurvedAnimation(
    parent: _fold,
    curve: LLMotion.curve,
  );

  bool _open = false;

  /// 展开中，或正在收拢的那 280ms 里，正文必须在场，否则高度硬跳。
  bool get _showBody => _open || _fold.isAnimating;

  @override
  void dispose() {
    _foldFactor.dispose();
    _fold.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _fold.forward();
    } else {
      _fold.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return Container(
      decoration: BoxDecoration(
        color: ll.surface,
        borderRadius: BorderRadius.circular(shape.card),
        border: Border.all(color: ll.divider, width: shape.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.build_outlined, size: 20, color: ll.textSecondary),
                  const SizedBox(width: LLSpacing.md),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LLText.itemTitle.copyWith(
                        color: ll.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      widget.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: LLText.itemSummary.copyWith(color: ll.textTertiary),
                    ),
                  ),
                  const SizedBox(width: LLSpacing.sm),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: LLMotion.fast,
                    curve: LLMotion.curve,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: ll.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _foldFactor,
            alignment: AlignmentDirectional.topStart,
            child: _showBody
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                    child: Column(children: widget.children),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}



enum _SettingsSection { tutor, translation, relay }


extension _SettingsSectionX on _SettingsSection {
  IconData get icon => switch (this) {
    _SettingsSection.tutor => Icons.smart_toy_outlined,
    _SettingsSection.translation => Icons.translate_rounded,
    _SettingsSection.relay => Icons.sync_alt_rounded,
  };

  String title(LLStrings s, AppPreferences prefs) {
    return switch (this) {
      _SettingsSection.tutor => s.tutorOnlineTitle,
      _SettingsSection.translation => s.translation,
      _SettingsSection.relay => s.youtubeRelayTitle,
    };
  }

  /// The one-line live value shown on the row.
  String summary(LLStrings s, AppPreferences prefs) {
    final zh = prefs.uiLanguage == AppLanguage.chinese;
    return switch (this) {
      _SettingsSection.tutor => prefs.hasTutorEndpoint
          ? '${zh ? "在线" : "Online"} · ${prefs.tutorModel}'
          : (zh ? '未配置 · 将退回离线解析' : 'Not set · falls back to offline'),
      _SettingsSection.translation => prefs.translationModel,
      _SettingsSection.relay => prefs.youtubeRelayBaseUrl,
    };
  }

  /// Level-2 content for this section.
  List<Widget> details({
    required BuildContext context,
    required PreferencesController controller,
  }) {
    final ll = context.ll;

    return switch (this) {
      _SettingsSection.tutor => [_AiTutorSection(controller: controller, palette: ll)],
      _SettingsSection.translation => [
        _TranslationSection(controller: controller, palette: ll),
      ],
      _SettingsSection.relay => [
        _YouTubeRelaySection(controller: controller, palette: ll),
      ],
    };
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

    return LLPage(
      title: Text(
        section.title(s, prefs),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ll.textPrimary,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LLSpacing.xl,
          LLSpacing.lg,
          LLSpacing.xl,
          LLSpacing.huge,
        ),
        children: [
          LLCard(
            children: section.details(
              context: context,
              controller: controller,
            ),
          ),
        ],
      ),
    );
  }
}


/// 字号区（2026-10-20 郭老师重做，三条要求合并实现）：
///
/// ① **不是按档位加，而是直接挑**。原来是 `A− 100% A+`——那是"加减法"，
///    用户要的是"挑一个"。现在给 3 枚字号（小/中/大），点一下就落到那个
///    字号，样字大小随档位变化，一眼比得出。
/// ② **长按可连续调整**。长按整行就地展开一条滑条，按住拖着实时变，
///    和调倍速一模一样（长按出轴 → 按住拖 → 松手保留），不用松手再重来。
///    滑条与档位双向同步：拖到哪一档，最近的那枚就高亮。
/// ③ **拼音大小单独一档**（2026-10-20 郭老师：「字体控制，再加一个拼音字体
///    的大小控制」）。汉字多大、拼音多大，**两件事各管各的**：低年级刚开始
///    学拼就把拼音调小些，认字阶段把拼音调大些看清单声调。
class _TextSizeSection extends StatefulWidget {
  const _TextSizeSection({
    required this.selected,
    required this.pinyinScale,
    required this.zh,
    required this.onChange,
    required this.onPinyinChange,
  });

  final double selected;

  /// 拼音大小倍率（1.0 = 跟随默认比例）。
  final double pinyinScale;

  final bool zh;
  final ValueChanged<double> onChange;
  final ValueChanged<double> onPinyinChange;

  @override
  State<_TextSizeSection> createState() => _TextSizeSectionState();
}

class _TextSizeSectionState extends State<_TextSizeSection> {
  /// 汉字滑条是否展开（长按整行才展开，不占常态空间）。
  bool _tuning = false;

  /// 拼音滑条是否展开。
  bool _tuningPinyin = false;

  /// 拼音的三档倍率（小 / 中 / 大）。
  static const List<double> _pinyinScales = [0.8, 1.0, 1.25];
  static const List<String> _pinyinLabels = ['小', '中', '大'];

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final presets = LearningTextSizePreset.values;
    final active = LearningTextSizePreset.fromScale(widget.selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onLongPress: () {
            if (!_tuning) setState(() => _tuning = true);
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.zh ? '字号' : 'Text size',
                        style: LLText.rowLabel.copyWith(color: ll.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.zh
                            ? '长按可连续微调'
                            : 'Long-press to fine-tune',
                        style: LLText.itemSummary.copyWith(
                          color: ll.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(widget.selected * 100).round()}%',
                  style: LLText.counter.copyWith(color: ll.textPrimary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          // 注意：这里**不能**用 CrossAxisAlignment.stretch —— 本页在竖向
          // ListView 里，行的高度是无界的，stretch 会把子件拉成无限高
          // （BoxConstraints forces an infinite height），整页直接白屏。
          children: [
            for (final p in presets)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _SizeChip(
                    preset: p,
                    selected: active == p,
                    onTap: () => widget.onChange(p.scale),
                  ),
                ),
              ),
          ],
        ),        if (_tuning) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${kMinTextScale.toStringAsFixed(2)}×',
                style: LLText.caption.copyWith(color: ll.textTertiary),
              ),
              Expanded(
                child: SliderTheme(
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
                    divisions: 20,
                    label: '${(widget.selected * 100).round()}%',
                    value: widget.selected.clamp(
                      kMinTextScale,
                      kMaxTextScale,
                    ),
                    // 按住拖动实时生效——这正是"长按后持续调整"的那一下。
                    onChanged: (value) => widget.onChange(value),
                  ),
                ),
              ),
              Text(
                '${kMaxTextScale.toStringAsFixed(2)}×',
                style: LLText.caption.copyWith(color: ll.textTertiary),
              ),
              IconButton(
                tooltip: widget.zh ? '收起微调' : 'Done',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: ll.textSecondary,
                ),
                onPressed: () => setState(() => _tuning = false),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),

        // ── 拼音大小（独立于汉字）────────────────────────────────
        InkWell(
          onLongPress: () {
            if (!_tuningPinyin) setState(() => _tuningPinyin = true);
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.zh ? '拼音大小' : 'Pinyin size',
                        style: LLText.rowLabel.copyWith(color: ll.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.zh
                            ? '与汉字大小互不影响'
                            : 'Independent of text size',
                        style: LLText.itemSummary.copyWith(color: ll.textTertiary),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(widget.pinyinScale * 100).round()}%',
                  style: LLText.counter.copyWith(color: ll.textPrimary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < _pinyinScales.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PinyinChip(
                    label: _pinyinLabels[i],
                    scale: _pinyinScales[i],
                    selected: (widget.pinyinScale - _pinyinScales[i]).abs() < 0.02,
                    onTap: () => widget.onPinyinChange(_pinyinScales[i]),
                  ),
                ),
              ),
          ],
        ),
        if (_tuningPinyin) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '0.6×',
                style: LLText.caption.copyWith(color: ll.textTertiary),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: ll.textPrimary,
                    inactiveTrackColor: ll.divider,
                    thumbColor: ll.textPrimary,
                    overlayColor: ll.textPrimary.withValues(alpha: 0.12),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    min: 0.6,
                    max: 1.6,
                    divisions: 20,
                    label: '${(widget.pinyinScale * 100).round()}%',
                    value: widget.pinyinScale.clamp(0.6, 1.6),
                    onChanged: (value) => widget.onPinyinChange(value),
                  ),
                ),
              ),
              Text(
                '1.6×',
                style: LLText.caption.copyWith(color: ll.textTertiary),
              ),
              IconButton(
                tooltip: widget.zh ? '收起微调' : 'Done',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: ll.textSecondary,
                ),
                onPressed: () => setState(() => _tuningPinyin = false),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 一枚拼音档位：样例拼音（按档位大小）+ 档位名。
class _PinyinChip extends StatelessWidget {
  const _PinyinChip({
    required this.label,
    required this.scale,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double scale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? ll.textPrimary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? ll.textPrimary.withValues(alpha: 0.35)
                : ll.divider,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'hǎo',
              style: TextStyle(
                fontSize: 8 + scale * 6,
                height: 1.0,
                fontWeight: FontWeight.w600,
                color: selected ? ll.textPrimary : ll.textSecondary,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? ll.textPrimary : ll.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一枚字号档位：样字（按档位大小）+ 档位名，横排紧凑。
class _SizeChip extends StatelessWidget {
  const _SizeChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final LearningTextSizePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        // 2026-10-20 郭老师：「字与读」要**一页装下**，控件重心留在屏幕
        // 上方 75%。所以档位卡压成一枚药丸：样字 + 名字并排，高度 40。
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? ll.textPrimary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? ll.textPrimary.withValues(alpha: 0.35)
                : ll.divider,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '字',
              style: TextStyle(
                // 样字随档位长大，档位差别一眼可见。
                fontSize: 11 + preset.scale * 7,
                fontWeight: FontWeight.w600,
                height: 1.0,
                color: selected ? ll.textPrimary : ll.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              preset.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? ll.textPrimary : ll.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 字体样张：每枚按钮用**它自己的字体**渲染一个样字，字体名写在下面。
///
/// 2026-10-20 郭老师：原来是一排 `LLSegmented` 小药丸，字体名被挤成省略号
/// （英文 System 只剩 "Sys…"），中文字体名也看不清。现在每个字体占一枚
/// 等宽卡片：样字 + 名字，名字永远完整可见（FittedBox 缩放，不截断）。
class _FontGallery extends StatelessWidget {
  const _FontGallery({
    required this.options,
    required this.selectedLabel,
    required this.sample,
    required this.onSelect,
  });

  final List<({String label, String? family})> options;
  final String selectedLabel;
  final String sample;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Row(
      // 同上：竖向 ListView 里行高无界，stretch 会把子件拉成无限高 → 白屏。
      children: [
        for (final opt in options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(opt.label),
                child: Container(
                  // 紧凑：样字 + 名字，卡高 ~66（原先 ~120）。
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: opt.label == selectedLabel
                        ? ll.textPrimary.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: opt.label == selectedLabel
                          ? ll.textPrimary.withValues(alpha: 0.35)
                          : ll.divider,
                      width: opt.label == selectedLabel ? 1.2 : 0.8,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sample,
                        style: TextStyle(
                          fontSize: 19,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          fontFamily: opt.family,
                          color: ll.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // 名字必须完整可见：缩放而不是省略号截断。
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          opt.label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: opt.label == selectedLabel
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: opt.label == selectedLabel
                                ? ll.textPrimary
                                : ll.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 预览窗格（2026-10-20 郭老师重做）。
///
/// 原版两个毛病：① 中英文样例上下摞着，中文那句被挤到卡片最下面，改完
/// 字号/字体几乎看不出差别；② 「此句宜再听三遍」那枚竖排眉批是**死装饰**
/// ——写着要听三遍，点它什么也不会发生。
///
/// 现在：中文样例（当前中文字体 + 字号 + 拼音）和英文样例（当前英文字体）
/// 各自一段、摆在一张纸上；「听一遍 / 听三遍」是**真按钮**，点一下系统
/// TTS 就播报（离线，不联网）；眉批也变成可点的同一件事。
class _PreviewCanvas extends StatefulWidget {
  const _PreviewCanvas({
    required this.title,
    required this.controller,
    required this.palette,
  });

  final String title;
  final PreferencesController controller;
  final LLPalette palette;

  @override
  State<_PreviewCanvas> createState() => _PreviewCanvasState();
}

class _PreviewCanvasState extends State<_PreviewCanvas> {
  /// 预览用的样句（固定不变，改的是它的字体与字号）。
  static const String _sampleZh = '池塘里有一群小蝌蚪。';
  static const String _sampleEn = 'Listen carefully to how the sentence flows.';

  final _PreviewTts _tts = _PreviewTts();
  bool _speaking = false;

  Future<void> _play(int times) async {
    if (_speaking) return;
    setState(() => _speaking = true);
    await _tts.speak(_sampleZh, times: times);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  Widget build(BuildContext context) {
    final ll = widget.palette;
    final prefs = widget.controller.prefs;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
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
              Flexible(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LLText.sectionLabel.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.0,
                    color: ll.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 原为 Spacer + 无约束 Text：系统大字号下右侧摘要撑爆整行
              // （382dp、1.5× 实测溢出 96px）。改为 Expanded + 右对齐 + 省略。
              Expanded(
                child: Text(
                  '${prefs.learningChineseFont.label} / ${prefs.learningFont.label} · ${(prefs.textScale * 100).round()}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10, color: ll.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 眉批移到整块预览的**右侧**（经典眉批位：正文与边栏之间有一道界栏）。
          // 2026-10-20 郭老师：原先它挤在中文样例右边，把样例压成两行、
          // 整块预览撑高，整页要下滑才看得见。现在正文占满宽度、眉批只在
          // 右边占一条；而且它**可点** —— 点它 = 听三遍。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 中文样例：当前中文字体 + 当前字号 + 拼音成组。
                    ChineseTextbookRubyLayout(
                      text: _sampleZh,
                      charSize: 19 * prefs.textScale,
                      charStyle: LLLearning.chineseMainSentence(ll, prefs).copyWith(
                        fontSize: 19 * prefs.textScale,
                      ),
                      chineseFontFamily: prefs.learningChineseFont.family,
                      pinyinScale: prefs.pinyinScale,
                      textAlign: TextAlign.left,
                      wordSpacing: 5.0,
                      lineSpacing: 6.0,
                    ),
                    const SizedBox(height: 8),
                    // 英文样例：当前英文字体。
                    Text(
                      _sampleEn,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LLLearning.englishSentence(ll, prefs),
                    ),
                    const SizedBox(height: 10),
                    // 真按钮：听一遍 / 听三遍（系统 TTS，离线）。
                    Row(
                      children: [
                        _PreviewAction(
                          icon: Icons.play_arrow_rounded,
                          label: '听一遍',
                          busy: _speaking,
                          onTap: () => _play(1),
                        ),
                        const SizedBox(width: 8),
                        _PreviewAction(
                          icon: Icons.replay_rounded,
                          label: '听三遍',
                          busy: _speaking,
                          onTap: () => _play(3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _speaking ? null : () => _play(3),
                child: Opacity(
                  opacity: _speaking ? 0.5 : 1,
                  child: const LLMarginalNote(
                    text: '此句宜再听三遍',
                    // 132 ≈ 7 字 × (12px × 1.45)：让这 7 个字**排成一列**。
                    // 原来的 104 只放得下 5 个字，剩下两个字被挤到左边第二列，
                    // 竖排一断就变成三列错落，看着像乱码。
                    maxHeight: 132,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 预览窗格里的一枚动作钮（发丝边 + 令牌色，不用实心主按钮抢戏）。
class _PreviewAction extends StatelessWidget {
  const _PreviewAction({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: ll.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ll.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: busy ? ll.textTertiary : ll.textPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              busy ? '播放中' : label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: busy ? ll.textTertiary : ll.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预览试听用的系统 TTS（离线，不联网）。
///
/// 与 `ReadAlongSpeaker` 同一套系统引擎，但这里要**连播 N 遍**，所以开了
/// `awaitSpeakCompletion`：一句播完再播下一句，而不是三句叠在一起。
class _PreviewTts {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> speak(String text, {int times = 1}) async {
    try {
      if (!_ready) {
        await _tts.setLanguage('zh-CN');
        await _tts.setSpeechRate(0.85);
        await _tts.awaitSpeakCompletion(true);
        _ready = true;
      }
      for (var i = 0; i < times; i++) {
        await _tts.speak(text);
      }
    } catch (_) {
      // 没有中文语音包 / 引擎异常：静默降级。预览是锦上添花，不能因此崩页。
    }
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
        LLRow(
          label: s.translationBaseUrl,
          value: prefs.translationBaseUrl,
          onTap: () => _editValue(
            title: s.translationBaseUrl,
            initial: prefs.translationBaseUrl,
            hint: s.translationBaseUrlHint,
            onSaved: (value) => widget.controller.update(translationBaseUrl: value),
          ),
        ),
        const LLHairline(),
        LLRow(
          label: s.translationApiKey,
          value: hasKey ? _mask(prefs.translationApiKey) : s.translationApiKeyHint,
          valueMuted: !hasKey,
          indicator: hasKey,
          onTap: () => _editValue(
            title: s.translationApiKey,
            initial: prefs.translationApiKey,
            hint: s.translationApiKeyHint,
            obscure: true,
            onSaved: (value) => widget.controller.update(translationApiKey: value),
          ),
        ),
        const LLHairline(),
        LLRow(
          label: s.translationModel,
          value: prefs.translationModel,
          showChevron: true,
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
        LLRow(
          label: s.youtubeRelayBaseUrl,
          value: prefs.youtubeRelayBaseUrl,
          onTap: () => _editValue(
            title: s.youtubeRelayBaseUrl,
            initial: prefs.youtubeRelayBaseUrl,
            hint: s.youtubeRelayBaseUrlHint,
            onSaved: (value) => widget.controller.update(youtubeRelayBaseUrl: value),
          ),
        ),
        const LLHairline(),
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
              color: passed ? ll.successWash : ll.dangerWash,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (passed ? ll.success : ll.danger).withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              message!,
              style: TextStyle(
                fontSize: 12,
                color: passed ? ll.success : ll.danger,
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
    final dotColor = online ? ll.success : ll.disabled;
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
            style: LLText.bodySm.copyWith(
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
              style: LLText.badge.copyWith(
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
        LLRow(
          label: s.tutorBaseUrl,
          value: prefs.tutorBaseUrl,
          onTap: () => _editValue(
            title: s.tutorBaseUrl,
            initial: prefs.tutorBaseUrl,
            hint: s.tutorBaseUrlHint,
            onSaved: (value) => widget.controller.update(tutorBaseUrl: value),
          ),
        ),
        const LLHairline(),
        LLRow(
          label: s.tutorApiKey,
          value: hasKey ? _mask(prefs.tutorApiKey) : s.tutorApiKeyHint,
          valueMuted: !hasKey,
          indicator: hasKey,
          onTap: () => _editValue(
            title: s.tutorApiKey,
            initial: prefs.tutorApiKey,
            hint: s.tutorApiKeyHint,
            obscure: true,
            onSaved: (value) => widget.controller.update(tutorApiKey: value),
          ),
        ),
        const LLHairline(),
        LLRow(
          label: s.tutorModel,
          value: prefs.tutorModel,
          showChevron: true,
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
                                            style: LLText.badge.copyWith(
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

/// 课件存储管理折叠卡（WP-I 高级设置 · 存储治理）：
///
/// 1. 按年级（一至六年级、其他）聚合展示课件数量与本地媒体占用的磁盘体积。
/// 2. 提供按年级一键「清理媒体」按钮，调用 [LessonRepository.deleteMediaPreservingProgress]，
///    安全清空音频媒体，绝不抹除用户的 [learning_progress] 打卡与学习记录。
/// 3. 提供一键打开云端课程库（OTA [CloudCatalogSheet]）按需重新下载课件媒体。
class _StorageManagementFoldedCard extends StatefulWidget {
  const _StorageManagementFoldedCard({
    required this.repository,
    required this.zh,
  });

  final LessonRepository? repository;
  final bool zh;

  @override
  State<_StorageManagementFoldedCard> createState() =>
      _StorageManagementFoldedCardState();
}

class _StorageManagementFoldedCardState
    extends State<_StorageManagementFoldedCard> {
  bool _loading = false;
  bool _cleaning = false;
  Map<String, GradeStorageStats>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(_StorageManagementFoldedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    final repo = widget.repository;
    if (repo == null) return;
    setState(() => _loading = true);
    try {
      final res = await repo.getLessonsStorageStats();
      if (mounted) {
        setState(() {
          _stats = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  int get _totalBytes {
    if (_stats == null) return 0;
    return _stats!.values.fold(0, (sum, item) => sum + item.totalBytes);
  }

  int get _totalCount {
    if (_stats == null) return 0;
    return _stats!.values.fold(0, (sum, item) => sum + item.lessonCount);
  }

  Future<void> _confirmAndCleanGrade(GradeStorageStats item) async {
    final repo = widget.repository;
    if (repo == null || item.lessonIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final ll = dialogCtx.ll;
        return AlertDialog(
          backgroundColor: ll.surface,
          title: Text(
            widget.zh
                ? '清理${item.gradeLabel}媒体文件？'
                : 'Clean ${item.gradeLabel} Media?',
            style: LLText.itemTitle.copyWith(color: ll.textPrimary),
          ),
          content: Text(
            widget.zh
                ? '将删除该年级所有本地音频与切片媒体文件，预计释放 ${_formatBytes(item.totalBytes)} 空间。\n\n用户的学习进度、打卡记录与课文文本将完整保留。'
                : 'This will delete local audio files to free ${_formatBytes(item.totalBytes)}.\n\nLearning progress and text will be safely preserved.',
            style: LLText.itemSummary.copyWith(color: ll.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                widget.zh ? '取消' : 'Cancel',
                style: TextStyle(color: ll.textTertiary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(
                widget.zh ? '确认清理' : 'Clean',
                style: TextStyle(
                  color: ll.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cleaning = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final id in item.lessonIds) {
        await repo.deleteMediaPreservingProgress(id);
      }
      await _loadStats();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              widget.zh
                  ? '${item.gradeLabel}媒体已清理，学习记录已完整保留'
                  : '${item.gradeLabel} media cleaned, progress kept',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cleaning = false);
      }
    }
  }

  void _openCloudCatalog() {
    final repo = widget.repository;
    if (repo == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CloudCatalogSheet(
        repository: repo,
        onLessonImported: (_) => _loadStats(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final zh = widget.zh;

    final summary = widget.repository == null
        ? (zh ? '无可用存储' : 'No storage')
        : _loading
            ? (zh ? '统计中...' : 'Calculating...')
            : '$_totalCount ${zh ? "篇" : "lessons"} · ${_formatBytes(_totalBytes)}';

    return _FoldedCard(
      title: zh ? '课件存储管理' : 'Lesson Storage',
      summary: summary,
      children: [
        if (widget.repository == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              zh ? '未检测到课件库' : 'No repository connected',
              style: LLText.itemSummary.copyWith(color: ll.textTertiary),
            ),
          )
        else ...[
          // 操作条
          Padding(
            padding: const EdgeInsets.only(bottom: LLSpacing.sm, top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    zh
                        ? '共 $_totalCount 篇课件 · 已占用 ${_formatBytes(_totalBytes)}'
                        : '$_totalCount lessons · ${_formatBytes(_totalBytes)}',
                    style: LLText.caption.copyWith(
                      color: ll.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                InkWell(
                  onTap: _loading || _cleaning ? null : _loadStats,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: _loading ? ll.textTertiary : ll.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _openCloudCatalog,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_download_outlined,
                          size: 16,
                          color: ll.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          zh ? '云端课件' : 'Cloud',
                          style: LLText.caption.copyWith(
                            color: ll.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const LLHairline(),

          // 年级列表
          if (_stats != null) ...[
            for (final entry in _stats!.entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.key,
                            style: LLText.rowLabel.copyWith(
                              color: ll.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${entry.value.lessonCount} ${zh ? "篇" : "lessons"} · ${_formatBytes(entry.value.totalBytes)}',
                            style: LLText.itemSummary.copyWith(
                              color: ll.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (entry.value.totalBytes > 0)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _cleaning
                            ? null
                            : () => _confirmAndCleanGrade(entry.value),
                        icon: Icon(
                          Icons.cleaning_services_outlined,
                          size: 15,
                          color: ll.textTertiary,
                        ),
                        label: Text(
                          zh ? '清理媒体' : 'Clean',
                          style: TextStyle(
                            fontSize: 12,
                            color: ll.textSecondary,
                          ),
                        ),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _openCloudCatalog,
                      icon: Icon(
                        Icons.download_rounded,
                        size: 15,
                        color: ll.accent,
                      ),
                      label: Text(
                        zh ? '重下' : 'Download',
                        style: TextStyle(
                          fontSize: 12,
                          color: ll.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const LLHairline(),
            ],
          ] else if (_loading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ll.accent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

