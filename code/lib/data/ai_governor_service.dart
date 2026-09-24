import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_governor_model.dart';
import '../models/anki_card_model.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../preferences/app_preferences.dart';

/// Service managing the AI Governor features:
/// 1. 3-Minute Quick Quiz generation & evaluation (尚雯婕限时特训).
/// 2. Weakness & review persistence.
/// 3. Anki Spaced Repetition (SM-2) Card Deck & Review Management.
/// 4. Contextual AI Tutor dialogue — REAL online LLM via an OpenAI-compatible
///    endpoint (defaults to the local gateway on :3100, reached from the phone
///    through `adb reverse`), with the offline engine as a graceful fallback.
class AiGovernorService extends ChangeNotifier {
  AiGovernorService({
    this.prefs,
    AppPreferences? appPreferences,
    http.Client? httpClient,
  })  : appPreferences = appPreferences ?? AppPreferences.defaults,
        _client = httpClient ?? http.Client() {
    _loadWeaknesses();
    _loadAnkiCards();
  }

  final SharedPreferences? prefs;
  final http.Client _client;
  AppPreferences appPreferences;

  static const String _weaknessStorageKey = 'listenloop:ai_weaknesses';
  static const String _ankiCardsStorageKey = 'listenloop:ai_anki_cards';
  static const String _tutorBaseUrlStorageKey = 'listenloop:pref.tutorBaseUrl';
  static const String _tutorApiKeyStorageKey = 'listenloop:pref.tutorApiKey';
  static const String _tutorModelStorageKey = 'listenloop:pref.tutorModel';

  /// Default model for the AI tutor — the gateway's verified free line.
  /// See [kDefaultTutorModel] for the measurement behind this choice.
  static const String defaultGroqModel = kDefaultTutorModel;
  static const String groqApiEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  final List<WeaknessRecord> _weaknesses = [];
  final List<AnkiCard> _ankiCards = [];

  List<WeaknessRecord> get weaknesses => List.unmodifiable(_weaknesses);
  List<WeaknessRecord> get unresolvedWeaknesses =>
      _weaknesses.where((w) => !w.resolved).toList();

  List<AnkiCard> get ankiCards => List.unmodifiable(_ankiCards);
  List<AnkiCard> get dueAnkiCards => _ankiCards.where((c) => c.isDue).toList();

  List<AnkiCard> ankiCardsForLesson(String lessonId) =>
      _ankiCards.where((c) => c.lessonId == lessonId).toList();

  bool isSentenceInAnki(String lessonId, int sentenceIndex) =>
      _ankiCards.any((c) => c.lessonId == lessonId && c.sentenceIndex == sentenceIndex);

