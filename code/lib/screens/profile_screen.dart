import 'package:flutter/material.dart';

import '../data/profile_store.dart';
import '../preferences/app_preferences.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_page.dart';
import 'root_shell.dart';

/// 档案管理页（离线登录）。
///
/// 一个设备可以有多份档案 —— 大宝一份、二宝一份、家长一份。每份档案有
/// 自己的学习进度、自己的字号字体；档案可以设 4 位 PIN，App 打开时先
/// 解锁再进。**全程离线**：档案表和 PIN 只存在本机，不联网、不上云。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    required this.preferences,
  });

  final ProfileStore store;
  final PreferencesController preferences;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final store = widget.store;
    final activeId = store.activeId;

    return LLPage(
      title: Text(
        '档案',
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
          Text(
            '每人一份学习记录，都存在这台设备上。',
            style: LLText.itemSummary.copyWith(color: ll.textTertiary),
          ),
          const SizedBox(height: LLSpacing.lg),
          for (final profile in store.profiles) ...[
            _ProfileTile(
              profile: profile,
              active: profile.id == activeId,
              onSwitch: () => _switchTo(profile),
              onMore: () => _showProfileMenu(profile),
            ),
            const SizedBox(height: LLSpacing.sm),
          ],
          const SizedBox(height: LLSpacing.md),
          _NewProfileCard(onTap: _createProfile),
        ],
      ),
    );
  }

  Future<void> _switchTo(UserProfile profile) async {
    final store = widget.store;
    if (profile.id == store.activeId) return;
    final ok = await _confirm(
      title: '切换到「${profile.name}」？',
      body: profile.hasPin
          ? '这个档案设了密码，切换后需要输入密码才能继续。'
          : '学习进度、字号与字体都会跟着这个档案走。',
      confirmLabel: '切换',
    );
    if (!ok || !mounted) return;
    await store.setActive(profile.id);
    // 偏好是按档案存的：换档案要把字号/字体重新读一遍。
    await widget.preferences.load();
    if (!mounted) return;
    // 课程库里的进度也是按档案存的：让课程页重新拉一次。
    await RootShell.globalKey.currentState?.reloadForProfileSwitch();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已切换到「${profile.name}」'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createProfile() async {
    final controller = TextEditingController();
    String emoji = '👦';
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('新建档案'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '名字'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 132,
                    child: GridView.count(
                      crossAxisCount: 8,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      children: [
                        for (final e in ProfileStore.emojiChoices)
                          GestureDetector(
                            onTap: () => setState(() => emoji = e),
                            child: Container(
                              decoration: BoxDecoration(
                                color: e == emoji
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(e, style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );
    if (created != true) return;
    final name = controller.text.trim();
    controller.dispose();
    if (name.isEmpty) return;
    final profile = await widget.store.create(name: name, emoji: emoji);
    if (!mounted) return;
    await _switchTo(profile);
  }

  Future<void> _showProfileMenu(UserProfile profile) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.ll.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('重命名'),
                onTap: () => Navigator.of(sheetContext).pop('rename'),
              ),
              ListTile(
                leading: const Icon(Icons.face_outlined),
                title: const Text('换头像'),
                onTap: () => Navigator.of(sheetContext).pop('emoji'),
              ),
              ListTile(
                leading: Icon(
                  profile.hasPin ? Icons.lock_open_outlined : Icons.lock_outline,
                ),
                // 密码**可选**：没设密码就直接进 App。这里写清楚"可取消"，
                // 免得以为设了就撤不掉。
                title: Text(profile.hasPin ? '取消密码' : '设置密码（可选）'),
                subtitle: Text(
                  profile.hasPin ? '取消后打开 App 不用输密码' : '设了之后打开 App 需要 4 位密码',
                ),
                onTap: () => Navigator.of(sheetContext).pop('pin'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除档案'),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'rename':
        await _rename(profile);
      case 'emoji':
        await _pickEmoji(profile);
      case 'pin':
        await _editPin(profile);
      case 'delete':
        await _delete(profile);
    }
  }

  Future<void> _rename(UserProfile profile) async {
    final controller = TextEditingController(text: profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '名字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await widget.store.rename(profile.id, name);
  }

  Future<void> _pickEmoji(UserProfile profile) async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('换头像'),
        content: SizedBox(
          height: 200,
          child: GridView.count(
            crossAxisCount: 8,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final e in ProfileStore.emojiChoices)
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(e),
                  child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (emoji == null) return;
    await widget.store.setEmoji(profile.id, emoji);
  }

  Future<void> _editPin(UserProfile profile) async {
    if (profile.hasPin) {
      final ok = await _confirm(
        title: '取消「${profile.name}」的密码？',
        body: '取消后，打开 App 不用再输密码。',
        confirmLabel: '取消密码',
      );
      if (!ok) return;
      await widget.store.setPin(profile.id, null);
      return;
    }
    final pin = await _askPin();
    if (pin == null) return;
    await widget.store.setPin(profile.id, pin);
  }

  Future<String?> _askPin() async {
    final first = TextEditingController();
    final second = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('设置 4 位密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(hintText: '输入密码'),
            ),
            TextField(
              controller: second,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(hintText: '再输一次'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (first.text.length != 4) return;
              if (first.text != second.text) return;
              Navigator.of(dialogContext).pop(first.text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _delete(UserProfile profile) async {
    if (widget.store.profiles.length <= 1) {
      await _confirm(
        title: '至少要留一个档案',
        body: '这个 App 至少要有一个用户。',
        confirmLabel: '知道了',
      );
      return;
    }
    final ok = await _confirm(
      title: '删除「${profile.name}」？',
      body: '这个档案的学习进度会一起删掉，删了就找不回来了。',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    final wasActive = profile.id == widget.store.activeId;
    final removed = await widget.store.remove(profile.id);
    if (!removed) return;
    if (wasActive) {
      await widget.preferences.load();
      if (!mounted) return;
      await RootShell.globalKey.currentState?.reloadForProfileSwitch();
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// 一枚档案行：头像 + 名字 + 状态。
class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.active,
    required this.onSwitch,
    required this.onMore,
  });

  final UserProfile profile;
  final bool active;
  final VoidCallback onSwitch;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Material(
      color: active ? ll.textPrimary.withValues(alpha: 0.06) : ll.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: active ? null : onSwitch,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ll.textPrimary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Text(profile.emoji, style: const TextStyle(fontSize: 21)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ll.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active
                          ? (profile.hasPin ? '当前档案 · 已设密码' : '当前档案')
                          : (profile.hasPin ? '已设密码' : '点一下切换到这个档案'),
                      style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
                    ),
                  ],
                ),
              ),
              if (active)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ll.textPrimary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '使用中',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ll.textPrimary,
                    ),
                  ),
                ),
              IconButton(
                tooltip: '更多',
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 19,
                  color: ll.textTertiary,
                ),
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「新建档案」那张卡。
class _NewProfileCard extends StatelessWidget {
  const _NewProfileCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ll.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add_alt_1_rounded, size: 18, color: ll.textSecondary),
              const SizedBox(width: 8),
              Text(
                '新建档案',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ll.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
