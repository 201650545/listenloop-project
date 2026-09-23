import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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

  /// Removes the lesson, its sentences, its progress and its media files.
  Future<void> deleteLesson(String lessonId);
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
  SqfliteLessonRepository._(this._db, this.lessonsRoot);

  final Database _db;

  /// Directory that holds one sub-directory per imported lesson.
  final String lessonsRoot;

  /// Opens (creating if needed) the database and the lessons root directory.
  static Future<SqfliteLessonRepository> open() async {
    final dbPath = p.join(await getDatabasesPath(), 'listenloop.db');
    final docs = await getApplicationDocumentsDirectory();
    final root = p.join(docs.path, 'lessons');
    await Directory(root).create(recursive: true);
    final db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return SqfliteLessonRepository._(db, root);
  }

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
        lesson_id TEXT PRIMARY KEY,
        last_sentence_index INTEGER NOT NULL,
        position_ms INTEGER NOT NULL,
        subtitle_mode TEXT NOT NULL DEFAULT 'bilingual',
        playback_rate REAL NOT NULL DEFAULT 1.0,
        repeat_target INTEGER NOT NULL DEFAULT 0,
        display_mode TEXT NOT NULL DEFAULT 'fluid',
        updated_at TEXT NOT NULL
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

  @override
  Future<List<LessonWithProgress>> listLessons() async {
    final rows = await _db.rawQuery('''
      SELECT l.*, p.last_sentence_index, p.position_ms, p.updated_at,
             p.repeat_target, p.playback_rate, p.subtitle_mode, p.display_mode
      FROM lessons l
      LEFT JOIN learning_progress p ON l.id = p.lesson_id
      ORDER BY COALESCE(p.updated_at, l.imported_at) DESC
    ''');
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
      // Idempotent re-import: wipe rows first; files are overwritten below.
      await _db.delete(
        'sentences',
        where: 'lesson_id = ?',
        whereArgs: [manifest.lessonId],
      );
      await _db.delete(
        'learning_progress',
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
