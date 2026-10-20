import 'dart:convert';
import 'package:flutter/material.dart';

import '../data/ai_governor_service.dart';
import '../data/vocabulary_store.dart';
import '../models/vocabulary_model.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_page.dart';

/// AI 听说实验舱 · 创意区数据模型
class SpeakingTurn {
  SpeakingTurn({
    required this.aiSentence,
    required this.aiChinese,
    this.linkingTip,
    this.quickReplies = const [],
    this.userResponse,
    this.nativePolish,
    this.pronunciationTip,
    this.keyPhrases = const [],
  });

  final String aiSentence;
  final String aiChinese;
  final String? linkingTip;
  final List<String> quickReplies;
  String? userResponse;
  String? nativePolish;
  String? pronunciationTip;
  List<({String phrase, String meaning})> keyPhrases;
}

class SpeakingScenario {
  SpeakingScenario({
    required this.id,
    required this.title,
    required this.englishTitle,
    required this.role,
    required this.description,
    required this.initialTurns,
  });

  final String id;
  final String title;
  final String englishTitle;
  final String role;
  final String description;
  final List<SpeakingTurn> Function() initialTurns;
}

/// 创意区：AI 英语听说实验舱 (AI Speaking Sandbox)
///
/// 由 AI 动态生成一切组件内容与听说任务形式：
/// 1. 动态生成角色背景与逼真英文听说情境；
/// 2. 启发式带读与连读失爆要点分析；
/// 3. 用户说话交互与实时 ASR/文字反馈；
/// 4. AI 动态吐出：地道母语润色卡、发音亮点卡、生词一键存入生词本。
class AiSpeakingSandboxScreen extends StatefulWidget {
  const AiSpeakingSandboxScreen({
    super.key,
    required this.aiGovernorService,
    required this.vocabularyStore,
  });

  final AiGovernorService aiGovernorService;
  final VocabularyStore vocabularyStore;

  @override
  State<AiSpeakingSandboxScreen> createState() => _AiSpeakingSandboxScreenState();
}

class _AiSpeakingSandboxScreenState extends State<AiSpeakingSandboxScreen> {
  final _inputController = TextEditingController();
  final _customTopicController = TextEditingController();
  final _scrollController = ScrollController();

  bool _isGenerating = false;
  bool _isCustomTopicExpanded = false;

  late List<SpeakingScenario> _presets;
  SpeakingScenario? _currentScenario;
  List<SpeakingTurn> _turns = [];

  @override
  void initState() {
    super.initState();
    _initPresets();
    _selectScenario(_presets.first);
  }

