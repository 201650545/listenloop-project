import 'package:flutter/material.dart';

import '../data/ai_governor_service.dart';
import '../l10n/ll_strings.dart';
import '../models/sentence.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_page.dart';

/// 听写完成流入口 —— 错句队列版「意思回忆」。
///
/// 定位：听写批改出「有错且对齐可靠」的行后，直接在这里做 productive
/// output（meaning → language）。它复用 [MeaningRecallScreen] 的 AI 反馈
/// 链路（经 [AiGovernorService.sendOnlineChat]），只是把单句改成队列。
///
/// 数据契约（对齐听写批改的红线）：
///   * 只接收「有错且 `uncertain == false`」的行 —— 留空句（合法答案）与
///     对齐不可靠的行**不进入本页**，它们在听写里回原声重听。
///   * 队列按句去重、按课内顺序排列；不会因某一段反复重写而堆积。
///
/// 架构红线：AI 不可用时显示原句自比，复习流程不断（与 Meaning Recall 一致）。
class MeaningRecallDrillScreen extends StatefulWidget {
  const MeaningRecallDrillScreen({
    super.key,
    required this.sentences,
    this.governor,
    this.initialIndex = 0,
  })  : assert(sentences.length > 0, 'sentences must not be empty'),
        assert(
          initialIndex >= 0 && initialIndex < sentences.length,
          'initialIndex out of range',
        );

  /// 待打磨的错句（课内顺序、已去重）。
  final List<Sentence> sentences;

  /// AI Governor（可选）。为空则整页走静态自比兜底。
  final AiGovernorService? governor;

  /// 初始定位到哪一句。
  final int initialIndex;

  @override
  State<MeaningRecallDrillScreen> createState() =>
      _MeaningRecallDrillScreenState();
}

class _MeaningRecallDrillScreenState extends State<MeaningRecallDrillScreen> {
  late final TextEditingController _controller;
  late int _index;

  bool _submitted = false;
  bool _loadingAi = false;
  bool _aiFailed = false;
  String? _aiFeedback;

  /// modified output（v0.9.1）： guided retry 只允许 1 次。
  /// 15 号 pushed-output loop：output → gap → feedback → **modified output**。
  bool _retryUsed = false;
  bool _showReference = false;

