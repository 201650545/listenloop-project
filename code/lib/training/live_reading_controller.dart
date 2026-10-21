import 'dart:async';

import 'package:flutter/foundation.dart';

import '../creation/streaming_asr_engine.dart';
import '../preferences/app_preferences.dart';
import '../utils/chinese_pinyin.dart';
import 'continuous_reading_session.dart';
import 'read_along_session.dart';
import 'wake_phrase.dart';

/// 实时朗读的**阶段**。
enum LiveReadPhase {
  /// 还没开始（麦克风未开）。
  idle,

  /// 麦克风开着，正在**等口令**（此时识别文本不参与判分）。
  waitingWake,

  /// 口令已识别，正在正式判这一句（逐字上色）。
  reading,

  /// 这一句读完，等孩子点/自动进下一句。
  sentenceDone,
}

/// 实时朗读控制器（2026-10-21）。
///
/// 把三件事串起来：
///   ① **流式识别**（[StreamingAsrSession]）—— 边说边出字；
///   ② **口令触发**（[WakePhraseDetector]）—— 说出自定义口令才正式开始；
///   ③ **逐字对齐**（[ContinuousReadingSession.applyRecognition] 的 live 模式）
///      —— 读到哪哪儿就变绿，不再是「读完一句忽然整句变红」。
///
/// 纯逻辑（不碰 Flutter widget），可以在电脑上完整单测。
class LiveReadingController extends ChangeNotifier {
  LiveReadingController({
    required this.session,
    required this.streamingEngine,
    String wakePhrase = kDefaultReadWakePhrase,
  }) : _wake = WakePhraseDetector(phrase: wakePhrase);

  /// 整课朗读会话（提供 token 与对齐）。
  final ContinuousReadingSession session;

  /// 流式识别引擎。
  final StreamingAsrEngine streamingEngine;

  final WakePhraseDetector _wake;

  StreamingAsrSession? _asr;
  StreamSubscription<String>? _textSub;

  LiveReadPhase _phase = LiveReadPhase.idle;
  LiveReadPhase get phase => _phase;

  /// 当前口令（用户可改）。
  String get wakePhrase => _wake.display;

  /// 口令文本（流式识别吐出来的累积文本）。
  String _liveText = '';
  String get liveText => _liveText;

  /// 口令已识别（宽松命中也算）。
  WakeMatch? _wakeHit;
  WakeMatch? get wakeHit => _wakeHit;

  /// 口令触发后，正式朗读部分的文本（已切掉口令）。
  String _readingText = '';
  String get readingText => _readingText;

  /// 识别文本 → 音节（去调）。ASR 出的是汉字，这里按课文的音节表转。
  ///
  /// ⚠️ 中文 CTC/流式模型吐的是**汉字**（不是拼音），而对齐器比的是**音节**
  /// （去调拼音）。所以要把识别到的汉字转成音节才能比。
  ///
  /// 做法：识别文本的每个字，用课文的 `char → toneless 音节` 表查（同一课里
  /// 同一个字读音基本一致；多音字取课文里的那个读音 —— 这正是我们要的：
  /// 孩子在照课文读）。
  Map<String, String> _charToSyllable = {};

  /// 识别文本里**不在课文里**的字（无法转音节）—— 记下来做诊断。
  int _unknownChars = 0;

  /// 当前累积文本里是否**还带着口令**。
  ///
  /// 逐句模式的流程：
  ///   · 口令触发那一刻：文本 = 「口令 + 本句」⇒ consume 切掉口令；
  ///   · 这一句读全绿 ⇒ **重置流式** ⇒ 之后吐的文本 = 纯下一句 ⇒ 不再 consume。
  bool _textHasWake = false;

  /// 建立课文「字 → 音节」表。
  void _buildCharMap() {
    _charToSyllable = {};
    for (final t in session.tokens) {
      _charToSyllable.putIfAbsent(t.char, () => t.toneless);
    }
  }

  /// 开始实时朗读：开麦克风、等口令。
  Future<void> start() async {
    if (_phase != LiveReadPhase.idle) return;
    _buildCharMap();
    try {
      _asr = await streamingEngine.openSession(language: 'zh');
    } catch (error) {
      // 没有流式模型 ⇒ 降级（调用方改走离线转写链路）。
      // ignore: avoid_print
      print('[LiveRead] 流式引擎不可用：$error');
      _phase = LiveReadPhase.idle;
      notifyListeners();
      return;
    }
    _textSub = _asr!.texts.listen(_onText);
    _phase = LiveReadPhase.waitingWake;
    notifyListeners();
  }

  /// 停：关麦克风、关流式会话。
  Future<void> stop() async {
    _textSub?.cancel();
    _textSub = null;
    _asr?.dispose();
    _asr = null;
    _phase = LiveReadPhase.idle;
    notifyListeners();
  }

