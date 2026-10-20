import 'package:flutter/material.dart';

import '../theme/listenloop_theme.dart';

/// The reserved account area at the head of the settings hub: a ring avatar,
/// the guest identity, a sign-in affordance and a membership strip — all
/// visible, all honest about being placeholders. Nothing here pretends a
/// backend exists: tapping any part opens one lightweight "on the way"
/// sheet, so no control is a dead end.
///
/// The card is designed to sit inside an [LLCard] on the hub — it carries
/// no surface of its own, only the content and the ink.
class LLProfileEntryCard extends StatelessWidget {
  const LLProfileEntryCard({
    super.key,
    required this.zh,
    this.onTap,
    this.profileName,
    this.profileEmoji,
    this.profileHasPin = false,
  });

  /// UI language switch taken from the hub (`prefs.uiLanguage`).
  final bool zh;

  /// Overrides the default placeholder sheet once real sign-in lands.
  final VoidCallback? onTap;

  /// 2026-10-20 离线登录：本地档案已经在册，卡片就从"访客 · 未登录"的假
  /// 身份改成**当前档案**（头像 + 名字 + 是否设了密码）。没有档案信息时
  /// 退回旧的访客形态（单测里就是这么用的）。
  final String? profileName;
  final String? profileEmoji;
  final bool profileHasPin;

  void _openPlaceholderSheet(BuildContext context) {
    final ll = context.ll;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ll.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final sll = sheetContext.ll;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sll.emphasis,
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 24,
                    color: sll.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  zh ? '个人中心正在建设中' : 'Profile is on the way',
                  style: LLText.cardTitle.copyWith(color: sll.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  zh
                      ? '登录与会员权益将在后续版本开放，敬请期待。'
                      : 'Sign-in and membership perks arrive in a later release.',
                  textAlign: TextAlign.center,
                  style: LLText.bodySm.copyWith(color: sll.textSecondary),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  key: const Key('profile-sheet-dismiss'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(sheetContext).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: sll.textPrimary,
                      borderRadius: BorderRadius.circular(
                        sheetContext.llShape.pill,
                      ),
                    ),
                    child: Text(
                      zh ? '知道了' : 'Got it',
                      style: LLText.controlLabel.copyWith(
                        color: sll.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    final name = profileName;
    final emoji = profileEmoji;
    final signedIn = name != null && name.isNotEmpty;
    return InkWell(
      key: const Key('profile-entry-card'),
      borderRadius: BorderRadius.circular(shape.card),
      onTap: onTap ?? () => _openPlaceholderSheet(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ll.emphasis,
                    border: Border.all(
                      color: ll.divider,
                      width: shape.hairline,
                    ),
                  ),
                  child: signedIn
                      ? Text(
                          emoji ?? '🙂',
                          style: const TextStyle(fontSize: 21),
                        )
                      : Icon(
                          Icons.person_outline_rounded,
                          size: 24,
                          color: ll.textSecondary,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signedIn
                            ? name
                            : (zh ? '访客' : 'Guest'),
                        style: LLText.itemTitle.copyWith(
                          color: ll.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        signedIn
                            ? (zh
                                ? '当前档案${profileHasPin ? " · 已设密码" : ""} · 轻点切换'
                                : 'Current profile${profileHasPin ? " · PIN on" : ""} · tap to switch')
                            : (zh
                                ? '未登录 · 轻点开启个人中心'
                                : 'Not signed in · tap to open profile'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LLText.itemSummary.copyWith(
                          color: ll.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  // 不叠 alpha：textTertiary@0.7 在八张色板上实测只有
                  // 2.09~2.42，低于图形对象 3:1 的门槛（WCAG 1.4.11），
                  // 而这枚箭头正是"此行可点"的唯一图形提示。
                  color: ll.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: ll.divider, height: 1, thickness: shape.hairline),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  size: 18,
                  color: ll.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    signedIn
                        // 离线登录：这一行说明"数据在哪"——本机，不上云。
                        ? (zh ? '本机档案 · 数据不出设备' : 'On-device profiles · nothing leaves the device')
                        : (zh ? '终身会员' : 'Lifetime membership'),
                    style: LLText.rowLabel.copyWith(color: ll.textPrimary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ll.emphasis,
                    borderRadius: BorderRadius.circular(shape.pill),
                  ),
                  child: Text(
                    signedIn
                        ? (zh ? '离线' : 'Offline')
                        : (zh ? '敬请期待' : 'Coming soon'),
                    style: LLText.badge.copyWith(color: ll.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