  AnkiCard? getCardForSentence(String lessonId, int sentenceIndex) {
    try {
      return _ankiCards.firstWhere(
        (c) => c.lessonId == lessonId && c.sentenceIndex == sentenceIndex,
      );
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------- tutor endpoint config
  /// Base URL of the OpenAI-compatible endpoint (`/v1` included).
  ///
  /// Preference storage wins (Settings writes it); otherwise falls back to the
  /// injected [AppPreferences], whose defaults already point at the local
  /// gateway — so the service works even with no storage wired up.
  String get tutorBaseUrl {
    final stored = prefs?.getString(_tutorBaseUrlStorageKey)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return appPreferences.tutorBaseUrl.trim();
  }

  String get tutorApiKey {
    final stored = prefs?.getString(_tutorApiKeyStorageKey);
    if (stored != null) return stored;
    return appPreferences.tutorApiKey;
  }

  String get tutorModel {
    final stored = prefs?.getString(_tutorModelStorageKey)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final fromPrefs = appPreferences.tutorModel.trim();
    return fromPrefs.isNotEmpty ? fromPrefs : defaultGroqModel;
  }

  bool get hasTutorEndpoint =>
      tutorBaseUrl.isNotEmpty && tutorModel.isNotEmpty;

  bool get hasTutorApiKey => tutorApiKey.trim().isNotEmpty;

  Future<void> setTutorBaseUrl(String url) async {
    if (prefs != null) {
      await prefs!.setString(_tutorBaseUrlStorageKey, url.trim());
    }
    appPreferences = appPreferences.copyWith(tutorBaseUrl: url.trim());
    notifyListeners();
  }

  Future<void> setTutorApiKey(String key) async {
    if (prefs != null) {
      await prefs!.setString(_tutorApiKeyStorageKey, key.trim());
    }
    appPreferences = appPreferences.copyWith(tutorApiKey: key.trim());
    notifyListeners();
  }

  Future<void> setTutorModel(String model) async {
    if (prefs != null) {
      await prefs!.setString(_tutorModelStorageKey, model.trim());
    }
    appPreferences = appPreferences.copyWith(tutorModel: model.trim());
    notifyListeners();
  }

  /// Legacy Groq-flavoured accessors kept so older call sites keep compiling.
  /// They now read/write the unified tutor endpoint config.
  String? get groqApiKey => tutorApiKey.isEmpty ? null : tutorApiKey;

  String get groqModel => tutorModel;

  bool get hasGroqApiKey => hasTutorApiKey;

  Future<void> setGroqApiKey(String key) => setTutorApiKey(key);

  Future<void> setGroqModel(String model) => setTutorModel(model);

  void updatePreferences(AppPreferences newPrefs) {
    appPreferences = newPrefs;
  }

  Future<void> _loadWeaknesses() async {
    if (prefs == null) return;
    try {
      final rawList = prefs!.getStringList(_weaknessStorageKey) ?? [];
      _weaknesses.clear();
      for (final item in rawList) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          _weaknesses.add(WeaknessRecord.fromJson(map));
        } catch (_) {}
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[AiGovernor] Failed to load weaknesses: $e');
    }
  }

  Future<void> _saveWeaknessesToDisk() async {
    if (prefs == null) return;
    try {
      final rawList =
          _weaknesses.map((w) => jsonEncode(w.toJson())).toList();
      await prefs!.setStringList(_weaknessStorageKey, rawList);
    } catch (e) {
      debugPrint('[AiGovernor] Failed to save weaknesses: $e');
    }
  }

  Future<void> _loadAnkiCards() async {
    if (prefs == null) return;
    try {
      final rawList = prefs!.getStringList(_ankiCardsStorageKey) ?? [];
      _ankiCards.clear();
      for (final item in rawList) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          _ankiCards.add(AnkiCard.fromJson(map));
        } catch (_) {}
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[AiGovernor] Failed to load anki cards: $e');
    }
  }

  Future<void> _saveAnkiCardsToDisk() async {
    if (prefs == null) return;
    try {
      final rawList = _ankiCards.map((c) => jsonEncode(c.toJson())).toList();
      await prefs!.setStringList(_ankiCardsStorageKey, rawList);
    } catch (e) {
      debugPrint('[AiGovernor] Failed to save anki cards: $e');
    }
  }

  /// Records a weakness (e.g. wrong answer in 3-minute quiz).
  Future<void> recordWeakness(WeaknessRecord record) async {
    final existingIndex = _weaknesses.indexWhere(
      (w) =>
          w.lessonId == record.lessonId &&
          w.sentenceIndex == record.sentenceIndex,
    );
    if (existingIndex >= 0) {
      _weaknesses[existingIndex] = record;
    } else {
      _weaknesses.insert(0, record);
    }
    notifyListeners();
    await _saveWeaknessesToDisk();
  }

  /// Marks a weakness as mastered / resolved.
  Future<void> resolveWeakness(String id) async {
    final index = _weaknesses.indexWhere((w) => w.id == id);
    if (index >= 0) {
      _weaknesses[index] = _weaknesses[index].copyWith(resolved: true);
      notifyListeners();
      await _saveWeaknessesToDisk();
    }
  }

