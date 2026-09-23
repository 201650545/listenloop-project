import '../lesson/lesson_package_reader.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import 'lesson_repository.dart';

/// In-memory [LessonRepository].
///
/// Two uses: the fake in widget tests, and a graceful fallback in `main()`
/// if SQLite cannot open (the app stays usable with the caveat that lessons
/// do not survive a restart — degraded, but never crashing at launch).
class InMemoryLessonRepository implements LessonRepository {
  final Map<String, Lesson> _lessons = {};
  final Map<String, List<Sentence>> _sentences = {};
  final Map<String, LearningProgress> _progress = {};

  @override
  Future<List<LessonWithProgress>> listLessons() async {
    final ids = _lessons.keys.toList()
      ..sort((a, b) => _touchedAt(b).compareTo(_touchedAt(a)));
    return [
      for (final id in ids)
        LessonWithProgress(lesson: _lessons[id]!, progress: _progress[id]),
    ];
  }

  @override
  Future<void> updateCoverPath(String lessonId, String coverPath) async {
    final lesson = _lessons[lessonId];
    if (lesson == null) return;
    _lessons[lessonId] = lesson.copyWith(coverPath: coverPath);
  }

  DateTime _touchedAt(String id) =>
      _progress[id]?.updatedAt ?? _lessons[id]!.importedAt;

  @override
  Future<LessonWithSentences?> getLessonWithSentences(String lessonId) async {
    final lesson = _lessons[lessonId];
    if (lesson == null) return null;
    return LessonWithSentences(
      lesson: lesson,
      sentences: List.unmodifiable(_sentences[lessonId] ?? const <Sentence>[]),
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
    _progress[lessonId] = LearningProgress(
      lessonId: lessonId,
      lastSentenceIndex: lastSentenceIndex,
      positionMs: positionMs,
      repeatTarget: repeatTarget,
      playbackRate: playbackRate,
      subtitleMode: subtitleMode,
      displayMode: displayMode,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<Lesson> importPackage(ParsedLessonPackage package) async {
    final id = package.manifest.lessonId;
    final lesson = Lesson(
      id: id,
      title: package.manifest.title,
      language: package.manifest.language,
      durationMs: package.manifest.durationMs,
      sentenceCount: package.manifest.sentenceCount,
      audioPath: 'memory://$id/${package.audioFileName}',
      importedAt: DateTime.now(),
    );
    _lessons[id] = lesson;
    _sentences[id] = List<Sentence>.unmodifiable(package.sentences);
    _progress.remove(id);
    return lesson;
  }

  @override
  Future<void> deleteLesson(String lessonId) async {
    _lessons.remove(lessonId);
    _sentences.remove(lessonId);
    _progress.remove(lessonId);
  }
}
