import 'dart:math' as math;

/// Rating chosen by user during Anki Spaced Repetition review.
enum AnkiRating {
  /// Forgot / unable to recall (< 10 minutes interval, resets repetition).
  again,

  /// Recalled with significant effort (1 day interval).
  hard,

  /// Recalled correctly with moderate effort (standard SM-2 interval progression).
  good,

  /// Recalled effortlessly (extended interval progression).
  easy;

  String get label => switch (this) {
    AnkiRating.again => '生疏',
    AnkiRating.hard => '困难',
    AnkiRating.good => '良好',
    AnkiRating.easy => '轻松',
  };

  String get intervalDescription => switch (this) {
    AnkiRating.again => '< 10 分钟',
    AnkiRating.hard => '1 天',
    AnkiRating.good => '3 天',
    AnkiRating.easy => '7 天',
  };
}

/// An Anki flashcard generated with AI for deep listening and spaced repetition.
class AnkiCard {
  const AnkiCard({
    required this.id,
    required this.lessonId,
    required this.lessonTitle,
    required this.sentenceIndex,
    required this.sentenceText,
    required this.chineseTranslation,
    required this.startMs,
    required this.endMs,
    this.audioPath,
    required this.clozeWord,
    required this.phoneticClue,
    required this.aiExplanation,
    this.repetition = 0,
    this.intervalDays = 0.0,
    this.easeFactor = 2.5,
    required this.dueDate,
    this.lastReviewed,
    this.isMastered = false,
  });

  final String id;
  final String lessonId;
  final String lessonTitle;
  final int sentenceIndex;
  final String sentenceText;
  final String chineseTranslation;
  final int startMs;
  final int endMs;
  final String? audioPath;

  /// The target keyword/chunk to blank out in Cloze mode.
  final String clozeWord;

  /// AI-generated phonetic guidance (connected speech, weak form, etc.).
  final String phoneticClue;

  /// In-depth AI explanation of the sentence nuances and grammar.
  final String aiExplanation;

  /// Consecutive successful reviews under SM-2.
  final int repetition;

  /// Current interval in days until the next review.
  final double intervalDays;

  /// Ease factor for SM-2 (default 2.5, clamped between 1.3 and 3.0).
  final double easeFactor;

  /// When this card is next scheduled for review.
  final DateTime dueDate;

  /// When this card was last reviewed.
  final DateTime? lastReviewed;

  /// Flag indicating card has reached long-term memory mastery (interval >= 21d).
  final bool isMastered;

  bool get isDue => dueDate.isBefore(DateTime.now());

  /// Returns sentence text with [clozeWord] replaced with blank brackets `[ ___ ]`.
  String get clozeSentence {
    if (clozeWord.trim().isEmpty) return sentenceText;
    final regex = RegExp(RegExp.escape(clozeWord), caseSensitive: false);
    if (!regex.hasMatch(sentenceText)) return sentenceText;
    return sentenceText.replaceAll(regex, '【 ______ 】');
  }