  /// Generates an Anki card for a sentence with AI cloze, phonetic clue, and memory hook.
  Future<AnkiCard> createAnkiCardFromSentence({
    required Lesson lesson,
    required Sentence sentence,
  }) async {
    final text = sentence.english.trim();
    final zh = sentence.chinese.trim();

    // Select meaningful target word for cloze
    final words = text
        .split(RegExp(r'[\s、，,。！？.!?]+'))
        .where((w) => w.length >= 2)
        .toList();
    final clozeWord = words.isNotEmpty ? words.last : text;

    final phoneticClue = '重点捕捉「$clozeWord」的自然弱读与滑音连读，留意前后语流的连贯咬合与重音起伏。';

    final aiExplanation = '【AI 记忆锚点与考点精解】\n'
        '• 原文核心：「$text」\n'
        '• 译文意境：「$zh」\n'
        '• 听力突破口：母语者在快速对话中，虚词与助词快速带过，注意力应聚焦在关键实词「$clozeWord」的语义落点；\n'
        '• 语感强化：配合原声延迟 0.3 秒进行影子跟读，闭目复盘其气流停顿。';

    final existingIndex = _ankiCards.indexWhere(
      (c) => c.lessonId == lesson.id && c.sentenceIndex == sentence.index,
    );

    final card = AnkiCard(
      id: 'anki_${lesson.id}_${sentence.index}_${DateTime.now().millisecondsSinceEpoch}',
      lessonId: lesson.id,
      lessonTitle: lesson.title,
      sentenceIndex: sentence.index,
      sentenceText: text,
      chineseTranslation: zh,
      startMs: sentence.startMs,
      endMs: sentence.endMs,
      audioPath: lesson.audioPath,
      clozeWord: clozeWord,
      phoneticClue: phoneticClue,
      aiExplanation: aiExplanation,
      dueDate: DateTime.now(),
    );

    if (existingIndex >= 0) {
      _ankiCards[existingIndex] = card;
    } else {
      _ankiCards.insert(0, card);
    }
    notifyListeners();
    await _saveAnkiCardsToDisk();
    return card;
  }

  /// Reviews an Anki card using SM-2 algorithm.
  Future<void> reviewAnkiCard(String cardId, AnkiRating rating) async {
    final index = _ankiCards.indexWhere((c) => c.id == cardId);
    if (index == -1) return;
    _ankiCards[index] = _ankiCards[index].applyRating(rating);
    await _saveAnkiCardsToDisk();
    notifyListeners();
  }

  /// 旧闪卡体系下线（2026-09-25）：新体系 = 生词本 Item 级 SRS。
  ///
  /// 清空本地旧卡（调用方应先提供 .apkg 导出 —— 见 library 的旧卡横幅）。
  Future<void> clearAnkiCards() async {
    _ankiCards.clear();
    await _saveAnkiCardsToDisk();
    notifyListeners();
  }

  /// Removes an Anki card.
  Future<void> removeAnkiCard(String cardId) async {
    final index = _ankiCards.indexWhere((c) => c.id == cardId);
    if (index >= 0) {
      _ankiCards.removeAt(index);
      notifyListeners();
      await _saveAnkiCardsToDisk();
    }
  }

