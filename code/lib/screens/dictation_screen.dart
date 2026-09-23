import 'package:flutter/material.dart';

import '../l10n/ll_strings.dart';
import '../player/sentence_player_controller.dart';
import '../theme/listenloop_theme.dart';
import '../training/dictation_engine.dart';
import '../training/dictation_session.dart';

/// 听写页 —— 核心层（P1）。
///
/// 交互契约（对齐 08 定调与外部评审结论）：
///   * **句级录入、段级集中批改**：逐句写，提交本段前不显示任何原文。
///   * **留空合法**：允许显式标记「没听出来」，且不与「写错」混为一谈。
///   * **两层分离**：客观错误类型可断言；语音学原因只能提示「可能与…有关」。
///   * **对齐不可靠时降级**：只给整体结果，不伪造逐词三色标注。
///   * **不读 TTS**：只用原片句轴音频，听写考的就是真实语流。
class DictationScreen extends StatefulWidget {
  const DictationScreen({super.key, required this.controller});

  /// 复用精听页的播放控制器 —— 保证听的是同一份原声句轴。
  final SentencePlayerController controller;

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  late final DictationSession _session;
  final Map<int, TextEditingController> _inputs = {};

  @override
  void initState() {
    super.initState();
    _session = DictationSession(sentences: widget.controller.sentences);
    _session.addListener(_onChanged);
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onChanged);
    widget.controller.removeListener(_onChanged);
    for (final c in _inputs.values) {
      c.dispose();
    }
    _session.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  TextEditingController _inputFor(int offset) {
    final absolute = _session.segmentStart + offset;
    return _inputs.putIfAbsent(absolute, () {
      final controller = TextEditingController(
        text: _session.entryAt(offset).text,
      );
      return controller;
    });
  }

