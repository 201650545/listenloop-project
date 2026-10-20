import 'package:flutter/material.dart';

import '../data/profile_store.dart';
import '../theme/listenloop_theme.dart';

/// 档案锁屏：输 4 位 PIN 才进 App。
///
/// 为什么要它：家里一台平板/手机，孩子一点开就是"听"页；设了 PIN 之后，
/// 打开 App 先得知道是谁的档案 —— 这就是"离线登录"最实在的那一层。
/// 密码只存在本机（加盐 sha256），**没有云端找回**；忘了只能清 App 数据。
class ProfileLockScreen extends StatefulWidget {
  const ProfileLockScreen({
    super.key,
    required this.store,
    required this.onUnlocked,
  });

  final ProfileStore store;
  final VoidCallback onUnlocked;

  @override
  State<ProfileLockScreen> createState() => _ProfileLockScreenState();
}

class _ProfileLockScreenState extends State<ProfileLockScreen> {
  String _entered = '';
  bool _wrong = false;

  void _press(String digit) {
    if (_entered.length >= 4) return;
    setState(() {
      _entered += digit;
      _wrong = false;
    });
    if (_entered.length == 4) {
      _verify();
    }
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _wrong = false;
    });
  }

  void _verify() {
    final profile = widget.store.active;
    if (widget.store.verifyPin(profile.id, _entered)) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _wrong = true;
      _entered = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final profile = widget.store.active;

    return Scaffold(
      backgroundColor: ll.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ll.textPrimary.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Text(profile.emoji, style: const TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 16),
            Text(
              profile.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ll.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _wrong ? '密码不对，再试一次' : '输入 4 位密码',
              style: TextStyle(
                fontSize: 13,
                color: _wrong ? ll.accent : ll.textTertiary,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 13,
                    height: 13,
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entered.length
                          ? (_wrong ? ll.accent : ll.textPrimary)
                          : Colors.transparent,
                      border: Border.all(
                        color: i < _entered.length
                            ? (_wrong ? ll.accent : ll.textPrimary)
                            : ll.divider,
                        width: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            _Keypad(onDigit: _press, onBackspace: _backspace),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                '密码只存在这台设备上',
                style: TextStyle(fontSize: 11, color: ll.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    Widget key(String label, {IconData? icon, VoidCallback? onTap}) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 78,
          height: 66,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 22, color: ll.textSecondary)
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: ll.textPrimary,
                    ),
                  ),
          ),
        ),
      );
    }

    Widget row(List<Widget> children) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final child in children) child,
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([
          key('1', onTap: () => onDigit('1')),
          key('2', onTap: () => onDigit('2')),
          key('3', onTap: () => onDigit('3')),
        ]),
        row([
          key('4', onTap: () => onDigit('4')),
          key('5', onTap: () => onDigit('5')),
          key('6', onTap: () => onDigit('6')),
        ]),
        row([
          key('7', onTap: () => onDigit('7')),
          key('8', onTap: () => onDigit('8')),
          key('9', onTap: () => onDigit('9')),
        ]),
        row([
          key('', icon: Icons.backspace_outlined, onTap: onBackspace),
          key('0', onTap: () => onDigit('0')),
          key(''),
        ]),
      ],
    );
  }
}

/// App 门：当前档案设了密码就先过锁屏，没设就直接进。
///
/// 切换档案后（[ProfileStore.activeId] 变了）会重新上锁 —— 换了人就该
/// 重新证明"你是我"。
class ProfileGate extends StatefulWidget {
  const ProfileGate({
    super.key,
    required this.store,
    required this.child,
  });

  final ProfileStore store;
  final Widget child;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late String _activeId = widget.store.activeId;
  late bool _unlocked = !widget.store.active.hasPin;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (widget.store.activeId == _activeId) return;
    _activeId = widget.store.activeId;
    setState(() => _unlocked = !widget.store.active.hasPin);
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return ProfileLockScreen(
      store: widget.store,
      onUnlocked: () {
        if (mounted) setState(() => _unlocked = true);
      },
    );
  }
}
