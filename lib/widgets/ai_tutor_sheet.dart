import 'dart:async';
import 'package:flutter/material.dart';

import '../data/ai_governor_service.dart';
import '../models/ai_governor_model.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../preferences/app_preferences.dart';
import 'll_brand.dart';

/// Modal bottom sheet for AI Governor:
/// 1. 3-Minute Quick Quiz (尚雯婕限时特训法)
/// 2. Contextual AI Learning Tutor discussion.
class AiTutorSheet extends StatefulWidget {
  const AiTutorSheet({
    super.key,
    required this.lesson,
    required this.currentSentenceIndex,
    required this.sentences,
    required this.aiGovernorService,
    required this.onSeekToSentence,
  });

  final Lesson lesson;
  final int currentSentenceIndex;
  final List<Sentence> sentences;
  final AiGovernorService aiGovernorService;
  final void Function(int sentenceIndex) onSeekToSentence;

  static Future<void> show({
    required BuildContext context,
    required Lesson lesson,
    required int currentSentenceIndex,
    required List<Sentence> sentences,
    required AiGovernorService aiGovernorService,
    required void Function(int sentenceIndex) onSeekToSentence,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF141414) : const Color(0xFFF9F9F8);

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => AiTutorSheet(
        lesson: lesson,
        currentSentenceIndex: currentSentenceIndex,
        sentences: sentences,
        aiGovernorService: aiGovernorService,
        onSeekToSentence: onSeekToSentence,
      ),
    );
  }

  @override
  State<AiTutorSheet> createState() => _AiTutorSheetState();
}

