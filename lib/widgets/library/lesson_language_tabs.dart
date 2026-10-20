import 'package:flutter/material.dart';

import '../../theme/listenloop_theme.dart';

/// 课程语种切换栏（[ 英文 | 中文 ]）。
///
/// 轨道 / 选中底 / 选中字三枚色全部来自 palette（doc 21 §四）——此前这里是
/// `brightness == dark ? 硬编码 : 硬编码`，四套风格到这一栏就被压回两套。
class LessonLanguageTabs extends StatelessWidget {
  const LessonLanguageTabs({
    super.key,
    required this.languages,
    required this.selectedLanguage,
    required this.onSelectLanguage,
    this.padding,
  });

  final List<String> languages;
  final String selectedLanguage;
  final ValueChanged<String> onSelectLanguage;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;

    // 默认展示 [ 英文 | 中文 ]；若外部传入其他语言（如测试用例），同样按 token 展示
    final effectiveLanguages =
        languages.contains('EN') && languages.contains('ZH')
        ? (languages.contains('ALL')
              ? languages
              : ['EN', 'ZH', ...languages.where((l) => l != 'EN' && l != 'ZH')])
        : languages;

    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: LLSpacing.xl),
      child: Container(
        padding: EdgeInsets.all(shape.hairline + 2),
        decoration: BoxDecoration(
          color: ll.tabTrack,
          borderRadius: BorderRadius.circular(shape.pill),
          border: Border.all(color: ll.divider, width: shape.hairline),
        ),
        // 语言集来自课程数据，数量不固定：超出可横滑，不再撑破容器。
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final lang in effectiveLanguages)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: _TabPill(
                    label: _labelFor(lang),
                    selected: lang == selectedLanguage,
                    tabKey: Key('lang-tab-$lang'),
                    onTap: () => onSelectLanguage(lang),
                    ll: ll,
                    shape: shape,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _labelFor(String lang) {
    if (lang == 'ALL') return '全部';
    return switch (lang.toUpperCase()) {
      'EN' => '英文',
      'ZH' => '中文',
      'JA' => '日文',
      _ => lang,
    };
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.tabKey,
    required this.onTap,
    required this.ll,
    required this.shape,
  });

  final String label;
  final bool selected;
  final Key tabKey;
  final VoidCallback onTap;
  final LLPalette ll;
  final LLShape shape;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: tabKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(shape.pill),
      child: AnimatedContainer(
        duration: LLMotion.normal,
        curve: LLMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: LLSpacing.lg,
          vertical: LLSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? ll.tabActive : Colors.transparent,
          borderRadius: BorderRadius.circular(shape.pill),
          boxShadow:
              selected && shape.shadowOn
                  ? [
                      BoxShadow(
                        color: ll.shadow,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LLText.caption.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? ll.tabOnActive : ll.textSecondary,
            letterSpacing: LLTracking.tight,
          ),
        ),
      ),
    );
  }
}