  /// 释放本段输入控制器。
  ///
  /// 必须延到帧后：提交/重写会同时触发重建，立即 dispose 会让仍在
  /// 树上的 TextField 拿到已释放的控制器并抛异常。
  void _clearInputs() {
    final stale = _inputs.values.toList(growable: false);
    _inputs.clear();
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in stale) {
        controller.dispose();
      }
    });
  }

  /// 播放某一句的原声（不读合成音）。
  Future<void> _play(int offset) async {
    _session.goTo(offset);
    await widget.controller.selectSentence(_session.absoluteIndex);
    await widget.controller.playCurrentSentence();
  }

  Future<void> _submit() async {
    final result = _session.submitSegment();
    if (result != null) {
      _clearInputs();
      _session.goTo(0);
    }
  }

  void _redo() {
    _session.redoSegment();
    _clearInputs();
  }

  void _goSegment(int delta) {
    if (delta > 0) {
      _session.nextSegment();
    } else {
      _session.previousSegment();
    }
    _clearInputs();
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final s = LLStrings.of(context);

    return Scaffold(
      backgroundColor: ll.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(ll, s),
            Expanded(child: _body(ll, s)),
            _footer(ll, s),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 头部

  Widget _header(LLPalette ll, LLStrings s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('dictation-back'),
            icon: Icon(Icons.arrow_back_rounded, color: ll.textPrimary, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Text(
            s.dictation,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ll.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            s.dictationSegment(
              _session.segmentIndex + 1,
              _session.segmentCount,
            ),
            style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
          ),
          const Spacer(),
          if (_session.trainingProgress > 0)
            Text(
              '${(_session.trainingProgress * 100).round()}%',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ll.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 主体

  Widget _body(LLPalette ll, LLStrings s) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      itemCount: _session.sentenceCountInSegment,
      itemBuilder: (context, offset) {
        final sentence = _session.segmentSentences[offset];
        return _session.phase == DictationPhase.entering
            ? _entryRow(ll, s, offset, sentence.english)
            : _reviewRow(ll, s, offset);
      },
    );
  }

  Widget _entryRow(LLPalette ll, LLStrings s, int offset, String _) {
    final entry = _session.entryAt(offset);
    final isCurrent = offset == _session.cursor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: ll.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrent ? ll.textPrimary : ll.divider,
            width: isCurrent ? 1.2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _play(offset),
                  child: Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline_rounded,
                        size: 16,
                        color: ll.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '#${offset + 1}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: ll.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    if (entry.markedUnknown) {
                      _session.setText(offset, _inputFor(offset).text);
                      _session.entryAt(offset).markedUnknown = false;
                      setState(() {});
                    } else {
                      _session.markUnknown(offset);
                      _inputFor(offset).clear();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: entry.markedUnknown
                          ? ll.textPrimary.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: entry.markedUnknown ? ll.textPrimary : ll.divider,
                      ),
                    ),
                    child: Text(
                      entry.markedUnknown
                          ? s.dictationClearUnknown
                          : s.dictationUnknown,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: entry.markedUnknown
                            ? ll.textPrimary
                            : ll.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: Key('dictation-input-$offset'),
              controller: _inputFor(offset),
              enabled: !entry.markedUnknown,
              maxLines: null,
              onTap: () => _session.goTo(offset),
              onChanged: (value) => _session.setText(offset, value),
              style: TextStyle(
                fontSize: 14.5,
                height: 1.35,
                color: entry.markedUnknown ? ll.textTertiary : ll.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: entry.markedUnknown ? s.dictationUnknown : s.dictationWriteHere,
                hintStyle: TextStyle(fontSize: 13.5, color: ll.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewRow(LLPalette ll, LLStrings s, int offset) {
    final line = _session.lineResultAt(offset);
    final sentence = _session.segmentSentences[offset];

    if (line == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: ll.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ll.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _play(offset),
                  child: Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline_rounded,
                        size: 16,
                        color: ll.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '#${offset + 1}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: ll.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (line.isBlank)
                  Text(
                    s.dictationBlankCount,
                    style: TextStyle(fontSize: 10.5, color: ll.textTertiary),
                  )
                else
                  Text(
                    '${(line.accuracy * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _accuracyColor(ll, line.accuracy),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (line.uncertain) ...[
              // 对齐不可靠 → 不伪造逐词诊断，只给整体结果
              Text(
                s.dictationUncertain,
                style: TextStyle(fontSize: 11, color: ll.textTertiary),
              ),
              const SizedBox(height: 6),
              _plainLine(ll, s.dictationYourAnswer, line.actualText),
              const SizedBox(height: 4),
              _plainLine(ll, s.dictationExpected, sentence.english),
            ] else ...[
              _coloredLine(ll, s.dictationExpected, line, showExpected: true),
              const SizedBox(height: 4),
              _coloredLine(ll, s.dictationYourAnswer, line, showExpected: false),
              if (line.errorCount > 0) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _errorChips(ll, s, line),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _errorChips(LLPalette ll, LLStrings s, DictationLineResult line) {
    final chips = <Widget>[];
    final counts = line.errorCounts;
    for (final type in DictationDiffType.values) {
      final count = counts[type];
      if (count == null || count == 0) continue;
      chips.add(_chip(ll, '${s.dictationDiffType(type.name)} ×$count', ll.textSecondary));
    }
    // 第二层提示：去重后展示，文案自带「可能」
    final hints = <String>{};
    for (final op in line.ops) {
      for (final hint in op.causeHints) {
        hints.add(s.dictationCause(hint.name));
      }
    }
    for (final hint in hints) {
      chips.add(_chip(ll, hint, _hintColor(ll)));
    }
    return chips;
  }

  Widget _chip(LLPalette ll, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, color: color, height: 1.2),
      ),
    );
  }

  Widget _plainLine(LLPalette ll, String label, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(fontSize: 10.5, color: ll.textTertiary),
          ),
        ),
        Expanded(
          child: Text(
            text.trim().isEmpty ? '—' : text,
            style: TextStyle(fontSize: 13, height: 1.4, color: ll.textPrimary),
          ),
        ),
      ],
    );
  }

  /// 双行三色对照：一行原文、一行用户答案，同一处错误在两行上颜色一致。
  Widget _coloredLine(
    LLPalette ll,
    String label,
    DictationLineResult line, {
    required bool showExpected,
  }) {
    final spans = <TextSpan>[];
    for (final op in line.ops) {
      final text = showExpected ? op.expected : op.actual;
      if (text == null || text.isEmpty) continue;
      final color = _opColor(ll, op, showExpected: showExpected);
      spans.add(
        TextSpan(
          text: '$text ',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: color,
            fontWeight: op.isError ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      );
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: '—', style: TextStyle(color: ll.textTertiary)));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(fontSize: 10.5, color: ll.textTertiary),
          ),
        ),
        Expanded(child: RichText(text: TextSpan(children: spans))),
      ],
    );
  }

  // ------------------------------------------------------------------ 底部

  Widget _footer(LLPalette ll, LLStrings s) {
    final entering = _session.phase == DictationPhase.entering;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: ll.bg,
        border: Border(top: BorderSide(color: ll.divider)),
      ),
      child: entering ? _enterFooter(ll, s) : _reviewFooter(ll, s),
    );
  }

  Widget _enterFooter(LLPalette ll, LLStrings s) {
    final answered = _session.answeredCount;
    final total = _session.sentenceCountInSegment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$answered / $total  ·  ${s.dictationIntro}',
                style: TextStyle(fontSize: 11, color: ll.textTertiary),
                maxLines: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _goSegment(-1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ll.textSecondary,
                  side: BorderSide(color: ll.divider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(s.dictationPrevious, style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('dictation-submit'),
                onPressed: _session.canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: ll.textPrimary,
                  foregroundColor: ll.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  s.dictationSubmit,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _session.canSubmit ? s.dictationAllAnswered : s.dictationRemaining,
          style: TextStyle(fontSize: 10.5, color: ll.textTertiary),
        ),
      ],
    );
  }

  Widget _reviewFooter(LLPalette ll, LLStrings s) {
    final result = _session.currentResult!;
    final counts = result.errorCounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${s.dictationAccuracy} ${(result.accuracy * 100).round()}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _accuracyColor(ll, result.accuracy),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${s.dictationBlankCount} ${result.blankLines}',
              style: TextStyle(fontSize: 11.5, color: ll.textTertiary),
            ),
            const SizedBox(width: 12),
            if (counts.isNotEmpty)
              Text(
                counts.entries
                    .map((e) => '${s.dictationDiffType(e.key.name)}×${e.value}')
                    .join('  '),
                style: TextStyle(fontSize: 11, color: ll.textSecondary),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('dictation-redo'),
                onPressed: _redo,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ll.textSecondary,
                  side: BorderSide(color: ll.divider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(s.dictationRewrite, style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('dictation-next-segment'),
                onPressed: _session.hasNextSegment
                    ? () => _goSegment(1)
                    : () => Navigator.of(context).maybePop(),
                style: FilledButton.styleFrom(
                  backgroundColor: ll.textPrimary,
                  foregroundColor: ll.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  _session.hasNextSegment ? s.dictationNextSegment : s.done,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ 配色

  Color _errorColor(LLPalette ll) =>
      ll.brightness == Brightness.dark
      ? const Color(0xFFFF7B72)
      : const Color(0xFFC0392B);

  Color _extraColor(LLPalette ll) =>
      ll.brightness == Brightness.dark
      ? const Color(0xFF79C0FF)
      : const Color(0xFF1F6FEB);

  Color _nearColor(LLPalette ll) =>
      ll.brightness == Brightness.dark
      ? const Color(0xFFF0B95E)
      : const Color(0xFFB77A11);

  Color _hintColor(LLPalette ll) => ll.textSecondary;

  Color _accuracyColor(LLPalette ll, double accuracy) {
    if (accuracy >= 0.95) return ll.textPrimary;
    if (accuracy >= 0.7) return _nearColor(ll);
    return _errorColor(ll);
  }

  Color _opColor(LLPalette ll, DictationOp op, {required bool showExpected}) {
    if (!op.isError) return ll.textSecondary;
    switch (op.type) {
      case DictationDiffType.missing:
        return showExpected ? _errorColor(ll) : ll.textTertiary;
      case DictationDiffType.extra:
        return showExpected ? ll.textTertiary : _extraColor(ll);
      default:
        return _nearColor(ll);
    }
  }
}
