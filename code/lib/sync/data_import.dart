import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import '../data/vocabulary_store.dart' show VocabularyStore;
import '../preferences/app_preferences.dart'
    show AppLanguage, AsrTier, PreferencesController;
import 'export_payload.dart';

/// L2 导入备份 —— 换机/重装后把 `.json` 备份恢复到本机。
///
/// 与导出（`data_backup.dart`）配对：导出把状态写成 JSON，本文件选回
/// 该 JSON 并走「选文件 → 校验 schemaVersion → 确认 → 合并/覆盖」闭环。
///
/// 原则：
///   * **生词本 FSRS 曲线最珍贵** —— 导入默认**合并**（同 lemma 保留本机，
///     只补本机没有的词），避免"新换的机上旧数据吞掉新学的词"。
///   * **偏好只恢复脱敏字段** —— API key 永不写入；主题/字号等外观偏好
///     也保留本机（见 [ExportPreferences] 注释）。
///   * **进度/弱点/Anki 卡不在本轮恢复** —— 进度依赖课程是否已导入，
///     governor 数据随生词本页面不持有；本轮只恢复生词本 + 脱敏偏好。
class ImportedBackup {
  const ImportedBackup({
    required this.payload,
    required this.sourceName,
  });

  final ExportPayload payload;

  /// 用户选中的文件显示名（提示语里用）。
  final String sourceName;
}

/// 导入失败 —— 调用方统一提示「无法导入」，区分"用户取消"与"真失败"。
class BackupImportException implements Exception {
  BackupImportException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => 'BackupImportException: $message';
}

/// 用户取消文件选择 —— 不算失败，不提示。
class BackupImportCancelled implements Exception {
  BackupImportCancelled();
  @override
  String toString() => 'BackupImportCancelled';
}

/// 用系统文件选择器选回 `.json` 备份并解码。
///
/// 用户取消时抛 [BackupImportCancelled]（调用方安静收场）。
/// [pick] 可注入以便测试（生产用 [FilePicker.platform.pickFiles]）。
Future<ImportedBackup> pickAndDecodeBackup({
  Future<FilePickerResult?> Function({
    required FileType type,
    List<String>? allowedExtensions,
  })? pick,
}) async {
  final picker = pick ??
      ({
        required FileType type,
        List<String>? allowedExtensions,
      }) =>
          FilePicker.platform.pickFiles(
            type: type,
            allowedExtensions: allowedExtensions,
          );

  final FilePickerResult? result;
  try {
    result = await picker(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
  } on MissingPluginException catch (e) {
    throw BackupImportException('文件选择器不可用', e);
  }
  if (result == null) throw BackupImportCancelled();

  final selected = result.files.first;
  final name = selected.name;
  final bytes = selected.bytes;
  if (bytes == null) {
    throw BackupImportException('无法读取所选文件「$name」（可能是大文件路径读取失败）');
  }
  final payload = decodePayload(bytes, sourceName: name);
  return ImportedBackup(payload: payload, sourceName: name);
}

/// 从字节解码 [ExportPayload]，并做 schemaVersion 校验。
///
/// 只有明确支持 / 可前向兼容的版本才放行；未来版本一律拒绝并给出提示，
/// 避免"用旧版应用导入新版数据导致静默丢字段"。
ExportPayload decodePayload(List<int> bytes, {String sourceName = '备份文件'}) {
  final Map<String, Object?> map;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('顶层不是 JSON 对象');
    }
    map = decoded.cast<String, Object?>();
  } catch (e) {
    throw BackupImportException('「$sourceName」不是有效的 JSON 备份文件', e);
  }

  final version = (map['schemaVersion'] as num?)?.toInt();
  if (version == null) {
    throw BackupImportException('「$sourceName」缺少 schemaVersion，不是句读备份');
  }
  if (version > ExportPayload.currentSchemaVersion) {
    throw BackupImportException(
      '「$sourceName」来自更新版本（schema v$version），请先升级句读再导入',
    );
  }
  if (version < 1) {
    throw BackupImportException('「$sourceName」的 schemaVersion 无效（v$version）');
  }

  try {
    return ExportPayload.fromJson(map);
  } catch (e) {
    throw BackupImportException('「$sourceName」解析失败：$e', e);
  }
}

/// 合并导入 —— 把 [payload] 里的生词本按 lemma 合并进 [store]。
///
/// 判重口径与生词本内部一致（normalizeTerm 归一化）：
///   * 本机已有同 lemma → **保留本机**（FSRS 状态、证据都在本机这份上）；
///   * 本机没有 → 插入导入词条。
///
/// 返回统计：[merged] 新增词条数，[skipped] 因 lemma 冲突跳过的条数。
ImportMergeResult importVocabulary(
  ExportPayload payload,
  VocabularyStore store,
) {
  var merged = 0;
  var skipped = 0;
  for (final incoming in payload.vocabularyItems) {
    if (store.itemBySurface(incoming.surfaceForm) != null) {
      skipped++;
      continue;
    }
    store.addImported(incoming);
    merged++;
  }
  return ImportMergeResult(merged: merged, skipped: skipped);
}

/// 覆盖导入 —— 清空本机后写入导入数据（用于"重装后首次恢复"）。
/// 会丢失本机现存的词条，调用方必须先经用户确认。
ImportMergeResult importVocabularyOverwrite(
  ExportPayload payload,
  VocabularyStore store,
) {
  final before = store.items.length;
  store.clear();
  for (final incoming in payload.vocabularyItems) {
    store.addImported(incoming);
  }
  return ImportMergeResult(
    merged: payload.vocabularyItems.length,
    skipped: before,
  );
}

/// 恢复脱敏偏好 —— 只写非敏感字段，API key 一律不动。
///
/// [controller] 为 null 时静默跳过（偏好不是关键数据）。
Future<void> importPreferences(
  ExportPayload payload,
  PreferencesController? controller,
) async {
  if (controller == null) return;
  final prefs = payload.preferences;
  if (prefs == null) return;
  await controller.update(
    // 外观偏好保留本机；只恢复功能字段。
    themeMode: null,
    learningFont: null,
    textScale: null,
    uiLanguage: _enumByName(AppLanguage.values, prefs.uiLanguage,
        fallback: AppLanguage.english),
    translationBaseUrl: prefs.translationBaseUrl,
    translationModel: prefs.translationModel,
    asrThreads: prefs.asrThreads,
    asrTier: _enumByName(AsrTier.values, prefs.asrTier,
        fallback: AsrTier.fast),
    youtubeRelayBaseUrl: prefs.youtubeRelayBaseUrl,
    tutorBaseUrl: prefs.tutorBaseUrl,
    tutorModel: prefs.tutorModel,
    libraryGridView: prefs.libraryGridView,
    scrubberHaptics: prefs.scrubberHaptics,
  );
}

/// 按 name 找枚举，找不到退回默认（备份来自更早版本 / 字段被改名的兜底）。
T _enumByName<T extends Enum>(List<T> values, String name,
    {required T fallback}) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// 导入统计结果。
class ImportMergeResult {
  const ImportMergeResult({required this.merged, required this.skipped});

  /// 真正写进本机的词条数。
  final int merged;

  /// 因 lemma 冲突（合并模式）或被覆盖（覆盖模式）未保留的条数。
  final int skipped;
}
