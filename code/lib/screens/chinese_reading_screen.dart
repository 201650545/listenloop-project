import 'dart:async';
import 'package:flutter/material.dart';

import '../creation/sherpa_onnx_asr_engine.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../player/sentence_player_controller.dart';
import '../preferences/app_preferences.dart';
import '../theme/listenloop_theme.dart';
import '../training/continuous_reading_session.dart';
import '../utils/chinese_pinyin.dart';
import '../widgets/lesson_reading_document.dart';
import '../widgets/live_reading_dock.dart';
import '../training/read_along_recorder.dart';
import '../training/read_along_session.dart';
import '../widgets/ll_page.dart';

/// 东方书卷极简风 · 跟读一级工作台 (Read Along Screen)
/// ---------------------------------------------------------------------------
/// 郭老师 2026-10-19 裁定：
/// 1. 颜色反馈：以“词语”为识别单位，读对绿色，读错红色，未读浅墨色；
/// 2. 边读边识别：后台流式快照节拍识别，读完一个词语即时上色，并展示实时回显；
/// 3. 错词单独训练：读完全句若有标红错词，单独列出；
///    (a) 自动慢速示范该字怎么拼（声母-韵母-带调拼读）；
///    (b) 孩子跟读识别，拼对后巩固读 2 遍；
///    (c) 错词攻克后，全句重读（上限 2 次，防挫败感）。
class ChineseReadingScreen extends StatefulWidget {
  const ChineseReadingScreen({
    super.key,
    required this.lesson,
    required this.sentences,
    required this.controller,
    this.session,
    this.recorder,
    this.onSelectSentence,
  });

  final Lesson lesson;
  final List<Sentence> sentences;
  final SentencePlayerController controller;
  final ReadAlongSession? session;
  final ReadAlongRecorder? recorder;
  final ValueChanged<int>? onSelectSentence;

  @override
  State<ChineseReadingScreen> createState() => _ChineseReadingScreenState();
}

