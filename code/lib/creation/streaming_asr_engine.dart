import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// **流式**（真·实时）语音识别会话。
///
/// 与离线 `transcribe(wav)` 的根本区别：
///   · 离线：喂一整个 wav，等它解完 → 出结果（**必须录完才有字**）
///   · 流式：PCM 块**逐块**推进去，每块解一次 → **边说边出字**
///
/// 这是「像语音输入法一样实时识别」的技术前提：
/// sherpa-onnx 的 `OnlineRecognizer` 维护**有状态的解码上下文**，
/// 每 100ms 喂一块 16kHz PCM，`isReady()` 为真时 `decode()` 一次，
/// `getResult()` 立刻拿到**当前累积文本**（不必等这一句读完）。
///
/// 2026-10-21 PC 端实测（sherpa_onnx 1.13.8 + 流式模型）：
///   · `streaming-zipformer-ctc-zh-int8-2025-06-30`（中文 CTC 流式，154MB）
///     喂课包真人朗读：帧序列
///     '小' → '小蝌' → '小蝌蚪找妈妈池塘里有一群小蝌蚪…'（增量出字 ✅）
///   · `x-asr-480ms-streaming-zipformer-transducer-zh-en-punct`（带标点，169MB）
///     同音频输出 '小蝌蚪找妈妈， 池塘里有一群小蝌蚪，…'（带标点 ✅）
///
/// **接口形态**：推入（不等待）+ 文本流回来。
///   · [pushPcm] 是 fire-and-forget —— 录音回调绝不能被解码阻塞
///   · [texts] 每次解码完成就吐一次**当前累积文本**（UI 据此逐字上色）
abstract class StreamingAsrSession {
  /// 推一块 16kHz 单声道 PCM（int16 原始字节）。**不等待**解码。
  void pushPcm(Uint8List pcmBytes);

  /// 解码结果流：每次解码完成就发一次**当前累积文本**。
  Stream<String> get texts;

  /// 冲一次尾部（= 说话结束），把最后的字逼出来。
  void finish();

  /// 清空上下文（下一句重新开始）。
  void reset();

  void dispose();
}

/// 流式 ASR 引擎：打开一个会话。
abstract class StreamingAsrEngine {
  /// 当前是否具备流式模型（没有就降级：调用方改走离线转写）。
  Future<bool> isAvailable();

  /// 打开一个流式会话。模型缺失时抛 [StateError]。
  Future<StreamingAsrSession> openSession({String? language});
}

/// sherpa-onnx 的流式实现（在线识别器常驻 isolate，模型只加载一次）。
///
/// **为什么放 isolate**：解码 100~300ms/块，放在 UI isolate 会掉帧
/// （这正是「字幕卡卡的」的来源之一）。常驻 isolate 后每块只付解码的钱，
/// 且 UI isolate 完全不被阻塞。
class SherpaOnnxStreamingAsrEngine implements StreamingAsrEngine {
  SherpaOnnxStreamingAsrEngine({
    required this.modelDirResolver,
    int Function()? threads,
  }) : _threads = threads ?? (() => 2);

  /// 解析流式模型根目录（懒解析 —— 目录可能 App 启动后才推上去）。
  final Future<String> Function() modelDirResolver;

  final int Function() _threads;

  /// 流式模型子目录名（按序探测，第一个文件齐的胜出）。
  static const List<String> candidates = [
    'sherpa-onnx-streaming-zipformer-ctc-zh-int8-2025-06-30',
    'sherpa-onnx-x-asr-480ms-streaming-zipformer-transducer-zh-en-punct-int8-2026-06-25',
  ];

  String? _cachedDir;
  bool? _cachedAvailable;

  @override
  Future<bool> isAvailable() async {
    if (_cachedAvailable != null) return _cachedAvailable!;
    final dir = await _resolveDir();
    _cachedAvailable = dir != null;
    return _cachedAvailable!;
  }

  Future<String?> _resolveDir() async {
    if (_cachedDir != null) return _cachedDir;
    final root = await modelDirResolver();
    final sep = Platform.pathSeparator;
    for (final name in candidates) {
      final dir = '$root$sep$name';
      final hasModel = File('$dir${sep}model.int8.onnx').existsSync() ||
          File('$dir${sep}encoder.int8.onnx').existsSync();
      final hasTokens = File('$dir${sep}tokens.txt').existsSync();
      if (hasModel && hasTokens) {
        _cachedDir = dir;
        // ignore: avoid_print
        print('[ReadAlong][stream] model dir = $dir');
        return dir;
      }
    }
    return null;
  }

  @override
  Future<StreamingAsrSession> openSession({String? language}) async {
    final dir = await _resolveDir();
    if (dir == null) {
      throw StateError('流式 ASR 模型未安装（期望 $candidates 之一）');
    }
    return _StreamSession.start(dir: dir, threads: _threads());
  }
}

/// isolate 侧的常驻流式解码器：**一个 isolate 管所有会话**。
class _StreamWorker {
  _StreamWorker._(this._isolate, this._commands);

  final Isolate _isolate;
  final SendPort _commands;

  SendPort get commands => _commands;

  static Future<_StreamWorker> start({
    required String dir,
    required int threads,
  }) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
      _streamWorkerMain,
      <String, Object>{
        'dir': dir,
        'threads': threads,
        'ready': ready.sendPort,
      },
      debugName: 'll-asr-stream',
    );
    final map = await ready.first as Map<String, Object>;
    ready.close();
    if (map['error'] != null) {
      isolate.kill(priority: Isolate.immediate);
      throw StateError('流式 ASR worker 启动失败：${map['error']}');
    }
    final cmds = map['commands']! as SendPort;
    return _StreamWorker._(isolate, cmds);
  }

  void send(Object msg) => _commands.send(msg);

  void kill() => _isolate.kill(priority: Isolate.immediate);
}

