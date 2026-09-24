/// AI 出题 —— 10 号文档 §五 的落地：每词两题起步（原语境理解 + 新语境产出）。
///
/// 红线（§5.5 + 08 定调，调用方必须遵守）：
///   * AI 失败**不阻塞**任何核心行为 —— 解析/网络失败一律抛 [AiQuizException]，
///     UI 侧降级为「跳过本步」，绝不重试轰炸；
///   * 「会 / 半会 / 不会」的映射在**本地**（[masteryVerdict]），
///     不让 LLM 输出「掌握度 83%」这类神秘数字；
///   * AI 对开放答案只返回结构化 `pass / partial / fail + reasonCode`（§5.4）；
///   * 第 3 题（冲突消解）本轮不做 —— 每词固定两题，与 §5.2 的「起步」一致。
///
/// 本文件只有**纯函数与纯数据**：网络调用由 UI/数据层注入（测试给 fake）。
library;

import 'dart:convert';

/// AI 出题请求的素材（全部来自已有数据，不需要额外查询）。
class AiQuizMaterial {
  const AiQuizMaterial({
    required this.surfaceForm,
    required this.sentenceText,
    required this.translation,
  });

  /// 目标词 / 短语。
  final String surfaceForm;

  /// 原句（第 1 题的语境来源）。
  final String sentenceText;

  /// 原句中文释义（只给 AI 参考语境，**不出现在题面上** —— 红线：正面零中文）。
  final String translation;
}

/// 两题题面（由 LLM 生成，App 只做展示与收集）。
class AiQuiz {
  const AiQuiz({required this.contextQuestion, required this.transferPrompt});

  /// 第 1 题 · 原语境理解：**不问翻译**，问 `In this sentence, what does
  /// "X" mean or do?`（§5.2）——测当前义项识别。允许中英自由答。
  final String contextQuestion;

  /// 第 2 题 · 新语境产出：AI 按同一义项换场景，要求**开放输入**英文
  /// （§5.2）——测能否真正取回 + 用法 / 形态 / 搭配。
  final String transferPrompt;

  /// 两个语境（§5.3：「会」必须经过 ≥2 个不同语境 —— 原句 + 新场景恰好两个）。
  int get distinctContextCount => 2;
}

/// LLM 返回不符合契约（缺字段 / 非法 JSON / 空题面）。
class AiQuizException implements Exception {
  const AiQuizException(this.message);
  final String message;

  @override
  String toString() => 'AiQuizException: $message';
}

/// 构造出题 prompt（纯函数，可测）。
///
/// 契约要点写进 prompt 本身：严格 JSON、义项一致、题面零中文、
/// 第 2 题必须是可以用目标词回答的开放英文产出任务。
String buildAiQuizPrompt(AiQuizMaterial material) {
  return [
    'You are an English listening tutor. Create TWO open-ended quiz prompts '
        'for one vocabulary item.',
    'Target item: "${material.surfaceForm}"',
    'Original sentence (its context): "${material.sentenceText}"',
    'Sentence meaning (for your reference only): "${material.translation}"',
    'Return STRICT JSON only, no markdown fence, with exactly two fields:',
    '{"contextQuestion": "...", "transferPrompt": "..."}',
    'contextQuestion: ask what "${material.surfaceForm}" means or does IN THIS '
        'sentence. Never ask for a translation. English only.',
    'transferPrompt: a NEW scenario (different from the original sentence) '
        'where the learner must USE "${material.surfaceForm}" with the SAME '
        'sense. Phrase it as an instruction like: Say in English that ... '
        'using "<item>". English only.',
    'Both prompts must be short (<= 30 words each).',
  ].join('\n');
}

/// 从 LLM 原始回复解析题面（容错：剥代码围栏、取首个平衡 JSON 对象）。
AiQuiz parseAiQuiz(String raw) {
  final json = _extractJsonObject(raw);
  if (json == null) {
    throw const AiQuizException('no JSON object found in response');
  }
  final context = (json['contextQuestion'] as String?)?.trim() ?? '';
  final transfer = (json['transferPrompt'] as String?)?.trim() ?? '';
  if (context.isEmpty || transfer.isEmpty) {
    throw const AiQuizException('missing contextQuestion / transferPrompt');
  }
  return AiQuiz(contextQuestion: context, transferPrompt: transfer);
}

/// 开放答案的 AI 判定结果（§5.4：只允许结构化结论）。
class AiAnswerJudgement {
  const AiAnswerJudgement({required this.verdict, required this.reasonCode});