class _ChineseReadingScreenState extends State<ChineseReadingScreen>
    with SingleTickerProviderStateMixin {
  late ReadAlongSession _session;
  late ReadAlongRecorder _recorder;

  bool _isRecording = false;
  String _statusHint = '';

  // 词语级流式识别与红绿状态
  Timer? _liveTimer;
  bool _liveBusy = false;
  bool _liveStopped = false;
  String _liveSpoken = '';

  // 错词单独训练队列与全句重读控制

  // 录音呼吸动效
  late final AnimationController _pulseController;
  StreamSubscription<ReadAlongRecorderEvent>? _recorderSub;

  // 2026-10-20 读页重构 §四：滑动识别窗口的参数。
  //
  // 　· 窗口容量 8 秒（16kHz × 2byte = 32KB/秒 ⇒ 256KB）
  // 　· 每次识别最近 7 秒（留 1 秒重叠，给对齐器接缝）
  // 　· 识别节奏 800ms 一次（镜像建议 700~1000ms）
  static const int _captureWindowMs = 7000;
  static const int _captureWindowBytes = 8 * 32000;
  static const Duration _captureInterval = Duration(milliseconds: 800);

  /// 当前是不是"整课连续收音"模式（连续模式下到点重开，不做句级判分）。
  bool _continuousCapture = false;

  /// 连续收音到点后的重开（整课收音不中断）。
  void _rearmContinuousCapture() {
    if (!mounted) return;
    Future<void>.delayed(const Duration(milliseconds: 200), () async {
      if (!mounted || !_continuousCapture) return;
      try {
        await _recorder.start(
          maxDurationMs: 10 * 60 * 1000,
          continuous: true,
          windowBytes: _captureWindowBytes,
        );
        _startLive();
      } catch (_) {
        // 重开失败：停在这个状态，让用户点底栏重新开始。
        if (mounted) {
          setState(() {
            _isRecording = false;
            _statusHint = '麦克风中断了，点这里重新开始读';
          });
        }
      }
    });
  }

  // 整课朗读会话（2026-10-20 读页重构 · 第 1 步）
  //
  // 它是"整篇课文一个流程"的数据底座：整篇 token 索引、跨句对齐、
  // committed/provisional 双游标都在里面。页面只订阅它的快照。
  late final ContinuousReadingSession _readingSession;

  /// 是否已经按"上次读到哪"定位过（控制器异步恢复句号，要等它报出来）。
  bool _sessionSeeked = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _readingSession = ContinuousReadingSession(sentences: widget.sentences);
    // 关键：页面必须**订阅**整课会话 —— 识别结果、字词状态、自动定位都从它来。
    // 不订阅的话，底栏出字了课文却不会变色，定位也不会滚。
    _readingSession.addListener(_onSessionChanged);
    _initEngine();
    widget.controller.addListener(_onControllerChanged);
    // 2026-10-20 读页重构：「不需要手动，都是自动识别」。
    // 进这一页就自动开麦（系统麦克风权限弹窗照常；被拒了就说"无法实时
    // 反馈"，绝不假装在识别）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 起始位置：控制器的句号是**异步恢复**的，首帧之后才知道孩子上次读到
      // 哪一句，这时再把整篇课文定位过去。
      _syncSessionPosition();
      if (mounted) _onStartRecording();
    });
  }

  /// 按控制器当前句号同步整篇课文的阅读位置（只做一次）。
  void _syncSessionPosition() {
    if (_sessionSeeked) return;
    final idx = widget.controller.currentSentenceIndex;
    if (idx <= 0) return;
    _sessionSeeked = true;
    _readingSession.seekToSentence(idx);
  }

  void _initEngine() {
    _session = widget.session ??
        ReadAlongSession(
          engine: SherpaOnnxAsrEngine(
            modelDirResolver: defaultAsrModelDir,
            threads: () => PreferencesScope.maybeOf(context).asrThreads,
          ),
        );
    _recorder = widget.recorder ?? ReadAlongRecorder();

    _recorderSub = _recorder.events.listen(_onRecorderEvent);
  }

  @override
  void didUpdateWidget(ChineseReadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _readingSession.removeListener(_onSessionChanged);
    _stopLive();
    _recorderSub?.cancel();
    _pulseController.dispose();
    if (_isRecording) {
      _recorder.abort();
    }
    super.dispose();
  }

  /// 是否已经弹过整课汇总（只弹一次）。
  bool _summaryShown = false;

  /// 整课会话变了（识别结果/字词状态/进度）→ 页面重画。
  void _onSessionChanged() {
    if (!mounted) return;
    final snapshot = _readingSession.snapshot;
    // 整课读完 → 一次性汇总（「阅读时阅读，纠音时纠音」：过程中不打断）。
    if (snapshot.finished && !_summaryShown) {
      _summaryShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showLessonSummary(context);
      });
    }
    setState(() {});
  }

  /// 读完这一课的汇总页：朗读进度 + **值得再练的字词**。
  ///
  /// 2026-10-20 读页第 3 步：错词不在阅读过程中弹纠错卡（那会一次次打断
  /// 孩子），而是等**整篇读完**再一次性摊开；点某个字就跳回它所在的句子
  /// 继续读。
  Future<void> _showLessonSummary(BuildContext context) async {
    final ll = context.ll;
    final snapshot = _readingSession.snapshot;
    // 同一个字只列一次（一个字读错三次也只算一个）。
    final seen = <String>{};
    final unique = [
      for (final t in snapshot.wrongTokens)
        if (seen.add(t.char)) t,
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ll.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_outlined, size: 26, color: ll.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '这一课读完啦',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: ll.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '《${widget.lesson.title}》',
                  style: TextStyle(fontSize: 13, color: ll.textTertiary),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _summaryStat('朗读进度', '${(snapshot.progress * 100).round()}%', ll),
                    const SizedBox(width: 12),
                    _summaryStat('值得再练', '${unique.length} 个', ll),
                  ],
                ),
                const SizedBox(height: 18),
                if (unique.isEmpty)
                  Text(
                    '这一课读得又准又稳，没有需要再练的字 👏',
                    style: TextStyle(fontSize: 13.5, color: ll.textSecondary),
                  )
                else ...[
                  Text(
                    '下面这些字还想再练一遍？点一下就回去读它所在的句子：',
                    style: TextStyle(fontSize: 13, color: ll.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in unique)
                        GestureDetector(
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            // 跳回这个词所在的句子，继续读（麦克风一直开着）。
                            widget.controller.selectSentence(t.sentenceIndex);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: ll.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: ll.divider),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t.char,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: ll.textPrimary,
                                  ),
                                ),
                                Text(
                                  t.pinyin,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: ll.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: ll.accent,
                      foregroundColor: ll.onAccent,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('好的'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryStat(String label, String value, LLPalette ll) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ll.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ll.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: ll.textTertiary)),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ll.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onControllerChanged() {
    // 2026-10-20 读页重构：控制器的起始句号是**异步恢复**的（initState 时
    // 可能还是 0），等它报出真实位置再把整篇课文定位过去 —— 否则孩子进来
    // 看到的是课文开头，而他上次读到第 73 句。
    _syncSessionPosition();
    _resetSentenceState();
    if (mounted) setState(() {});
  }

  void _resetSentenceState() {
    _stopLive();
    _statusHint = '';
    _liveSpoken = '';
  }

  void _onRecorderEvent(ReadAlongRecorderEvent event) {
    if (!mounted) return;
    switch (event) {
      case RecorderLevel():
        if (_isRecording && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      case RecorderSilent():
        setState(() {
          _isRecording = false;
          _pulseController.stop();
          _stopLive();
          _statusHint = '未检出人声，请靠近重读';
        });
      case RecorderFailed():
        setState(() {
          _isRecording = false;
          _pulseController.stop();
          _stopLive();
          _statusHint = '录音异常，请重试';
        });
      case RecorderStopped():
        // 2026-10-20 读页第 3 步：判定统一由整课会话负责，句级判分链已拆。
        // 连续模式跑到 10 分钟兜底上限才停 —— 停了**立刻重开**，整课收音
        // 不中断（识别继续走滑动窗口）。
        if (_continuousCapture) {
          _rearmContinuousCapture();
        }
    }
  }

  /// 播放原声示范
  void _onPlayDemonstration() {
    if (_isRecording) return;
    widget.controller.replaySentence();
    setState(() {
      _statusHint = '正在示范原声...';
    });
  }

  /// 点击开始跟读（全句）
  Future<void> _onStartRecording() async {
    if (_isRecording) {
      // 提前结束录音并送评
      _haltLive();
      await _recorder.finishNow();
      return;
    }

    if (widget.controller.isPlaying) {
      widget.controller.pause();
    }

    final currentSentence = _currentSentence;
    if (currentSentence != null) {
      }
    _liveSpoken = '';

    // 2026-10-20 读页重构 §四：连续模式下不按"当前这一句"算上限 —— 整课一个
    // 流程，麦克风要能一直开着（10 分钟兜底，到点自动重开）。
    final maxMsContinuous = 10 * 60 * 1000;

    setState(() {
      _isRecording = true;
      _continuousCapture = true;
      _statusHint = '请朗读... 边读边识别';
    });

    try {
      await _recorder.start(
        maxDurationMs: maxMsContinuous,
        // 2026-10-20 读页重构 §四（不中断采集）：
        // 整课一个流程 ⇒ 麦克风**一直开着**，静音不再结束录音；识别改走
        // 滑动窗口（最近 8 秒），识别量恒定、延迟不随时长增长。
        continuous: true,
        windowBytes: _captureWindowBytes,
      );
      _pulseController.repeat(reverse: true);
      _startLive();
    } on ReadAlongMicPermissionDenied {
      setState(() {
        _isRecording = false;
        _pulseController.stop();
        _statusHint = '麦克风权限未开启（已降级为仅跟读不打分）';
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        _pulseController.stop();
        _statusHint = '启动麦克风失败';
      });
    }
  }

  // --------------------------------------------------------- 边读边识别节拍器

  void _startLive() {
    _stopLive();
    _liveStopped = false;
    _runLiveTick();
    // 2026-10-20 读页重构 §四：滑动窗口识别节奏 800ms（原来 1000ms 且每次
    // 跑整段累计音频）。
    _liveTimer = Timer.periodic(_captureInterval, (_) => _runLiveTick());
  }

  void _haltLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  void _stopLive() {
    _liveStopped = true;
    _liveTimer?.cancel();
    _liveTimer = null;
    _liveBusy = false;
  }

  Future<void> _runLiveTick() async {
    if (_liveBusy || _liveStopped || !mounted) return;
    if (!_recorder.isRecording || !_recorder.hasSpeechSoFar) return;
    _liveBusy = true;
    try {
      // 2026-10-20 读页重构 §四：**滑动窗口**识别。
      // 原来每 1 秒重识别**整段累计音频** —— 那是 O(n²)，越读到后面越慢；
      // 现在只取最近 7 秒（窗口 8 秒、识别用 7 秒，留一点重叠给对齐器），
      // 识别量恒定。
      final snap = await _recorder.snapshotWindowWav(
        windowMs: _captureWindowMs,
      );
      if (snap == null || _liveStopped || !mounted) {
        if (snap != null) await _recorder.deleteWav(snap);
        return;
      }
      try {
        final words = await _session.engine.transcribe(
          snap,
          language: 'zh',
          onProgress: (_) {},
          isCancelled: () => _liveStopped,
        );
        if (_liveStopped || !mounted) return;
        final text = words.map((w) => w.word).join().trim();
        if (text.isNotEmpty && mounted) {
          setState(() {
            _liveSpoken = text;
          });
          // 2026-10-20 读页第 3 步（视觉收敛）：**判定只有一套** ——
          // 整课会话。旧的那条句级链（_charStatuses / _evaluateWordsLive /
          // _allWordsMatchedAndCorrect）跟整课会话并存时，两套"读对/读错"会
          // 各说各话，课文上的颜色也说不清是谁给的。
          //
          // 音节从同一套拼音源取（课文与识别用同一把尺），对齐后才更新
          // 课文上的字词状态。
          _readingSession.applyRecognition(
            syllables: [
              for (final t in ChinesePinyin.format(text))
                if ((t.pinyin ?? '').isNotEmpty) t.pinyin!,
            ],
            text: text,
          );
          // 连续模式下**不早停**：麦克风要一直开着（整篇一个流程）。
          // 旧版那句"全词读对就收句"属于句级闭环，在整课流程里反而会把
          // 收音打断。
        }
      } finally {
        await _recorder.deleteWav(snap);
      }
    } catch (_) {
    } finally {
      _liveBusy = false;
    }
  }

  /// 以“词语”为识别单位，等读完一个词语后再对齐判定
  ///
  /// 2026-10-20 读页第 3 步：**已废弃**。判定统一由整课会话
  /// （ContinuousReadingSession）负责，句级这套（_charStatuses）与之并存
  /// 只会让"谁给课文上的颜色"说不清。保留这段只为对照，**不再被调用**。
  @Deprecated('句级判定链已废弃，改用整课会话')










  /// 识别游标当前所在的句号（0 起）。
  ///
  /// 2026-10-20：定位区与课文灰块统一以此为真源（原先定位区报音频控制器
  /// 的句号，灰块跟识别游标 ⇒ 两边对不上）。
  ///
  /// 识别游标还没动（刚进页面、还没出声）时，退回音频控制器的句号 ——
  /// 那样至少和"听到哪句"对得上。
  int get _readingSentenceIndex {
    final tokens = _readingSession.tokens;
    final cursor = _readingSession.snapshot.visibleCursor;
    if (tokens.isNotEmpty && cursor >= 0 && cursor < tokens.length) {
      return tokens[cursor].sentenceIndex;
    }
    final idx = widget.controller.currentSentenceIndex;
    if (idx >= 0 && idx < widget.sentences.length) return idx;
    return 0;
  }

  Sentence? get _currentSentence {
    final list = widget.sentences;
    final idx = widget.controller.currentSentenceIndex;
    if (list.isNotEmpty && idx >= 0 && idx < list.length) {
      return list[idx];
    }
    return null;
  }

  /// 2026-10-20 郭老师：「一般来读的话，是以**一篇课文**为一个流程，不是读
  /// 一句话就停下来……把这个课文都读完，然后才结束」。
  ///
  /// 2026-10-20 读页第 3 步：整课会话自己管"读到哪"，不再需要"一句读通就
  /// 接着录下一句"的句级推进（那是旧闭环的补丁，连续采集不需要它）。
  void _onNext() {
    if (_isRecording) _recorder.abort();
    _resetSentenceState();
    if (widget.controller.canGoNext) {
      widget.controller.nextSentence();
      // 识别游标跟着走：定位区/灰块/句单都报识别游标，不同步的话
      // 点一下「下一句」，定位区数字不动、课文形状也不动。
      _readingSession.seekToSentence(widget.controller.currentSentenceIndex);
    }
  }

  void _onPrevious() {
    if (_isRecording) _recorder.abort();
    _resetSentenceState();
    if (widget.controller.canGoPrevious) {
      widget.controller.previousSentence();
      _readingSession.seekToSentence(widget.controller.currentSentenceIndex);
    }
  }

  void _showSentenceSheet(BuildContext context) {
    final ll = context.ll;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ll.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Text(
                      '全课句单 (${widget.sentences.length} 句)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ll.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ll.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: widget.sentences.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: ll.divider),
                  itemBuilder: (_, index) {
                    final s = widget.sentences[index];
                    // 句单高亮与定位区、课文灰块**同源**（识别游标）。
                    final isCurrent = index == _readingSentenceIndex;
                    return ListTile(
                      dense: true,
                      leading: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: isCurrent ? ll.textPrimary : ll.textTertiary,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      title: Text(
                        s.chinese,
                        style: TextStyle(
                          fontSize: 14,
                          color: isCurrent ? ll.textPrimary : ll.textSecondary,
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      trailing: isCurrent
                          ? Icon(Icons.chevron_right_rounded,
                              size: 18, color: ll.textTertiary)
                          : null,
                      onTap: () {
                        widget.controller.selectSentence(index);
                        widget.onSelectSentence?.call(index);
                        // 识别游标也挪过去：否则课文灰块还停在别处，
                        // 句单选中的句子和课文里的形状对不上。
                        _readingSession.seekToSentence(index);
                        _resetSentenceState();
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final controller = widget.controller;
    final sentences = widget.sentences;
    final currentSentence = _currentSentence;

    final totalCount = sentences.length;
    // 定位区句号与课文灰块**同源**：都取识别会话的可见游标所在句。
    //
    // 2026-10-20 真机发现的不一致：定位区写「第 17 / 69 句」（那是**音频
    // 控制器**的句号），而课文里的灰色形状跟着**识别游标**（在第 46 句
    // 「看见荷叶上」）。两个真源各说各话，孩子看着是懵的。
    //
    // 读页的语义是「实时自动识别」⇒ 孩子在哪儿，识别游标就在哪儿 ⇒
    // 定位区也该报识别游标的位置。音频控制器的句号只用于播放。
    final currentIndex = _readingSentenceIndex;
    final countLabel = totalCount > 0 ? '${currentIndex + 1} / $totalCount' : '-';

    return LLPage(
      title: Text(
        widget.lesson.title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ll.textPrimary,
          letterSpacing: 0.5,
        ),
      ),
      actions: [
        // 听示范挪到顶栏：底部只留"识别"这一件事（镜像评审：这一页不放
        // 下一句/完成/重读这类句级按钮）。
        IconButton(
          tooltip: '听示范',
          icon: Icon(
            controller.isPlaying ? Icons.pause : Icons.volume_up_outlined,
            size: 20,
            color: ll.textSecondary,
          ),
          onPressed: () => controller.isPlaying
              ? controller.pause()
              : _onPlayDemonstration(),
        ),
        IconButton(
          tooltip: '查看全课句单',
          icon: Icon(Icons.format_list_numbered, size: 20, color: ll.textSecondary),
          onPressed: () => _showSentenceSheet(context),
        ),
        // 句序移到下方的定位区（2026-10-20 评审 P1）—— 顶栏只留动作。
      ],
      body: currentSentence == null
          ? Center(
              child: Text('当前课文无句子', style: TextStyle(color: ll.textTertiary)),
            )
          : SafeArea(
              child: Column(
                children: [
                  // 定位区：上一句 / 句序 / 下一句
                  _buildPositionRow(context, ll, controller, countLabel),
                  const SizedBox(height: 4),

                  // ── 整篇课文（2026-10-20 读页重构 · 整课骨架）────────
                  //
                  // 原来是一句一屏的"工作台"；现在是**整篇课文一次排开**，
                  // 随朗读位置自动滚动（孩子想往前翻也能翻）。
                  Expanded(
                    child: LessonReadingDocument(
                      sentences: widget.sentences,
                      tokens: _readingSession.tokens,
                      tokenStates: _readingSession.snapshot.tokenStates,
                      visibleToken: _readingSession.snapshot.visibleCursor,
                      // 列表一上来就落在上次读到的那一句（否则离得远时
                      // SliverList 还没铺到，定位会停在课文开头）。
                      initialSentenceIndex: widget.controller.currentSentenceIndex,
                      charSize: 23.0,
                      charStyle:
                          LLLearning.chineseMainSentence(
                        ll,
                        PreferencesScope.maybeOf(context),
                      ).copyWith(
                        fontSize: 23.0,
                      ),
                      pinyinScale:
                          PreferencesScope.maybeOf(context).pinyinScale,
                      chineseFontFamily:
                          PreferencesScope.maybeOf(context)
                              .learningChineseFont
                              .family,
                    ),
                  ),

                  // ── 底部实时识别栏：这一页唯一的"操作区" ──────────────
                  // 不放下一句/完成/重读：整篇是一个流程，没有"下一步"。
                  // 但**入口必须显眼**：整条底栏就是「开始读」那颗按钮
                  // （郭老师：「没有开始读的按钮呀，怎么读」）。
                  LiveReadingDock(
                    transcript: _liveSpoken,
                    listening: _isRecording,
                    hint: _statusHint.isNotEmpty
                        ? _statusHint
                        : _readingSession.snapshot.hint,
                    onTap: _onStartRecording,
                  ),
                ],
              ),
            ),
    );
  }

  /// 定位区：上一句 / 句序 / 下一句（2026-10-20 评审 P1）。
  ///
  /// 三个元素等宽平铺，句序居中；导航用轻量的圆形按钮，**不与主操作
  /// 争视觉重量**。
  Widget _buildPositionRow(
    BuildContext context,
    LLPalette ll,
    SentencePlayerController controller,
    String countLabel,
  ) {
    return Row(
      children: [
        _buildNavButton(
          icon: Icons.chevron_left_rounded,
          tooltip: '上一句',
          enabled: controller.canGoPrevious,
          onTap: _onPrevious,
          ll: ll,
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '第 $countLabel 句',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: ll.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildNavButton(
          icon: Icons.chevron_right_rounded,
          tooltip: '下一句',
          enabled: controller.canGoNext,
          onTap: _onNext,
          ll: ll,
        ),
      ],
    );
  }

  /// 定位区的小导航钮：圆形、描边、无填充 —— 一眼就知道是"翻页"，
  /// 不会误认成主操作。
  Widget _buildNavButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    required LLPalette ll,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ll.divider, width: 1),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? ll.textSecondary : ll.disabled,
          ),
        ),
      ),
    );
  }


}
