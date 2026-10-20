import 'package:flutter/material.dart';

import '../data/ai_governor_service.dart';
import '../l10n/ll_strings.dart';
import '../models/sentence.dart';
import '../theme/listenloop_theme.dart';
import '../widgets/ll_page.dart';

/// Meaning Recall（15 号 Phase A 第一优先）。
///
/// 科学依据：Swain 输出假设 —— 听写是 audio → orthography（听力诊断器），
/// Meaning Recall 是 meaning → language（真正的 productive output）。
///
/// 流程：显示中文释义（原句隐藏）→ 用户用英语表达意思 →
/// AI 对比原句给结构化反馈（AI 不可用 → 静态自比兜底）→ 用户可修正输出。
///
/// 架构红线：AI 不可用时显示原句自比，复习流程不断。
class MeaningRecallScreen extends StatefulWidget {
  const MeaningRecallScreen({
    super.key,
    required this.sentence,
    this.governor,
  });

  final Sentence sentence;
  final AiGovernorService? governor;

  @override
  State<MeaningRecallScreen> createState() => _MeaningRecallScreenState();
}

class _MeaningRecallScreenState extends State<MeaningRecallScreen> {
  final _controller = TextEditingController();
  bool _submitted = false;
  bool _loadingAi = false;
  bool _aiFailed = false;
  String? _aiFeedback;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final expr = _controller.text.trim();
    if (expr.isEmpty) return;
    setState(() => _submitted = true);

    if (widget.governor == null) return; // 静态兜底：直接显示原句

    setState(() => _loadingAi = true);
    try {
      final result = await widget.governor!.sendOnlineChat(
        sentence: widget.sentence,
        userMessage:
            '原句：${widget.sentence.english}\n'
            '用户的表达：$expr\n\n'
            '请对比用户的表达与原句，给出结构化反馈：\n'
            '1. 意思是否表达到位（yes/partially/no）\n'
            '2. 具体语法或词汇改进建议\n'
            '3. 一个更自然的版本\n'
            '用中文回答，简洁。',
      );
      if (mounted) setState(() => _aiFeedback = result);
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
    final hasGov = widget.governor != null;

    return LLPage(
      title: Text(s.mrTitle,
          style: TextStyle(fontSize: 16, color: ll.textPrimary)),
      leading: BackButton(color: ll.textSecondary),
      body: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

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
            child: Text(widget.sentence.chinese,
                style: TextStyle(
                    fontSize: 14,
                    color: ll.textPrimary,
                    height: 1.5)),
          ),

          const SizedBox(height: 16),
          Text(s.mrPrompt,
              style: TextStyle(fontSize: 12, color: ll.textTertiary)),
          const SizedBox(height: 8),

          // 输入框
          TextField(
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
                      child: CircularProgressIndicator(strokeWidth: 2))
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
          ],

          // 静态兜底：AI 不可用 / AI 失败 → 显示原句自比
          if (_submitted && (!hasGov || _aiFailed)) ...[
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
                  Text(widget.sentence.english,
                      style: TextStyle(
                          fontSize: 14, color: ll.textPrimary)),
                ],
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    )
    );
  }
}
