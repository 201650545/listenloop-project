import 'dart:async';
import 'package:flutter/material.dart';

import '../creation/sherpa_onnx_asr_engine.dart';
import '../models/lesson.dart';
import '../models/sentence.dart';
import '../player/sentence_player_controller.dart';
import '../preferences/app_preferences.dart';
import '../theme/listenloop_theme.dart';
import '../training/chinese_word_segmenter.dart';
import '../training/read_along_recorder.dart';
import '../training/read_along_session.dart';
import '../training/read_along_speaker.dart';
import '../utils/chinese_pinyin.dart';
import '../widgets/chinese_textbook_ruby_layout.dart';
import '../widgets/ll_page.dart';
import '../widgets/ll_primitives.dart';

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
    this.speaker,
    this.onSelectSentence,
  });

  final Lesson lesson;
  final List<Sentence> sentences;
  final SentencePlayerController controller;
  final ReadAlongSession? session;
  final ReadAlongRecorder? recorder;
  final ReadAlongSpeaker? speaker;
  final ValueChanged<int>? onSelectSentence;

  @override
  State<ChineseReadingScreen> createState() => _ChineseReadingScreenState();
}

class _ChineseReadingScreenState extends State<ChineseReadingScreen>
    with SingleTickerProviderStateMixin {
  late ReadAlongSession _session;
  late ReadAlongRecorder _recorder;
  late ReadAlongSpeaker _speaker;

  bool _isRecording = false;
  bool _isScoring = false;
  String _statusHint = '';
  int _passedCount = 0;
  final Set<int> _passedIndices = {};

  // 词语级流式识别与红绿状态
  final Map<int, RubyCharStatus> _charStatuses = {};
  List<ChineseWord> _currentWords = [];
  Timer? _liveTimer;
  bool _liveBusy = false;
  bool _liveStopped = false;
  String _liveSpoken = '';

  // 错词单独训练队列与全句重读控制
  List<ChineseWord> _wrongWordsToDrill = [];
  ChineseWord? _drillingWord;
  int _drillPassCount = 0; // 当前错词已连续读准次数（目标 2 遍）
  int _sentenceRetryCount = 0; // 全句重读次数（上限 2 次）

  // 录音呼吸动效
  late final AnimationController _pulseController;
  StreamSubscription<ReadAlongRecorderEvent>? _recorderSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    widget.controller.addListener(_onControllerChanged);
    _initEngine();
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
    _speaker = widget.speaker ?? ReadAlongSpeaker();

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
    _stopLive();
    _recorderSub?.cancel();
    _pulseController.dispose();
    if (_isRecording) {
      _recorder.abort();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    _resetSentenceState();
    if (mounted) setState(() {});
  }

  void _resetSentenceState() {
    _stopLive();
    _charStatuses.clear();
    _wrongWordsToDrill.clear();
    _drillingWord = null;
    _drillPassCount = 0;
    _sentenceRetryCount = 0;
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
      case RecorderStopped(:final wavPath):
        if (_drillingWord != null) {
          _handleDrillRecordingFinished(wavPath);
        } else {
          _handleRecordingFinished(wavPath);
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
    if (currentSentence == null) return;

    _currentWords = ChineseWordSegmenter.segment(currentSentence.chinese);
    _charStatuses.clear();
    _liveSpoken = '';

    final maxMs = (currentSentence.durationMs * 3 + 2000).clamp(6000, 25000);

    setState(() {
      _isRecording = true;
      _isScoring = false;
      _statusHint = '请朗读... 边读边识别';
    });

    try {
      await _recorder.start(maxDurationMs: maxMs);
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
    _liveTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) => _runLiveTick());
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
      final snap = await _recorder.snapshotWav();
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
            _evaluateWordsLive(text);
          });
          // 若全词均已识别且全部正确，提前早停
          if (_allWordsMatchedAndCorrect()) {
            _haltLive();
            await _recorder.finishNow();
          }
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
  void _evaluateWordsLive(String spokenText) {
    if (_currentWords.isEmpty || spokenText.isEmpty) return;
    final spokenTokens = ChinesePinyin.format(spokenText);
    final spokenPinyins = spokenTokens
        .map((t) => ReadAlongSession.stripTones(t.pinyin ?? '').toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    var sIdx = 0;
    for (final word in _currentWords) {
      final wLen = word.tonelessPinyins.length;
      if (wLen == 0) continue;

      if (sIdx + wLen <= spokenPinyins.length) {
        // 该词语完整读完：开始识别比对
        bool isCorrect = true;
        for (var k = 0; k < wLen; k++) {
          final expected = ReadAlongSession.stripTones(word.tonelessPinyins[k]).toLowerCase();
          final actual = spokenPinyins[sIdx + k];
          if (expected != actual) {
            isCorrect = false;
            break;
          }
        }
        final status = isCorrect ? RubyCharStatus.correct : RubyCharStatus.wrong;
        for (final charIdx in word.charIndices) {
          _charStatuses[charIdx] = status;
        }
        sIdx += wLen;
      } else {
        // 该词语尚未读完：保持未读状态
        for (final charIdx in word.charIndices) {
          _charStatuses.remove(charIdx);
        }
        break;
      }
    }
  }

  bool _allWordsMatchedAndCorrect() {
    if (_currentWords.isEmpty) return false;
    for (final w in _currentWords) {
      for (final idx in w.charIndices) {
        if (_charStatuses[idx] != RubyCharStatus.correct) {
          return false;
        }
      }
    }
    return true;
  }

  // --------------------------------------------------------- 全句录音完成判分

  Future<void> _handleRecordingFinished(String wavPath) async {
    if (!mounted) return;
    _stopLive();

    setState(() {
      _isRecording = false;
      _isScoring = true;
      _pulseController.stop();
      _statusHint = '正在核验朗读...';
    });

    final current = _currentSentence;
    if (current == null) return;

    try {
      final words = await _session.engine.transcribe(
        wavPath,
        language: 'zh',
        onProgress: (_) {},
        isCancelled: () => false,
      );
      final text = words.map((w) => w.word).join().trim();
      if (text.isNotEmpty) {
        _evaluateWordsLive(text);
      }

      // 提取读错的词
      final wrongWords = _currentWords.where((w) {
        return w.charIndices.any((idx) => _charStatuses[idx] == RubyCharStatus.wrong);
      }).toList();

      if (!mounted) return;

      setState(() {
        _isScoring = false;

        if (wrongWords.isEmpty && _allWordsMatchedAndCorrect()) {
          // 全部正确通关
          _statusHint = '优 · 咬字准确饱满，全读对啦！';
          final curIdx = widget.controller.currentSentenceIndex;
          if (!_passedIndices.contains(curIdx)) {
            _passedIndices.add(curIdx);
            _passedCount = _passedIndices.length;
          }
          _sentenceRetryCount = 0;
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted && widget.controller.canGoNext) {
              widget.controller.nextSentence();
            }
          });
        } else if (_sentenceRetryCount >= 2) {
          // 规则 4：全句重读最多搞两次，防烦躁
          _statusHint = '已达 2 次重读上限，很棒的尝试！';
          final curIdx = widget.controller.currentSentenceIndex;
          if (!_passedIndices.contains(curIdx)) {
            _passedIndices.add(curIdx);
            _passedCount = _passedIndices.length;
          }
          _sentenceRetryCount = 0;
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted && widget.controller.canGoNext) {
              widget.controller.nextSentence();
            }
          });
        } else {
          // 有错词：启动错词单独训练
          _wrongWordsToDrill = List.of(wrongWords.isNotEmpty ? wrongWords : _currentWords);
          _startNextWrongWordDrill();
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isScoring = false;
          _statusHint = '评测完成';
        });
      }
    }
  }

  // --------------------------------------------------------- 错词单独训练

  Future<void> _startNextWrongWordDrill() async {
    if (_wrongWordsToDrill.isEmpty) {
      // 规则 3(c)：错词读两遍都识别正确之后，再让他把这一整句话重读一遍
      setState(() {
        _drillingWord = null;
        _charStatuses.clear();
        _sentenceRetryCount++;
        _statusHint = '太棒了！错词已攻克，请把整句话重读一遍 (第 $_sentenceRetryCount/2 次)';
      });
      return;
    }

    final target = _wrongWordsToDrill.removeAt(0);
    setState(() {
      _drillingWord = target;
      _drillPassCount = 0;
      _statusHint = '错词专练：系统慢速示范拼读...';
    });

    // 规则 3(a)：自动示范——系统直接自动播放该字怎么拼，慢速拼一遍
    await _speaker.speak(target.spellingSpeech);
    if (!mounted) return;

    setState(() {
      _statusHint = '请跟读拼一遍：${target.word}';
    });
  }

  /// 点击错词跟读
  Future<void> _onStartDrillRecording() async {
    if (_isRecording) {
      await _recorder.finishNow();
      return;
    }

    setState(() {
      _isRecording = true;
      _statusHint = '请拼读：${_drillingWord?.word ?? ''}...';
    });

    try {
      await _recorder.start(maxDurationMs: 8000);
      _pulseController.repeat(reverse: true);
    } catch (_) {
      setState(() {
        _isRecording = false;
        _pulseController.stop();
      });
    }
  }

  /// 错词录音完成送检
  Future<void> _handleDrillRecordingFinished(String wavPath) async {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _pulseController.stop();
      _statusHint = '正在核对拼读...';
    });

    final target = _drillingWord;
    if (target == null) return;

    try {
      final words = await _session.engine.transcribe(
        wavPath,
        language: 'zh',
        onProgress: (_) {},
        isCancelled: () => false,
      );
      final text = words.map((w) => w.word).join().trim();
      final spokenTokens = ChinesePinyin.format(text);
      final spokenPinyins = spokenTokens
          .map((t) => ReadAlongSession.stripTones(t.pinyin ?? '').toLowerCase())
          .toList(growable: false);

      // 判断是否读对
      bool passed = false;
      final expected = target.tonelessPinyins.map((s) => s.toLowerCase()).toList();
      if (spokenPinyins.isNotEmpty && expected.isNotEmpty) {
        if (spokenPinyins.any((s) => expected.contains(s)) ||
            text.contains(target.word)) {
          passed = true;
        }
      }

      if (!mounted) return;
      setState(() {
        if (passed) {
          _drillPassCount++;
          // 规则 3(b)：拼对了让他读两遍
          if (_drillPassCount < 2) {
            _statusHint = '拼对啦！请再跟读第 2 遍巩固 (1/2)';
          } else {
            _statusHint = '两遍都读对啦！真棒！(2/2)';
            Future.delayed(const Duration(milliseconds: 700), () {
              if (mounted) _startNextWrongWordDrill();
            });
          }
        } else {
          _statusHint = '读音不够标准，可点击喇叭重听示范拼读';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusHint = '可点击喇叭重听示范';
        });
      }
    }
  }

  Sentence? get _currentSentence {
    final list = widget.sentences;
    final idx = widget.controller.currentSentenceIndex;
    if (list.isNotEmpty && idx >= 0 && idx < list.length) {
      return list[idx];
    }
    return null;
  }

  void _onNext() {
    if (_isRecording) _recorder.abort();
    _resetSentenceState();
    if (widget.controller.canGoNext) {
      widget.controller.nextSentence();
    }
  }

  void _onPrevious() {
    if (_isRecording) _recorder.abort();
    _resetSentenceState();
    if (widget.controller.canGoPrevious) {
      widget.controller.previousSentence();
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
                    final isCurrent = index == widget.controller.currentSentenceIndex;
                    final isPassed = _passedIndices.contains(index);
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
                      trailing: isPassed
                          ? Icon(Icons.check_circle_outline, size: 16, color: ll.textPrimary)
                          : null,
                      onTap: () {
                        widget.controller.selectSentence(index);
                        widget.onSelectSentence?.call(index);
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
    final currentIndex = controller.currentSentenceIndex;
    final currentSentence = _currentSentence;

    final totalCount = sentences.length;
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
        IconButton(
          tooltip: '查看全课句单',
          icon: Icon(Icons.format_list_numbered, size: 20, color: ll.textSecondary),
          onPressed: () => _showSentenceSheet(context),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              countLabel,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: ll.textTertiary,
              ),
            ),
          ),
        ),
      ],
      body: currentSentence == null
          ? Center(
              child: Text('当前课文无句子', style: TextStyle(color: ll.textTertiary)),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  children: [
                    Expanded(
                      // 2026-10-20 修：LayoutBuilder 不支持 intrinsic 尺寸查询，
                      // 它被 IntrinsicHeight 包着时会抛
                      // 「LayoutBuilder does not support returning intrinsic dimensions」，
                      // 导致整棵子树布局失败（阅读页红屏、热重启必炸）。
                      // 改用 Builder + MediaQuery 取屏高，IntrinsicHeight 不再问它要 intrinsic。
                      child: Builder(
                        builder: (context) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: MediaQuery.sizeOf(context).height,
                              ),
                              // 2026-10-20 修（2）：IntrinsicHeight 会向子树问内在高度，
                              // 子树不支持 intrinsic 时整段布局失败（RenderBox was not laid out）。
                              // 去掉它；「内容少时也撑满」由外层 ConstrainedBox(minHeight) 负责。
                              child: SizedBox(
                                width: double.infinity,
                                // 2026-10-20 修（3）：Column 内有 Expanded，
                                // 高度无界时 Expanded 非法（incoming height constraints are unbounded）。
                                // 给一个有界高度，Expanded 才合法。
                                height: MediaQuery.sizeOf(context).height,
                                child: Column(
                                  children: [
                                    // 顶部状态提示行
                                    SizedBox(
                                      height: 26,
                                      child: Center(
                                        child: Text(
                                          _statusHint.isNotEmpty
                                              ? _statusHint
                                              : (controller.isPlaying ? '正在播放示范...' : ''),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: _statusHint.contains('对啦') || _statusHint.contains('准确')
                                                ? const Color(0xFF2E7D32)
                                                : (_statusHint.contains('错词') || _statusHint.contains('标准')
                                                    ? const Color(0xFFD32F2F)
                                                    : ll.textSecondary),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),

                                    const Spacer(flex: 1),

                                    // 核心大字课文排版（红绿字词判定上色）
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Center(
                                            child: ChineseTextbookRubyLayout(
                                              text: currentSentence.chinese,
                                              charSize: 28.0,
                                              textAlign: TextAlign.center,
                                              wordSpacing: 6.0,
                                              lineSpacing: 14.0,
                                              charStatuses: _charStatuses.isEmpty ? null : _charStatuses,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        LLMarginalNote(
                                          text: '已通 $_passedCount 句',
                                          maxHeight: 72,
                                        ),
                                      ],
                                    ),

                                    // 边读边识别实时回显字幕行
                                    if (_isRecording && _liveSpoken.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: ll.surface,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: ll.divider),
                                        ),
                                        child: Text(
                                          '正在识别：$_liveSpoken',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: ll.textSecondary,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],

                                    // 错词单独训练专练卡片
                                    if (_drillingWord != null) ...[
                                      const SizedBox(height: 14),
                                      _buildWrongWordDrillCard(context, ll),
                                    ],

                                    const Spacer(flex: 2),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 底部四个核心按钮：[ 上一句 ] [ 示范 ] [ 跟读 ] [ 下一句 ]
                    Row(
                      children: [
                        _buildBorderButton(
                          label: '上一句',
                          onTap: controller.canGoPrevious ? _onPrevious : null,
                          ll: ll,
                          flex: 2,
                        ),
                        const SizedBox(width: 8),

                        _buildBorderButton(
                          label: controller.isPlaying ? '暂停' : '示范',
                          onTap: controller.isPlaying
                              ? controller.pause
                              : _onPlayDemonstration,
                          ll: ll,
                          flex: 3,
                          isHighlight: false,
                          icon: controller.isPlaying ? Icons.pause : Icons.volume_up_outlined,
                        ),
                        const SizedBox(width: 8),

                        _buildBorderButton(
                          label: _isRecording
                              ? '完成'
                              : (_isScoring ? '评测中' : (_drillingWord != null ? '词语跟读' : '跟读')),
                          onTap: _isScoring
                              ? null
                              : (_drillingWord != null ? _onStartDrillRecording : _onStartRecording),
                          ll: ll,
                          flex: 3,
                          isHighlight: true,
                          isPulse: _isRecording,
                          icon: _isRecording ? Icons.stop : Icons.mic_none_outlined,
                        ),
                        const SizedBox(width: 8),

                        _buildBorderButton(
                          label: '下一句',
                          onTap: controller.canGoNext ? _onNext : null,
                          ll: ll,
                          flex: 2,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
    );
  }

  /// 错词单独训练专练卡片
  Widget _buildWrongWordDrillCard(BuildContext context, LLPalette ll) {
    final cur = _drillingWord!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ll.surface,
        border: Border.all(color: const Color(0xFFD32F2F), width: 1.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '错词专练 ($_drillPassCount/2 遍)：',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD32F2F),
                  ),
                ),
                const SizedBox(width: 6),
                ChineseTextbookRubyLayout(
                  text: cur.word,
                  charSize: 22.0,
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: '听示范拼读',
                  icon: Icon(Icons.volume_up, size: 20, color: ll.textPrimary),
                  onPressed: () => _speaker.speak(cur.spellingSpeech),
                ),
                const SizedBox(width: 2),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: '跳过此词',
                  icon: Icon(Icons.close, size: 18, color: ll.textTertiary),
                  onPressed: () {
                    setState(() {
                      _startNextWrongWordDrill();
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '示范拼音：${cur.pinyinList.join(" ")}',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: ll.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBorderButton({
    required String label,
    required VoidCallback? onTap,
    required LLPalette ll,
    required int flex,
    bool isHighlight = false,
    bool isPulse = false,
    IconData? icon,
  }) {
    final enabled = onTap != null;
    final isDark = ll.brightness == Brightness.dark;

    final bgColor = isHighlight
        ? (isDark ? Colors.white : const Color(0xFF14161A))
        : ll.surface;

    final textColor = isHighlight
        ? (isDark ? const Color(0xFF14161A) : Colors.white)
        : (enabled ? ll.textPrimary : ll.disabled);

    final borderColor = isHighlight
        ? (isDark ? Colors.white : const Color(0xFF14161A))
        : ll.divider;

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 48,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPulse ? const Color(0xFFD32F2F) : borderColor,
              width: isPulse ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: textColor),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
