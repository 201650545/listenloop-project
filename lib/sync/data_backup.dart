import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/ai_governor_service.dart' show AiGovernorService;
import '../data/vocabulary_store.dart' show VocabularyStore;
import '../preferences/app_preferences.dart' show AppPreferences;
import 'export_payload.dart';

/// 用户取消分享备份 —— 调用方应视为"用户主动放弃"，不提示错误。
class BackupShareCancelled implements Exception {
  BackupShareCancelled();
  @override
  String toString() => 'BackupShareCancelled';
}

/// 把当前学习数据组装成 [ExportPayload] 并写成 JSON 文件分享出去。
///
/// 与 Anki `.apkg` 导出（`anki/apkg_share.dart`）区分开：
/// `.apkg` 是"知识库导出"，本包是"用户状态备份"（生词本 FSRS + 弱点 +
/// 挖卡 + 偏好 + 进度）。**不含音频等大文件，也不含任何 API key**。
///
/// 成功返回 true；用户取消抛 [BackupShareCancelled]。
Future<bool> exportBackup({
  required VocabularyStore store,
  required AiGovernorService governor,
  required AppPreferences? prefs,
  List<ExportProgressRecord> progress = const [],
  DateTime? now,
}) async {
  final payload = ExportPayload.build(
    vocabularyStore: store,
    governor: governor,
    prefs: prefs,
    progress: progress,
    now: now,
  );
  final bytes = payload.encode();

  final tmp = await getTemporaryDirectory();
  final fileName = 'listenloop_backup_${_stamp(now ?? DateTime.now())}.json';
  final file = File('${tmp.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);

  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: '句读 学习数据备份',
      text: '句读 学习数据备份（生词本 / FSRS / 弱点 / 偏好）。'
          '导入到另一台设备即可继续学习。',
    ),
  );
  if (result.status == ShareResultStatus.dismissed) {
    throw BackupShareCancelled();
  }
  return true;
}

/// 文件名时间戳（秒级，与 LocalSnapshotManager 一致）。
String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}_'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// 生成本地快照字节（不落分享，供 [exportBackup] 之外的调用复用）。
Uint8List encodeBackupBytes({
  required VocabularyStore store,
  required AiGovernorService governor,
  required AppPreferences? prefs,
  List<ExportProgressRecord> progress = const [],
  DateTime? now,
}) {
  final payload = ExportPayload.build(
    vocabularyStore: store,
    governor: governor,
    prefs: prefs,
    progress: progress,
    now: now,
  );
  return Uint8List.fromList(payload.encode());
}