  /// AI 反馈清洗（v0.9.1 · 轻量）：governor 常返回 Markdown 记号
  /// （`#`/`##`/`**`/`*`/反引号），当前无富文本渲染器——剥掉记号保留纯文本，
  /// 不做完整 renderer（17 号控范围决策）。
  static String _stripMarkdown(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    s = s.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(
        RegExp(r'(?<!\*)\*([^*\n]+)\*(?!\*)'), (m) => m.group(1) ?? '');
    s = s.replaceAll('`', '');
    s = s.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '· ');
    return s.trim();
  }

  Sentence get _sentence => widget.sentences[_index];
  bool get _hasGovernor => widget.governor != null;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 跳到指定句，并清掉上一次的输入与反馈状态。
  void _goTo(int index) {
    setState(() {
      _index = index;
      _controller.clear();
      _submitted = false;
      _aiFeedback = null;
      _aiFailed = false;
      _loadingAi = false;
      _retryUsed = false;
      _showReference = false;
    });
  }

  Future<void> _onSubmit() async {
    final expr = _controller.text.trim();
    if (expr.isEmpty) return;
    setState(() => _submitted = true);

    if (!_hasGovernor) return; // 静态兜底：直接显示原句

    setState(() => _loadingAi = true);
    try {
      final result = await widget.governor!.sendOnlineChat(
        sentence: _sentence,
        userMessage:
            '原句：${_sentence.english}\n'
            '用户的表达：$expr\n\n'
            '请对比用户的表达与原句，给出结构化反馈：\n'
            '1. 意思是否表达到位（yes/partially/no）\n'
            '2. 具体语法或词汇改进建议\n'
            '3. 一个更自然的版本\n'
            '用中文回答，简洁。',
      );
      if (mounted) {
        setState(() => _aiFeedback = _stripMarkdown(result));
      }
    } catch (_) {
      if (mounted) setState(() => _aiFailed = true);
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);
    final total = widget.sentences.length;

    return LLPage(
      title: Text(s.mrDrillTitle,
          style: TextStyle(fontSize: 16, color: ll.textPrimary)),
      leading: BackButton(color: ll.textSecondary),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        s.mrDrillCount(_index + 1, total),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ll.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          s.mrDrillHint,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 10.5, color: ll.textTertiary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── 中文释义 ──
                  Text(s.mrPromptTitle,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ll.textPrimary)),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ll.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ll.divider),
                    ),
                    child: Text(_sentence.chinese,
                        style: TextStyle(
                            fontSize: 14,
                            color: ll.textPrimary,
                            height: 1.5)),
                  ),

                  const SizedBox(height: 16),
                  Text(s.mrPrompt,
                      style: TextStyle(
                          fontSize: 12, color: ll.textTertiary)),
                  const SizedBox(height: 8),

                  // 输入框
                  TextField(
                    key: Key('drill-input'),
                    controller: _controller,
                    maxLines: 3,
                    style: TextStyle(fontSize: 15, color: ll.textPrimary),
                    decoration: InputDecoration(
                      hintText: s.mrHint,
                      hintStyle:
                          TextStyle(color: ll.textTertiary, fontSize: 13),
                      filled: true,
                      fillColor: ll.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: ll.divider),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 提交按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const Key('drill-submit'),
                      onPressed: _loadingAi ? null : _onSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ll.textPrimary,
                        foregroundColor: ll.bg,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loadingAi
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : Text(s.mrSubmit,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: ll.bg)),
                    ),
                  ),

                  // ── AI 反馈 ──
                  if (_aiFeedback != null && _aiFeedback!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ll.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ll.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.mrFeedbackTitle,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ll.textPrimary)),
                          const SizedBox(height: 8),
                          Text(_aiFeedback!,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: ll.textSecondary,
                                  height: 1.5)),
                        ],
                      ),
                    ),

                    // ── modified output（v0.9.1）：反馈后再答一次 ──
                    // 15 号 pushed-output loop 的最后一步。guided retry
                    // 只允许 1 次；第二次提交后无论结果允许下一句。
                    if (!_retryUsed) ...[
                      const SizedBox(height: 10),
                      Text(s.mrRetryPrompt,
                          style: TextStyle(
                              fontSize: 12, color: ll.textTertiary)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('drill-retry'),
                          onPressed: _loadingAi
                              ? null
                              : () {
                                  setState(() {
                                    _retryUsed = true;
                                    _submitted = false;
                                    _aiFeedback = null;
                                    _controller.clear();
                                  });
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: ll.textPrimary,
                            foregroundColor: ll.onPrimary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.replay_rounded, size: 16),
                          label: Text(s.mrRetryButton,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // 看参考表达（secondary）—— 不打断，按需展开
                    TextButton(
                      key: const Key('drill-reference'),
                      onPressed: () =>
                          setState(() => _showReference = !_showReference),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                      ),
                      child: Text(
                        _showReference
                            ? _sentence.english
                            : s.mrSeeReference,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _showReference
                              ? ll.textPrimary
                              : ll.textSecondary,
                        ),
                      ),
                    ),
                  ],

                  // 已用掉 guided retry：提交后无论结果允许下一句。
                  // 独立于反馈卡显示（retry 后反馈被清空，本提示仍可见）。
                  if (_retryUsed && _submitted) ...[
                    const SizedBox(height: 8),
                    Text(s.mrRetryUsed,
                        style: TextStyle(
                            fontSize: 11, color: ll.textTertiary)),
                  ],

                  // 静态兜底：AI 不可用 / AI 失败 → 显示原句自比
                  if (_submitted && (!_hasGovernor || _aiFailed)) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ll.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ll.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.mrOriginalLabel,
                              style: TextStyle(
                                  fontSize: 11, color: ll.textTertiary)),
                          const SizedBox(height: 4),
                          Text(_sentence.english,
                              style: TextStyle(
                                  fontSize: 14, color: ll.textPrimary)),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // ── 底部：队列导航 ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: ll.bg,
              border: Border(top: BorderSide(color: ll.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('drill-prev'),
                    onPressed:
                        _index > 0 ? () => _goTo(_index - 1) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ll.textSecondary,
                      side: BorderSide(color: ll.divider),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(s.mrDrillPrev,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('drill-next'),
                    onPressed: _index < total - 1
                        ? () => _goTo(_index + 1)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ll.textSecondary,
                      side: BorderSide(color: ll.divider),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(s.mrDrillNext,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const Key('drill-done'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: ll.textPrimary,
                      foregroundColor: ll.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      s.mrDrillDone,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}