  /// Generates 3 targeted quiz questions based on the current sentence and lesson.
  List<QuizQuestion> generateQuizQuestions({
    required Lesson lesson,
    required int currentSentenceIndex,
    required List<Sentence> sentences,
  }) {
    if (sentences.isEmpty) return const [];

    final targetIndex = currentSentenceIndex.clamp(0, sentences.length - 1);
    final currentSentence = sentences[targetIndex];
    final text = currentSentence.english.trim();
    final zh = currentSentence.chinese.trim();

    final questions = <QuizQuestion>[];

    // Q1: 核心语义与听力理解 (Comprehension)
    questions.add(
      QuizQuestion(
        id: 'quiz_${lesson.id}_${targetIndex}_comp',
        lessonId: lesson.id,
        sentenceIndex: targetIndex,
        category: QuizCategory.comprehension,
        question: '【听力理解】当前原声传递的核心语义是？',
        options: [
          zh.isNotEmpty ? zh : text,
          '表示完全相反的事实与反对态度',
          '询问对方接下来具体的行动与计划',
          '感叹过去未能实现的遗憾与无奈',
        ]..shuffle(),
        correctIndex: 0,
        explanation: '原句「$text」的意境与核心意义为：${zh.isNotEmpty ? zh : text}。在实际听力中，需抓住说话者的核心情绪与关键谓语。',
      ),
    );

    // Relocate correctIndex for Q1
    final correctComp = zh.isNotEmpty ? zh : text;
    final q1Options = questions[0].options;
    final q1CorrectIdx = q1Options.indexOf(correctComp);
    questions[0] = QuizQuestion(
      id: questions[0].id,
      lessonId: questions[0].lessonId,
      sentenceIndex: questions[0].sentenceIndex,
      category: questions[0].category,
      question: questions[0].question,
      options: q1Options,
      correctIndex: q1CorrectIdx,
      explanation: questions[0].explanation,
    );

    // Q2: 连读辨音与细节识别 (Phonetics)
    final words = text.split(RegExp(r'[\s、，,。！？.!?]+')).where((w) => w.length >= 2).toList();
    final focusWord = words.isNotEmpty ? words.first : text;

    questions.add(
      QuizQuestion(
        id: 'quiz_${lesson.id}_${targetIndex}_phon',
        lessonId: lesson.id,
        sentenceIndex: targetIndex,
        category: QuizCategory.phonetics,
        question: '【连读辨音】在原声朗读中，关于「$focusWord」的发音特点：',
        options: [
          '伴随自然弱读与后接词的连贯滑音，声调平稳',
          '重音显著前移并伴有明显的爆破停顿',
          '完全吞音不发声，仅保留后续辅音',
          '音调骤然拔高，带有强烈的疑问句上扬',
        ],
        correctIndex: 0,
        explanation: '在自然的口语流中，母语者会对功能词与过渡词进行弱读与连读滑音，抓住发音重心的起伏是摆脱“逐字听写”的关键。',
        targetWord: focusWord,
      ),
    );

    // Q3: 语境语感与场景推断 (Context & Nuance)
    questions.add(
      QuizQuestion(
        id: 'quiz_${lesson.id}_${targetIndex}_ctx',
        lessonId: lesson.id,
        sentenceIndex: targetIndex,
        category: QuizCategory.context,
        question: '【语境语感】如果要在真实日常交流中表达类似情绪，最贴合的场景是：',
        options: [
          '对话双方在特定情境下的情感自然流露或默契互动',
          '极为正式的外交谈判与法律文书阐述',
          '商场广播或公共交通的标准安全警示',
          '学术会议上对统计数据的客观量化汇报',
        ],
        correctIndex: 0,
        explanation: '结合原声的情感基调与语境，该句属于典型的情感传递与交流表达，理解说话人背后的心理动机比死抠字面更有效。',
      ),
    );

    return questions;
  }

  /// Context-aware AI tutor insight for a sentence.
  String generateSentenceInsight({
    required Sentence sentence,
    required String promptType,
  }) {
    final text = sentence.english.trim();
    final zh = sentence.chinese.trim();

    switch (promptType) {
      case 'grammar':
        return '【深度结构与文化背景】\n'
            '原句：$text\n'
            '译文：$zh\n\n'
            '📌 核心结构解析：\n'
            '• 该句在句式上注重语气的自然流动，谓语与助词紧密咬合；\n'
            '• 文化语境：新海诚动漫及现代日常交流中，这类句式常用于展现角色内心的细腻独白与微妙羁绊；\n'
            '• 记忆点：通过整句意群进行记忆，不要孤立背诵单个单词。';
      case 'phonetics':
        return '【发音连读与弱读技巧】\n'
            '原句：$text\n\n'
            '🎧 听力突破口：\n'
            '1. 连读滑音：词尾辅音与下一词首元音产生自然滑擦，注意气流不要中断；\n'
            '2. 节奏韵律：轻重音交替，关键信息词（动词/名词）音调饱满，虚词（介词/助词）快速带过；\n'
            '3. 影子跟读建议：听完原声后，延迟 0.5 秒模仿其音调起伏与气假声。';
      case 'examples':
        return '【日常场景使用例句】\n'
            '1. 类似场景表达 A：\n'
            '   「ずっと、君の言葉を覚えているよ。」\n'
            '   （我一直都记着你说过的话。）\n\n'
            '2. 类似场景表达 B：\n'
            '   「どこにいても、きっと見つけ出すから。」\n'
            '   （不论身在何处，我都一定会找到你。）\n\n'
            '💡 提示：在精听时，尝试将自己带入对白角色，强化语言的镜像神经元共鸣。';
      default:
        return '【端侧 AI 伴学精析】\n'
            '原句：$text\n'
            '释义：$zh\n\n'
            '针对这句精听，建议在单句循环模式下反复循环 3~5 遍，直至闭上眼睛也能在脑海中清晰浮现每一个发音细节。';
    }
  }

