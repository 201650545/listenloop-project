import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sentence.dart';
import '../player/sentence_player_controller.dart';
import '../theme/listenloop_theme.dart';
import '../training/dictation_engine.dart';
import '../training/read_along_drill.dart';
import '../training/read_along_recorder.dart';
import '../training/read_along_session.dart';
import '../training/read_along_speaker.dart';
import 'll_pill_button.dart';

/// 跟读验收面板（WP-H 阶段 3：录音态 / 结果态 UI，方案 §六.2 + §七）。
///
/// 本文件是「会话的驾驶舱」：句末门触发一次 [startAttempt]，此后
/// 录音 → 判分 → 分支（过关进下一句 / 不过原声重播 / 三次三选）全部
/// 在这里闭环。四风格适配纪律（方案 §七）：
///   * 录音脉冲圈：底 `ll.accent`、扩散 `ll.accent.withValues(alpha: 0.15)`；
///   * 判定色：对 `ll.success`、漏 `ll.warning`、错 `ll.danger`；
///   * 卡片底 `ll.surface`、描边 `ll.divider` 宽 `context.llShape.hairline`；
///   * 动画只走 `LLMotion.fast` / `LLMotion.normal`，不用 slow；
///   * 排版只走 `LLText` 阶梯，间距圆角只走 `LLSpacing` / `LLRadius` /
///     `LLShape`——全文件没有一处字面色、没有一处裸 fontSize。
class LlReadAlongSheet extends StatefulWidget {
  const LlReadAlongSheet({
    super.key,
    required this.session,
    required this.recorder,
    required this.controller,
    required this.expectedTextOf,
    required this.onExit,
    this.speaker,
    this.autoStartAttempt = false,
    this.attemptMaxDurationMs = 0,
  });

  final ReadAlongSession session;
  final ReadAlongRecorder recorder;
  final SentencePlayerController controller;

  /// 判定期望文本：中文课取 `Sentence.chinese`（方案 §九.4 雷区）。
  final String Function(Sentence sentence) expectedTextOf;

  final VoidCallback onExit;

  /// 纠错播报器（默认系统 TTS；测试注入假后端）。
  final ReadAlongSpeaker? speaker;

  /// 打开时立即开始一次收音（句末门刚触发）。
  final bool autoStartAttempt;

  /// 本次收音的兜底上限（毫秒），0 = 按当前句时长推导。
  final int attemptMaxDurationMs;

  @override
  State<LlReadAlongSheet> createState() => LlReadAlongSheetState();
}

/// 面板视图。最小形态（2026-10-16 郭老师拍板）：
///   等听 → 在录 → 判分中 → 结果 / 单字练习
/// 砍掉了：分数、满星、第 N 次、逐字对照折叠、边读边显示、语音纠错播报。
enum _ReadAlongView {
  listening,
  recording,
  scoring,
  /// 单字练习中：没读准的字单独、很大地列出，附拼音。
  drilling,
  passed,
  retry,
  unclear,
  silent,
  micFailed,
  degraded,
  done,
}

