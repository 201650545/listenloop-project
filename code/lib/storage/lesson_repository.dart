import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/profile_store.dart';
import '../lesson/lesson_package_reader.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../models/video_source.dart';

/// Persistence contract for the offline lesson library (spec V0.2 §15, §19).
abstract class LessonRepository {
  /// All lessons, most-recently-touched first (progress `updatedAt`, falling
  /// back to `importedAt`), each joined with its optional progress.
  Future<List<LessonWithProgress>> listLessons();

  /// Persists a runtime-fetched cover (Visual Polish V2 follow-up: video
  /// lessons whose package predates the cover pipeline). A value update on
  /// the existing `lessons.cover_path` column — no schema change.
  Future<void> updateCoverPath(String lessonId, String coverPath);

  Future<LessonWithSentences?> getLessonWithSentences(String lessonId);

  /// Upserts where the user left off in [lessonId] (V0.2.1: repeat target,
  /// playback rate, subtitle and display modes restore with the sentence).
  Future<void> saveProgress({
    required String lessonId,
    required int lastSentenceIndex,
    required int positionMs,
    int repeatTarget = 1,
    double playbackRate = 1.0,
    String subtitleMode = 'bilingual',
    String displayMode = 'fluid',
  });

  /// Validates nothing (the reader did) and stores a package: media files
  /// are copied under the repository's lessons root, metadata + sentences go
  /// into the database. Re-importing an existing [package.manifest.lessonId]
  /// replaces the previous copy.
  Future<Lesson> importPackage(ParsedLessonPackage package);

  /// Returns alternate sentences (e.g. fluent.json or chunks.json) if present for [lessonId].
  Future<List<Sentence>?> getAlternateSentences(String lessonId);

  /// Removes the lesson, its sentences, its progress and its media files.
  Future<void> deleteLesson(String lessonId);

  /// 仅清除课件媒体文件（音频、视频、图片、大文本），保留学习进度与核心记录
  Future<void> deleteMediaPreservingProgress(String lessonId);

  /// 批量删除指定课件列表（可选择保留用户学习进度），返回删除数量
  Future<int> deleteLessons(List<String> lessonIds, {bool preserveProgress = true});

  /// 按年级统计已占用的媒体存储空间（字节数与课件数）
  Future<Map<String, GradeStorageStats>> getLessonsStorageStats();
}

/// 某年级存储统计
class GradeStorageStats {
  const GradeStorageStats({
    required this.gradeLabel,
    required this.lessonCount,
    required this.totalBytes,
    required this.lessonIds,
  });

  final String gradeLabel;
  final int lessonCount;
  final int totalBytes;
  final List<String> lessonIds;
}

/// Result of [LessonRepository.getLessonWithSentences].
class LessonWithSentences {
  const LessonWithSentences({required this.lesson, required this.sentences});

  final Lesson lesson;
  final List<Sentence> sentences;
}

/// SQLite-backed [LessonRepository].
///
/// Light data (lessons, sentences, progress) lives in SQLite; media files
/// live under `<app documents>/lessons/<lessonId>/` — never inside the
/// database (spec V0.2 §19).
class SqfliteLessonRepository implements LessonRepository {
  SqfliteLessonRepository._(
    this._db,
    this.lessonsRoot, {
    String Function()? profileId,
  }) : _profileId = profileId ?? (() => kDefaultProfileId);

  final Database _db;

  /// 当前档案 id 的取数器。**每次查询都现取**，所以切换档案立刻生效，
  /// 不必重开数据库。
  final String Function() _profileId;

  /// 当前档案 id。
  String get profileId => _profileId();

  /// Directory that holds one sub-directory per imported lesson.
  final String lessonsRoot;

