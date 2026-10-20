import 'dart:convert';

import '../data/ai_governor_service.dart' show AiGovernorService;
import '../data/vocabulary_store.dart' show VocabularyStore;
import '../models/ai_governor_model.dart' show WeaknessRecord;
import '../models/anki_card_model.dart' show AnkiCard;
import '../models/vocabulary_model.dart' show VocabularyItem;
import '../preferences/app_preferences.dart' show AppPreferences;

/// ListenLoop 数据留存导出包的统一模型（本轮落地 L1/L2 的载体）。
///
/// 设计原则：
///   1. **纯函数可测** —— encode/decode 只依赖入参，不碰 IO。
///   2. **带 schemaVersion** —— 将来格式变化靠版本迁移，不破坏旧包。
///   3. **脱敏** —— 绝不包含 `translationApiKey` / `tutorApiKey` 等凭据。
///      只带 base URL 与 model id（换机后可重新填 key，key 永远不出本机）。
///   4. **不打包大文件** —— 音频/封面不进 JSON，导入后按需重新获取。
///
/// 未来 L3 云同步只需把本包作为传输 payload，业务层不动。
class ExportPayload {
  const ExportPayload({
    required this.schemaVersion,
    required this.exportedAt,
    this.vocabularyItems = const [],
    this.weaknesses = const [],
    this.ankiCards = const [],
    this.preferences,
    this.progress = const [],
  });

  /// 当前导出格式版本。变更字段结构时必须递增，并提供对应迁移。
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime exportedAt;

  /// 生词本全部词条（含 FSRS 状态、occurrences、drills）。
  final List<VocabularyItem> vocabularyItems;

  /// AI 伴学弱点记录。
  final List<WeaknessRecord> weaknesses;

  /// 历史挖卡得到的 Anki 卡。
  final List<AnkiCard> ankiCards;

  /// 脱敏后的个人偏好（不含任何 API key）。
  final ExportPreferences? preferences;

  /// 各课程学习进度。
  final List<ExportProgressRecord> progress;

  /// 组装一份新包：从 [vocabularyStore] 与 [governor] 抽出数据，
  /// 偏好由 [prefs] 提供（只拷贝非敏感字段）。
  ///
  /// [governor] 可空：L1 启动快照时 governor 尚未创建，此时只备份
  /// 生词本（最珍贵的 FSRS 曲线）；L2 用户主动导出时才带 governor 数据。
  factory ExportPayload.build({
    required VocabularyStore vocabularyStore,
    AiGovernorService? governor,
    required AppPreferences? prefs,
    List<ExportProgressRecord> progress = const [],
    DateTime? now,
  }) {
    return ExportPayload(
      schemaVersion: currentSchemaVersion,
      exportedAt: now ?? DateTime.now(),
      vocabularyItems: vocabularyStore.items,
      weaknesses: governor == null
          ? const []
          : List<WeaknessRecord>.from(governor.weaknesses),
      ankiCards: governor == null
          ? const []
          : List<AnkiCard>.from(governor.ankiCards),
      preferences: prefs == null ? null : ExportPreferences.from(prefs),
      progress: progress,
    );
  }

  /// 序列化为 UTF-8 JSON 字节。
  List<int> encode() {
    final map = toJson();
    return utf8.encode(jsonEncode(map));
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'app': 'listenloop',
    'vocabularyItems': [
      for (final i in vocabularyItems) i.toJson(),
    ],
    'weaknesses': [
      for (final w in weaknesses) w.toJson(),
    ],
    'ankiCards': [
      for (final c in ankiCards) c.toJson(),
    ],
    'preferences': preferences?.toJson(),
    'progress': [
      for (final p in progress) p.toJson(),
    ],
  };

  /// 从 JSON map 解码；未知字段忽略，缺字段用默认值（向前兼容）。
  static ExportPayload fromJson(Map<String, Object?> json) {
    return ExportPayload(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      exportedAt:
          DateTime.tryParse((json['exportedAt'] ?? '') as String) ??
              DateTime.now(),
      vocabularyItems: <VocabularyItem>[
        for (final e in (json['vocabularyItems'] as List? ?? const []))
          VocabularyItem.fromJson((e as Map).cast<String, Object?>()),
      ],
      weaknesses: <WeaknessRecord>[
        for (final e in (json['weaknesses'] as List? ?? const []))
          WeaknessRecord.fromJson((e as Map).cast<String, dynamic>()),
      ],
      ankiCards: <AnkiCard>[
        for (final e in (json['ankiCards'] as List? ?? const []))
          AnkiCard.fromJson((e as Map).cast<String, dynamic>()),
      ],
      preferences: json['preferences'] == null
          ? null
          : ExportPreferences.fromJson(
              (json['preferences']! as Map).cast<String, Object?>(),
            ),
      progress: <ExportProgressRecord>[
        for (final e in (json['progress'] as List? ?? const []))
          ExportProgressRecord.fromJson((e as Map).cast<String, Object?>()),
      ],
    );
  }

  /// 解码 UTF-8 字节。
  static ExportPayload decode(List<int> bytes) {
    final map = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    return fromJson(map);
  }
}