class _AiTutorSheetState extends State<AiTutorSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Quiz state
  late List<QuizQuestion> _questions;
  int _currentQuestionIndex = 0;
  int? _selectedOptionIndex;
  bool _answered = false;
  int _correctCount = 0;
  bool _quizFinished = false;

  // 3-Minute Timer (尚雯婕限时法)
  Timer? _timer;
  int _secondsRemaining = 180; // 3 minutes

  // Chat state
  final List<AiChatMessage> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _questions = widget.aiGovernorService.generateQuizQuestions(
      lesson: widget.lesson,
      currentSentenceIndex: widget.currentSentenceIndex,
      sentences: widget.sentences,
    );

    _startTimer();

    // Initial AI Tutor greeting
    final curSentence = _getCurrentSentence();
    _chatMessages.add(
      AiChatMessage(
        id: 'msg_0',
        role: 'assistant',
        content: '你好！我是你的 AI 精听管家。\n'
            '当前我们正在学习第 ${widget.currentSentenceIndex + 1} 句：\n'
            '「${curSentence.english}」\n'
            '你可以点击下方快捷分析卡片，或直接向我提问关于发音、文化背景或语法细节。',
        timestamp: DateTime.now(),
        relatedSentenceIndex: widget.currentSentenceIndex,
      ),
    );
  }

  Sentence _getCurrentSentence() {
    final idx = widget.currentSentenceIndex.clamp(0, widget.sentences.length - 1);
    return widget.sentences[idx];
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timer?.cancel();
        setState(() => _quizFinished = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabController.dispose();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onSelectOption(int index) {
    if (_answered || _quizFinished) return;

    final question = _questions[_currentQuestionIndex];
    final isCorrect = index == question.correctIndex;

    setState(() {
      _selectedOptionIndex = index;
      _answered = true;
      if (isCorrect) {
        _correctCount++;
      } else {
        // Record weakness
        final sentence = widget.sentences[question.sentenceIndex];
        widget.aiGovernorService.recordWeakness(
          WeaknessRecord(
            id: 'weak_${question.id}_${DateTime.now().millisecondsSinceEpoch}',
            lessonId: widget.lesson.id,
            lessonTitle: widget.lesson.title,
            sentenceIndex: question.sentenceIndex,
            sentenceText: sentence.english,
            chineseTranslation: sentence.chinese,
            startMs: sentence.startMs,
            endMs: sentence.endMs,
            reason: '${question.category.label}测试错误：选了「${question.options[index]}」',
            timestamp: DateTime.now(),
          ),
        );
      }
    });
  }

  void _nextQuestion() {
    if (_currentQuestionIndex + 1 < _questions.length) {
      setState(() {
        _currentQuestionIndex++;
        _selectedOptionIndex = null;
        _answered = false;
      });
    } else {
      setState(() {
        _quizFinished = true;
      });
    }
  }

  void _restartQuiz() {
    setState(() {
      _questions = widget.aiGovernorService.generateQuizQuestions(
        lesson: widget.lesson,
        currentSentenceIndex: widget.currentSentenceIndex,
        sentences: widget.sentences,
      );
      _currentQuestionIndex = 0;
      _selectedOptionIndex = null;
      _answered = false;
      _correctCount = 0;
      _quizFinished = false;
      _secondsRemaining = 180;
    });
    _startTimer();
  }

  Future<void> _showTutorConfigDialog() async {
    final service = widget.aiGovernorService;
    final baseUrlController = TextEditingController(text: service.tutorBaseUrl);
    final keyController = TextEditingController(text: service.tutorApiKey);
    final modelController = TextEditingController(text: service.tutorModel);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, size: 20),
            SizedBox(width: 8),
            Text('AI 伴学 · 在线通道', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '默认走本机 :3100 网关的免费线路，失败会自动切换备选线路并给出离线兜底。',
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: baseUrlController,
                style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: '网关地址 (含 /v1)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyController,
                obscureText: true,
                style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Bearer 密钥',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: modelController,
                style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: '模型',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '失败自动回退：${kTutorFallbackModels.join(' · ')}',
                style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await service.setTutorBaseUrl(kDefaultTutorBaseUrl);
              await service.setTutorApiKey(kDefaultTutorApiKey);
              await service.setTutorModel(kDefaultTutorModel);
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('恢复默认', style: TextStyle(fontSize: 12.5)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await service.setTutorBaseUrl(baseUrlController.text);
              await service.setTutorApiKey(keyController.text);
              await service.setTutorModel(modelController.text);
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUserChat(String userText, {String? promptType}) async {
    if (userText.trim().isEmpty) return;

    // 已配置在线通道 → 直接走真实大模型；失败时气泡内自带离线兜底按钮。
    if (widget.aiGovernorService.hasTutorEndpoint) {
      await _executeOnlineChat(userText);
      return;
    }

    _executeOfflineChat(userText, promptType: promptType);
  }


  void _sendChatPrompt(String promptType) {
    final userText = switch (promptType) {
      'grammar' => '✨ 请深度解析这句的语法结构与文化背景',
      'phonetics' => '🎧 请分析原声的连读、弱读与发音技巧',
      'examples' => '💡 给我举 2 个日常使用例句',
      _ => '请解析当前句子',
    };
    _handleUserChat(userText, promptType: promptType);
  }

  void _sendCustomChatMessage() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty) return;
    _chatInputController.clear();
    _handleUserChat(text);
  }

  void _executeOfflineChat(String userText, {String? promptType}) {
    final curSentence = _getCurrentSentence();
    final insight = widget.aiGovernorService.generateOfflineReply(
      sentence: curSentence,
      userMessage: userText,
      promptType: promptType,
    );

    setState(() {
      _chatMessages.add(
        AiChatMessage(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          role: 'user',
          content: userText,
          timestamp: DateTime.now(),
        ),
      );
      _chatMessages.add(
        AiChatMessage(
          id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: insight,
          timestamp: DateTime.now(),
        ),
      );
    });

    _scrollChatToBottom();
  }

  /// Returns true when the online line actually answered.
  Future<bool> _executeOnlineChat(String userText) async {
    final curSentence = _getCurrentSentence();
    final userMsgId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final aiMsgId = 'ai_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _chatMessages.add(
        AiChatMessage(
          id: userMsgId,
          role: 'user',
          content: userText,
          timestamp: DateTime.now(),
        ),
      );
      _chatMessages.add(
        AiChatMessage(
          id: aiMsgId,
          role: 'assistant',
          content: '',
          timestamp: DateTime.now(),
          isLoading: true,
        ),
      );
    });

    _scrollChatToBottom();

    try {
      final reply = await widget.aiGovernorService.sendOnlineChat(
        sentence: curSentence,
        userMessage: userText,
        history: _chatMessages,
      );

      if (!mounted) return true;
      setState(() {
        final idx = _chatMessages.indexWhere((m) => m.id == aiMsgId);
        if (idx >= 0) {
          _chatMessages[idx] = _chatMessages[idx].copyWith(
            content: reply,
            isLoading: false,
          );
        }
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        final idx = _chatMessages.indexWhere((m) => m.id == aiMsgId);
        if (idx >= 0) {
          _chatMessages[idx] = _chatMessages[idx].copyWith(
            content: '【在线伴学异常】\n${e.toString()}\n\n'
                '已自动保留离线兜底方案，点下方「离线解析」即可继续。',
            isLoading: false,
            isError: true,
          );
        }
      });
      return false;
    } finally {
      _scrollChatToBottom();
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? Colors.white : Colors.black;
    final secondaryColor = isDark ? Colors.white70 : Colors.black87;
    final tertiaryColor = isDark ? Colors.white38 : Colors.black45;
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final dividerColor = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E5E5);

    final height = MediaQuery.of(context).size.height * 0.85;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: tertiaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header with tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const LLMark(size: 16),
                const SizedBox(width: 8),
                Text(
                  'AI 智能管家',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: tertiaryColor, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: primaryColor,
              indicatorWeight: 2,
              labelColor: primaryColor,
              unselectedLabelColor: tertiaryColor,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: '3分钟快测'),
                Tab(text: 'AI 伴学讨论'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildQuizView(
                  primaryColor: primaryColor,
                  secondaryColor: secondaryColor,
                  tertiaryColor: tertiaryColor,
                  surfaceColor: surfaceColor,
                  dividerColor: dividerColor,
                ),
                _buildChatView(
                  primaryColor: primaryColor,
                  secondaryColor: secondaryColor,
                  tertiaryColor: tertiaryColor,
                  surfaceColor: surfaceColor,
                  dividerColor: dividerColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizView({
    required Color primaryColor,
    required Color secondaryColor,
    required Color tertiaryColor,
    required Color surfaceColor,
    required Color dividerColor,
  }) {
    if (_questions.isEmpty) {
      return Center(
        child: Text('当前课程暂无测试题目', style: TextStyle(color: tertiaryColor)),
      );
    }

    if (_quizFinished) {
      return _buildQuizSummary(
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        tertiaryColor: tertiaryColor,
        surfaceColor: surfaceColor,
        dividerColor: dividerColor,
      );
    }

    final question = _questions[_currentQuestionIndex];
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    final timeStr =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timer and Progress bar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _secondsRemaining < 30
                      ? Colors.red.withValues(alpha: 0.15)
                      : surfaceColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _secondsRemaining < 30
                        ? Colors.redAccent
                        : dividerColor,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.alarm,
                      size: 14,
                      color: _secondsRemaining < 30
                          ? Colors.redAccent
                          : secondaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: _secondsRemaining < 30
                            ? Colors.redAccent
                            : primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '第 ${_currentQuestionIndex + 1} / ${_questions.length} 题',
                style: TextStyle(
                  fontSize: 12,
                  color: tertiaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Question Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dividerColor, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    question.category.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  question.question,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Options
          for (var i = 0; i < question.options.length; i++) ...[
            _buildOptionTile(
              index: i,
              optionText: question.options[i],
              question: question,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              surfaceColor: surfaceColor,
              dividerColor: dividerColor,
            ),
            const SizedBox(height: 10),
          ],

          // Explanation box when answered
          if (_answered) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _selectedOptionIndex == question.correctIndex
                    ? Colors.green.withValues(alpha: 0.08)
                    : Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _selectedOptionIndex == question.correctIndex
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _selectedOptionIndex == question.correctIndex
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        size: 16,
                        color: _selectedOptionIndex == question.correctIndex
                            ? Colors.green
                            : Colors.redAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedOptionIndex == question.correctIndex
                            ? '回答正确！'
                            : '已记录为薄弱点',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _selectedOptionIndex == question.correctIndex
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                      ),
                      const Spacer(),
                      // Jump to sentence audio
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.volume_up, size: 14),
                        label: const Text('重听原声', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          widget.onSeekToSentence(question.sentenceIndex);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已跳转到该句原声重听'),
                              duration: Duration(milliseconds: 1200),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    question.explanation,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: secondaryColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.black
                          : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _nextQuestion,
                child: Text(
                  _currentQuestionIndex + 1 < _questions.length
                      ? '下一题 →'
                      : '查看测试报告',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required int index,
    required String optionText,
    required QuizQuestion question,
    required Color primaryColor,
    required Color secondaryColor,
    required Color surfaceColor,
    required Color dividerColor,
  }) {
    Color borderColor = dividerColor;
    Color tileBg = surfaceColor;
    Widget? trailingIcon;

    if (_answered) {
      if (index == question.correctIndex) {
        borderColor = Colors.green;
        tileBg = Colors.green.withValues(alpha: 0.08);
        trailingIcon =
            const Icon(Icons.check_circle, color: Colors.green, size: 18);
      } else if (index == _selectedOptionIndex) {
        borderColor = Colors.redAccent;
        tileBg = Colors.redAccent.withValues(alpha: 0.08);
        trailingIcon =
            const Icon(Icons.cancel, color: Colors.redAccent, size: 18);
      }
    }

    final optionLetters = ['A', 'B', 'C', 'D'];
    final letter = index < optionLetters.length ? optionLetters[index] : '';

    return InkWell(
      onTap: () => _onSelectOption(index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: secondaryColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: secondaryColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                optionText,
                style: TextStyle(
                  fontSize: 13.5,
                  color: primaryColor,
                  height: 1.3,
                ),
              ),
            ),
            ?trailingIcon,
          ],
        ),
      ),
    );
  }

  Widget _buildQuizSummary({
    required Color primaryColor,
    required Color secondaryColor,
    required Color tertiaryColor,
    required Color surfaceColor,
    required Color dividerColor,
  }) {
    final accuracy = (_correctCount / _questions.length * 100).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            accuracy >= 80 ? Icons.emoji_events_outlined : Icons.track_changes,
            size: 56,
            color: primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            '3分钟限时快测完成！',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '正确率：$accuracy%  ($_correctCount / ${_questions.length})',
            style: TextStyle(
              fontSize: 14,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            accuracy >= 80
                ? '太棒了！听觉敏锐度与语境推断极佳，请继续保持。'
                : '已将本次测验中的薄弱点自动归档至「今日弱点」，可在首页一键针对性重听。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: tertiaryColor,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: dividerColor),
                  ),
                  onPressed: _restartQuiz,
                  child: Text('重新挑战', style: TextStyle(color: primaryColor)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.black
                            : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成并返回'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatView({
    required Color primaryColor,
    required Color secondaryColor,
    required Color tertiaryColor,
    required Color surfaceColor,
    required Color dividerColor,
  }) {
    final curSentence = _getCurrentSentence();
    final online = widget.aiGovernorService.hasTutorEndpoint;

    return Column(
      children: [
        // Sentence context card
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: dividerColor, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '当前讨论焦点 · 第 ${widget.currentSentenceIndex + 1} 句',
                    style: TextStyle(
                      fontSize: 11,
                      color: tertiaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () =>
                        widget.onSeekToSentence(widget.currentSentenceIndex),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.volume_up, size: 14, color: primaryColor),
                        const SizedBox(width: 4),
                        Text('播放原声',
                            style: TextStyle(
                                fontSize: 11, color: primaryColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                curSentence.english,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              if (curSentence.chinese.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  curSentence.chinese,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                ),
              ],
            ],
          ),
        ),

        // AI Tutor Status Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: dividerColor, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: online
                            ? const Color(0xFF10B981)
                            : Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      online
                          ? '在线 · ${widget.aiGovernorService.tutorModel}'
                          : 'AI 伴学 · 离线智能模式',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (online)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(Icons.tune, size: 13, color: secondaryColor),
                  label: Text(
                    '管理',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: secondaryColor,
                    ),
                  ),
                  onPressed: () => _showTutorConfigDialog(),
                ),
            ],
          ),
        ),


        const SizedBox(height: 4),

        // Quick prompt chips
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _buildPromptChip(
                label: '✨ 语法与文化背景',
                onTap: () => _sendChatPrompt('grammar'),
                surfaceColor: surfaceColor,
                dividerColor: dividerColor,
                primaryColor: primaryColor,
              ),
              const SizedBox(width: 8),
              _buildPromptChip(
                label: '🎧 连读与弱读技巧',
                onTap: () => _sendChatPrompt('phonetics'),
                surfaceColor: surfaceColor,
                dividerColor: dividerColor,
                primaryColor: primaryColor,
              ),
              const SizedBox(width: 8),
              _buildPromptChip(
                label: '💡 2个日常例句',
                onTap: () => _sendChatPrompt('examples'),
                surfaceColor: surfaceColor,
                dividerColor: dividerColor,
                primaryColor: primaryColor,
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Chat message list
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            itemCount: _chatMessages.length,
            itemBuilder: (ctx, i) {
              final msg = _chatMessages[i];
              return _buildChatBubble(
                msg: msg,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                tertiaryColor: tertiaryColor,
                surfaceColor: surfaceColor,
                dividerColor: dividerColor,
              );
            },
          ),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: surfaceColor,
            border: Border(top: BorderSide(color: dividerColor, width: 1)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatInputController,
                    style: TextStyle(fontSize: 13.5, color: primaryColor),
                    decoration: InputDecoration(
                      hintText: '向 AI 管家提问当前句子...',
                      hintStyle: TextStyle(fontSize: 13, color: tertiaryColor),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                    onSubmitted: (_) => _sendCustomChatMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_upward_rounded,
                      color: primaryColor, size: 20),
                  onPressed: _sendCustomChatMessage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPromptChip({
    required String label,
    required VoidCallback onTap,
    required Color surfaceColor,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    return ActionChip(
      label: Text(label, style: TextStyle(fontSize: 11.5, color: primaryColor)),
      backgroundColor: surfaceColor,
      side: BorderSide(color: dividerColor, width: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: onTap,
    );
  }

  Widget _buildChatBubble({
    required AiChatMessage msg,
    required Color primaryColor,
    required Color secondaryColor,
    required Color tertiaryColor,
    required Color surfaceColor,
    required Color dividerColor,
  }) {
    final isUser = msg.isUser;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(right: 8, top: 2),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: surfaceColor,
                shape: BoxShape.circle,
                border: Border.all(color: dividerColor),
              ),
              child: const LLMark(size: 14),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? primaryColor.withValues(alpha: 0.12)
                    : (msg.isError
                        ? Colors.redAccent.withValues(alpha: 0.08)
                        : surfaceColor),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: msg.isError
                      ? Colors.redAccent.withValues(alpha: 0.3)
                      : dividerColor,
                  width: 0.8,
                ),
              ),
              child: msg.isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "${widget.aiGovernorService.tutorModel} 正在思考…",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            color: tertiaryColor,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          msg.content,
                          style: TextStyle(
                            fontSize: 13,
                            color: msg.isError ? Colors.redAccent : primaryColor,
                            height: 1.45,
                          ),
                        ),
                        if (msg.isError) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.key, size: 12),
                                label: const Text('配置 Key',
                                    style: TextStyle(fontSize: 11.5)),
                                onPressed: () => _showTutorConfigDialog(),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.refresh, size: 12),
                                label: const Text('离线解析',
                                    style: TextStyle(fontSize: 11.5)),
                                onPressed: () => _executeOfflineChat(
                                    '请解析当前句子'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, size: 14, color: primaryColor),
            ),
          ],
        ],
      ),
    );
  }
}
