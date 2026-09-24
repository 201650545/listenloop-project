import 'package:flutter/material.dart';

import '../data/ai_governor_service.dart';
import '../data/vocabulary_store.dart';
import '../models/vocabulary_model.dart';
import '../player/audio_player_facade.dart';
import '../training/vocabulary_ai_drill.dart';
import '../training/vocabulary_plan.dart';
import 'vocabulary_drill_screen.dart';

/// 打开 AI 检查（10 号 §五.1「检查我是不是真的会」）—— 单词一张卷。
///
/// 网关、prompt、解析都在这里接线；执行页只拿回调，AI 挂了
/// 自然降级为「跳过」（§5.5 红线：附属失败不得阻塞核心）。
/// 练习结果经执行页落 `VocabularyDrillLog`，不改词条状态
/// （状态只由显式动作转移 —— 派生规则 1）。
Future<void> openAiQuizScreen({
  required BuildContext context,
  required VocabularyStore store,
  required VocabularyItem item,
  required AiGovernorService governor,
  AudioPlayerFacade? audioFacade,
  bool autoCreateAudioFacade = true,
}) {
  final occurrence = item.latestOccurrence;
  final material = AiQuizMaterial(
    surfaceForm: item.surfaceForm,
    sentenceText: occurrence?.sentenceText ?? '',
    // occurrence 不存句子释义 —— 留空，AI 从原句自行取义项（prompt 已说明）。
    translation: '',
  );

  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VocabularyDrillScreen(
        store: store,
        itemId: item.id,
        components: const [StudyComponent.contextTransfer],
        audioFacade: audioFacade,
        autoCreateAudioFacade: autoCreateAudioFacade,
        loadAiQuiz: (target) async {
          final raw = await governor.completeRaw(
            buildAiQuizPrompt(material),
            timeout: const Duration(seconds: 45),
          );
          return parseAiQuiz(raw);
        },
        judgeAiAnswer:
            ({
              required AiQuiz quiz,
              required int questionIndex,
              required String answer,
            }) async {
              final raw = await governor.completeRaw(
                buildJudgementPrompt(
                  quiz: quiz,
                  questionIndex: questionIndex,
                  answer: answer,
                  material: material,
                ),
                timeout: const Duration(seconds: 45),
              );
              return AiAnswerJudgement.parse(raw);
            },
      ),
    ),
  );
}
