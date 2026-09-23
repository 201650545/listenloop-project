import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/sentence.dart';
import 'lesson_manifest.dart';
import 'lesson_package_exception.dart';

/// A `.lllesson` package that passed validation, with all payload bytes
/// decoded and ready to be copied into app storage.
class ParsedLessonPackage {
  const ParsedLessonPackage({
    required this.manifest,
    required this.sentences,
    required this.audioBytes,
    required this.audioFileName,
    this.coverBytes,
    this.coverFileName,
  });

  final LessonManifest manifest;
  final List<Sentence> sentences;
  final Uint8List audioBytes;
  final String audioFileName;

  /// Cover image bytes, or null when the package has no cover.
  final Uint8List? coverBytes;

  /// Base name of the cover file inside the package, or null.
  final String? coverFileName;
}

/// Opens and validates `.lllesson` packages (spec V0.2 §12-14).
///
/// A package is a ZIP container holding at least:
///  * `manifest.json` — [LessonManifest];
///  * the declared sentence file (JSON array of sentence objects);
///  * the declared audio file.
///
/// A cover image is optional. Every failure surfaces as a
/// [LessonPackageException] with a stable [LessonPackageError] code — never a
/// raw decode crash — so the import UI can show a friendly message.
class LessonPackageReader {
  LessonPackageReader._();

  /// Reads and fully validates the package at [filePath].
  static Future<ParsedLessonPackage> read(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const LessonPackageException(
        LessonPackageError.notFound,
        'picked file does not exist',
      );
    }

    final List<int> raw;
    try {
      raw = await file.readAsBytes();
    } catch (e) {
      throw LessonPackageException(LessonPackageError.unreadable, '$e');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(raw);
    } catch (e) {
      throw LessonPackageException(
        LessonPackageError.unreadable,
        'not a valid zip container: $e',
      );
    }

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const LessonPackageException(
        LessonPackageError.missingManifest,
        'manifest.json not found in package',
      );
    }

    final Map<String, dynamic> manifestJson;
    try {
      final decoded = jsonDecode(utf8.decode(_bytes(manifestFile)));
      if (decoded is! Map<String, dynamic>) {
        throw const LessonPackageException(
          LessonPackageError.badManifest,
          'manifest.json must be a JSON object',
        );
      }
      manifestJson = decoded;
    } on LessonPackageException {
      rethrow;
    } catch (e) {
      throw LessonPackageException(
        LessonPackageError.badManifest,
        'manifest.json is not valid JSON: $e',
      );
    }

    final manifest = LessonManifest.fromJson(manifestJson);

    final sentenceFile = archive.findFile(manifest.sentenceFile);
    if (sentenceFile == null) {
      throw LessonPackageException(
        LessonPackageError.missingSentences,
        'sentence file "${manifest.sentenceFile}" not found in package',
      );
    }
    final sentences = _parseSentences(sentenceFile);

    if (sentences.length != manifest.sentenceCount) {
      throw LessonPackageException(
        LessonPackageError.sentenceCountMismatch,
        'manifest declares ${manifest.sentenceCount} sentences but '
        '${sentences.length} were parsed',
      );
    }

    final audioFile = archive.findFile(manifest.audioFile);
    if (audioFile == null) {
      throw LessonPackageException(
        LessonPackageError.missingAudio,
        'audio file "${manifest.audioFile}" not found in package',
      );
    }

    Uint8List? coverBytes;
    String? coverFileName;
    if (manifest.coverFile != null) {
      final coverFile = archive.findFile(manifest.coverFile!);
      if (coverFile != null) {
        coverBytes = Uint8List.fromList(_bytes(coverFile));
        coverFileName = _baseName(manifest.coverFile!);
      }
      // Declared but absent cover is tolerated — the cover is decorative.
    }

    return ParsedLessonPackage(
      manifest: manifest,
      sentences: sentences,
      audioBytes: Uint8List.fromList(_bytes(audioFile)),
      audioFileName: _baseName(manifest.audioFile),
      coverBytes: coverBytes,
      coverFileName: coverFileName,
    );
  }

  // ------------------------------------------------------------- internals --

  static List<Sentence> _parseSentences(ArchiveFile sentenceFile) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(_bytes(sentenceFile)));
    } catch (e) {
      throw LessonPackageException(
        LessonPackageError.badSentences,
        'sentence file is not valid JSON: $e',
      );
    }
    if (decoded is! List) {
      throw const LessonPackageException(
        LessonPackageError.badSentences,
        'sentence file must be a JSON array',
      );
    }
    if (decoded.isEmpty) {
      throw const LessonPackageException(
        LessonPackageError.emptySentences,
        'sentence file contains no sentences',
      );
    }

    final parsed = <Sentence>[];
    for (var i = 0; i < decoded.length; i++) {
      final entry = decoded[i];
      if (entry is! Map<String, dynamic>) {
        throw LessonPackageException(
          LessonPackageError.badSentences,
          'sentence #$i must be a JSON object',
        );
      }
      parsed.add(_sentenceFromJson(entry, i));
    }

    // Indexes must be exactly 0..n-1 in order so playback navigation is
    // well-defined.
    for (var i = 0; i < parsed.length; i++) {
      if (parsed[i].index != i) {
        throw LessonPackageException(
          LessonPackageError.badSentences,
          'sentence #$i declares index ${parsed[i].index}; indexes must be '
          '0..n-1 in order',
        );
      }
    }
    return parsed;
  }

  static Sentence _sentenceFromJson(Map<String, dynamic> json, int position) {
    int? intField(String key) {
      final v = json[key];
      if (v is int) return v;
      return null;
    }

    String? stringField(String key) {
      final v = json[key];
      if (v is String) return v;
      return null;
    }

    final id = stringField('id');
    final index = intField('index');
    final startMs = intField('startMs');
    final endMs = intField('endMs');
    final english = stringField('english');
    final chinese = stringField('chinese');

    if (id == null ||
        id.isEmpty ||
        index == null ||
        startMs == null ||
        startMs < 0 ||
        endMs == null ||
        endMs <= startMs ||
        english == null ||
        chinese == null) {
      throw LessonPackageException(
        LessonPackageError.badSentences,
        'sentence #$position: missing or invalid fields (id, index, '
        'startMs, endMs, english, chinese)',
      );
    }

    return Sentence(
      id: id,
      index: index,
      startMs: startMs,
      endMs: endMs,
      english: english,
      chinese: chinese,
    );
  }

  /// Strips any directory components so a hostile manifest cannot point
  /// outside the lesson's storage directory.
  static String _baseName(String entryName) {
    final normalized = entryName.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  static List<int> _bytes(ArchiveFile file) {
    final content = file.content;
    if (content is List<int>) return content;
    throw LessonPackageException(
      LessonPackageError.unreadable,
      'entry "${file.name}" could not be decoded',
    );
  }
}
