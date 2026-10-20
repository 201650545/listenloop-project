import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ai_governor_service.dart' show AiGovernorService;
import '../data/vocabulary_store.dart' show VocabularyStore;
import '../preferences/app_preferences.dart' show AppPreferences;
import 'export_payload.dart';

/// L1 本地留存 —— 在用户毫无动作的情况下自动保护「最容易丢的数据」。
///
/// 三个动作，全部幂等、静默失败（不打扰学习）：
///   1. [takeSnapshot]  把当前数据打包成 `ExportPayload` JSON，落到
///      `<documents>/backup/listenloop_snapshot_<timestamp>.json`；
///   2. [backupSqlite]  把 `listenloop.db` 复制一份（SQLite 快照），
///      应对 schema 损坏 / 误操作 / 数据库文件被覆盖；
///   3. [prune]         滚动清理，只保留最近 [keepCount] 份快照。
///
/// 快照只覆盖**结构数据**；音频/封面等大文件不落快照（体积爆炸，收益低）。
class LocalSnapshotManager {
  LocalSnapshotManager({
    String? backupRoot,
    int keepCount = 3,
  })  : _backupRootOverride = backupRoot,
        _keepCount = keepCount;

  /// 快照目录。默认 `<documents>/backup`，测试可注入 [backupRoot]。
  Future<Directory> _backupRoot() async {
    final override = _backupRootOverride;
    if (override != null) {
      return Directory(override);
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'backup'));
  }

  final String? _backupRootOverride;
  final int _keepCount;

  /// 当前时间戳文件名（秒级，避免毫秒级重名）。
  static String _stamp([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// 组装 ExportPayload（数据从三处抽过来）。
  static ExportPayload _buildPayload({
    required VocabularyStore store,
    AiGovernorService? governor,
    required AppPreferences? prefs,
    List<ExportProgressRecord> progress = const [],
  }) {
    return ExportPayload.build(
      vocabularyStore: store,
      governor: governor,
      prefs: prefs,
      progress: progress,
    );
  }

  /// 把当前状态打包落盘（JSON），返回文件路径；失败返回 null。
  ///
  /// [governor] 可空：启动快照时 governor 尚未创建，此时只备份生词本。
  Future<String?> takeSnapshot({
    required VocabularyStore store,
    AiGovernorService? governor,
    required AppPreferences? prefs,
    List<ExportProgressRecord> progress = const [],
    DateTime? now,
  }) async {
    try {
      final dir = await _backupRoot();
      await dir.create(recursive: true);
      final payload = _buildPayload(
        store: store,
        governor: governor,
        prefs: prefs,
        progress: progress,
      );
      final file = File(p.join(dir.path, 'listenloop_snapshot_${_stamp(now)}.json'));
      await file.writeAsBytes(payload.encode(), flush: true);
      await prune();
      return file.path;
    } catch (e) {
      // L1 是锦上添花，失败绝不能阻塞启动或打扰用户。
      return null;
    }
  }

  /// 把 SQLite db 复制一份快照。
  /// 注意：Android sqflite 默认 WAL 模式，复制时未 checkpoint 的 WAL
  /// 数据可能不在主文件里。因此这里**同时复制 -wal / -shm** 两个文件
  /// （若存在），保证快照可被独立打开。恢复时需把三个文件放回原位。
  /// 返回主 db 快照路径；失败返回 null。
  Future<String?> backupSqlite({
    required String dbPath,
    DateTime? now,
  }) async {
    try {
      final src = File(dbPath);
      if (!src.existsSync()) return null;
      final dir = await _backupRoot();
      await dir.create(recursive: true);
      final stamp = _stamp(now);
      final dest = File(p.join(dir.path, 'listenloop_db_$stamp.db'));
      await src.copy(dest.path);
      // 一并复制 WAL / SHM，保证快照完整性（WAL 未合并时不丢数据）。
      for (final suffix in ['-wal', '-shm']) {
        final side = File('$dbPath$suffix');
        if (side.existsSync()) {
          await side.copy('${dest.path}$suffix');
        }
      }
      await prune();
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  /// 滚动清理：只保留最近 [keepCount] 份快照（按文件名排序，
  /// 时间戳前缀保证字典序=时间序）。
  Future<void> prune() async {
    try {
      final dir = await _backupRoot();
      if (!dir.existsSync()) return;
      final snapshots = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.json') || f.path.endsWith('.db'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final excess = snapshots.length - _keepCount;
      for (var i = 0; i < excess && i < snapshots.length; i++) {
        try {
          snapshots[i].deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 列出当前快照目录里的全部快照文件（供 UI 展示）。
  Future<List<File>> listSnapshots() async {
    final dir = await _backupRoot();
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.json') || f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }
}

/// 从 SharedPreferences 里把三处散存的数据读成 ExportPayload 各分区。
/// 供 L1/L2 组装时使用（避免 UI 层到处找键名）。
class SharedPreferencesPayloadReader {
  SharedPreferencesPayloadReader();

  /// 生词本 items 的原始 JSON 列表（从 SharedPreferences 读取）。
  /// 返回空列表表示无数据或读失败。
  List<Map<String, Object?>> readVocabularyRaw() {
    return _readList(VocabularyStore.storageKey);
  }

  /// AI 伴学弱点原始 JSON。
  List<Map<String, Object?>> readWeaknessesRaw() {
    return _readList('listenloop:ai_weaknesses');
  }

  /// AI 伴学 Anki 卡原始 JSON。
  List<Map<String, Object?>> readAnkiCardsRaw() {
    return _readList('listenloop:ai_anki_cards');
  }

  /// 读取 SharedPreferences 里的 StringList（`listenloop:` 前缀）。
  List<Map<String, Object?>> _readList(String key) {
    final sp = _cachedSp;
    if (sp == null) return const [];
    final raw = sp.getStringList(key) ?? const [];
    final out = <Map<String, Object?>>[];
    for (final entry in raw) {
      try {
        final map = (jsonDecode(entry) as Map).cast<String, Object?>();
        out.add(map);
      } catch (_) {}
    }
    return out;
  }

  SharedPreferences? _cachedSp;
  Future<void> ensureLoaded() async {
    if (_cachedSp != null) return;
    try {
      _cachedSp = await SharedPreferences.getInstance();
    } catch (_) {
      _cachedSp = null;
    }
  }
}
