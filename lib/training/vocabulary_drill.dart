/// 学习组件的**本地判定** —— v1 全部离线，不调用任何模型。
///
/// 设计依据：`docs/02_工程架构与系统设计/10_生词本与Anki记忆卡设计.md` §十四。
/// v1 刻意不做 AI 出题与开放答案评判；这里只有"能不能对得上"的客观判定，
/// 以及**诚实的自评**（原声回听这类无法客观测量的步骤，就明说是自评）。
library;

import '../models/vocabulary_model.dart';
import 'dictation_engine.dart';

/// 判定给用户的短提示。文案由 l10n 映射，训练层不做本地化。
enum DrillHint {
  /// 完全正确。
  exact,

  /// 只差拼写 —— 听清了但没记准词形。
  spelling,

  /// 写成了别的词 —— 听辨或词义问题。
  wrongWord,

  /// 什么都没写。
  blank,

  /// 写对了一部分。
  partial,

  /// 听写对齐不可靠，只能给整体正误。
  alignment;

  static DrillHint parse(String? raw) => DrillHint.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => DrillHint.wrongWord,
  );
}

/// 一次组件执行的结果。
class DrillOutcome {
  const DrillOutcome({
    required this.passed,
    required this.accuracy,
    required this.hint,
    this.detail,
  });

  /// 是否通过（写进 `VocabularyDrillLog.passed`）。
  final bool passed;

  /// 词级准确率 0..1。自评类步骤固定为 1 或 0，不假装是测量值。
  final double accuracy;

  final DrillHint hint;

  /// 用户实际输入（供复盘与落盘）。
  final String? detail;

  @override
  String toString() =>
      'DrillOutcome(${passed ? 'pass' : 'fail'}, ${accuracy.toStringAsFixed(2)}, ${hint.name})';
}

/// Cloze 题面：把目标词从原句里挖空。
class ClozePrompt {
  const ClozePrompt({
    required this.before,
    required this.target,
    required this.after,
  });

  final String before;
  final String target;
  final String after;

  /// 挖空后的句子：下划线长度与目标词一致，给一点"还能想起来"的视觉线索。
  String get blanked {
    final underscores = '_' * target.length;
    return '$before$underscores$after';
  }

  /// 完整原句（揭晓答案时用）。
  String get revealed => '$before$target$after';

  @override
  String toString() {
    final shown = target.isEmpty ? '∅' : target;
    return 'ClozePrompt("$before[$shown]$after")';
  }
}

/// 组件判定器。
abstract final class VocabularyDrillJudge {
  /// 整句听写重试的通过线（词级准确率）。
  ///
  /// 定 0.85 而不是 1.0：重听写的目的是"这次听清了吗"，不是"一字不差"。
  /// 把线拉到满分会让弱读吞掉的功能词把整句判死，反而打击人。
  static const double sentencePassAccuracy = 0.85;

  /// 从原句切出挖空题面。区间非法时返回 null（调用方退回不显示 Cloze）。
  static ClozePrompt? buildCloze({
    required String sentenceText,
    required int charStart,
    required int charEnd,
  }) {
    if (sentenceText.isEmpty) return null;
    if (charStart < 0 || charEnd > sentenceText.length || charEnd <= charStart) {
      return null;
    }
    return ClozePrompt(
      before: sentenceText.substring(0, charStart),
      target: sentenceText.substring(charStart, charEnd),
      after: sentenceText.substring(charEnd),
    );
  }

  /// Cloze：只判目标词本身。
  ///
  /// 「差一个字母」与「写成别的词」是两种不同的问题，提示必须分开 ——
  /// 前者是词形没记准，后者是没听出来（见 09 的两层错误结构）。
  static DrillOutcome judgeCloze({
    required String target,
    required String answer,
  }) {
    final trimmed = answer.trim();
    if (trimmed.isEmpty) {
      return const DrillOutcome(
        passed: false,
        accuracy: 0,
        hint: DrillHint.blank,
      );
    }

    if (normalizeTerm(trimmed) == normalizeTerm(target)) {
      return DrillOutcome(
        passed: true,
        accuracy: 1,
        hint: DrillHint.exact,
        detail: trimmed,
      );
    }

    final result = DictationEngine.compare(expected: target, actual: trimmed);
    final errors = result.ops.where((op) => op.isError).toList();
    final spellingOnly =
        errors.isNotEmpty &&
        errors.every((op) => op.type == DictationDiffType.spelling);

    return DrillOutcome(
      passed: false,
      accuracy: result.accuracy,
      hint: spellingOnly ? DrillHint.spelling : DrillHint.wrongWord,
      detail: trimmed,
    );
  }

  /// 整句听写重试。
  static DrillOutcome judgeSentenceDictation({
    required String expected,
    required String actual,
    double passAccuracy = sentencePassAccuracy,
  }) {
    final trimmed = actual.trim();
    if (trimmed.isEmpty) {
      return const DrillOutcome(
        passed: false,
        accuracy: 0,
        hint: DrillHint.blank,
      );
    }

    final result = DictationEngine.compare(expected: expected, actual: trimmed);
    // 对齐不可靠时不做精确定位，只按整体准确率给结论（与 09 的口径一致）
    final hint = result.uncertain
        ? DrillHint.alignment
        : (result.accuracy >= 1.0
              ? DrillHint.exact
              : (result.accuracy >= passAccuracy
                    ? DrillHint.partial
                    : DrillHint.wrongWord));

    return DrillOutcome(
      passed: result.accuracy >= passAccuracy,
      accuracy: result.accuracy,
      hint: hint,
      detail: trimmed,
    );
  }

  /// 原声回听 —— **无法客观测量**，如实记为自评。
  ///
  /// 不伪造"已掌握"：用户说听清了就是听清了，用户说还有没听出的，
  /// 就以失败落盘，下轮计划继续出这一步。
  static DrillOutcome selfReported({required bool satisfied}) => DrillOutcome(
    passed: satisfied,
    accuracy: satisfied ? 1 : 0,
    hint: satisfied ? DrillHint.exact : DrillHint.partial,
  );

  /// 形态纠错展示 —— 只是"看懂了"，同样是自评。
  static DrillOutcome acknowledgeMorphology() => const DrillOutcome(
    passed: true,
    accuracy: 1,
    hint: DrillHint.exact,
  );
}
