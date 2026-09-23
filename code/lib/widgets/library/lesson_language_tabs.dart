import 'package:flutter/material.dart';

import '../../l10n/ll_strings.dart';
import '../../theme/listenloop_theme.dart';

/// 课程语种筛选标签栏（ALL / EN / JA 等）
/// 极简纯文字排版：选中的为白字 + 2dp 下划线，未选中的为三级灰。
class LessonLanguageTabs extends StatelessWidget {
  const LessonLanguageTabs({
    super.key,
    required this.languages,
    required this.selectedLanguage,
    required this.onSelectLanguage,
  });

  final List<String> languages;
  final String selectedLanguage;
  final ValueChanged<String> onSelectLanguage;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: LLSpacing.xl),
        itemCount: languages.length,
        separatorBuilder: (_, _) => const SizedBox(width: LLSpacing.lg),
        itemBuilder: (context, index) {
          final lang = languages[index];
          final isSelected = lang == selectedLanguage;
          final label = lang == 'ALL' ? s.filterAll : lang;
          return InkWell(
            key: Key('lang-tab-$lang'),
            onTap: () => onSelectLanguage(lang),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? ll.textPrimary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? ll.textPrimary : ll.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