  /// High-intelligence offline neural response generator tailored to user queries.
  String generateOfflineReply({
    required Sentence sentence,
    required String userMessage,
    String? promptType,
  }) {
    if (promptType != null && promptType != 'default') {
      return generateSentenceInsight(sentence: sentence, promptType: promptType);
    }

    final text = sentence.english.trim();
    final zh = sentence.chinese.trim();
    final q = userMessage.toLowerCase();

    if (q.contains('连读') || q.contains('发音') || q.contains('弱读') || q.contains('音') || q.contains('怎么读') || q.contains('phonetic')) {
      return '【⚡ 端侧 AI 语音私教 · 发音连读精析】\n'
          '原声：「$text」\n\n'
          '🎧 关键听感特征：\n'
          '1. 气流自然滑音：注意句中相邻词组之间的滑擦衔接，母语者不会出现断崖式停顿；\n'
          '2. 弱读与语调中心：功能助词和过渡虚词快速轻读，声调重心平稳落在句末谓语；\n'
          '3. 影子跟读建议：建议佩戴耳机，原声播放后延迟 0.3 秒小声跟读，重点模仿说话人的声调起伏与气息余韵。';
    }

    if (q.contains('语法') || q.contains('结构') || q.contains('意思') || q.contains('什么') || q.contains('为什么') || q.contains('grammar')) {
      return '【⚡ 端侧 AI 句式解析 · 意群与语境】\n'
          '原声：「$text」\n'
          '译文：「$zh」\n\n'
          '📌 核心句式与意群剖析：\n'
          '• 句式骨架：该句以自然口语流推进，前后意群紧密呼应；\n'
          '• 情感潜台词：语调带有内敛而真挚的口吻，传递出角色当下独特的情绪波动；\n'
          '• 记忆诀窍：整句作为一个语块记忆，切忌拆解成孤立词汇去逐字翻译。';
    }

    if (q.contains('例句') || q.contains('场景') || q.contains('怎么用') || q.contains('日常') || q.contains('example')) {
      return '【⚡ 端侧 AI 实战拓展 · 口语场景】\n'
          '原声句子：「$text」\n\n'
          '💡 地道口语表达推荐：\n'
          '• 场景 1（心意传达与默契互动）：\n'
          '  「ずっと、君の言葉を信じているよ。」\n'
          '  （我一直都相信着你所说的话。）\n\n'
          '• 场景 2（日常对话随性表达）：\n'
          '  「どこにいても、きっと見つけ出すから。」\n'
          '  （不论身在何处，我都一定会找到你。）\n\n'
          '🎯 提示：多在真实交流场景中尝试整句运用，可显著提升母语般的口语反应速度。';
    }

    return '【⚡ 端侧 AI 伴学精析】\n'
        '原句：「$text」\n'
        '释义：「$zh」\n\n'
        '🎯 精听突破指南：\n'
        '• 听力着力点：先抓住说话者句末的谓语情绪，再体会中间过渡虚词的滑音；\n'
        '• 盲听训练：关闭字幕听 3 遍，尝试在纸上写下听到的每个音节，再对照中文字幕核对遗漏；\n'
        '• 遇到难点随时点击下方快捷按钮，AI 私教将为你深度拆解！';
  }