  /// 把一块 PCM 推给流式引擎（由录音器的 onPcm 回调驱动）。
  void pushPcm(List<int> pcm16k) {
    final asr = _asr;
    if (asr == null) {
      _pcmDropped++;
      return;
    }
    _pcmPushed++;
    if (_pcmPushed == 1 || _pcmPushed % 50 == 0) {
      // ignore: avoid_print
      print('[LiveRead] pcm pushed=$_pcmPushed bytes=${pcm16k.length}');
    }
    asr.pushPcm(Uint8List.fromList(pcm16k));
  }

  /// 推给引擎的 PCM 块数（诊断用）。
  int _pcmPushed = 0;

  /// 因引擎没开而丢掉的 PCM 块数（诊断用）。
  int _pcmDropped = 0;

  /// 推给引擎的 PCM 块数（诊断用）。
  int get pcmPushed => _pcmPushed;

  /// 丢掉的 PCM 块数（诊断用）。
  int get pcmDropped => _pcmDropped;

  /// 收到的识别文本条数（诊断用）。
  int _textCount = 0;

  /// 收到的识别文本条数（诊断用）。
  int get textCount => _textCount;

  /// 流式识别吐回来的**累积文本**。
  void _onText(String text) {
    _liveText = text;
    _textCount++;
    if (_textCount == 1 || _textCount % 20 == 0) {
      // ignore: avoid_print
      print('[LiveRead] text#$_textCount = "$text"');
    }

    if (_phase == LiveReadPhase.waitingWake) {
      final hit = _wake.check(text);
      if (hit == WakeMatch.none) {
        notifyListeners();
        return;
      }
      _wakeHit = hit;
      // 切掉口令，剩下的才是课文。
      _readingText = _wake.consume(text);
      _textHasWake = true;
      _phase = LiveReadPhase.reading;
      // ⚠️ 口令和课文可能在**同一段**识别结果里（孩子连着说）。
      //    这里必须立刻对齐一次，否则这段课文要等下一次文本更新才判
      //    —— 表现为「说完口令+课文，那句还是没上色」。
      _applyLive(_readingText);
      notifyListeners();
      return;
    }

    if (_phase == LiveReadPhase.reading) {
      // 口令之后的部分（累积）。
      //
      // ⚠️ 逐句模式：这一句读全绿后上层会**重置流式**（`_asr.reset()`），
      //    重置后吐的文本 = 纯下一句的内容 ⇒ 这时**不能再 consume**（否则会把
        //    下一句的头几个字切掉）。用 [_textHasWake] 区分这两种情况。
      _readingText = _textHasWake ? _wake.consume(text) : text;
      if (_textHasWake) {
        // 本句还没全绿 ⇒ 文本仍带着口令（重置前）。
      }
      final completed = _applyLive(_readingText);
      if (completed) {
        // 这一句全绿了 ⇒ 重置流式，让下一句从干净的音频重新开始。
        //
        // 不重置的话，流式累积文本会一直带着这一句 + 下一句，对齐到下一句时
        // 整体错位 —— 表现为「还没读完这句就一直往下跳」。
        _asr?.reset();
        _textHasWake = false;
        _readingText = '';
      }
      notifyListeners();
    }
  }

  /// 把识别文本喂给对齐器（live 模式 ⇒ 逐字推进）。
  ///
  /// 返回：这一句是否刚刚**全绿完成**（逐句模式）。
  bool _applyLive(String text) {
    if (text.isEmpty) return false;
    final syllables = <String>[];
    _unknownChars = 0;

    // 逐字取读音：
    //   · 课文里有的字 ⇒ 用**课文里的读音**（孩子在照课文读，多音字也对得上）
    //   · 课文里没有的字 ⇒ 用**拼音库给它的读音**（孩子读成了别的字）
    //     ⚠️ 绝不能**丢掉**！丢了的话，对齐器那边就变成「那个字没读到」
    //        （missed / pending），而不是「可能读成了 X」（substituted）——
    //        孩子看不到自己读错成了什么。
    for (final token in ChinesePinyin.format(text)) {
      if (!token.isChinese) continue; // 标点/空白不参与判定
      final inText = _charToSyllable[token.char];
      if (inText != null) {
        syllables.add(inText);
      } else {
        _unknownChars++;
        final py = token.pinyin;
        if (py != null && py.isNotEmpty) {
          syllables.add(ReadAlongSession.stripTones(py).toLowerCase());
        }
      }
    }
    if (syllables.isEmpty) return false;
    return session.applyRecognition(
      syllables: syllables,
      text: text,
      live: true,
    );
  }

  /// 识别文本里不在课文里的字数（诊断用：非零说明 ASR 听到了课文外的东西）。
  int get unknownChars => _unknownChars;

  @override
  void dispose() {
    _textSub?.cancel();
    _asr?.dispose();
    super.dispose();
  }
}
