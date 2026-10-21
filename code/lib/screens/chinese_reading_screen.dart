import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../creation/sherpa_onnx_asr_engine.dart';
import '../creation/streaming_asr_engine.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../player/sentence_player_controller.dart';
import '../preferences/app_preferences.dart';
import '../theme/listenloop_theme.dart';
import '../training/continuous_reading_session.dart';
import '../training/live_reading_controller.dart';
import '../utils/chinese_pinyin.dart';
import '../widgets/lesson_reading_document.dart';
import '../widgets/live_reading_dock.dart';
import '../widgets/live_record_button.dart';
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
    this.alternateSentences,
  });

  final Lesson lesson;
  final List<Sentence> sentences;
  final SentencePlayerController controller;
  final ReadAlongSession? session;
  final ReadAlongRecorder? recorder;
  final ValueChanged<int>? onSelectSentence;

  /// 熟读档的句子（长意群）。给了才能切「初读 / 熟读」。
  final List<Sentence>? alternateSentences;

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
  //
  // ⚠️ 2026-10-21：这三条是**降级路径**的参数（没有流式模型时走它）。
  //    首选路径是**流式识别**（[LiveReadingController]）：边说边出字，
  //    不用每 800ms 把 7 秒音频从头重转写一遍。
  static const int _captureWindowMs = 7000;
  static const int _captureWindowBytes = 8 * 32000;
  static const Duration _captureInterval = Duration(milliseconds: 800);

  // ── 2026-10-21：实时朗读（流式 + 口令 + 逐字上色）────────────────
  //
  // 用户需求原文：
  //   「能不能做到像语音识别输入一样实时识别了」
  //   「把开始识别和暂停识别浓缩为一个圆形的录音按钮，集合在底部中间的
  //     "听"和"读"上面」
  //   「给这个按钮增加实时识别功能……录制一个口令（口令可由用户自定义，
  //     比如"开始朗读课文"）。当用户说出自定义口令，且系统准确识别到之后，
  //     才会触发正式测试」
  //   「一个一个字地来识别并做这个动画」
  LiveReadingController? _liveController;
  bool _useStreaming = false;   // 流式可用？不可用则降级到滑动窗口
  /// 口令（可由用户自定义）。用户能在设置里改，所以不是 final。
  // ignore: prefer_final_fields
  String _wakePhrase = kDefaultReadWakePhrase;

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
  //
  // ⚠️ 2026-10-21：切「初读 / 熟读」会换一整套句子（切分粒度不同）⇒
  //    token 索引全变 ⇒ 会话必须**重建**（不能是 final）。
  late ContinuousReadingSession _readingSession;

  /// 当前生效的句子列表（初读 = 短句；熟读 = 长意群）。
  late List<Sentence> _activeSentences;

  /// 熟读档的句子（长意群）；null = 这课没有熟读切分。
  List<Sentence>? _alternateSentences;

  /// 当前是不是熟读档。
  bool _isAlternateMode = false;

  /// 朗读模式（句为单位 / 全文）。
  ReadingMode _readingMode = ReadingMode.sentence;

  /// 是否已经按"上次读到哪"定位过（控制器异步恢复句号，要等它报出来）。
  bool _sessionSeeked = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _activeSentences = widget.sentences;
    _alternateSentences = widget.alternateSentences;
    _readingSession = ContinuousReadingSession(
      sentences: _activeSentences,
      mode: _readingMode,
    );
    // 关键：页面必须**订阅**整课会话 —— 识别结果、字词状态、自动定位都从它来。
    // 不订阅的话，底栏出字了课文却不会变色，定位也不会滚。
    _readingSession.addListener(_onSessionChanged);
    _initEngine();
    widget.controller.addListener(_onControllerChanged);
    // 2026-10-21：**不再自动开麦**。
    //
    // 郭老师：「我竟然不能自己手动点击开始识别和暂停识别。」
    // 以前是「进这一页就自动开麦」⇒ 麦克风一直开着（整课 10 分钟），
    // 录进来大量环境噪音与扬声器回授，还没法暂停。
    // ⇒ 现在由**底部的圆形录音按钮**控制（开始 / 暂停 合一），
    //   而且点开之后先**等口令**（默认「开始朗读课文」），说出口令才正式判读。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 起始位置：控制器的句号是**异步恢复**的，首帧之后才知道孩子上次读到
      // 哪一句，这时再把整篇课文定位过去。
      _syncSessionPosition();
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

  /// 切换**朗读模式**：句为单位 / 全文（2026-10-21 郭老师定的两种）。
  ///
  /// 两种模式**逐字反馈完全一样**（都是边读边一个一个变色），
  /// 区别只在判定边界：
  ///   · 句为单位：一句读好才进下一句，读完一句就结算这一句（反馈快）
  ///   · 全文    ：整篇一口气读完，最后统一处理
  void _setReadingMode(ReadingMode mode) {
    if (_readingMode == mode) return;
    setState(() {
      _readingMode = mode;
    });
    _readingSession.setMode(mode);
  }

  /// 切换**切分档**：初读（短句）/ 熟读（长意群）。
  ///
  /// 初读 = 呼吸节拍，短句、要求过关；熟读 = 长意群、照给分但不卡进度。
  /// 切档会换一整套句子 ⇒ token 索引全变 ⇒ 整课会话**重建**。
  void _toggleSegmentationMode() {
    final alt = _alternateSentences;
    if (alt == null || alt.isEmpty) return;
    final toAlternate = !_isAlternateMode;
    final target = toAlternate ? alt : widget.sentences;

    _readingSession.removeListener(_onSessionChanged);
    _readingSession.dispose();
    setState(() {
      _isAlternateMode = toAlternate;
      _activeSentences = target;
      _readingSession = ContinuousReadingSession(
        sentences: target,
        mode: _readingMode,
      );
    });
    _readingSession.addListener(_onSessionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 口令从偏好读（用户可自定义；空串 = 不等口令，点开直接判读）。
    //
    // ⚠️ 必须在 didChangeDependencies 里读，**不能**在 initState 里 ——
    //    initState 时 inherited widget（PreferencesScope）还没挂上，
    //    `dependOnInheritedWidgetOfExactType` 会抛断言（真机红屏实证）。
    final phrase = PreferencesScope.maybeOf(context).readWakePhrase;
    if (phrase != _wakePhrase) {
      _wakePhrase = phrase;
    }
  }

  void _initEngine() {    _session = widget.session ??
        ReadAlongSession(
          engine: SherpaOnnxAsrEngine(
            modelDirResolver: defaultAsrModelDir,
            threads: () => PreferencesScope.maybeOf(context).asrThreads,
          ),
        );
    _recorder = widget.recorder ?? ReadAlongRecorder();

    _recorderSub = _recorder.events.listen(_onRecorderEvent);

    // 2026-10-21：进读页就**常驻监听口令**（用户原话：「识别口令这个语音识别
    // 要常驻，听到我的口令之后它就自动开始」）。
    // 等一帧再开：initState 阶段还不能碰界面/插件。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartListening();
    });
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

  /// 点圆形录音按钮（**开始 / 暂停 合一**）。
  ///
  /// 2026-10-21 郭老师：「把开始识别和暂停识别浓缩为一个圆形的录音按钮」
  Future<void> _onStartRecording() async {
    if (_isRecording) {
      // ── 暂停 ────────────────────────────────────────────────
      _haltLive();
      _recorder.onPcm = null; // 断掉流式推流
      final live = _liveController;
      if (live != null) {
        live.removeListener(_onLiveControllerChanged);
        await live.stop();
      }
      _liveController = null;
      _useStreaming = false;
      await _recorder.finishNow();
      setState(() {
        _isRecording = false;
        _statusHint = '已暂停，点一下继续';
      });
      return;
    }

    await _startListening();
  }

  /// 进读页就**常驻监听口令**（2026-10-21 用户原话）。
  ///
  /// > 「是加一个识别口令，识别到开始朗读这个语音识别要常驻，听到我的口令
  /// > 之后它就自动开始。」
  ///
  /// 麦克风权限还没拿到时**不自动开**（免得每次进页都弹权限框），
  /// 仍可点圆形按钮手动开始。
  Future<void> _autoStartListening() async {
    if (!mounted || _isRecording || _liveController != null) return;
    try {
      if (!await _recorder.hasPermission()) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await _startListening();
  }

  /// 真正开始常驻监听（按钮手动开始 / 进页自动开始都走这里）。
  Future<void> _startListening() async {
    if (widget.controller.isPlaying) {
      widget.controller.pause();
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
      // 2026-10-21：**首选流式识别**（边说边出字 + 口令触发）。
      // 没有流式模型（或打开失败）⇒ 降级到旧的滑动窗口离线转写。
      //
      // ⚠️ 顺序很重要（2026-10-21 评审意见）：**先开 ASR 会话，再挂 onPcm，
      //   最后才开麦** ——
      //   ① ASR 没开成就不该开麦（否则麦克风白转、还一直占着权限）；
      //   ② onPcm 必须在 recorder.start() 之前挂上，否则开麦的头几块 PCM 会丢
      //      （原代码把 onPcm 挂在 start 之后，而它自己的注释写的是"必须在之前"）。
      final live = LiveReadingController(
        session: _readingSession,
        streamingEngine: SherpaOnnxStreamingAsrEngine(
          modelDirResolver: _asrModelRootDir,
        ),
        wakePhrase: _wakePhrase,
      );
      await live.start();
      _useStreaming = live.phase != LiveReadPhase.idle;
      if (_useStreaming) {
        _liveController = live;
        // 流式路径：PCM 块直接推给流式引擎（不再每 800ms 重转写 7 秒）。
        _recorder.onPcm = (pcm) => _liveController?.pushPcm(pcm);
      } else {
        live.dispose();
      }

      await _recorder.start(
        maxDurationMs: maxMsContinuous,
        // 2026-10-20 读页重构 §四（不中断采集）：
        // 整课一个流程 ⇒ 麦克风**一直开着**，静音不再结束录音；识别改走
        // 滑动窗口（最近 8 秒），识别量恒定、延迟不同时长增长。
        continuous: true,
        windowBytes: _captureWindowBytes,
      );
      _pulseController.repeat(reverse: true);
      if (_useStreaming) {
        _liveController!.addListener(_onLiveControllerChanged);
        setState(() {
          _statusHint = '请说「$_wakePhrase」开始朗读';
        });
      } else {
        _startLive();
      }
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

  /// 流式控制器状态变化 ⇒ 刷新界面（口令提示、识别文本、逐字上色）。
  void _onLiveControllerChanged() {
    if (!mounted) return;
    final c = _liveController;
    if (c == null) return;
    setState(() {
      _liveSpoken = c.readingText.isNotEmpty ? c.readingText : c.liveText;
      switch (c.phase) {
        case LiveReadPhase.waitingWake:
          _statusHint = '请说「$_wakePhrase」开始朗读';
        case LiveReadPhase.reading:
          _statusHint = '正在判读…';
        case LiveReadPhase.idle:
        case LiveReadPhase.sentenceDone:
          _statusHint = '';
      }
    });
  }

  /// ASR 模型根目录（外置目录；App 启动后才推上去的模型也能找到）。
  Future<String> _asrModelRootDir() async {
    final dir = await getExternalStorageDirectory();
    final sep = Platform.pathSeparator;
    return '${dir!.path}$sep${'models'}$sep${'asr'}';
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
              child: Stack(
                children: [
                  Column(
                    children: [
                  // 定位区：上一句 / 句序 / 下一句
                  _buildPositionRow(context, ll, controller, countLabel),
                  const SizedBox(height: 4),

                  // ── 模式选择（2026-10-21）────────────────────────
                  // 左：初读 / 熟读（切分粒度）
                  // 右：逐句 / 全文（判定边界）
                  _buildModeRow(context, ll),
                  const SizedBox(height: 4),
                  // ── 整篇课文（2026-10-20 读页重构 · 整课骨架）────────
                  //
                  // 原来是一句一屏的"工作台"；现在是**整篇课文一次排开**，
                  // 随朗读位置自动滚动（孩子想往前翻也能翻）。
                  Expanded(
                    child: LessonReadingDocument(
                      sentences: _activeSentences,
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

                  // ── 圆形录音按钮（2026-10-21）─────────────────────
                  // 郭老师：「把开始识别和暂停识别浓缩为一个圆形的录音按钮，
                  // 集合在底部中间的"听"和"读"上面」。
                  //
                  // 放在**课文区与识别回显栏之间**（不是悬浮）—— 悬浮会压住
                  // 下面的文字（真机截图实证）。
                  _buildRecordButton(ll),

                  // ── 底部实时识别栏：只显示**识别文本回显** ────────────
                  // 2026-10-21：主操作移到上面的圆形按钮，这条底栏不再
                  // 当按钮用（只是孩子读的内容回显 + 提示）。
                  LiveReadingDock(
                    transcript: _liveSpoken,
                    listening: _isRecording,
                    hint: _statusHint.isNotEmpty
                        ? _statusHint
                        : _readingSession.snapshot.hint,
                  ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  /// **模式选择行**（2026-10-21）。
  ///
  /// 左半：初读 / 熟读 —— 切分粒度（短句 vs 长意群）。
  /// 右半：逐句 / 全文 —— 判定边界（一句一结算 vs 读完统一处理）。
  ///
  /// 两组都是小药丸，视觉权重刻意压低（不与圆形录音按钮争）。
  Widget _buildModeRow(BuildContext context, LLPalette ll) {
    return Row(
      children: [
        _segButton(
          label: '初读',
          selected: !_isAlternateMode,
          onTap: _alternateSentences == null ? null : _toggleSegmentationMode,
        ),
        const SizedBox(width: 6),
        _segButton(
          label: '熟读',
          selected: _isAlternateMode,
          onTap: _alternateSentences == null ? null : _toggleSegmentationMode,
        ),
        const Spacer(),
        _segButton(
          label: '逐句',
          selected: _readingMode == ReadingMode.sentence,
          onTap: () => _setReadingMode(ReadingMode.sentence),
        ),
        const SizedBox(width: 6),
        _segButton(
          label: '全文',
          selected: _readingMode == ReadingMode.fullText,
          onTap: () => _setReadingMode(ReadingMode.fullText),
        ),
      ],
    );
  }

  Widget _segButton({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final ll = context.ll;
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? ll.textPrimary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? ll.textPrimary.withValues(alpha: 0.22) : ll.divider,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: enabled
                ? (selected ? ll.textPrimary : ll.textSecondary)
                : ll.disabled,
          ),
        ),
      ),
    );
  }

  /// **圆形录音按钮**（2026-10-21）。
  ///
  /// 一颗按钮管开始/暂停：
  ///   · 待命 ⇒ 点一下开麦（进「等口令」）
  ///   · 录音中 ⇒ 再点一下暂停
  ///
  /// 位置：课文区**下方**、识别回显栏**上方**（不是悬浮）—— 悬浮会压住
  /// 下面的文字（真机截图实证）。这样它仍在 App 底部导航（听/读）**上面**。
  Widget _buildRecordButton(LLPalette ll) {
    final controller = _liveController;
    final state = switch (controller?.phase) {
      LiveReadPhase.waitingWake => LiveRecordButtonState.waitingWake,
      LiveReadPhase.reading => LiveRecordButtonState.reading,
      LiveReadPhase.sentenceDone => LiveRecordButtonState.reading,
      _ => _isRecording
          ? LiveRecordButtonState.waitingWake
          : LiveRecordButtonState.idle,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Center(
        child: LiveRecordButton(
          state: state,
          wakePhrase: _wakePhrase,
          onTap: _onStartRecording,
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
