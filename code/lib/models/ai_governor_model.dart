/// Category of quiz questions in the AI Governor 3-Minute Check.
enum QuizCategory {
  /// Core comprehension of the sentence meaning.
  comprehension,

  /// Connected speech, liaison, elision, or subtle pronunciation.
  phonetics,

  /// Contextual nuance, tone, or pragmatic usage.
  context;

  String get label => switch (this) {
    QuizCategory.comprehension => '语义理解',
    QuizCategory.phonetics => '连读辨音',
    QuizCategory.context => '语境语感',
  };
}

/// A single quiz question in the 3-Minute Check.
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.lessonId,
    required this.sentenceIndex,
    required this.category,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.targetWord,
  });

  final String id;
  final String lessonId;
  final int sentenceIndex;
  final QuizCategory category;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String? targetWord;

  Map<String, dynamic> toJson() => {
    'id': id,
    'lessonId': lessonId,
    'sentenceIndex': sentenceIndex,
    'category': category.name,
    'question': question,
    'options': options,
    'correctIndex': correctIndex,
    'explanation': explanation,
    'targetWord': targetWord,
  };

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
    id: json['id'] as String,
    lessonId: json['lessonId'] as String,
    sentenceIndex: json['sentenceIndex'] as int,
    category: QuizCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => QuizCategory.comprehension,
    ),
    question: json['question'] as String,
    options: (json['options'] as List).map((e) => e.toString()).toList(),
    correctIndex: json['correctIndex'] as int,
    explanation: json['explanation'] as String,
    targetWord: json['targetWord'] as String?,
  );
}

/// Record of a user's listening weakness / mistake during quizzes.
class WeaknessRecord {
  const WeaknessRecord({
    required this.id,
    required this.lessonId,
    required this.lessonTitle,
    required this.sentenceIndex,
    required this.sentenceText,
    required this.chineseTranslation,
    required this.startMs,
    required this.endMs,
    required this.reason,
    required this.timestamp,
    this.resolved = false,
  });

  final String id;
  final String lessonId;
  final String lessonTitle;
  final int sentenceIndex;
  final String sentenceText;
  final String chineseTranslation;
  final int startMs;
  final int endMs;
  final String reason;
  final DateTime timestamp;
  final bool resolved;

  WeaknessRecord copyWith({bool? resolved}) => WeaknessRecord(
    id: id,
    lessonId: lessonId,
    lessonTitle: lessonTitle,
    sentenceIndex: sentenceIndex,
    sentenceText: sentenceText,
    chineseTranslation: chineseTranslation,
    startMs: startMs,
    endMs: endMs,
    reason: reason,
    timestamp: timestamp,
    resolved: resolved ?? this.resolved,
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
    'reason': reason,
    'timestamp': timestamp.toIso8601String(),
    'resolved': resolved,
  };

  factory WeaknessRecord.fromJson(Map<String, dynamic> json) => WeaknessRecord(
    id: json['id'] as String,
    lessonId: json['lessonId'] as String,
    lessonTitle: json['lessonTitle'] as String? ?? '精听课程',
    sentenceIndex: json['sentenceIndex'] as int,
    sentenceText: json['sentenceText'] as String,
    chineseTranslation: json['chineseTranslation'] as String? ?? '',
    startMs: json['startMs'] as int? ?? 0,
    endMs: json['endMs'] as int? ?? 0,
    reason: json['reason'] as String,
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    resolved: json['resolved'] as bool? ?? false,
  );
}

/// Message in the AI Tutor discussion.
class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.relatedSentenceIndex,
    this.isLoading = false,
    this.isError = false,
  });

  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;
  final int? relatedSentenceIndex;
  final bool isLoading;
  final bool isError;

  bool get isUser => role == 'user';

  AiChatMessage copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? timestamp,
    int? relatedSentenceIndex,
    bool? isLoading,
    bool? isError,
  }) => AiChatMessage(
    id: id ?? this.id,
    role: role ?? this.role,
    content: content ?? this.content,
    timestamp: timestamp ?? this.timestamp,
    relatedSentenceIndex: relatedSentenceIndex ?? this.relatedSentenceIndex,
    isLoading: isLoading ?? this.isLoading,
    isError: isError ?? this.isError,
  );
}