class LlReadAlongSheetState extends State<LlReadAlongSheet>
    with SingleTickerProviderStateMixin {
  _ReadAlongView _view = _ReadAlongView.listening;
  double _level = 0;
  ReadAlongResult? _result;

  /// 错字练习队列（跨整句重读存活，换句时 reset）。
  final ReadAlongDrill _drill = ReadAlongDrill();

  /// 单字练习这一遍的判定（null = 还没判）。
  DrillVerdict? _drillVerdict;

  /// 边说边判：最新一拍解出的进度（纯展示 + 提前收尾依据，终判仍走完整 wav）。
  LiveProgress _live = LiveProgress.empty;

  /// 快照节拍器：录音途中每 [ _liveInterval ] 解一次已采集音频。
  Timer? _liveTimer;

  /// 串行 guard：上一拍还没解完就不启动下一拍，防解码堆积。
  bool _liveBusy = false;

  /// 快照是否已停（读完/退出/重听时置 true）。
  bool _liveStopped = true;

  /// 快照节拍。真机离线解码一次约 1~2 秒（含模型首次加载），
  /// 2 秒一拍 + 串行 guard，刚好错开不堆积。
  static const Duration _liveInterval = Duration(seconds: 2);

  Object? _micError;

  StreamSubscription<ReadAlongRecorderEvent>? _recorderSub;
  late final AnimationController _pulse;
  late final ReadAlongSpeaker _speaker;

  @override
  void initState() {
    super.initState();
    _speaker = widget.speaker ?? ReadAlongSpeaker();
    // 呼吸脉冲：fast 起、normal 循环（方案 §七），别用 slow。
    // 只在收音态转——不收音时停住，省电也免得动画空跑。
    _pulse = AnimationController(vsync: this, duration: LLMotion.normal);
    _recorderSub = widget.recorder.events.listen(_onRecorderEvent);
    widget.controller.addListener(_onPlayerChanged);
    // 会话也是会变的：初读/熟读切档（熟读不拦）要在结果态当场生效，
    // 不能等下一次收音才刷新。
    widget.session.addListener(_onSessionChanged);
    if (widget.autoStartAttempt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) startAttempt(maxDurationMs: widget.attemptMaxDurationMs);
      });
    }
  }

  /// 跟着视图切脉冲：只在「在录/在听这个字」两态呼吸。
  void _syncPulse() {
    final active = _view == _ReadAlongView.recording ||
        _view == _ReadAlongView.drilling;
    if (active && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!active && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _stopLive();
    unawaited(_speaker.stop());
    _recorderSub?.cancel();
    widget.controller.removeListener(_onPlayerChanged);
    widget.session.removeListener(_onSessionChanged);
    if (_pulse.isAnimating) _pulse.stop();
    _pulse.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------- 录音链路

  /// 句末门触发：开始一次跟读收音。权限被拒 → 降级「仅跟读不评分」，
  /// 页面不死锁（方案 §三）。
  ///
  /// 不调用 `session.startSentence()`——重试计数归零由上层在「换句」时
  /// 做；同句重播再触发门时必须保留计数，否则 3 次软上限永远不触发。
  ///
  /// [keepView] = 单字练习自动开录：不能把视图切回 recording，否则大字块
  /// 会被课文双行顶掉（郭老师 2026-10-16：错字要一直放大居中）。
  Future<void> startAttempt({
    int? maxDurationMs,
    bool keepView = false,
  }) async {
    final session = widget.session;
    // 新一轮收音前先停掉上一轮的播报（纠错话没说完就重读会打架）。
    await _speaker.stop();
    if (!session.canScore || !session.beginAttempt()) {
      setState(() => _view = _ReadAlongView.degraded);
      return;
    }
    setState(() {
      if (!keepView) _view = _ReadAlongView.recording;
      _level = 0;
      _result = null;
      _drillVerdict = null;
      _live = LiveProgress.empty;
      _micError = null;
    });
    final sentence = widget.controller.currentSentence;
    // 兜底上限（2026-10-16 收窄）：原来是「音频时长 × 3 + 2000ms」，
    // 《春夏秋冬》4 字行音频 3.9 秒 → 上限 13.7 秒还行；但 8 字行 14.8 秒
    // → 上限 46 秒，孩子读完 app 还在录，谁还想读下去。
    //
    // 边说边判之后不需要那么长的兜底：孩子跟读一般与原声同速或略慢，
    // 给「音频时长 + 4 秒」足够覆盖慢读与停顿；超了就走超时收尾，
    // 判定链照常判（只是这段音频偏长，unclear 会兜住读飞的情况）。
    final maxMs = maxDurationMs ??
        (sentence.durationMs + 4000).clamp(6000, 20000);
    try {
      await widget.recorder.start(maxDurationMs: maxMs);
      _startLive();
    } on ReadAlongMicPermissionDenied {
      session.blockScoringNoMic();
      if (mounted) setState(() => _view = _ReadAlongView.degraded);
    } catch (error) {
      if (mounted) {
        setState(() {
          _view = _ReadAlongView.micFailed;
          _micError = error;
        });
      }
    }
  }

  // --------------------------------------------------------- 边说边判

  /// 开拍：立即跑第一拍（模型首次加载要几秒，早跑早热），之后按节拍跑。
  ///
  /// 快照只读已采集 PCM，收音不中断；解出的进度只做展示与提前收尾，
  /// 终判仍走完整 wav（`_score` 那条链一字未动）。
  void _startLive() {
    _stopLive();
    _liveStopped = false;
    _runLiveTick();
    _liveTimer = Timer.periodic(_liveInterval, (_) => _runLiveTick());
  }

  /// 停新拍，让在飞的那拍解完（读完进判分态时最后一拍正好填 spinner 空白）。
  void _haltLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  /// 彻底停（退出 / 重听 / 中止）。
  void _stopLive() {
    _liveStopped = true;
    _liveTimer?.cancel();
    _liveTimer = null;
    _liveBusy = false;
  }

  /// 跑一拍：快照 wav → 识别 → 推实时进度。串行 guard 防堆积。
  Future<void> _runLiveTick() async {
    if (_liveBusy || _liveStopped || !mounted) return;
    final recorder = widget.recorder;
    if (!recorder.isRecording || !recorder.hasSpeechSoFar) return;
    _liveBusy = true;
    try {
      final snap = await recorder.snapshotWav();
      if (snap == null || _liveStopped || !mounted) {
        if (snap != null) await recorder.deleteWav(snap);
        return;
      }
      try {
        final words = await widget.session.engine.transcribe(
          snap,
          language: 'zh',
          onProgress: (_) {},
          isCancelled: () => _liveStopped,
        );
        if (_liveStopped || !mounted) return;
        final text = words.map((w) => w.word).join().trim();
        final progress = ReadAlongLiveJudge.progress(
          expectedToned: ReadAlongSession.normalizeWithTones(
            widget.expectedTextOf(widget.controller.currentSentence),
          ),
          actual: text,
        );
        // 空串不覆盖上一次：半个音节上的快照本就可能解空。
        if (progress.isEmpty) return;
        if (mounted && _live.spoken != progress.spoken) {
          setState(() => _live = progress);
        }
        // 期望音节已全部命中 → 立刻收尾，不再等尾静音和整句时长。
        if (progress.complete) {
          _haltLive();
          await widget.recorder.finishNow();
        }
      } finally {
        // 快照即用即删（§九.6 纪律同样适用）。
        await recorder.deleteWav(snap);
      }
    } catch (_) {
      // 预览失败静默忽略——终判走完整 wav，不受影响。
    } finally {
      _liveBusy = false;
    }
  }

  void _onRecorderEvent(ReadAlongRecorderEvent event) {
    if (!mounted) return;
    switch (event) {
      case RecorderLevel(:final rms):
        // 脉冲强度：RMS 放大一点看着更活；变化太小不重建。
        final next = (rms * 2).clamp(0.0, 1.0);
        if ((next - _level).abs() > 0.03) setState(() => _level = next);
      case RecorderSilent():
        // 全程没检出语音：不计失败（方案 §三），回到「再来一次」。
        debugPrint('[read-along] event: silent (no speech detected)');
        _stopLive();
        widget.session.cancelAttempt();
        setState(() => _view = _ReadAlongView.silent);
      case RecorderFailed(:final error):
        _stopLive();
        widget.session.cancelAttempt();
        setState(() {
          _view = _ReadAlongView.micFailed;
          _micError = error;
        });
      case RecorderStopped(:final wavPath):
        _haltLive();
        _score(wavPath);
    }
  }

  /// 判分入口：单字练习与整句各走一套口径。
  ///
  /// 单字练习判的是**单个字**且要管声调（2026-10-16 拍板 B）；
  /// 整句判定仍走 `session.scoreWav` 比音不比字。
  Future<void> _score(String wavPath) async {
    final isDrill = _view == _ReadAlongView.drilling;
    final target = _drill.current;
    final expected = widget.expectedTextOf(widget.controller.currentSentence);
    setState(() => _view = _ReadAlongView.scoring);
    debugPrint('[ReadAlong][diag] scoring: expected="$expected" wav=$wavPath'
        '${isDrill ? ' drill=${target?.char}' : ''}');
    try {
      if (isDrill && target != null) {
        await _scoreDrillChar(wavPath, target);
        return;
      }
      final result = await widget.session.scoreWav(
        expected: expected,
        wavPath: wavPath,
        language: 'zh',
      );
      debugPrint('[ReadAlong][diag] scored: $result');
      if (!mounted) return;
      setState(() {
        _result = result;
        _view = switch (result.verdict) {
          ReadAlongVerdict.star || ReadAlongVerdict.pass =>
            _ReadAlongView.passed,
          ReadAlongVerdict.unclear => _ReadAlongView.unclear,
          ReadAlongVerdict.retry => _ReadAlongView.retry,
          ReadAlongVerdict.giveUp => _ReadAlongView.retry,
        };
      });
      // 读准了：队列空就直接收队；有错字则结果屏给「开始练字」入口。
      if (result.passed) _drill.finish();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _view = _ReadAlongView.micFailed;
        _micError = error;
      });
    } finally {
      // §九.6：识别完即删，不进任何持久层。
      await widget.recorder.deleteWav(wavPath);
    }
  }

  /// 单字练习判一遍：读准 → 光标后移；没读准 → 光标不动可重来；
  /// 队列清空 → 回整句重读（郭老师：练完再把整句读一遍）。
  Future<void> _scoreDrillChar(String wavPath, DrillTarget target) async {
    try {
      final words = await widget.session.engine.transcribe(
        wavPath,
        language: 'zh',
        onProgress: (_) {},
        isCancelled: () => false,
      );
      final actual = words.map((w) => w.word).join();
      final verdict = ReadAlongDrillJudge.judgeChar(
        char: target.char,
        expectedPinyin: target.pinyin,
        actual: actual,
      );
      debugPrint('[ReadAlong][diag] drill: ${target.char}/${target.pinyin} '
          '<- "$actual" => $verdict');
      if (!mounted) return;
      setState(() {
        _drillVerdict = verdict;
        if (verdict == DrillVerdict.hit) {
          _drill.markCurrentCleared();
        } else {
          _drill.markCurrentMissed();
        }
        _view = _ReadAlongView.drilling;
      });
      if (verdict == DrillVerdict.hit && _drill.queueEmpty) {
        // 单字都练完了：自动重放原声，进入整句重读那一轮。
        _drill.advanceRound();
        await widget.controller.playCurrentSentence();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _view = _ReadAlongView.micFailed;
        _micError = error;
      });
    }
  }

  // ------------------------------------------------------------- 动作

  Future<void> _advance() async {
    await _speaker.stop();
    final controller = widget.controller;
    if (!controller.canGoNext) {
      setState(() => _view = _ReadAlongView.done);
      return;
    }
    await controller.nextSentence();
    await controller.playCurrentSentence();
    setState(() {
      _drill.reset();
      _drillVerdict = null;
      _result = null;
      _view = _ReadAlongView.listening;
    });
  }

  /// 收音中手动重听原声：丢弃本次收音 → 重播本句 → 句末门再触 →
  /// 重新收音。本次不计数（submit 没跑），计数保留。
  Future<void> _replayWhileRecording() async {
    await _speaker.stop();
    _stopLive();
    await widget.recorder.abort();
    setState(() {
      _live = LiveProgress.empty;
      _view = _ReadAlongView.listening;
    });
    await widget.controller.playCurrentSentence();
  }

  /// 结果态手动重听原声：停播报 → 切回待听 → 重播本句。
  Future<void> _replayFromResult() async {
    await _speaker.stop();
    _stopLive();
    setState(() {
      _live = LiveProgress.empty;
      _view = _ReadAlongView.listening;
    });
    await widget.controller.playCurrentSentence();
  }

  Future<void> _requestPermission() async {
    widget.session.resumeScoring();
    await startAttempt();
  }

  // ------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    _syncPulse();
    // 最小形态 v3：整页，不弹窗。原来底部弹窗会盖住课文正文，孩子读的
    // 时候看不见原句；整页之后正文只由本页承载，字能放到最大。
    return Material(
      color: ll.surface,
      child: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: ll.surface,
            border: Border(
              top: BorderSide(color: ll.divider, width: shape.hairline),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            LLSpacing.xl,
            LLSpacing.md,
            LLSpacing.xl,
            LLSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              SizedBox(height: LLSpacing.md),
              // 整页之后中部要能撑开（Expanded）：内容区拿剩余高度，
              // 由 SingleChildScrollView 兜底防爆屏；Expanded 只出现在
              // 已确定高度的子树上，不会撞上「scroll view 里 unbounded」。
              Expanded(
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: _bodyHeight(context),
                    child: _body(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 内容区高度：整页之后的剩余空间，扣掉页头与内外边距。
  ///
  /// 用 MediaQuery 算而不是 LayoutBuilder——内容区在 SingleChildScrollView
  /// 里，LayoutBuilder 拿到的是 unbounded 高度，Expanded 会直接炸。
  double _bodyHeight(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final usable = media.height - padding.top - padding.bottom;
    // 页头约 44 + 两处 md 间距 + 上下 xl/lg 边距，留足余量不掐内容。
    const chrome = 44.0 + LLSpacing.md * 2 + LLSpacing.xl + LLSpacing.lg;
    return (usable - chrome).clamp(200.0, double.infinity);
  }

  Widget _header(BuildContext context) {
    final ll = context.ll;
    final controller = widget.controller;
    final drilling = _view == _ReadAlongView.drilling;
    return Row(
      children: [
        Icon(
          _view == _ReadAlongView.recording
              ? Icons.graphic_eq_rounded
              : Icons.record_voice_over_outlined,
          size: 20,
          color: _view == _ReadAlongView.degraded ? ll.warning : ll.accent,
        ),
        const SizedBox(width: LLSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                drilling ? '练这个字' : '跟读',
                style: LLText.itemTitle.copyWith(color: ll.textPrimary),
              ),
              // 进度：本课第几句（v2：孩子要知道自己读到哪了）。
              Text(
                '第 ${controller.displayIndex} / ${controller.sentenceCount} 句',
                style: LLText.badge.copyWith(color: ll.textTertiary),
              ),
            ],
          ),
        ),
        LLPillButton(
          label: '退出',
          onTap: widget.onExit,
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    switch (_view) {
      case _ReadAlongView.listening:
        return _listeningBody(context);
      case _ReadAlongView.recording:
        return _recordingBody(context);
      case _ReadAlongView.scoring:
        return _scoringBody(context);
      case _ReadAlongView.drilling:
        return _drillingBody(context);
      case _ReadAlongView.passed:
      case _ReadAlongView.retry:
        return _resultBody(context);
      case _ReadAlongView.unclear:
        return _unclearBody(context);
      case _ReadAlongView.silent:
        return _silentBody(context);
      case _ReadAlongView.micFailed:
        return _micFailedBody(context);
      case _ReadAlongView.degraded:
        return _degradedBody(context);
      case _ReadAlongView.done:
        return _doneBody(context);
    }
  }

  Widget _listeningBody(BuildContext context) {
    final ll = context.ll;
    // 单字都练完了 → 这遍是「整句重读」，文案要说清楚。
    if (_drill.queueEmpty && _drill.cleared > 0) {
      return _CenterBlock(
        icon: Icons.replay_rounded,
        iconColor: ll.accent,
        title: '再把整句读一遍',
        subtitle: '刚练过的字，连起来读一次',
        child: _sentenceText(context),
      );
    }
    return _CenterBlock(
      icon: Icons.hearing_rounded,
      iconColor: ll.accent,
      title: '跟着音频读',
      subtitle: '这句读完会自动停下来，等你跟读',
      child: _sentenceText(context),
    );
  }

  Widget _recordingBody(BuildContext context) {
    final ll = context.ll;
    final live = _live;
    final plain = _sentencePlain(context);

    return Column(
      children: [
        // 私塾先生伴读书卷：正中大字，就地水墨变色
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: LLSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '我在听',
                        style: LLText.controlLabel.copyWith(
                          color: ll.textSecondary,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        ' · 请随声诵读',
                        style: LLText.controlLabel.copyWith(
                          color: ll.textTertiary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: LLSpacing.xl),
                  // 书卷大字正文（就地水墨上色）
                  _ScrollCalligraphyView(expected: plain, live: live),
                  const SizedBox(height: LLSpacing.xxl),
                  // 下方轻声伴读小注（实时回显，温润自然）
                  _EchoFeedbackTile(
                    spoken: live.spoken,
                    isComplete: live.complete,
                    animation: _pulse,
                    level: _level,
                  ),
                  const SizedBox(height: LLSpacing.sm),
                  Text(
                    live.complete ? '读对了，正在收尾' : '读完了会自动停下来评分',
                    style: LLText.caption.copyWith(color: ll.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: LLSpacing.md),
        Wrap(
          spacing: LLSpacing.sm,
          runSpacing: LLSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            LLPillButton(
              label: '我读完了',
              active: true,
              onTap: () => widget.recorder.finishNow(),
            ),
            LLPillButton(
              label: '重听原声',
              onTap: _replayWhileRecording,
            ),
          ],
        ),
      ],
    );
  }

  Widget _scoringBody(BuildContext context) {
    final ll = context.ll;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LLSpacing.xl),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ll.accent,
            ),
          ),
          SizedBox(height: LLSpacing.md),
          Text(
            _view == _ReadAlongView.drilling ? '在听这个字' : '判分中',
            style: LLText.rowTitle.copyWith(color: ll.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 结果态（郭老师 2026-10-16 重排）：
  ///   * 读准 → 「这几个字都读准了」放页面正中
  ///   * 没读准 → 自动把错字拎进单字练习（不让孩子多点一下），
  ///     自动播标准发音，自动开录等他读
  Widget _resultBody(BuildContext context) {
    final ll = context.ll;
    final result = _result;
    if (result == null) return _listeningBody(context);

    // 读准了：居中一句人话 + 下一句。不出分、不评星。
    if (result.passed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 48, color: ll.success),
            SizedBox(height: LLSpacing.md),
            Text(
              '这几个字都读准了',
              style: LLText.pageTitle.copyWith(color: ll.success),
              textAlign: TextAlign.center,
            ),
            if (_drill.cleared > 0) ...[
              SizedBox(height: LLSpacing.xs),
              Text(
                '练过的字，整句也读对了',
                style: LLText.caption.copyWith(color: ll.textSecondary),
              ),
            ],
            SizedBox(height: LLSpacing.lg),
            LLPillButton(
              label: '下一句',
              active: true,
              onTap: _advance,
            ),
          ],
        ),
      );
    }

    // 没读准：直接进单字练习，不摆中间那一屏。
    _beginDrill();
    return _drillingBody(context);
  }

  /// 从整句结果抽出读不准的字，进入单字练习。
  ///
  /// 郭老师 2026-10-16：结果出来之后直接把红色错字单拎出来放大居中，
  /// 并播放标准发音。所以这里是「自动进」，不是等孩子点按钮。
  void _beginDrill() {
    final result = _result;
    if (result == null) return;
    final targets = _drill.record(result);
    debugPrint('[ReadAlong][diag] drill queue: '
        '${targets.map((t) => t.char).join()}');
    if (targets.isEmpty) return;
    setState(() {
      _drillVerdict = null;
      _view = _ReadAlongView.drilling;
    });
    // 播标准发音 + 开录等他读（两个都不等：TTS 有 2 秒超时兜底）。
    unawaited(_speakCurrentChar());
    unawaited(startAttempt(keepView: true));
  }

  /// 单字练习态（郭老师 2026-10-16）：错字单拎出来、放大、居中，附拼音，
  /// 自动播标准发音，自动开录等孩子读。
  ///
  ///   * 读准 → 自动收队进下一个字（队列空则回整句重读）
  ///   * 没读准 → 同一个字再读，不卡次数（拍板 A）
  ///   * 手动：家长可点「这个字会了」直接收队
  Widget _drillingBody(BuildContext context) {
    final ll = context.ll;
    final target = _drill.current;
    if (target == null) return _listeningBody(context);

    final verdict = _drillVerdict;
    final feedback = switch (verdict) {
      DrillVerdict.hit => '这个字读准了',
      DrillVerdict.toneOnly => '声调再注意一下',
      DrillVerdict.miss => '再试一次',
      DrillVerdict.unclear => '没听清，再读一次',
      null => '跟着读这个字',
    };
    final feedbackColor = switch (verdict) {
      DrillVerdict.hit => ll.success,
      DrillVerdict.toneOnly => ll.warning,
      DrillVerdict.miss => ll.warning,
      DrillVerdict.unclear => ll.textSecondary,
      null => ll.textSecondary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_drill.queue.length > 1) ...[
          Text(
            '还有 ${_drill.remaining} 个字要练'
            '${_drill.cleared > 0 ? '（已读准 ${_drill.cleared} 个）' : ''}',
            style: LLText.caption.copyWith(color: ll.textTertiary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: LLSpacing.sm),
        ],
        // 错字放大、居中（郭老师 2026-10-16）。整页之后中部有大片空白，
        // 大字块撑开占满，孩子视线自然落在中间。
        Expanded(
          child: Center(child: _BigChar(char: target)),
        ),
        SizedBox(height: LLSpacing.md),
        Text(
          feedback,
          style: LLText.rowTitle.copyWith(color: feedbackColor),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: LLSpacing.lg),
        Wrap(
          spacing: LLSpacing.sm,
          runSpacing: LLSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            LLPillButton(
              label: '我读完了',
              active: true,
              onTap: () => widget.recorder.finishNow(),
            ),
            LLPillButton(
              label: '再听这个字',
              onTap: _speakCurrentChar,
            ),
            LLPillButton(
              label: '重听整句',
              onTap: _replayFromResult,
            ),
            LLPillButton(
              label: '这个字会了',
              onTap: _markCurrentClearedByHand,
            ),
          ],
        ),
      ],
    );
  }

  /// 家长/老师手动确认「这个字会了」：不等 ASR，记录家长确认放行并直接收队。
  void _markCurrentClearedByHand() {
    setState(() {
      _drillVerdict = DrillVerdict.hit;
      _drill.confirmByParent();
      _view = _drill.queueEmpty
          ? _ReadAlongView.listening
          : _ReadAlongView.drilling;
    });
    if (_drill.queueEmpty) {
      _drill.advanceRound();
      widget.controller.playCurrentSentence();
    }
  }

  /// 用系统 TTS 念一遍当前要练的字。
  Future<void> _speakCurrentChar() async {
    final target = _drill.current;
    if (target == null) return;
    await _speaker.speak(target.char);
  }

  /// 熟读「不拦」档的放行出口。
  ///
  /// 「不卡进度」不能只管判负那一屏：没听清（unclear）、没听到声音（silent）
  /// 同样是把孩子钉在原句上的原因。熟读档下这两屏都多给一枚「继续下一句」，
  /// 初读档返回 null（保持原来的单一「再读一次」出口）。
  Widget? _lenientAdvancePill() => widget.session.lenient
      ? LLPillButton(label: '继续下一句', onTap: _advance)
      : null;

  /// 一屏里的动作区：主出口 + 熟读档的放行出口（可能只有一个）。
  Widget _actions(Widget primary) {
    final extra = _lenientAdvancePill();
    if (extra == null) return primary;
    return Wrap(
      spacing: LLSpacing.sm,
      runSpacing: LLSpacing.sm,
      alignment: WrapAlignment.center,
      children: [primary, extra],
    );
  }

  Widget _unclearBody(BuildContext context) {
    final ll = context.ll;
    return _CenterBlock(
      icon: Icons.question_mark_rounded,
      iconColor: ll.warning,
      title: '没听清',
      subtitle: '刚才那遍没听清楚，不扣分，对着麦克风再读一次',
      action: _actions(LLPillButton(
        label: '再读一次',
        active: true,
        onTap: startAttempt,
      )),
    );
  }

  Widget _silentBody(BuildContext context) {
    final ll = context.ll;
    return _CenterBlock(
      icon: Icons.hearing_disabled_rounded,
      iconColor: ll.warning,
      title: '没听到你的声音',
      subtitle: '不影响成绩，对着麦克风再读一次',
      action: _actions(LLPillButton(
        label: '再读一次',
        active: true,
        onTap: startAttempt,
      )),
    );
  }

  Widget _micFailedBody(BuildContext context) {
    return _CenterBlock(
      icon: Icons.mic_off_rounded,
      iconColor: context.ll.danger,
      title: '麦克风没准备好',
      subtitle: _micError == null ? '再试一次看看' : '再试一次看看（可重试）',
      action: LLPillButton(
        label: '再试一次',
        active: true,
        onTap: startAttempt,
      ),
    );
  }

  Widget _degradedBody(BuildContext context) {
    final ll = context.ll;
    return Column(
      children: [
        _CenterBlock(
          icon: Icons.mic_none_rounded,
          iconColor: ll.warning,
          title: '麦克风权限未开启',
          subtitle: '照读照停，暂不评分；开启后即可恢复判分',
        ),
        SizedBox(height: LLSpacing.md),
        Wrap(
          spacing: LLSpacing.sm,
          runSpacing: LLSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            LLPillButton(
              label: '去开启权限',
              active: true,
              onTap: _requestPermission,
            ),
            LLPillButton(
              label: '我读好了，下一句',
              onTap: _advance,
            ),
          ],
        ),
      ],
    );
  }

  Widget _doneBody(BuildContext context) {
    final ll = context.ll;
    return _CenterBlock(
      icon: Icons.check_circle_outline_rounded,
      iconColor: ll.success,
      title: '本课跟读完成',
      subtitle: '每一句都停下来读过了',
      action: LLPillButton(
        label: '完成',
        active: true,
        onTap: widget.onExit,
      ),
    );
  }

  // ------------------------------------------------------------- 片段

  /// 课文原句的纯汉字串（逐格对齐用：只数汉字位，标点不占格）。
  String _sentencePlain(BuildContext context) {
    final sentence = widget.expectedTextOf(widget.controller.currentSentence);
    final chars = sentence.runes
        .map((r) => String.fromCharCode(r))
        .where((c) {
          final code = c.codeUnitAt(0);
          return code >= 0x4E00 && code <= 0x9FA5;
        })
        .toList(growable: false);
    return chars.join();
  }

  /// 课文原句。两种上色：
  ///  * [liveProgress] 非空 = 录音中说边判：已读准的字 success，还没读到
  ///    的字保持正文色（不说"错"，只等他说下去）
  ///  * [result] 非空 = 结果态：漏 warning / 错 danger
  Widget _sentenceText(
    BuildContext context, {
    ReadAlongResult? result,
    LiveProgress? liveProgress,
    bool big = false,
  }) {
    final ll = context.ll;
    // big = 录音中说边判：课文放到屏幕正中，用大字号（郭老师 2026-10-16）。
    final base = (big ? LLText.appTitle : LLText.rowTitle)
        .copyWith(color: ll.textPrimary, height: 1.4);
    final sentence = widget.expectedTextOf(widget.controller.currentSentence);

    final live = liveProgress;
    if (live != null && !live.isEmpty) {
      final spans = <TextSpan>[];
      var syllable = 0;
      for (final rune in sentence.runes) {
        final ch = String.fromCharCode(rune);
        final code = ch.codeUnitAt(0);
        final isCjk = code >= 0x4E00 && code <= 0x9FA5;
        if (!isCjk) {
          spans.add(TextSpan(text: ch, style: base));
          continue;
        }
        // 已读准 → success；还没读到 → 正正文（不判错，只等他说下去）。
        final done = syllable < live.matchedCount;
        syllable++;
        spans.add(TextSpan(
          text: ch,
          style: base.copyWith(
            color: done ? ll.success : ll.textPrimary,
            fontWeight: done ? FontWeight.w600 : null,
          ),
        ));
      }
      return Text.rich(
        TextSpan(children: spans),
        textAlign: TextAlign.center,
      );
    }

    if (result == null) {
      return Text(sentence, style: base, textAlign: TextAlign.center);
    }
    final ops = result.ops
        .where((op) => op.expected != null)
        .toList(growable: false);
    final spans = <TextSpan>[];
    var syllable = 0;
    for (final rune in sentence.runes) {
      final ch = String.fromCharCode(rune);
      final code = ch.codeUnitAt(0);
      final isCjk = code >= 0x4E00 && code <= 0x9FA5;
      if (!isCjk) {
        spans.add(TextSpan(text: ch, style: base));
        continue;
      }
      final op = syllable < ops.length ? ops[syllable] : null;
      syllable++;
      final color = switch (op?.type) {
        DictationDiffType.matched || null => ll.textPrimary,
        DictationDiffType.missing => ll.warning,
        _ => ll.danger,
      };
      spans.add(TextSpan(text: ch, style: base.copyWith(color: color)));
    }
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }
}

