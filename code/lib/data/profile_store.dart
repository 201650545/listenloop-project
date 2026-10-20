import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 默认档案 id。
///
/// 老用户升级后自动落在这个档案里 —— 已有的学习进度**一条不丢**
/// （数据库迁移把 learning_progress 的旧行全部归到 `default`）。
const String kDefaultProfileId = 'default';

/// 本地用户档案（离线登录）。
///
/// 刻意不做云端：这是给一台手机/平板上的多个孩子（或一个孩子 + 家长）
/// 各自留一份学习记录用的，数据只在本机，不出设备。
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.emoji,
    required this.createdAt,
    this.pinHash,
    this.pinSalt,
  });

  final String id;
  final String name;
  final String emoji;
  final DateTime createdAt;

  /// PIN 的哈希（加盐 sha256）。null = 这个档案没设密码，开 App 直接进。
  final String? pinHash;
  final String? pinSalt;

  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  UserProfile copyWith({
    String? name,
    String? emoji,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      createdAt: createdAt,
      pinHash: clearPin ? null : (pinHash ?? this.pinHash),
      pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'createdAt': createdAt.toIso8601String(),
        'pinHash': pinHash,
        'pinSalt': pinSalt,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? kDefaultProfileId,
      name: json['name'] as String? ?? '我',
      emoji: json['emoji'] as String? ?? '🙂',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      pinHash: json['pinHash'] as String?,
      pinSalt: json['pinSalt'] as String?,
    );
  }
}

/// 档案登记表（本机 SharedPreferences，单一真源）。
///
/// 放在 SharedPreferences 而不是数据库：即使课件库打开失败（降级成内存
/// 库），登录这一层依然能用；而且档案/密码都是"壳"级数据，量极小。
class ProfileStore extends ChangeNotifier {
  ProfileStore();

  static const String _kProfilesKey = 'listenloop:profiles.v1';
  static const String _kActiveKey = 'listenloop:activeProfile.v1';

  static const List<String> _emojiChoices = [
    '🙂', '👦', '👧', '🧒', '🐯', '🐰', '🦊', '🐼',
    '🦁', '🐧', '🐳', '🌟', '🚀', '🎻', '🎨', '⚽',
  ];

  static List<String> get emojiChoices => _emojiChoices;

  List<UserProfile> _profiles = const [];
  String _activeId = kDefaultProfileId;
  bool _loaded = false;

  List<UserProfile> get profiles => List.unmodifiable(_profiles);
  String get activeId => _activeId;
  bool get isLoaded => _loaded;

  UserProfile get active {
    if (_profiles.isEmpty) {
      return UserProfile(
        id: kDefaultProfileId,
        name: '我',
        emoji: '🙂',
        createdAt: DateTime.now(),
      );
    }
    return _profiles.firstWhere(
      (p) => p.id == _activeId,
      orElse: () => _profiles.first,
    );
  }

  UserProfile? byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 读盘。首次运行会建一个默认档案 —— 老用户的学习进度全部归它。
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kProfilesKey);
    final parsed = <UserProfile>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              parsed.add(UserProfile.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
      } catch (_) {
        // 存档损坏：当作没有档案，重新建默认档案，绝不因此崩在启动路径上。
      }
    }
    if (parsed.isEmpty) {
      parsed.add(
        UserProfile(
          id: kDefaultProfileId,
          name: '我',
          emoji: '🙂',
          createdAt: DateTime.now(),
        ),
      );
    }
    // 默认档案永远存在（第一个）。
    if (!parsed.any((p) => p.id == kDefaultProfileId)) {
      parsed.insert(
        0,
        UserProfile(
          id: kDefaultProfileId,
          name: '我',
          emoji: '🙂',
          createdAt: DateTime.now(),
        ),
      );
    }
    _profiles = parsed;
    final storedActive = sp.getString(_kActiveKey);
    _activeId = _profiles.any((p) => p.id == storedActive)
        ? storedActive!
        : _profiles.first.id;
    _loaded = true;
    notifyListeners();
  }

  /// 新建档案。返回新档案。
  Future<UserProfile> create({required String name, String emoji = '👦'}) async {
    final id = 'p_${DateTime.now().microsecondsSinceEpoch}';
    final profile = UserProfile(
      id: id,
      name: name.trim().isEmpty ? '新用户' : name.trim(),
      emoji: emoji,
      createdAt: DateTime.now(),
    );
    _profiles = [..._profiles, profile];
    await _persist();
    notifyListeners();
    return profile;
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _profiles = [
      for (final p in _profiles)
        if (p.id == id) p.copyWith(name: trimmed) else p,
    ];
    await _persist();
    notifyListeners();
  }

  Future<void> setEmoji(String id, String emoji) async {
    _profiles = [
      for (final p in _profiles)
        if (p.id == id) p.copyWith(emoji: emoji) else p,
    ];
    await _persist();
    notifyListeners();
  }

  /// 删除档案。**不允许删掉最后一个** —— 否则 App 会变成"没有用户"的空壳。
  Future<bool> remove(String id) async {
    if (_profiles.length <= 1) return false;
    _profiles = [for (final p in _profiles) if (p.id != id) p];
    if (_activeId == id) _activeId = _profiles.first.id;
    await _persist();
    notifyListeners();
    return true;
  }

  /// 切换当前档案。调用方负责接着刷新偏好与学习进度。
  Future<void> setActive(String id) async {
    if (_activeId == id) return;
    if (!_profiles.any((p) => p.id == id)) return;
    _activeId = id;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kActiveKey, id);
    notifyListeners();
  }

  /// 设置/取消 PIN。pin 传 null = 取消密码。
  Future<void> setPin(String id, String? pin) async {
    if (pin == null || pin.isEmpty) {
      _profiles = [
        for (final p in _profiles)
          if (p.id == id) p.copyWith(clearPin: true) else p,
      ];
    } else {
      final salt = _randomSalt();
      _profiles = [
        for (final p in _profiles)
          if (p.id == id) p.copyWith(pinHash: _hash(pin, salt), pinSalt: salt)
          else p,
      ];
    }
    await _persist();
    notifyListeners();
  }

  /// 校验 PIN。档案没设密码时一律放行。
  bool verifyPin(String id, String pin) {
    final profile = byId(id);
    if (profile == null) return false;
    if (!profile.hasPin) return true;
    return _hash(pin, profile.pinSalt ?? '') == profile.pinHash;
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kProfilesKey,
      jsonEncode([for (final p in _profiles) p.toJson()]),
    );
    await sp.setString(_kActiveKey, _activeId);
  }

  static String _randomSalt() {
    final rnd = Random();
    final bytes = List<int>.generate(8, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}

/// 把当前档案登记表放进 widget 树（设置页的「档案」入口靠它拿档案）。
class ProfileScope extends InheritedWidget {
  const ProfileScope({
    super.key,
    required this.store,
    required super.child,
  });

  final ProfileStore store;

  static ProfileStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'ProfileScope 未挂载：离线登录入口拿不到档案表');
    return scope!.store;
  }

  /// 取不到时返回 null（单测里没挂 scope 的场合用）。
  static ProfileStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileScope>()?.store;

  @override
  bool updateShouldNotify(ProfileScope oldWidget) => oldWidget.store != store;
}