  /// `pass / partial / fail`。
  final AiVerdict verdict;

  /// `WRONG_SENSE / BAD_COLLOCATION / WRONG_FORM / GRAMMAR_ERROR / OTHER`。
  final String reasonCode;

  static AiAnswerJudgement parse(String raw) {
    final json = _extractJsonObject(raw);
    if (json == null) {
      throw const AiQuizException('no JSON object found in judgement');
    }
    final v = (json['verdict'] as String?)?.trim().toLowerCase() ?? '';
    final verdict = AiVerdict.values.firstWhere(
      (e) => e.name == v,
      orElse: () => throw const AiQuizException('verdict must be pass/partial/fail'),
    );
    return AiAnswerJudgement(
      verdict: verdict,
      reasonCode: ((json['reasonCode'] as String?) ?? 'OTHER').trim(),
    );
  }
}

/// AI 判定结论。
enum AiVerdict { pass, partial, fail }

/// 构造判答案的 prompt（纯函数，可测）。
String buildJudgementPrompt({
  required AiQuiz quiz,
  required int questionIndex,
  required String answer,
  required AiQuizMaterial material,
}) {
  final field = questionIndex == 0 ? 'contextQuestion' : 'transferPrompt';
  return [
    'You are grading an open-ended answer for an English learner.',
    'Target item: "${material.surfaceForm}"',
    'The question ($field): "${questionIndex == 0 ? quiz.contextQuestion : quiz.transferPrompt}"',
    'Learner answer: "${answer.trim()}"',
    'Return STRICT JSON only: {"verdict": "pass|partial|fail", "reasonCode": '
        '"WRONG_SENSE|BAD_COLLOCATION|WRONG_FORM|GRAMMAR_ERROR|OTHER"}',
    'Judge the SENSE and USAGE, not spelling. Empty answer is fail.',
  ].join('\n');
}

/// §5.3 的本地映射 —— 判定权在 App，不在 LLM。
///
/// 三个维度：
/// * `listeningPass` —— 09 的可靠听写证据（外部传入）；
/// * `recognitionPass` —— 第 1 题判定；
/// * `productionPass` —— 第 2 题判定。
///
/// 硬规则（逐条对应 §5.3 表格与 §5.4）：
/// * **会**：recognition pass AND production pass（原句 + 新场景 = 2 个语境）；
/// * **不会**：至少两个独立证据失败（两题都 fail）；
/// * **半会**：其余一切（含冲突、partial）；
/// * listening 未通过时附加「认识，但原声里还听不稳」的提示位（文案 l10n 给）。
MasteryVerdict masteryVerdict({
  required bool listeningPass,
  required bool recognitionPass,
  required bool productionPass,
}) {
  final failedEvidences = [
    if (!recognitionPass) 1,
    if (!productionPass) 1,
  ].length;

  if (failedEvidences >= 2) {
    return const MasteryVerdict(
      level: MasteryLevel.unknown,
      listeningUnstable: false,
    );
  }
  if (recognitionPass && productionPass) {
    return MasteryVerdict(
      level: MasteryLevel.known,
      listeningUnstable: !listeningPass,
    );
  }
  return MasteryVerdict(
    level: MasteryLevel.halfKnown,
    listeningUnstable: !listeningPass,
  );
}

/// 掌握判定结论（**不直接改词条状态** —— 状态只由显式动作转移，
/// 这是 P4 落地时定下的派生规则 1；本结论只展示给用户 + 落 drill log）。
class MasteryVerdict {
  const MasteryVerdict({
    required this.level,
    required this.listeningUnstable,
  });

  final MasteryLevel level;

  /// listening 证据仍失败时的附加提示位（§5.3 附加行）。
  final bool listeningUnstable;
}

enum MasteryLevel { known, halfKnown, unknown }

/// 从 LLM 文本里剥出第一个平衡的 JSON 对象（处理 ```json 围栏 / 前后废话）。
Map<String, dynamic>? _extractJsonObject(String raw) {
  final text = raw.trim();
  final start = text.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (ch == '\\') {
      if (inString) escaped = true;
      continue;
    }
    if (ch == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        try {
          final decoded = jsonDecode(text.substring(start, i + 1));
          return decoded is Map<String, dynamic> ? decoded : null;
        } on FormatException {
          return null;
        }
      }
    }
  }
  return null;
}