/// isolate 入口：建 OnlineRecognizer，之后按 sessionId 管理多个流。
void _streamWorkerMain(Map<String, Object> payload) {
  final ready = payload['ready'] as SendPort;
  final dir = payload['dir']! as String;
  final threads = payload['threads']! as int;
  final sep = Platform.pathSeparator;

  sherpa.initBindings();
  late final sherpa.OnlineRecognizer recognizer;
  try {
    // 中文流式 CTC：单个 model.int8.onnx + tokens.txt。
    //
    // ⚠️ **不传 modelType** —— 2026-10-21 真机实测：传 sherpa C++ 不认的
    // 值（离线档那边传过 'zipformer_ctc'）会让解码器走错分支 ⇒ text 乱码
    // （「眼镛」）；不传则输出完整中文。
    recognizer = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        feat: const sherpa.FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        model: sherpa.OnlineModelConfig(
          zipformer2Ctc: sherpa.OnlineZipformer2CtcModelConfig(
            model: '$dir${sep}model.int8.onnx',
          ),
          tokens: '$dir${sep}tokens.txt',
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        ),
        decodingMethod: 'greedy_search',
      ),
    );
  } catch (error) {
    ready.send(<String, Object>{'error': '$error'});
    return;
  }

  final sessions = <int, sherpa.OnlineStream>{};
  var _pcmCount = 0;
  final inbox = ReceivePort();
  inbox.listen((dynamic message) {
    if (message is! Map) return;
    final reply = message['port'] as SendPort?;
    try {
      final sid = message['session'] as int;
      switch (message['op'] as String) {
        case 'open':
          sessions[sid] = recognizer.createStream();
          reply?.send(<String, Object>{'text': ''});
        case 'pcm':
          final stream = sessions[sid]!;
          final pcm = message['pcm'] as Uint8List;
          final n = pcm.length ~/ 2;
          final samples = Float32List(n);
          final view = ByteData.sublistView(pcm);
          for (var i = 0; i < n; i++) {
            samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
          }
          stream.acceptWaveform(samples: samples, sampleRate: 16000);
          while (recognizer.isReady(stream)) {
            recognizer.decode(stream);
          }
          final text = recognizer.getResult(stream).text;
          _pcmCount++;
          if (_pcmCount == 1 || _pcmCount % 50 == 0) {
            // ignore: avoid_print
            print('[LiveRead][worker] pcm=$_pcmCount text="$text"');
          }
          reply?.send(<String, Object>{'text': text});
        case 'finish':
          final stream = sessions[sid]!;
          stream.inputFinished();
          while (recognizer.isReady(stream)) {
            recognizer.decode(stream);
          }
          reply?.send(<String, Object>{
            'text': recognizer.getResult(stream).text,
          });
        case 'reset':
          final stream = sessions[sid]!;
          recognizer.reset(stream);
          reply?.send(<String, Object>{'text': ''});
        case 'close':
          sessions.remove(sid)?.free();
          reply?.send(<String, Object>{'text': ''});
      }
    } catch (error) {
      reply?.send(<String, Object>{'error': '$error'});
    }
  });

  ready.send(<String, Object>{'ok': true, 'commands': inbox.sendPort});
}

/// 一个流式会话（主 isolate 侧）。
class _StreamSession implements StreamingAsrSession {
  _StreamSession._(this._worker, this._id, this._reply, this._texts);

  final _StreamWorker _worker;
  final int _id;
  final ReceivePort _reply;
  final StreamController<String> _texts;

  static Future<_StreamSession> start({
    required String dir,
    required int threads,
  }) async {
    final worker = await _StreamWorker.start(dir: dir, threads: threads);
    final reply = ReceivePort();
    final texts = StreamController<String>.broadcast();
    // isolate 的回信 → 文本流（UI 侧订阅它做逐字上色）。
    reply.listen((dynamic message) {
      if (message is! Map) return;
      final err = message['error'];
      if (err != null) return;
      final text = message['text'] as String? ?? '';
      if (text.isNotEmpty) texts.add(text);
    });
    final id = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    worker.send(<String, Object>{
      'op': 'open',
      'session': id,
      'port': reply.sendPort,
    });
    return _StreamSession._(worker, id, reply, texts);
  }

  @override
  void pushPcm(Uint8List pcmBytes) {
    // fire-and-forget：录音回调绝不能等解码。
    _worker.send(<String, Object>{
      'op': 'pcm',
      'session': _id,
      'pcm': pcmBytes,
      'port': _reply.sendPort,
    });
  }

  @override
  Stream<String> get texts => _texts.stream;

  @override
  void finish() {
    _worker.send(<String, Object>{
      'op': 'finish',
      'session': _id,
      'port': _reply.sendPort,
    });
  }

  @override
  void reset() {
    _worker.send(<String, Object>{
      'op': 'reset',
      'session': _id,
      'port': _reply.sendPort,
    });
  }

  @override
  void dispose() {
    try {
      _worker.send(<String, Object>{
        'op': 'close',
        'session': _id,
        'port': _reply.sendPort,
      });
    } catch (_) {
      // 关掉失败也别抛 —— worker 即将被 kill。
    }
    _texts.close();
    _reply.close();
    _worker.kill();
  }
}