  /// Evaluates this card using the standard SuperMemo-2 (SM-2) algorithm.
  AnkiCard applyRating(AnkiRating rating, {DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    int newRepetition = repetition;
    double newInterval = intervalDays;
    double newEaseFactor = easeFactor;

    switch (rating) {
      case AnkiRating.again:
        newRepetition = 0;
        newInterval = 0.0;
        newEaseFactor = math.max(1.3, easeFactor - 0.2);
        break;
      case AnkiRating.hard:
        newInterval = intervalDays <= 0 ? 1.0 : (intervalDays * 1.2);
        newEaseFactor = math.max(1.3, easeFactor - 0.15);
        break;
      case AnkiRating.good:
        if (repetition == 0) {
          newInterval = 1.0;
        } else if (repetition == 1) {
          newInterval = 3.0;
        } else {
          newInterval = intervalDays * easeFactor;
        }
        newRepetition++;
        break;
      case AnkiRating.easy:
        if (repetition == 0) {
          newInterval = 3.0;
        } else if (repetition == 1) {
          newInterval = 7.0;
        } else {
          newInterval = intervalDays * easeFactor * 1.3;
        }
        newRepetition++;
        newEaseFactor = math.min(3.0, easeFactor + 0.15);
        break;
    }

    final nextDue = rating == AnkiRating.again
        ? now.add(const Duration(minutes: 10))
        : now.add(Duration(hours: (newInterval * 24).round()));

    return copyWith(
      repetition: newRepetition,
      intervalDays: newInterval,
      easeFactor: newEaseFactor,
      dueDate: nextDue,
      lastReviewed: now,
      isMastered: newInterval >= 21.0,
    );
  }

  AnkiCard copyWith({
    String? id,
    String? lessonId,
    String? lessonTitle,
    int? sentenceIndex,
    String? sentenceText,
    String? chineseTranslation,
    int? startMs,
    int? endMs,
    String? audioPath,
    String? clozeWord,
    String? phoneticClue,
    String? aiExplanation,
    int? repetition,
    double? intervalDays,
    double? easeFactor,
    DateTime? dueDate,
    DateTime? lastReviewed,
    bool? isMastered,
  }) => AnkiCard(
    id: id ?? this.id,
    lessonId: lessonId ?? this.lessonId,
    lessonTitle: lessonTitle ?? this.lessonTitle,
    sentenceIndex: sentenceIndex ?? this.sentenceIndex,
    sentenceText: sentenceText ?? this.sentenceText,
    chineseTranslation: chineseTranslation ?? this.chineseTranslation,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    audioPath: audioPath ?? this.audioPath,
    clozeWord: clozeWord ?? this.clozeWord,
    phoneticClue: phoneticClue ?? this.phoneticClue,
    aiExplanation: aiExplanation ?? this.aiExplanation,
    repetition: repetition ?? this.repetition,
    intervalDays: intervalDays ?? this.intervalDays,
    easeFactor: easeFactor ?? this.easeFactor,
    dueDate: dueDate ?? this.dueDate,
    lastReviewed: lastReviewed ?? this.lastReviewed,
    isMastered: isMastered ?? this.isMastered,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'lessonId': lessonId,
    'lessonTitle': lessonTitle,
    'sentenceIndex': sentenceIndex,
    'sentenceText': sentenceText,
    'chineseTranslation': chineseTranslation,
    'startMs': startMs,
    'endMs': endMs,
    'audioPath': audioPath,
    'clozeWord': clozeWord,
    'phoneticClue': phoneticClue,
    'aiExplanation': aiExplanation,
    'repetition': repetition,
    'intervalDays': intervalDays,
    'easeFactor': easeFactor,
    'dueDate': dueDate.toIso8601String(),
    'lastReviewed': lastReviewed?.toIso8601String(),
    'isMastered': isMastered,
  };

  factory AnkiCard.fromJson(Map<String, dynamic> json) => AnkiCard(
    id: json['id'] as String,
    lessonId: json['lessonId'] as String,
    lessonTitle: json['lessonTitle'] as String? ?? '精听课程',
    sentenceIndex: json['sentenceIndex'] as int,
    sentenceText: json['sentenceText'] as String,
    chineseTranslation: json['chineseTranslation'] as String? ?? '',
    startMs: json['startMs'] as int? ?? 0,
    endMs: json['endMs'] as int? ?? 0,
    audioPath: json['audioPath'] as String?,
    clozeWord: json['clozeWord'] as String? ?? '',
    phoneticClue: json['phoneticClue'] as String? ?? '',
    aiExplanation: json['aiExplanation'] as String? ?? '',
    repetition: json['repetition'] as int? ?? 0,
    intervalDays: (json['intervalDays'] as num?)?.toDouble() ?? 0.0,
    easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
    dueDate: DateTime.tryParse(json['dueDate'] as String? ?? '') ?? DateTime.now(),
    lastReviewed: json['lastReviewed'] != null
        ? DateTime.tryParse(json['lastReviewed'] as String)
        : null,
    isMastered: json['isMastered'] as bool? ?? false,
  );
}
