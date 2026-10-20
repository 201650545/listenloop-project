/// Meaning Recall 交互模型（15 号 Phase A 第一优先）。
///
/// 科学依据：Swain 输出假设 —— 听写是 audio → orthography（听力诊断器），
/// Meaning Recall 是 meaning → language（真正的 productive output）。
library;

/// 一次 Meaning Recall 尝试的完整记录。
class MeaningRecallAttempt {
  const MeaningRecallAttempt({
    required this.sentenceId,
    required this.originalEnglish,
    required this.chineseMeaning,
    required this.userExpression,
    this.aiFeedback,
  });

  final String sentenceId;
  final String originalEnglish;
  final String chineseMeaning;
  final String userExpression;
  final String? aiFeedback;
}

/// 摘自 R4 评审：组件结果 ≠ FSRS 评分。
/// Meaning Recall 交互产生事实，FSRS 评分由 RatingPolicy 决定。
class InteractionResult {
  const InteractionResult({
    required this.completed,
    this.correct,
    this.usedHint = false,
    this.responseTime,
  });

  final bool completed;
  final bool? correct;
  final bool usedHint;
  final Duration? responseTime;
}
