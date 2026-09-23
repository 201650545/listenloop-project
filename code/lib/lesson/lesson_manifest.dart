import '../models/video_source.dart';
import 'lesson_package_exception.dart';

/// Typed, validated view of `manifest.json` inside a `.lllesson` package
/// (spec V0.2 §13; optional `video` source added V0.3 §3A).
class LessonManifest {
  const LessonManifest({
    required this.formatVersion,
    required this.lessonId,
    required this.title,
    required this.language,
    required this.durationMs,
    required this.sentenceCount,
    required this.audioFile,
    required this.sentenceFile,
    this.coverFile,
    this.video,
  });

  /// The only format this build understands.
  static const int supportedFormatVersion = 1;

  /// Allowed characters for [lessonId] — it becomes a directory name in app
  /// storage, so path separators and traversal sequences must never appear.
  static final RegExp _lessonIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$',
  );

  final int formatVersion;
  final String lessonId;
  final String title;
  final String language;
  final int durationMs;
  final int sentenceCount;
  final String audioFile;
  final String sentenceFile;
  final String? coverFile;

  /// Optional online video the sentence timeline is shown against (V0.3 §3A).
  /// Null for audio-only lessons, which remain fully supported.
  final VideoSource? video;

  /// Parses and validates a decoded manifest map.
  ///
  /// Throws [LessonPackageException] with [LessonPackageError.badManifest]
  /// (or [LessonPackageError.unsupportedVersion]) on any problem.
  factory LessonManifest.fromJson(Map<String, dynamic> json) {
    final version = _int(json, 'formatVersion');
    if (version != supportedFormatVersion) {
      throw LessonPackageException(
        LessonPackageError.unsupportedVersion,
        'formatVersion is $version, expected $supportedFormatVersion',
      );
    }

    final lessonId = _string(json, 'lessonId');
    if (!_lessonIdPattern.hasMatch(lessonId)) {
      throw LessonPackageException(
        LessonPackageError.badManifest,
        'lessonId "$lessonId" contains characters outside [A-Za-z0-9._-]',
      );
    }

    final audioFile = _string(json, 'audioFile');
    final sentenceFile = _string(json, 'sentenceFile');
    final sentenceCount = _int(json, 'sentenceCount');
    if (sentenceCount <= 0) {
      throw LessonPackageException(
        LessonPackageError.badManifest,
        'sentenceCount must be > 0, got $sentenceCount',
      );
    }
    final durationMs = _int(json, 'durationMs');
    if (durationMs < 0) {
      throw LessonPackageException(
        LessonPackageError.badManifest,
        'durationMs must be >= 0, got $durationMs',
      );
    }

    final cover = json['coverFile'];
    if (cover != null && cover is! String) {
      throw LessonPackageException(
        LessonPackageError.badManifest,
        'coverFile must be a string when present',
      );
    }

    return LessonManifest(
      formatVersion: version,
      lessonId: lessonId,
      title: _string(json, 'title'),
      language: _string(json, 'language'),
      durationMs: durationMs,
      sentenceCount: sentenceCount,
      audioFile: audioFile,
      sentenceFile: sentenceFile,
      coverFile: cover as String?,
      video: _video(json['video']),
    );
  }

  /// Parses the optional `video` block.
  ///
  /// An unrecognised or unsupported block is dropped (returns null) rather
  /// than failing the whole import: video is an enhancement, and the lesson
  /// must stay usable as audio-only on any device.
  static VideoSource? _video(Object? raw) {
    if (raw is! Map) return null;
    final provider = raw['provider'];
    final bvid = raw['bvid'];
    final page = raw['page'];
    if (provider is! String ||
        !VideoSource.supportedProviders.contains(provider)) {
      return null;
    }
    if (bvid is! String || bvid.isEmpty) return null;
    if (page is! int || page < 1) return null;
    final cid = raw['cid'];
    final offsetMs = raw['offsetMs'];
    return VideoSource(
      provider: provider,
      bvid: bvid,
      page: page,
      cid: cid is int ? cid : null,
      offsetMs: offsetMs is int ? offsetMs : 0,
    );
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw LessonPackageException(
      LessonPackageError.badManifest,
      'field "$key" must be a non-empty string, got $value',
    );
  }

  static int _int(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw LessonPackageException(
      LessonPackageError.badManifest,
      'field "$key" must be an integer, got $value',
    );
  }
}