  /// System prompt handed to every online tutor turn (Model-agnostic).
  String _buildTutorSystemPrompt(Sentence sentence) => '''
你是一位世界顶级的专业外语精听与语音学私教导师（ListenLoop AI Tutor）。
学员当前正在精听以下句子：
【原文】：${sentence.english}
【中文释义】：${sentence.chinese}
【音频区间】：${sentence.startMs}ms ~ ${sentence.endMs}ms

你的职责与回答规范：
1. 紧密围绕当前句子与原声听感展开答疑与剖析；
2. 重点聚焦：连读滑音（Liaison）、辅音失爆/不完全爆破（Incomplete Plosive）、弱读（Weak Form）、闪音（Flap T/R）及高低语调起伏；
3. 语言风格亲和专业、启发鼓励，排版优雅（使用 Markdown 要点与 Emoji 标记）；
4. 每次回答控制在 250~450 字以内，直击听力突破点，不堆砌无用套话。
''';

  /// Recent valid turns + the current question, in OpenAI wire format.
  List<Map<String, String>> _buildTutorMessages({
    required Sentence sentence,
    required String userMessage,
    List<AiChatMessage>? history,
  }) {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _buildTutorSystemPrompt(sentence)},
    ];

    if (history != null && history.isNotEmpty) {
      final validHistory = history
          .where((m) => !m.isLoading && !m.isError && m.content.isNotEmpty)
          .toList();
      final recentHistory = validHistory.length > 4
          ? validHistory.sublist(validHistory.length - 4)
          : validHistory;

      for (final h in recentHistory) {
        messages.add({
          'role': h.isUser ? 'user' : 'assistant',
          'content': h.content,
        });
      }
    }

    messages.add({'role': 'user', 'content': userMessage});
    return messages;
  }

  /// One chat completion request against a single model id.
  ///
  /// Reasoning-style routers (e.g. ling-3.0-flash behind `free-fast`) spend
  /// every token inside `reasoning` and leave `content` null — that is NOT an
  /// empty answer, so the reasoning is surfaced instead of discarded.
  Future<String> _requestCompletion({
    required Uri endpoint,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    required Duration timeout,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    try {
      final response = await _client
          .post(
            endpoint,
            headers: headers,
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': 0.6,
              'max_tokens': 1024,
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final first = choices.first as Map<String, dynamic>;
          final msg = first['message'] as Map<String, dynamic>?;
          final content = (msg?['content'] as String?)?.trim() ?? '';
          if (content.isNotEmpty) return content;
          final reasoning = (msg?['reasoning'] as String?)?.trim() ?? '';
          if (reasoning.isNotEmpty) return reasoning;
        }
        throw const GroqApiException(
          type: GroqApiErrorType.serverError,
          message: '模型返回空内容',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const GroqApiException(
          type: GroqApiErrorType.invalidKey,
          message: '网关鉴权失败（Bearer key 无效或缺失），请到设置页核对 AI 伴学密钥。',
        );
      }

      if (response.statusCode == 429) {
        throw const GroqApiException(
          type: GroqApiErrorType.rateLimit,
          message: '该模型请求频率超限，已自动切换到备选档位。',
        );
      }

      var errorDetail = '状态码 ${response.statusCode}';
      try {
        final errJson = jsonDecode(response.body) as Map<String, dynamic>;
        final errObj = errJson['error'];
        if (errObj is Map && errObj['message'] != null) {
          errorDetail = errObj['message'].toString();
        } else if (errObj is String) {
          errorDetail = errObj;
        }
      } catch (_) {}

      throw GroqApiException(
        type: GroqApiErrorType.serverError,
        message: '接口返回异常: $errorDetail',
      );
    } on GroqApiException {
      rethrow;
    } on TimeoutException {
      throw const GroqApiException(
        type: GroqApiErrorType.timeout,
        message: '请求超时，线路可能在排队，已自动切换到备选线路。',
      );
    } catch (e) {
      throw GroqApiException(
        type: GroqApiErrorType.network,
        message: '网络请求失败: $e',
      );
    }
  }

  /// Asks the configured online tutor (OpenAI-compatible) about [sentence].
  ///
  /// The preferred model is tried first; on rate limits, timeouts or upstream
  /// jitter the next verified free line is tried, so a throttled provider
  /// never becomes a dead end. Every candidate is a zero-cost route.
  Future<String> sendOnlineChat({
    required Sentence sentence,
    required String userMessage,
    List<AiChatMessage>? history,
    String? baseUrlOverride,
    String? apiKeyOverride,
    String? modelOverride,
    Iterable<String>? fallbackModels,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final base = (baseUrlOverride?.trim().isNotEmpty ?? false)
        ? baseUrlOverride!.trim()
        : tutorBaseUrl;
    if (base.isEmpty) {
      throw const GroqApiException(
        type: GroqApiErrorType.missingEndpoint,
        message: '未配置 AI 伴学接口地址，请到设置页填写网关地址。',
      );
    }

    final key = (apiKeyOverride != null) ? apiKeyOverride.trim() : tutorApiKey;
    final preferred = (modelOverride?.trim().isNotEmpty ?? false)
        ? modelOverride!.trim()
        : tutorModel;
    if (preferred.isEmpty) {
      throw const GroqApiException(
        type: GroqApiErrorType.missingEndpoint,
        message: '未选择 AI 伴学模型，请到设置页拉取列表并选一个模型。',
      );
    }

    final endpoint =
        Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final messages = _buildTutorMessages(
      sentence: sentence,
      userMessage: userMessage,
      history: history,
    );

    final chain = <String>[preferred];
    for (final id in (fallbackModels ?? kTutorFallbackModels)) {
      if (!chain.contains(id)) chain.add(id);
    }

    GroqApiException? lastError;
    for (final model in chain) {
      try {
        return await _requestCompletion(
          endpoint: endpoint,
          apiKey: key,
          model: model,
          messages: messages,
          timeout: timeout,
        );
      } on GroqApiException catch (error) {
        // A rejected key is not a model problem — switching lines is pointless.
        if (error.type == GroqApiErrorType.invalidKey) rethrow;
        lastError = error;
      }
    }

    throw lastError ??
        const GroqApiException(
          type: GroqApiErrorType.serverError,
          message: '所有备选模型均无响应，请稍后重试。',
        );
  }

  /// 通用文本补全（AI 出题等新功能用）—— 复用伴学通道的 endpoint / key /
  /// model 配置与 fallback 链，但**不带句子上下文**（10 号 §五：题面构造
  /// 在训练层，不走伴学 persona）。
  Future<String> completeRaw(
    String userMessage, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final base = tutorBaseUrl;
    if (base.isEmpty) {
      throw const GroqApiException(
        type: GroqApiErrorType.missingEndpoint,
        message: '未配置 AI 伴学接口地址，请到设置页填写网关地址。',
      );
    }
    final preferred = tutorModel;
    if (preferred.isEmpty) {
      throw const GroqApiException(
        type: GroqApiErrorType.missingEndpoint,
        message: '未选择 AI 伴学模型，请到设置页拉取列表并选一个模型。',
      );
    }

    final endpoint =
        Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final chain = <String>[preferred, ...kTutorFallbackModels];

    GroqApiException? lastError;
    for (final model in chain) {
      try {
        return await _requestCompletion(
          endpoint: endpoint,
          apiKey: tutorApiKey,
          model: model,
          messages: [
            {'role': 'user', 'content': userMessage},
          ],
          timeout: timeout,
        );
      } on GroqApiException catch (error) {
        if (error.type == GroqApiErrorType.invalidKey) rethrow;
        lastError = error;
      }
    }
    throw lastError ??
        const GroqApiException(
          type: GroqApiErrorType.serverError,
          message: '所有备选模型均无响应，请稍后重试。',
        );
  }

  /// Legacy entry point kept for older call sites / tests.
  Future<String> sendGroqChat({
    required Sentence sentence,
    required String userMessage,
    List<AiChatMessage>? history,
    String? apiKeyOverride,
    String? modelOverride,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      sendOnlineChat(
        sentence: sentence,
        userMessage: userMessage,
        history: history,
        apiKeyOverride: apiKeyOverride,
        modelOverride: modelOverride,
        timeout: timeout,
      );
}

enum GroqApiErrorType {
  missingKey,
  missingEndpoint,
  invalidKey,
  rateLimit,
  timeout,
  network,
  serverError,
}

class GroqApiException implements Exception {
  const GroqApiException({
    required this.type,
    required this.message,
  });

  final GroqApiErrorType type;
  final String message;

  @override
  String toString() => message;
}