  void _initPresets() {
    _presets = [
      SpeakingScenario(
        id: 'coffee',
        title: '☕ 咖啡定制点单',
        englishTitle: 'Ordering at a Specialty Cafe',
        role: 'Barista (Native UK / 伦敦咖啡师)',
        description: '在伦敦街头咖啡馆点一杯特调咖啡，并定制少冰与燕麦奶。',
        initialTurns: () => [
          SpeakingTurn(
            aiSentence: "Good morning! Welcome to Monmouth. What can I get started for you today?",
            aiChinese: '早上好！欢迎光临。今天想先来点什么？',
            linkingTip: "💡 连读要点：'What can I' 连读为 /wɒt kə naɪ/，'get started' 中 t 不完全爆破。",
            quickReplies: [
              "Could I get an iced Americano, please?",
              "Hi, I'd love a flat white with oat milk.",
              "Do you have any decaf options available today?",
            ],
            keyPhrases: [
              (phrase: 'flat white', meaning: '澳白咖啡（浓缩与细腻奶泡）'),
              (phrase: 'oat milk', meaning: '燕麦奶'),
            ],
          ),
        ],
      ),
      SpeakingScenario(
        id: 'airport',
        title: '✈️ 机场入境问询',
        englishTitle: 'Airport Border Control',
        role: 'Border Officer (Heathrow Airport)',
        description: '抵达伦敦希思罗机场海关，接受入境官员对旅行目的与停留时长的问询。',
        initialTurns: () => [
          SpeakingTurn(
            aiSentence: "Passport and landing card, please. What is the main purpose of your visit to the UK?",
            aiChinese: '请出示护照和入境卡。你这次来英国的主要目的是什么？',
            linkingTip: "💡 弱读要点：'What is the' 语流中弱读为 /wɒts ðə/，'purpose of' 连读为 /pɜːpəs əv/。",
            quickReplies: [
              "I'm here on holiday for sightseeing and museums.",
              "I'm attending an academic conference in London.",
              "I'm visiting some friends for two weeks.",
            ],
            keyPhrases: [
              (phrase: 'main purpose', meaning: '主要目的'),
              (phrase: 'on holiday', meaning: '度假中'),
            ],
          ),
        ],
      ),
      SpeakingScenario(
        id: 'hotel',
        title: '🏨 酒店入住换房',
        englishTitle: 'Hotel Front Desk Check-in',
        role: 'Front Desk Receptionist (Boutique Hotel)',
        description: '办理预订入住，并礼貌询问是否能调整到远离电梯的高楼层安静房间。',
        initialTurns: () => [
          SpeakingTurn(
            aiSentence: "Welcome to The Standard. Do you have a reservation with us under your name?",
            aiChinese: '欢迎光临。请问您有在您的名下预订房间吗？',
            linkingTip: "💡 连读要点：'under your' 连读为 /ˈʌndə jɔː/，'with us' 连读为 /wɪð ʌs/。",
            quickReplies: [
              "Yes, I have a booking under Michael Zhang.",
              "Yes, here is my confirmation number.",
              "Could I check in a bit earlier if the room is ready?",
            ],
            keyPhrases: [
              (phrase: 'under your name', meaning: '在您的名字下'),
              (phrase: 'check in', meaning: '办理入住'),
            ],
          ),
        ],
      ),
      SpeakingScenario(
        id: 'interview',
        title: '💼 英文求职破冰',
        englishTitle: 'Tech Job Interview Opening',
        role: 'Senior Hiring Manager (Tech Lead)',
        description: '远程外企技术面试开场，做 1 分钟利落的职业背景自我介绍。',
        initialTurns: () => [
          SpeakingTurn(
            aiSentence: "Thanks for taking the time today. Why don't you start by walking us through your background?",
            aiChinese: '感谢你今天抽空参会。不如先由你开始，向我们概述一下你的背景？',
            linkingTip: "💡 连读要点：'Why don't you' 口语中常融为 /waɪ doʊntʃu/，'walk through' 为地道职场语。",
            quickReplies: [
              "Sure! I've been building mobile apps for the past 4 years.",
              "Glad to be here! My focus has been on audio processing and UI design.",
              "Thanks for having me! Let me briefly highlight my recent projects.",
            ],
            keyPhrases: [
              (phrase: 'walk through', meaning: '带领过一遍、详细阐述'),
              (phrase: 'take the time', meaning: '抽空、拨冗'),
            ],
          ),
        ],
      ),
    ];
  }

  void _selectScenario(SpeakingScenario scenario) {
    setState(() {
      _currentScenario = scenario;
      _turns = scenario.initialTurns();
    });
  }

  Future<void> _submitUserResponse(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || _isGenerating) return;

    _inputController.clear();
    FocusScope.of(context).unfocus();

    final currentTurn = _turns.last;
    setState(() {
      currentTurn.userResponse = cleanText;
      _isGenerating = true;
    });

    _scrollToBottom();