/// 单字练习的大字格（2026-10-16 郭老师拍板）：没读准的字**单独、很大地**
/// 列出，下方挂带声调拼音。字色/描边走 design token，无裸 fontSize。
class _BigChar extends StatelessWidget {
  const _BigChar({required this.char});

  final DrillTarget char;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LLSpacing.xl,
        vertical: LLSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: ll.emphasis,
        borderRadius: BorderRadius.circular(LLRadius.large),
        border: Border.all(
          color: ll.divider,
          width: context.llShape.hairline,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            char.char,
            style: LLText.appTitle.copyWith(
              color: char.missing ? ll.warning : ll.textPrimary,
            ),
          ),
          const SizedBox(height: LLSpacing.xs),
          Text(
            char.pinyin,
            style: LLText.rowTitle.copyWith(color: ll.accent),
          ),
        ],
      ),
    );
  }
}

/// 书卷水墨大字视图：整句课文大字在中央自然排布（郭老师 2026-10-18 纠偏：
/// 彻底推翻考卷方格子，字在中央就地水墨变色，读准墨绿，偏读朱砂红，未读沉墨）。
class _ScrollCalligraphyView extends StatelessWidget {
  const _ScrollCalligraphyView({
    required this.expected,
    required this.live,
  });

  final String expected;
  final LiveProgress live;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final slots = live.slots;

    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 12,
      children: [
        for (var i = 0; i < expected.length; i++)
          _CalligraphyChar(
            char: expected[i],
            slot: i < slots.length ? slots[i] : LiveSlot.pending,
            ll: ll,
          ),
      ],
    );
  }
}