/// 脱敏后的个人偏好。**有意省略所有 API key** ——
/// 换机后 key 由用户重新填写，绝不随导出包外泄。
class ExportPreferences {
  const ExportPreferences({
    required this.themeMode,
    required this.learningFont,
    required this.textScale,
    required this.uiLanguage,
    required this.translationBaseUrl,
    required this.translationModel,
    required this.asrThreads,
    required this.asrTier,
    required this.youtubeRelayBaseUrl,
    required this.tutorBaseUrl,
    required this.tutorModel,
    required this.libraryGridView,
    required this.scrubberHaptics,
  });

  final String themeMode; // 'dark' / 'light' / 'system'
  final String learningFont; // 'sans' / 'serif' / 'system'
  final double textScale;
  final String uiLanguage; // 'english' / 'chinese'
  final String translationBaseUrl;
  final String translationModel;
  final int asrThreads;
  final String asrTier; // 'fast' / 'accurate'
  final String youtubeRelayBaseUrl;
  final String tutorBaseUrl;
  final String tutorModel;
  final bool libraryGridView;
  final bool scrubberHaptics;

  factory ExportPreferences.from(AppPreferences p) => ExportPreferences(
    themeMode: p.themeMode.name,
    learningFont: p.learningFont.name,
    textScale: p.textScale,
    uiLanguage: p.uiLanguage.name,
    translationBaseUrl: p.translationBaseUrl,
    translationModel: p.translationModel,
    asrThreads: p.asrThreads,
    asrTier: p.asrTier.name,
    youtubeRelayBaseUrl: p.youtubeRelayBaseUrl,
    tutorBaseUrl: p.tutorBaseUrl,
    tutorModel: p.tutorModel,
    libraryGridView: p.libraryGridView,
    scrubberHaptics: p.scrubberHaptics,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'themeMode': themeMode,
    'learningFont': learningFont,
    'textScale': textScale,
    'uiLanguage': uiLanguage,
    'translationBaseUrl': translationBaseUrl,
    'translationModel': translationModel,
    'asrThreads': asrThreads,
    'asrTier': asrTier,
    'youtubeRelayBaseUrl': youtubeRelayBaseUrl,
    'tutorBaseUrl': tutorBaseUrl,
    'tutorModel': tutorModel,
    'libraryGridView': libraryGridView,
    'scrubberHaptics': scrubberHaptics,
  };

  static ExportPreferences fromJson(Map<String, Object?> json) =>
      ExportPreferences(
        themeMode: (json['themeMode'] ?? 'dark') as String,
        learningFont: (json['learningFont'] ?? 'sans') as String,
        textScale: (json['textScale'] as num?)?.toDouble() ?? 0.75,
        uiLanguage: (json['uiLanguage'] ?? 'english') as String,
        translationBaseUrl: (json['translationBaseUrl'] ?? '') as String,
        translationModel: (json['translationModel'] ?? '') as String,
        asrThreads: (json['asrThreads'] as num?)?.toInt() ?? 4,
        asrTier: (json['asrTier'] ?? 'fast') as String,
        youtubeRelayBaseUrl: (json['youtubeRelayBaseUrl'] ?? '') as String,
        tutorBaseUrl: (json['tutorBaseUrl'] ?? '') as String,
        tutorModel: (json['tutorModel'] ?? '') as String,
        libraryGridView: (json['libraryGridView'] as bool?) ?? true,
        scrubberHaptics: (json['scrubberHaptics'] as bool?) ?? true,
      );
}

/// 单条学习进度（对应 SQLite `learning_progress` 一行）。
class ExportProgressRecord {
  const ExportProgressRecord({
    required this.lessonId,
    required this.lastSentenceIndex,
    required this.positionMs,
    required this.subtitleMode,
    required this.playbackRate,
    required this.repeatTarget,
    required this.displayMode,
    required this.updatedAt,
  });

  final String lessonId;
  final int lastSentenceIndex;
  final int positionMs;
  final String subtitleMode;
  final double playbackRate;
  final int repeatTarget;
  final String displayMode;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'lessonId': lessonId,
    'lastSentenceIndex': lastSentenceIndex,
    'positionMs': positionMs,
    'subtitleMode': subtitleMode,
    'playbackRate': playbackRate,
    'repeatTarget': repeatTarget,
    'displayMode': displayMode,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static ExportProgressRecord fromJson(Map<String, Object?> json) =>
      ExportProgressRecord(
        lessonId: json['lessonId']! as String,
        lastSentenceIndex: (json['lastSentenceIndex'] as num?)?.toInt() ?? 0,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        subtitleMode: (json['subtitleMode'] ?? 'bilingual') as String,
        playbackRate: (json['playbackRate'] as num?)?.toDouble() ?? 1.0,
        repeatTarget: (json['repeatTarget'] as num?)?.toInt() ?? 1,
        displayMode: (json['displayMode'] ?? 'fluid') as String,
        updatedAt:
            DateTime.tryParse((json['updatedAt'] ?? '') as String) ??
                DateTime.now(),
      );
}