  /// Opens (creating if needed) the database and the lessons root directory.
  ///
  /// [profileId] is read **on every query** (not captured once), so switching
  /// the active local profile takes effect immediately without reopening the
  /// database. 2026-10-20 离线登录：学习进度按档案隔离。
  static Future<SqfliteLessonRepository> open({
    String Function()? profileId,
  }) async {
    final dbPath = p.join(await getDatabasesPath(), 'listenloop.db');
    final docs = await getApplicationDocumentsDirectory();
    final root = p.join(docs.path, 'lessons');
    await Directory(root).create(recursive: true);
    final db = await openDatabase(
      dbPath,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return SqfliteLessonRepository._(
      db,
      root,
      profileId: profileId ?? () => kDefaultProfileId,
    );
  }

  /// Creates the v3 schema from scratch.
  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE lessons (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        language TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        sentence_count INTEGER NOT NULL,
        audio_path TEXT NOT NULL,
        cover_path TEXT,
        video_json TEXT,
        series TEXT,
        imported_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sentences (
        lesson_id TEXT NOT NULL,
        idx INTEGER NOT NULL,
        sentence_id TEXT NOT NULL,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        english TEXT NOT NULL,
        chinese TEXT NOT NULL,
        PRIMARY KEY (lesson_id, idx)
      )
    ''');
    await db.execute('''
      CREATE TABLE learning_progress (
        profile_id TEXT NOT NULL DEFAULT 'default',
        lesson_id TEXT NOT NULL,
        last_sentence_index INTEGER NOT NULL,
        position_ms INTEGER NOT NULL,
        subtitle_mode TEXT NOT NULL DEFAULT 'bilingual',
        playback_rate REAL NOT NULL DEFAULT 1.0,
        repeat_target INTEGER NOT NULL DEFAULT 0,
        display_mode TEXT NOT NULL DEFAULT 'fluid',
        updated_at TEXT NOT NULL,
        PRIMARY KEY (profile_id, lesson_id)
      )
    ''');
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
    );
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      // V0.2.1: extended learning progress columns.
      //
      // Real v1 databases shipped with `subtitle_mode` AND `playback_rate`
      // already present in `learning_progress`, so a plain
      // `ALTER TABLE ... ADD COLUMN playback_rate` throws
      // `duplicate column name: playback_rate`, aborts the whole upgrade
      // transaction, leaves `user_version` at 1 and makes `openDatabase`
      // fail — which used to drop the app to an empty in-memory library.
      // Add every column defensively so the migration is idempotent.
      await _addColumnIfMissing(
        db,
        'learning_progress',
        'repeat_target',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        'learning_progress',
        'playback_rate',
        'REAL NOT NULL DEFAULT 1.0',
      );
      await _addColumnIfMissing(
        db,
        'learning_progress',
        'display_mode',
        "TEXT NOT NULL DEFAULT 'fluid'",
      );
    }
    if (oldVersion < 3) {
      // V0.3 §3A: optional online video source, stored as a JSON blob so the
      // shape can grow without another migration. Null = audio-only lesson.
      // Added defensively (see the v1→v2 note): a re-run must not throw.
      await _addColumnIfMissing(db, 'lessons', 'video_json', 'TEXT');
    }
    if (oldVersion < 4) {
      // 2026-09-29 课文朗读系列：同一 series 的课程在课程列表归组展示。
      await _addColumnIfMissing(db, 'lessons', 'series', 'TEXT');
    }
    if (oldVersion < 5) {
      // 2026-10-20 离线登录：学习进度按**档案**隔离。
      //
      // 旧表的主键是 lesson_id —— 一个课只能存一份进度，两个孩子没法各自
      // 记自己的读到第几句。这里把主键改成 (profile_id, lesson_id)，旧行
      // 全部归到 'default' 档案：**老用户进度一条不丢**。
      //
      // 必须走"建新表 → 搬数据 → 删旧表 → 改名"，不能只 ADD COLUMN：
      // SQLite 不支持改主键，复合主键只能重建表。
      await db.execute('''
        CREATE TABLE learning_progress_v5 (
          profile_id TEXT NOT NULL DEFAULT 'default',
          lesson_id TEXT NOT NULL,
          last_sentence_index INTEGER NOT NULL,
          position_ms INTEGER NOT NULL,
          subtitle_mode TEXT NOT NULL DEFAULT 'bilingual',
          playback_rate REAL NOT NULL DEFAULT 1.0,
          repeat_target INTEGER NOT NULL DEFAULT 0,
          display_mode TEXT NOT NULL DEFAULT 'fluid',
          updated_at TEXT NOT NULL,
          PRIMARY KEY (profile_id, lesson_id)
        )
      ''');
      await db.execute('''
        INSERT OR REPLACE INTO learning_progress_v5 (
          profile_id, lesson_id, last_sentence_index, position_ms,
          subtitle_mode, playback_rate, repeat_target, display_mode, updated_at
        )
        SELECT 'default', lesson_id, last_sentence_index, position_ms,
               subtitle_mode, playback_rate, repeat_target, display_mode,
               updated_at
        FROM learning_progress
      ''');
      await db.execute('DROP TABLE learning_progress');
      await db.execute('ALTER TABLE learning_progress_v5 RENAME TO learning_progress');
    }
  }

  /// Adds [column] to [table] only if it is not already present.
  ///
  /// Historical databases drifted from the recorded schema, so v1→v2 must be
  /// idempotent: an `ALTER TABLE ... ADD COLUMN` on an existing column throws
  /// and would abort [open] entirely.
  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  /// Migration hooks exposed for host-side regression tests (Task 1.4):
  /// `sqflite_common_ffi` drives the same SQLite engine on the host, so the
  /// v1→v2→v3 idempotent upgrades can be locked down without a device.
  @visibleForTesting
  static Future<void> debugCreateSchema(Database db, int version) =>
      _onCreate(db, version);

  @visibleForTesting
  static Future<void> debugUpgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) =>
      _onUpgrade(db, oldVersion, newVersion);

  @override
  Future<List<LessonWithProgress>> listLessons() async {
    final rows = await _db.rawQuery('''
      SELECT l.*, p.last_sentence_index, p.position_ms, p.updated_at,
             p.repeat_target, p.playback_rate, p.subtitle_mode, p.display_mode
      FROM lessons l
      LEFT JOIN learning_progress p
        ON l.id = p.lesson_id AND p.profile_id = ?
      ORDER BY COALESCE(p.updated_at, l.imported_at) DESC
    ''', [profileId]);
    return rows.map(_lessonWithProgressFromRow).toList();
  }

  @override
  Future<void> updateCoverPath(String lessonId, String coverPath) async {
    // Value update only — the column already exists, no schema change.
    await _db.update(
      'lessons',
      {'cover_path': coverPath},
      where: 'id = ?',
      whereArgs: [lessonId],
    );
  }

  @override
  Future<LessonWithSentences?> getLessonWithSentences(String lessonId) async {
    final lessonRows = await _db.query(
      'lessons',
      where: 'id = ?',
      whereArgs: [lessonId],
      limit: 1,
    );
    if (lessonRows.isEmpty) return null;

    final lessonDir = Directory(p.join(lessonsRoot, lessonId));
    final chunksFile = File(p.join(lessonDir.path, 'chunks.json'));
    if (await chunksFile.exists()) {
      try {
        final content = await chunksFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List && decoded.isNotEmpty) {
          final chunks = decoded.asMap().entries.map((e) {
            final m = e.value as Map<String, dynamic>;
            final rawCharStarts = m['charStarts'];
            List<int>? charStarts;
            if (rawCharStarts is List) {
              charStarts = rawCharStarts.map((c) => (c as num).toInt()).toList();
            }
            return Sentence(
              id: m['id'] as String? ?? 'c_${e.key}',
              index: m['index'] as int? ?? e.key,
              startMs: m['startMs'] as int? ?? (m['startTime'] as int? ?? 0),
              endMs: m['endMs'] as int? ?? (m['endTime'] as int? ?? 0),
              english: m['english'] as String? ?? (m['text'] as String? ?? ''),
              chinese: m['chinese'] as String? ?? (m['text'] as String? ?? ''),
              charStarts: charStarts,
            );
          }).toList();
          return LessonWithSentences(
            lesson: _lessonFromRow(lessonRows.first),
            sentences: chunks,
          );
        }
      } catch (_) {}
    }

    final sentenceRows = await _db.query(
      'sentences',
      where: 'lesson_id = ?',
      whereArgs: [lessonId],
      orderBy: 'idx ASC',
    );
    return LessonWithSentences(
      lesson: _lessonFromRow(lessonRows.first),
      sentences: sentenceRows.map(_sentenceFromRow).toList(),
    );
  }

  @override
  Future<List<Sentence>?> getAlternateSentences(String lessonId) async {
    final lessonDir = Directory(p.join(lessonsRoot, lessonId));
    final fluentFile = File(p.join(lessonDir.path, 'fluent.json'));
    if (!await fluentFile.exists()) return null;
    try {
      final content = await fluentFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) return null;
      return decoded.asMap().entries.map((e) {
        final m = e.value as Map<String, dynamic>;
        final rawCharStarts = m['charStarts'];
        List<int>? charStarts;
        if (rawCharStarts is List) {
          charStarts = rawCharStarts.map((c) => (c as num).toInt()).toList();
        }
        return Sentence(
          id: m['id'] as String? ?? 'alt_${e.key}',
          index: m['index'] as int? ?? e.key,
          startMs: m['startMs'] as int,
          endMs: m['endMs'] as int,
          english: m['english'] as String? ?? '',
          chinese: m['chinese'] as String? ?? '',
          charStarts: charStarts,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveProgress({
    required String lessonId,
    required int lastSentenceIndex,
    required int positionMs,
    int repeatTarget = 1,
    double playbackRate = 1.0,
    String subtitleMode = 'bilingual',
    String displayMode = 'fluid',
  }) async {
    await _db.insert('learning_progress', {
      'profile_id': profileId,
      'lesson_id': lessonId,
      'last_sentence_index': lastSentenceIndex,
      'position_ms': positionMs,
      'repeat_target': repeatTarget,
      'playback_rate': playbackRate,
      'subtitle_mode': subtitleMode,
      'display_mode': displayMode,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Lesson> importPackage(ParsedLessonPackage package) async {
    final manifest = package.manifest;
    final existing = await _db.query(
      'lessons',
      where: 'id = ?',
      whereArgs: [manifest.lessonId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      // Idempotent re-import: update sentences & lessons; PRESERVE learning_progress!
      await _db.delete(
        'sentences',
        where: 'lesson_id = ?',
        whereArgs: [manifest.lessonId],
      );
      await _db.delete(
        'lessons',
        where: 'id = ?',
        whereArgs: [manifest.lessonId],
      );
    }

    final dir = Directory(p.join(lessonsRoot, manifest.lessonId));
    await dir.create(recursive: true);

    final audioPath = p.join(dir.path, package.audioFileName);
    await File(audioPath).writeAsBytes(package.audioBytes, flush: true);

    String? coverPath;
    if (package.coverBytes != null && package.coverFileName != null) {
      coverPath = p.join(dir.path, package.coverFileName!);
      await File(coverPath).writeAsBytes(package.coverBytes!, flush: true);
    }

    for (final entry in package.extraFiles.entries) {
      final extraPath = p.join(dir.path, entry.key);
      await File(extraPath).writeAsBytes(entry.value, flush: true);
    }

    final importedAt = DateTime.now().toIso8601String();
    final lesson = Lesson(
      id: manifest.lessonId,
      title: manifest.title,
      language: manifest.language,
      durationMs: manifest.durationMs,
      sentenceCount: manifest.sentenceCount,
      audioPath: audioPath,
      coverPath: coverPath,
      video: manifest.video,
      series: manifest.series,
      importedAt: DateTime.parse(importedAt),
    );

    await _db.transaction((txn) async {
      await txn.insert('lessons', {
        'id': lesson.id,
        'title': lesson.title,
        'language': lesson.language,
        'duration_ms': lesson.durationMs,
        'sentence_count': lesson.sentenceCount,
        'audio_path': lesson.audioPath,
        'cover_path': lesson.coverPath,
        'video_json': lesson.video == null
            ? null
            : jsonEncode(lesson.video!.toJson()),
        'series': lesson.series,
        'imported_at': importedAt,
      });
      final batch = txn.batch();
      for (final s in package.sentences) {
        batch.insert('sentences', {
          'lesson_id': manifest.lessonId,
          'idx': s.index,
          'sentence_id': s.id,
          'start_ms': s.startMs,
          'end_ms': s.endMs,
          'english': s.english,
          'chinese': s.chinese,
        });
      }
      await batch.commit(noResult: true);
    });
    return lesson;
  }

  @override
  Future<void> deleteLesson(String lessonId) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'sentences',
        where: 'lesson_id = ?',
        whereArgs: [lessonId],
      );
      await txn.delete(
        'learning_progress',
        where: 'lesson_id = ?',
        whereArgs: [lessonId],
      );
      await txn.delete('lessons', where: 'id = ?', whereArgs: [lessonId]);
    });
    final dir = Directory(p.join(lessonsRoot, lessonId));
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (e) {
        // Media cleanup is best-effort; the library entry is already gone.
        debugPrint('[ListenLoop] failed to delete media dir $dir: $e');
      }
    }
  }

  @override
  Future<void> deleteMediaPreservingProgress(String lessonId) async {
    final dir = Directory(p.join(lessonsRoot, lessonId));
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (e) {
        debugPrint('[ListenLoop] failed to clean media dir $dir: $e');
      }
    }
    // 同时从 lessons 目录和数据库中标记媒体丢失或清空本地路径
    await _db.update(
      'lessons',
      {'audio_path': '', 'cover_path': ''},
      where: 'id = ?',
      whereArgs: [lessonId],
    );
  }

  @override
  Future<int> deleteLessons(List<String> lessonIds, {bool preserveProgress = true}) async {
    if (lessonIds.isEmpty) return 0;
    final placeholders = List.filled(lessonIds.length, '?').join(',');
    await _db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM sentences WHERE lesson_id IN ($placeholders)',
        lessonIds,
      );
      if (!preserveProgress) {
        await txn.rawDelete(
          'DELETE FROM learning_progress WHERE lesson_id IN ($placeholders)',
          lessonIds,
        );
      }
      await txn.rawDelete(
        'DELETE FROM lessons WHERE id IN ($placeholders)',
        lessonIds,
      );
    });

    for (final id in lessonIds) {
      final dir = Directory(p.join(lessonsRoot, id));
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } catch (e) {
          debugPrint('[ListenLoop] failed to delete dir $dir: $e');
        }
      }
    }
    return lessonIds.length;
  }

  @override
  Future<Map<String, GradeStorageStats>> getLessonsStorageStats() async {
    final rows = await _db.rawQuery('SELECT id, title, series FROM lessons');
    final Map<String, List<String>> gradeLessons = {
      '一年级': [],
      '二年级': [],
      '三年级': [],
      '四年级': [],
      '五年级': [],
      '六年级': [],
      '其他': [],
    };

    for (final r in rows) {
      final id = r['id'] as String;
      final title = (r['title'] as String?) ?? '';
      final series = (r['series'] as String?) ?? '';
      final s = '$series $title';

      if (s.contains('一年级') || id.startsWith('g1')) {
        gradeLessons['一年级']!.add(id);
      } else if (s.contains('二年级') || id.startsWith('g2') || id.contains('xiaokedou') || id.contains('woshishenme') || id.contains('zhiwumama')) {
        gradeLessons['二年级']!.add(id);
      } else if (s.contains('三年级') || id.startsWith('g3') || id.contains('daqingshu') || id.contains('huadexuexiao') || id.contains('jinsebazhang')) {
        gradeLessons['三年级']!.add(id);
      } else if (s.contains('四年级') || id.startsWith('g4')) {
        gradeLessons['四年级']!.add(id);
      } else if (s.contains('五年级') || id.startsWith('g5')) {
        gradeLessons['五年级']!.add(id);
      } else if (s.contains('六年级') || id.startsWith('g6')) {
        gradeLessons['六年级']!.add(id);
      } else {
        gradeLessons['其他']!.add(id);
      }
    }

    final Map<String, GradeStorageStats> result = {};
    for (final entry in gradeLessons.entries) {
      final gradeLabel = entry.key;
      final ids = entry.value;
      int totalBytes = 0;
      for (final id in ids) {
        final d = Directory(p.join(lessonsRoot, id));
        if (await d.exists()) {
          try {
            await for (final entity in d.list(recursive: true, followLinks: false)) {
              if (entity is File) {
                totalBytes += await entity.length();
              }
            }
          } catch (_) {}
        }
      }
      result[gradeLabel] = GradeStorageStats(
        gradeLabel: gradeLabel,
        lessonCount: ids.length,
        totalBytes: totalBytes,
        lessonIds: ids,
      );
    }
    return result;
  }

  // ------------------------------------------------------------- row mappers

  LessonWithProgress _lessonWithProgressFromRow(Map<String, Object?> row) {
    final progressUpdatedAt = row['updated_at'] as String?;
    return LessonWithProgress(
      lesson: _lessonFromRow(row),
      progress: progressUpdatedAt == null
          ? null
          : LearningProgress(
              lessonId: row['id'] as String,
              lastSentenceIndex: row['last_sentence_index'] as int,
              positionMs: row['position_ms'] as int,
              repeatTarget: (row['repeat_target'] as int?) ?? 1,
              playbackRate: (row['playback_rate'] as double?) ?? 1.0,
              subtitleMode: (row['subtitle_mode'] as String?) ?? 'bilingual',
              displayMode: (row['display_mode'] as String?) ?? 'fluid',
              updatedAt: DateTime.parse(progressUpdatedAt),
            ),
    );
  }

  Lesson _lessonFromRow(Map<String, Object?> row) => Lesson(
    id: row['id'] as String,
    title: row['title'] as String,
    language: row['language'] as String,
    durationMs: row['duration_ms'] as int,
    sentenceCount: row['sentence_count'] as int,
    audioPath: row['audio_path'] as String,
    coverPath: row['cover_path'] as String?,
    video: _videoFromColumn(row['video_json']),
    series: row['series'] as String?,
    importedAt: DateTime.parse(row['imported_at'] as String),
  );

  /// Decodes the `video_json` column, tolerating absent or corrupt payloads.
  static VideoSource? _videoFromColumn(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return VideoSource.tryFromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('[ListenLoop] ignoring bad video_json: $e');
      return null;
    }
  }

  Sentence _sentenceFromRow(Map<String, Object?> row) => Sentence(
    id: (row['sentence_id'] as String?) ??
        '${row['lesson_id']}-${row['idx']}',
    index: row['idx'] as int,
    startMs: row['start_ms'] as int,
    endMs: row['end_ms'] as int,
    english: row['english'] as String,
    chinese: row['chinese'] as String,
  );
}