/// 墨染单字格：带极淡宣纸米字印底衬，随朗读进度就地水墨渗透着色
class _CalligraphyChar extends StatelessWidget {
  const _CalligraphyChar({
    required this.char,
    required this.slot,
    required this.ll,
  });

  final String char;
  final LiveSlot slot;
  final LLPalette ll;

  @override
  Widget build(BuildContext context) {
    final isHit = slot == LiveSlot.hit;
    final isWrong = slot == LiveSlot.wrong;
    final isPartial = slot == LiveSlot.partial;

    final textColor = switch (slot) {
      LiveSlot.hit => ll.success,
      LiveSlot.wrong => ll.danger,
      LiveSlot.partial => ll.warning,
      LiveSlot.pending => ll.textPrimary,
    };

    final bgColor = isHit
        ? ll.success.withValues(alpha: 0.08)
        : isWrong
            ? ll.danger.withValues(alpha: 0.08)
            : isPartial
                ? ll.warning.withValues(alpha: 0.08)
                : ll.emphasis.withValues(alpha: 0.4);

    final borderColor = isHit
        ? ll.success.withValues(alpha: 0.35)
        : isWrong
            ? ll.danger.withValues(alpha: 0.35)
            : isPartial
                ? ll.warning.withValues(alpha: 0.35)
                : ll.divider.withValues(alpha: 0.4);

    return AnimatedContainer(
      duration: LLMotion.fast,
      width: 46,
      height: 54,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        char,
        style: TextStyle(
          fontSize: 26,
          fontWeight: isHit ? FontWeight.w700 : FontWeight.w500,
          color: textColor,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 先生轻声伴读回显小注
class _EchoFeedbackTile extends StatelessWidget {
  const _EchoFeedbackTile({
    required this.spoken,
    required this.isComplete,
    required this.animation,
    required this.level,
  });

  final String spoken;
  final bool isComplete;
  final Animation<double> animation;
  final double level;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    if (isComplete) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 16, color: ll.success),
          const SizedBox(width: 6),
          Text(
            '字正腔圆，整句读准了',
            style: LLText.itemSummary.copyWith(
              color: ll.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final displayText = spoken.trim().isEmpty ? '字正腔圆，慢慢念' : spoken;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ll.emphasis.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseCircle(level: level, animation: animation, small: true),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              spoken.trim().isEmpty ? displayText : '先生在听：『$displayText』',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LLText.caption.copyWith(color: ll.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 边说边判的进度条：读准几个字 / 一共几个字。
///
/// 只走 design token；条高走 hairline 的整数倍，颜色对 success、底 divider。
class _LiveProgressBar extends StatelessWidget {
  const _LiveProgressBar({required this.progress});

  final LiveProgress progress;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final ratio = progress.ratio;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(LLRadius.pill),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: ll.divider,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress.wrong ? ll.warning : ll.success,
            ),
          ),
        ),
        SizedBox(height: LLSpacing.xs),
        Text(
          progress.wrong
              ? '这个字再读一遍'
              : '读准 ${progress.matchedCount} / ${progress.totalSyllables} 个字',
          style: LLText.caption.copyWith(
            color: progress.wrong ? ll.warning : ll.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 图标 + 标题 + 一句说明（+ 可选动作）的居中块。
class _CenterBlock extends StatelessWidget {
  const _CenterBlock({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.child,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    return Column(
      children: [
        SizedBox(height: LLSpacing.md),
        Icon(icon, size: 30, color: iconColor),
        SizedBox(height: LLSpacing.sm),
        Text(title, style: LLText.rowTitle.copyWith(color: ll.textPrimary)),
        SizedBox(height: LLSpacing.xs),
        Text(
          subtitle,
          style: LLText.caption.copyWith(color: ll.textSecondary),
          textAlign: TextAlign.center,
        ),
        if (child != null) ...[
          SizedBox(height: LLSpacing.md),
          child!,
        ],
        if (action != null) ...[
          SizedBox(height: LLSpacing.md),
          action!,
        ],
      ],
    );
  }
}

/// 呼吸脉冲圈（方案 §七）：三帧呼吸动画 fast 起、normal 循环；
/// 底色 ll.accent，扩散 ll.accent.withValues(alpha: 0.15)。
class _PulseCircle extends StatelessWidget {
  const _PulseCircle({
    required this.level,
    required this.animation,
    this.small = false,
  });

  /// 音量级 0~1（RMS 放大后）。
  final double level;

  final Animation<double> animation;

  /// 小号（录音态配角：主角是课文大字）。
  final bool small;

  static const double _size = 96;
  static const double _smallSize = 16;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final side = small ? _smallSize : _size;
    return SizedBox(
      width: side,
      height: side,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => CustomPaint(
          painter: _PulsePainter(
            accent: ll.accent,
            glow: ll.accent.withValues(alpha: 0.15),
            breath: animation.value,
            level: level,
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.accent,
    required this.glow,
    required this.breath,
    required this.level,
  });

  final Color accent;
  final Color glow;

  /// 呼吸相位 0~1。
  final double breath;

  /// 音量级 0~1。
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.shortestSide * 0.26;

    // 扩散环：呼吸驱动，音量放大半径。
    final ring = Paint()
      ..color = glow
      ..maskFilter = null;
    canvas.drawCircle(
      center,
      base + size.shortestSide * 0.28 * breath * (0.45 + 0.55 * level),
      ring,
    );

    // 实心圈：随音量轻微胀缩。
    final core = Paint()..color = accent;
    canvas.drawCircle(center, base * (0.92 + 0.08 * level), core);
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.breath != breath ||
      oldDelegate.level != level ||
      oldDelegate.accent != accent;
}