    try {
      final prompt = '''
你是一位资深英美英语听说口语私教兼角色扮演导师。
当前情境：${_currentScenario?.englishTitle}
角色身份：${_currentScenario?.role}
AI刚才说：${currentTurn.aiSentence}
学员刚才回应说："$cleanText"

请你根据学员的回应，完成以下四项任务，并严格以合法 JSON 格式输出（不要附带任何多余 markdown 围栏）：
{
  "nativePolish": "将学员的表达改成地道、母语者会自然说出口的高级口语表达（1句）",
  "pronunciationTip": "指出学员这句话里的连读、失爆或重音建议（1~2句话，简短精炼）",
  "keyPhrases": [
    {"phrase": "地道短语1", "meaning": "中文释义"},
    {"phrase": "地道短语2", "meaning": "中文释义"}
  ],
  "nextAiSentence": "作为当前角色，自然接续学员的话并提出下一个对话推进问题（英文，约15~25词）",
  "nextAiChinese": "对下一句的中文翻译",
  "nextLinkingTip": "下一句的连读/听力盲区点拨",
  "quickReplies": ["供学员参考的3个高情商回复短句A", "回复短句B", "回复短句C"]
}
''';

      final response = await widget.aiGovernorService.completeRaw(
        prompt,
        timeout: const Duration(seconds: 25),
      );

      _parseAiResponse(response);
    } catch (_) {
      // 离线/网络受限时的智能保底自适应生成
      _fallbackGenerateTurn(cleanText);
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
        _scrollToBottom();
      }
    }
  }

  void _parseAiResponse(String rawJson) {
    try {
      final clean = rawJson.replaceAll(RegExp(r'^```json\s*|^```\s*|```$', multiLine: true), '').trim();
      final Map<String, dynamic> data = jsonDecode(clean);

      final currentTurn = _turns.last;
      currentTurn.nativePolish = data['nativePolish']?.toString();
      currentTurn.pronunciationTip = data['pronunciationTip']?.toString();

      final rawPhrases = data['keyPhrases'] as List?;
      if (rawPhrases != null) {
        currentTurn.keyPhrases = rawPhrases.map((p) {
          final map = p as Map<String, dynamic>;
          return (
            phrase: map['phrase']?.toString() ?? '',
            meaning: map['meaning']?.toString() ?? '',
          );
        }).where((p) => p.phrase.isNotEmpty).toList();
      }

      final nextAiSentence = data['nextAiSentence']?.toString();
      final nextAiChinese = data['nextAiChinese']?.toString();

      if (nextAiSentence != null && nextAiSentence.isNotEmpty) {
        final quickRepliesList = (data['quickReplies'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];

        _turns.add(SpeakingTurn(
          aiSentence: nextAiSentence,
          aiChinese: nextAiChinese ?? '',
          linkingTip: data['nextLinkingTip']?.toString(),
          quickReplies: quickRepliesList,
        ));
      }
    } catch (e) {
      _fallbackGenerateTurn(_turns.last.userResponse ?? '');
    }
  }

  void _fallbackGenerateTurn(String userText) {
    final currentTurn = _turns.last;

    // 本地自适应离线生成
    final lower = userText.toLowerCase();
    if (lower.contains('coffee') || lower.contains('latte') || lower.contains('americano') || lower.contains('flat white')) {
      currentTurn.nativePolish = "Could I get a large iced oat latte to take away, please?";
      currentTurn.pronunciationTip = "连读提醒：'iced oat' 连读为 /aɪs doʊt/，'take away' 连读自然流畅。";
      currentTurn.keyPhrases = [
        (phrase: 'to take away', meaning: '打包带走 (英式)'),
        (phrase: 'iced oat latte', meaning: '冰燕麦拿铁'),
      ];
      _turns.add(SpeakingTurn(
        aiSentence: "Brilliant. Any pastry or croissant with that today?",
        aiChinese: '太棒了。今天需要搭配牛角包或点心吗？',
        linkingTip: "💡 连读要点：'with that' 中的 th 舌尖咬紧，'Any pastry or' 语流连贯。",
        quickReplies: [
          "Just the coffee today, thanks!",
          "An almond croissant would be lovely.",
          "How much does that come to?",
        ],
      ));
    } else {
      currentTurn.nativePolish = "I'd really appreciate your help with this.";
      currentTurn.pronunciationTip = "连读提醒：注意句子末尾的声调起伏，疑问使用微升调，陈述使用降调。";
      currentTurn.keyPhrases = [
        (phrase: 'appreciate your help', meaning: '非常感谢你的帮助'),
      ];
      _turns.add(SpeakingTurn(
        aiSentence: "Got it! That sounds completely reasonable. How would you like to proceed next?",
        aiChinese: '明白了！这完全合情合理。接下来您希望如何推进？',
        linkingTip: "💡 连读要点：'That sounds' 中的 t 弱化，'proceed next' 重音在 ceed 上。",
        quickReplies: [
          "Let's move forward as planned.",
          "Could you give me a few minutes to think it over?",
          "Whatever works best for your schedule.",
        ],
      ));
    }
  }

  Future<void> _createCustomTopic() async {
    final topic = _customTopicController.text.trim();
    if (topic.isEmpty) return;

    _customTopicController.clear();
    setState(() {
      _isCustomTopicExpanded = false;
      _isGenerating = true;
    });

    final customScenario = SpeakingScenario(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      title: '💡 $topic',
      englishTitle: topic,
      role: 'AI Conversation Partner (Native English)',
      description: '围绕「$topic」展开定制化沉浸式听说交互训练。',
      initialTurns: () => [
        SpeakingTurn(
          aiSentence: "Hello! I'm ready to practice speaking with you about '$topic'. How would you like to start?",
          aiChinese: '你好！我已经准备好和你一起练习关于“$topic”的口语对话了。你想从哪里开始聊起？',
          linkingTip: "💡 连读建议：'ready to practice' 弱读为 /ˈredi tə ˈpræktɪs/，注意重音落在 practice。",
          quickReplies: [
            "Let's jump right into the main topic.",
            "Can you ask me some typical questions first?",
            "I'd like to practice some common phrases around this.",
          ],
          keyPhrases: [
            (phrase: 'jump right in', meaning: '直接切入正题'),
          ],
        ),
      ],
    );

    _selectScenario(customScenario);
    setState(() => _isGenerating = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _savePhraseToVocab(String phrase, String meaning) {
    widget.vocabularyStore.saveOccurrence(
      surface: phrase,
      kind: VocabularyKind.word,
      lessonId: 'speaking_sandbox',
      lessonTitle: 'AI 英语听说实验舱',
      sentenceId: 'speaking_${DateTime.now().millisecondsSinceEpoch}',
      sentenceIndex: 0,
      sentenceText: phrase,
      startMs: 0,
      endMs: 0,
      audioPath: '',
      charStart: 0,
      charEnd: phrase.length,
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已收录至生词本: $phrase ($meaning)'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _customTopicController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;

    return LLPage(
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: ll.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AI 英语听说实验舱',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ll.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: ll.textPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: ll.divider, width: 0.6),
                ),
                child: Text(
                  '创意实验区',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: ll.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          Text(
            _currentScenario?.englishTitle ?? 'AI-Generated Speaking Sandbox',
            style: TextStyle(fontSize: 11, color: ll.textTertiary),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '重置当前场景',
          icon: Icon(Icons.refresh_rounded, size: 20, color: ll.textSecondary),
          onPressed: () {
            if (_currentScenario != null) {
              _selectScenario(_currentScenario!);
            }
          },
        ),
      ],
      body: Column(
        children: [
          // 1. 场景快捷切换栏（黑白极简横向滑轨）
          _buildScenarioSelector(context),

          // 2. 自定义话题折叠栏
          _buildCustomTopicBar(context),

          Divider(height: 1, color: ll.divider.withValues(alpha: 0.6)),

          // 3. 对话与动态组件主视区
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _turns.length + (_isGenerating ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _turns.length) {
                  return _buildTurnItem(context, _turns[index], index);
                }
                // AI 正在动态生成组件状态
                return _buildGeneratingIndicator(context);
              },
            ),
          ),

          // 4. 底部快捷回答与听说输入控制台
          _buildBottomControls(context),
        ],
      ),
    );
  }

  Widget _buildScenarioSelector(BuildContext context) {
    final ll = context.ll;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: _presets.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index < _presets.length) {
            final p = _presets[index];
            final isSelected = p.id == _currentScenario?.id;
            return InkWell(
              key: Key('scenario-chip-${p.id}'),
              onTap: () => _selectScenario(p),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? ll.textPrimary.withValues(alpha: 0.1)
                      : ll.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? ll.textPrimary : ll.divider,
                    width: isSelected ? 1.0 : 0.8,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  p.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? ll.textPrimary : ll.textSecondary,
                  ),
                ),
              ),
            );
          }

          // 自定义情境展开按钮
          return InkWell(
            key: const Key('custom-topic-button'),
            onTap: () => setState(() => _isCustomTopicExpanded = !_isCustomTopicExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isCustomTopicExpanded
                    ? ll.textPrimary.withValues(alpha: 0.1)
                    : ll.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ll.divider, width: 0.8),
              ),
              alignment: Alignment.center,
              child: Row(
                children: [
                  Icon(Icons.add, size: 14, color: ll.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '自定义情境',
                    style: TextStyle(fontSize: 12, color: ll.textSecondary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCustomTopicBar(BuildContext context) {
    if (!_isCustomTopicExpanded) return const SizedBox.shrink();
    final ll = context.ll;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      color: ll.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _customTopicController,
              style: TextStyle(fontSize: 12.5, color: ll.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: '输入任何想练的英语情境 (如: 伦敦退税、租房谈价)...',
                hintStyle: TextStyle(fontSize: 12, color: ll.textTertiary),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: ll.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: ll.divider),
                ),
              ),
              onSubmitted: (_) => _createCustomTopic(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: ll.textPrimary,
              foregroundColor: ll.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _createCustomTopic,
            child: const Text('生成', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnItem(BuildContext context, SpeakingTurn turn, int index) {
    final ll = context.ll;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. AI 角色说出的话（听力输入卡片）
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ll.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ll.divider, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, size: 16, color: ll.textPrimary),
                    const SizedBox(width: 6),
                    Text(
                      _currentScenario?.role ?? 'AI Speaker',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: ll.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  turn.aiSentence,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ll.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  turn.aiChinese,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ll.textTertiary,
                    height: 1.3,
                  ),
                ),
                if (turn.linkingTip != null && turn.linkingTip!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ll.textPrimary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      turn.linkingTip!,
                      style: TextStyle(fontSize: 11, color: ll.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 2. 用户的回答与 AI 动态生成的诊断反馈组件
          if (turn.userResponse != null) ...[
            const SizedBox(height: 12),
            _buildUserResponseAndFeedback(context, turn),
          ],
        ],
      ),
    );
  }

  Widget _buildUserResponseAndFeedback(BuildContext context, SpeakingTurn turn) {
    final ll = context.ll;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ll.textPrimary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ll.divider.withValues(alpha: 0.8), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mic_none_rounded, size: 15, color: ll.textPrimary),
              const SizedBox(width: 6),
              Text(
                '你的回答 (My Response)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: ll.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            turn.userResponse ?? '',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: ll.textPrimary,
            ),
          ),

          // 动态组件 A：🌟 地道润色卡 (Native Polish)
          if (turn.nativePolish != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ll.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ll.divider, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 13, color: ll.textPrimary),
                      const SizedBox(width: 5),
                      Text(
                        '地道母语者说 (Native Polish)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ll.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    turn.nativePolish!,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ll.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 动态组件 B：🎯 连读与发音要点 (Pronunciation & Linking Tips)
          if (turn.pronunciationTip != null) ...[
            const SizedBox(height: 8),
            Text(
              '🎯 ${turn.pronunciationTip!}',
              style: TextStyle(fontSize: 11.5, color: ll.textSecondary, height: 1.4),
            ),
          ],

          // 动态组件 C：📚 高频词汇胶囊 (一键收录生词本)
          if (turn.keyPhrases.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: turn.keyPhrases.map((kp) {
                return InkWell(
                  onTap: () => _savePhraseToVocab(kp.phrase, kp.meaning),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ll.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ll.divider, width: 0.6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bookmark_add_outlined, size: 12, color: ll.textPrimary),
                        const SizedBox(width: 4),
                        Text(
                          '${kp.phrase} · ${kp.meaning}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: ll.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneratingIndicator(BuildContext context) {
    final ll = context.ll;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: ll.textPrimary),
          ),
          const SizedBox(width: 8),
          Text(
            'AI 正在动态推演下一轮情境与表达诊断…',
            style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context) {
    final ll = context.ll;
    final lastTurn = _turns.isNotEmpty ? _turns.last : null;
    final quickReplies = lastTurn?.userResponse == null ? (lastTurn?.quickReplies ?? []) : [];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: ll.surface,
        border: Border(top: BorderSide(color: ll.divider.withValues(alpha: 0.8), width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 快速参考回答短语（Quick Replies）
          if (quickReplies.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: quickReplies.map((reply) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: InkWell(
                      onTap: () => _submitUserResponse(reply),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: ll.textPrimary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ll.divider, width: 0.6),
                        ),
                        child: Text(
                          reply,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: ll.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // 听说输入行
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  style: TextStyle(fontSize: 13, color: ll.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '输入你的英语回答，或点击上方推荐短语…',
                    hintStyle: TextStyle(fontSize: 12, color: ll.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: ll.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: ll.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: ll.divider),
                    ),
                  ),
                  onSubmitted: _submitUserResponse,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: ll.textPrimary,
                  foregroundColor: ll.bg,
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                onPressed: () => _submitUserResponse(_inputController.text),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
