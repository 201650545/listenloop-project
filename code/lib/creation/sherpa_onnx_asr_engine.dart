import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../preferences/app_preferences.dart';
import 'asr_engine.dart';
import 'asr_window_planner.dart';
import 'seam_reconciler.dart';
import 'vad_segmenter.dart';
import 'word_timestamp.dart';

/// 默认 ASR 模型根目录（App 私有目录，历史位置）。
/// 大模型（FireRedASR2-CTC 740MB）的 adb 部署走 [_rootCandidates] 里的
/// App 外部目录——release 包 run-as 不可用，但 adb 可写
/// `/sdcard/Android/data/<pkg>/files/`（App 对自己的外部目录永远可读）。
Future<String> defaultAsrModelDir() async {
  final docs = await getApplicationDocumentsDirectory();
  return p.join(docs.path, 'models', 'asr');
}

/// 中文流自动换档（2026-10-01 手机端轻量模型矩阵）：
/// 语言 hint 为 zh 时用「中文手机主力档」（Zipformer CTC small zh），
/// 否则回退设置档（默认 fast = NeMo Parakeet CTC 110M 英文手机主力）。
AsrTier resolveTierForLanguage(String? language, AsrTier configured) {
  if (language != null && language.trim().toLowerCase().startsWith('zh')) {
    return AsrTier.zhSmall;
  }
  return configured;
}

/// Runs INSIDE a spawned isolate.
///
/// Decodes the media one BOUNDED window at a time rather than in a single
/// pass. Two reasons, and both are load-bearing (Creation V2 §六十一):
///
/// * a single pass longer than ~400 s deterministically kills the model — the
///   encoder aborts inside `/layers.0/self_attn/Add_2` with a broadcast shape
///   mismatch (`2513 by 7513` at 601 s, `63 by 5063` at 405 s), so a lesson
///   longer than about six and a half minutes could not be created at all;
/// * attention cost grows faster than linearly with length, so windowing is
///   also ~3x faster on the same material.
///
/// Words are grouped, offset and de-duplicated HERE, inside the window loop:
/// the ownership rule needs each token's midpoint relative to the window that
/// produced it, and the layers above must never learn that chunks exist.
///
/// Progress is streamed back over `payload['port']` — a 30 minute job would
/// otherwise sit on a frozen bar for minutes.
/// 常驻 ASR worker 隔离区：**模型只加载一次**，之后循环接活。
///
/// PC 实测（2026-10-15）：zipformer-ctc small zh 构造 recognizer ≈ 8.5s，
/// 而解码 5.6s 音频只要 ≈ 0.17s。旧实现每次 `transcribe` 都 `Isolate.spawn`
/// 并在里面重建 recognizer —— 跟读边读边预览每 2 秒一拍，等于每 2 秒
/// 重加载一次 60MB 模型，慢的是加载不是解码。常驻后每拍只付解码的钱。
void _decodeInIsolate(Map<String, Object> payload) {
  final ready = payload['ready'] as SendPort;
  final jobs = ReceivePort();
  // 昂贵的一半：只在 worker 起时付一次。
  final recognizer = _buildRecognizer(payload);
  ready.send(jobs.sendPort);
  jobs.listen((dynamic message) {
    if (message is! Map) return;
    if (message['stop'] == true) {
      jobs.close();
      return;
    }
    final reply = message['port'] as SendPort;
    try {
      _decodeJob(recognizer, payload, message, reply);
    } catch (error) {
      reply.send({'error': '$error'});
    }
  });
}

/// 按档位配置造 recognizer（贵：加载 ONNX 模型）。
sherpa.OfflineRecognizer _buildRecognizer(Map<String, Object> payload) {
  sherpa.initBindings();
  final dir = payload['dir']! as String;
  final sep = Platform.pathSeparator;
  final targetLanguage = (payload['language'] as String? ?? '').trim();
  final modelKind = (payload['modelKind'] as String? ?? 'whisper').trim();
  final sherpa.OfflineModelConfig modelConfig;
  if (modelKind == 'paraformer') {
    // sherpa-onnx-paraformer-zh-small-2024-03-09（中文·手机主力，~81.8MB）
    modelConfig = sherpa.OfflineModelConfig(
      paraformer: sherpa.OfflineParaformerModelConfig(
        model: '$dir$sep${payload['singleModel']}',
      ),
      tokens: '$dir$sep${payload['tokens']}',
      modelType: 'paraformer',
      numThreads: int.tryParse(payload['threads'] as String? ?? '') ??
          kDefaultAsrThreads,
      debug: false,
      provider: 'cpu',
    );
  } else if (modelKind == 'zipformer_ctc') {
    // sherpa-onnx-zipformer-ctc-small-zh-int8-2025-07-16（中文·手机主力，~60MB，31/31 字级时间戳）
    //
    // ⚠️ 2026-10-21 真机实测修复：**不要传 `modelType: 'zipformer_ctc'`**。
    //   sherpa C++ 的合法 modelType 没有 'zipformer_ctc'（合法的是
    //   'zipformer2' / 'zipformer' / 'paraformer' / 'nemo_ctc' / …），
    //   传一个不认的值 ⇒ 解码器走错分支 ⇒ **text 变成乱码**
    //   （真机日志实证：text="眼镛"、tokens="▁ƍĩ▁ƎŁŢ▁Ɛĸľ"）。
    //   同一模型 + 同一 tokens.txt，在 PC 端不传 modelType 时输出**完整中文**
    //   （「小蝌蚪找妈妈池塘里有一群小蝌蚪…」）。
    //   ⇒ 这里**不传 modelType**（留空，走 sherpa 默认的 CTC 路径）。
    modelConfig = sherpa.OfflineModelConfig(
      zipformerCtc: sherpa.OfflineZipformerCtcModelConfig(
        model: '$dir$sep${payload['singleModel']}',
      ),
      tokens: '$dir$sep${payload['tokens']}',
      numThreads: int.tryParse(payload['threads'] as String? ?? '') ??
          kDefaultAsrThreads,
      debug: false,
      provider: 'cpu',
    );
  } else if (modelKind == 'nemo_ctc') {
    // sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8（英文·手机主力，~131.6MB）
    modelConfig = sherpa.OfflineModelConfig(
      nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(
        model: '$dir$sep${payload['singleModel']}',
      ),
      tokens: '$dir$sep${payload['tokens']}',
      modelType: 'nemo_ctc',
      numThreads: int.tryParse(payload['threads'] as String? ?? '') ??
          kDefaultAsrThreads,
      debug: false,
      provider: 'cpu',
    );
  } else if (modelKind == 'fire_red_asr_ctc') {
    modelConfig = sherpa.OfflineModelConfig(
      fireRedAsrCtc: sherpa.OfflineFireRedAsrCtcModelConfig(
        model: '$dir$sep${payload['singleModel']}',
      ),
      tokens: '$dir$sep${payload['tokens']}',
      modelType: 'fire_red_asr_ctc',
      numThreads: int.tryParse(payload['threads'] as String? ?? '') ??
          kDefaultAsrThreads,
      debug: false,
      provider: 'cpu',
    );
  } else {
    modelConfig = sherpa.OfflineModelConfig(
      whisper: sherpa.OfflineWhisperModelConfig(
        encoder: '$dir$sep${payload['encoder']}',
        decoder: '$dir$sep${payload['decoder']}',
        language: targetLanguage,
        task: 'transcribe',
        enableTokenTimestamps: true,
      ),
      tokens: '$dir$sep${payload['tokens']}',
      modelType: 'whisper',
      numThreads: int.tryParse(payload['threads'] as String? ?? '') ??
          kDefaultAsrThreads,
      debug: false,
      provider: 'cpu',
    );
  }
  return sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: modelConfig,
      decodingMethod: 'greedy_search',
    ),
  );
}

/// 跑一个识别任务（便宜的一半：模型已常驻，只做解码）。
void _decodeJob(
  sherpa.OfflineRecognizer recognizer,
  Map<String, Object> payload,
  Map<Object?, Object?> job,
  SendPort port,
) {
  void progress(double value) => port.send(value);
  final dir = payload['dir']! as String;
  final sep = Platform.pathSeparator;

  final bytes = File(job['wav']! as String).readAsBytesSync();
  const dataOffset = 44;
  // 16-bit mono at 16 kHz: 2 bytes per sample, 16 samples per millisecond.
  final audioMs = (bytes.length - dataOffset) ~/ 2 * 1000 ~/ 16000;

  // Windowing is independent of VAD: with no silence map the planner simply
  // hard-splits at the target length, which is already bounded and safe. VAD
  // only improves WHERE the cuts land (Creation V2 §九/§十) — so a missing VAD
  // model degrades the boundary quality, it never fails the job.
  var silenceGaps = const <SpeechRegion>[];
  final vadPath = '$dir$sep${payload['vad']}';
  if (payload['vad'] != null && File(vadPath).existsSync()) {
    try {
      silenceGaps = VadSegmenter.silenceGaps(
        vadModelPath: vadPath,
        wavBytes: bytes,
        totalMs: audioMs,
      );
    } catch (error) {
      debugPrint('[ListenLoop][vad] unavailable, hard-splitting: $error');
    }
  }

  final windows = AsrWindowPlanner.plan(
    totalMs: audioMs,
    silenceGaps: silenceGaps,
    targetWindowMs:
        int.tryParse(payload['windowTargetMs'] as String? ?? '') ??
        kDefaultTargetWindowMs,
    hardMaxWindowMs:
        int.tryParse(payload['windowHardMaxMs'] as String? ?? '') ??
        kHardMaxWindowMs,
  );
  debugPrint(
    '[ListenLoop][vad] pauses=${silenceGaps.length} windows=${windows.length}',
  );
  progress(0);

  final collected = <SeamWord>[];
  for (var i = 0; i < windows.length; i++) {
    final window = windows[i];
    final samples = _samplesFor(bytes, window.readStartMs, window.readEndMs);
    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);

    // 字节级 BBPE 档（中文手机主力档）：`result.tokens` 是 `tokens.txt` 里的
    // 原始字节片，拼起来是 `▁ƌŕş…` 这种乱码；只有 `result.text` 是正确中文。
    // 直接把 `text` 拆成字符当作 token 流，并把时间戳重采样到等长——
    // 下游 `tokensToWords` 与接缝逻辑因此完全不用知道 BBPE 的存在。
    final List<String> tokens;
    final List<double> timestamps;
    if (payload['byteLevelBpe'] == true) {
      tokens = _charsOf(result.text);
      timestamps = _resampleTimestamps(result.timestamps, tokens.length);
      // WP-H 诊断常驻可见：BBPE 档必须看到 text 是中文、tokens 是字节片。
      // ignore: avoid_print
      print(
        '[ReadAlong][diag][bbpe] win=$i rawTokens=${result.tokens.length} '
        'rawJoined="${result.tokens.join().length > 40 ? result.tokens.join().substring(0, 40) : result.tokens.join()}" '
        'text="${result.text}" chars=${tokens.length}',
      );
    } else {
      tokens = result.tokens;
      timestamps = result.timestamps;
    }

    final local = tokensToWords(
      tokens,
      timestamps,
      durationMs: window.readEndMs - window.readStartMs,
    );
    for (final word in local) {
      // The one invariant that keeps the Timeline honest: global requires the
      // window's read offset, because local times are relative to what the
      // model actually saw (Creation V2 §八).
      final startMs = word.startMs + window.readStartMs;
      final endMs = word.endMs + window.readStartMs;
      // Owned by whichever window contains the midpoint. This stays the first
      // ownership signal; the seam pass below refines it (§二十七).
      final midpoint = (startMs + endMs) ~/ 2;
      if (midpoint < window.keepStartMs || midpoint >= window.keepEndMs) {
        continue;
      }
      collected.add(
        SeamWord(
          word: word.word,
          startMs: startMs,
          endMs: endMs,
          windowId: i,
          readStartMs: window.readStartMs,
          readEndMs: window.readEndMs,
        ),
      );
    }
    progress((i + 1) / windows.length);
  }

  collected.sort((a, b) => a.startMs.compareTo(b.startMs));
  // Ownership alone is not enough: the two windows straddling a seam estimate
  // a token's midpoint independently, and a millisecond of disagreement puts
  // the same word in both keep ranges (§二十八).
  final words = reconcileSeams(
    collected,
    [for (final window in windows.skip(1)) window.keepStartMs],
  );
  port.send({
    'words': [
      for (final word in words) [word.word, word.startMs, word.endMs],
    ],
    'windows': windows.length,
    'audioMs': audioMs,
  });
}

/// Splits decoded text into per-character pieces.
///
/// Byte-level-BPE models hand back the finished string in `result.text` but
/// only raw byte pieces in `result.tokens`, so the characters themselves are
/// the finest granularity available. Punctuation stays as its own piece, which
/// is what [tokensToWords] already expects (`music` + `.`).
List<String> _charsOf(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  return trimmed.split('');
}

/// Re-maps `count` source timestamps onto `length` output slots.
///
/// Used with [_charsOf]: a BBPE byte piece and a decoded character are not
/// 1:1 (a Chinese character is typically 3 bytes), so the real per-token
/// times have to be stretched over the characters they produced. Linear
/// resampling keeps monotonic, in-range times, which is all the seam and
/// ownership logic needs (Creation V2 §八).
List<double> _resampleTimestamps(List<double> source, int length) {
  if (source.isEmpty || length <= 0) return const [];
  if (source.length == length) return source;
  final total = source.last;
  final out = <double>[];
  for (var i = 0; i < length; i++) {
    final t = length == 1 ? 0.0 : (i / (length - 1)) * (source.length - 1);
    if (t >= source.length - 1) {
      out.add(source.last);
      continue;
    }
    final lo = t.floor();
    final frac = t - lo;
    out.add(source[lo] + (source[lo + 1] - source[lo]) * frac);
  }
  // Resampling lands on the last token time, never past it.
  if (out.length == length && total > 0 && out.last > total) {
    out[length - 1] = total;
  }
  return out;
}

/// Builds one window's samples straight out of the WAV bytes.
///
/// Deliberately per window rather than one buffer for the whole media: a
/// 30 minute clip would otherwise hold a 115 MB Float32List for the entire
/// job (Creation V2 §十六).
Float32List _samplesFor(Uint8List bytes, int startMs, int endMs) {
  const dataOffset = 44;
  const samplesPerMs = 16; // 16 kHz
  final first = dataOffset + startMs * samplesPerMs * 2;
  final last = (dataOffset + endMs * samplesPerMs * 2).clamp(0, bytes.length);
  final count = last > first ? (last - first) ~/ 2 : 0;
  final out = Float32List(count);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < count; i++) {
    out[i] = view.getInt16(first + i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Production ASR engine: a self-exported Whisper ONNX model with
/// cross-attention outputs, served by sherpa-onnx. Two tiers share the same
/// pipeline (2026-09-18 用户拍板, both multilingual checkpoints):
///
/// * fast — whisper base (`models/asr/whisper-base/`, ~160 MB int8);
/// * precise — whisper small (`models/asr/whisper-small/`, ~374 MB int8).
///
/// WHY SELF-EXPORTED (the M1 blocker, resolved 2026-09-18): the whisper
/// exports sherpa-onnx publishes carry NO cross-attention outputs, so
/// `enableTokenTimestamps` warns and every token timestamp is 0 — a 4:46
/// transcript collapses to a single word. Word timestamps exist only when the
/// decoder has the 4th `cross_attention_weights` output; sherpa-onnx then
/// derives per-token times via DTW. The official `export-onnx-with-attention.py`
/// produces exactly that — BUT it must run under torch ≤2.8: the torch 2.14
/// dynamo exporter bakes the dynamic T axis and the runtime fails with a
/// Reshape error (verified both ways on PC). The multilingual checkpoints are
/// used deliberately (用户: 不要把路走窄 — 中文课是同一管道换个语言参数).
///
/// Whisper still caps a single inference at 30 s ("Only waves less than 30
/// seconds are supported" — longer input is silently truncated), so windows
/// are planned at 25 s keep / 27 s hard max: with the 2 s context overlap the
/// read span stays under the cap while the windowing architecture is
/// untouched.
///
/// Windows are decoded in a spawned isolate so the UI keeps breathing
/// (spec V1 §四十二) and so progress can be reported per window.
class SherpaOnnxAsrEngine implements AsrEngine {
  SherpaOnnxAsrEngine({
    required this.modelDirResolver,
    this.tier,
    this.vadModelFile = 'silero_vad.onnx',
    int Function()? threads,
  }) : _threads = threads ?? (() => kDefaultAsrThreads);

  /// Resolves the ASR models root (resolved lazily — the directory may be
  /// created/pushed after app start). The tier selects a subdirectory under
  /// it via [AsrTier.modelDirName].
  final Future<String> Function() modelDirResolver;

  /// Which quality tier to transcribe with, read per job so a settings
  /// change applies without rebuilding the engine. Null = fast tier.
  final AsrTier Function()? tier;

  /// Silero VAD model, relative to the resolved directory. Optional: when it
  /// is absent the planner hard-splits instead of cutting at pauses.
  final String vadModelFile;

  /// Decode threads, read per call so a settings change applies to the next
  /// job without rebuilding the engine (Creation V2 §十五).
  final int Function() _threads;

  String? _resolvedRoot;

  /// 常驻 worker：key 是模型配置指纹，值是「投任务的 SendPort」。
  ///
  /// 同一个配置只加载一次模型，后续所有识别（含跟读每 2 秒的快照预览）
  /// 复用它——见 [_decodeInIsolate] 的耗时实测。
  final Map<String, Future<SendPort>> _workers = {};

  /// 取（必要时启动）与 [config] 对应的常驻 worker。
  ///
  /// 配置变了（换档 / 换模型目录）就换 key 起新的；旧 worker 被丢弃，
  /// 由 GC 随 isolate 回收，不主动 kill 以免打断在飞的解码。
  Future<SendPort> _workerFor(Map<String, Object> config) {
    final key = config.entries
        .map((e) => '${e.key}=${e.value}')
        .join('|');
    return _workers.putIfAbsent(key, () async {
      final ready = ReceivePort();
      await Isolate.spawn(
        _decodeInIsolate,
        <String, Object>{...config, 'ready': ready.sendPort},
      );
      return await ready.first as SendPort;
    });
  }

  /// 该档的模型文件是否齐全（whisper 双档 vs CTC 单文件）。
  Future<bool> _tierFilesExist(AsrTier currentTier, String dir) async {
    final sep = Platform.pathSeparator;
    if (currentTier.needsEncoderDecoder) {
      return File('$dir$sep${currentTier.encoderFile}').existsSync() &&
          File('$dir$sep${currentTier.decoderFile}').existsSync() &&
          File('$dir$sep${currentTier.tokensFile}').existsSync();
    }
    return File('$dir$sep${currentTier.singleModelFile}').existsSync() &&
        File('$dir$sep${currentTier.tokensFile}').existsSync();
  }

  /// 按语言 hint 选档（2026-09-29：中文流自动换 FireRedASR2-CTC 中文朗读档），
  /// 该档模型未安装时回退设置档（whisper）——增强项不阻塞（08 号红线）。
  Future<(AsrTier, String, bool)> _resolveEffectiveTier(String? language) async {
    final configured = tier?.call() ?? AsrTier.fast;
    final wanted = resolveTierForLanguage(language, configured);
    final wantedDir = await _dirFor(wanted);
    if (await _tierFilesExist(wanted, wantedDir)) {
      return (wanted, wantedDir, true);
    }
    if (wanted != configured) {
      // WP-H 诊断常驻可见：静默 fallback 是头号坑，必须在 release/logcat 可见。
      // ignore: avoid_print
      print(
        '[ReadAlong][diag][fallback] ${wanted.label} model not installed in '
        '$wantedDir, falling back to ${configured.label}',
      );
      debugPrint(
        '[ListenLoop][asr] ${wanted.label} model not installed, '
        'falling back to ${configured.label}',
      );
      final fallbackDir = await _dirFor(configured);
      return (configured, fallbackDir, false);
    }
    return (configured, wantedDir, false);
  }

  /// 模型根目录候选（按序探测，取第一个有该档模型文件的）：
  /// 1. `modelDirResolver`（App 私有目录，历史位置）；
  /// 2. App 外部目录 `Android/data/<pkg>/files/models/asr` —— adb 可写、
  ///    App 可读（release 包 run-as 不可用，大模型 adb 部署走这里，
  ///    2026-09-29 FireRedASR2-CTC 中文朗读档引入）。
  Future<List<String>> _rootCandidates() async {
    final primary = _resolvedRoot ??= await modelDirResolver();
    final roots = <String>[primary];
    final ext = await getExternalStorageDirectory();
    if (ext != null && ext.path != primary) {
      roots.add(p.join(ext.path, 'models', 'asr'));
    }
    return roots;
  }

  Future<String> _dirFor(AsrTier tierKind) async {
    final sep = Platform.pathSeparator;
    final roots = await _rootCandidates();
    String? found;
    for (final root in roots) {
      for (final candidate in tierKind.dirCandidates) {
        final dir = '$root$sep$candidate';
        found ??= dir;
        final exists = await _tierFilesExist(tierKind, dir);
        debugPrint('[ListenLoop][asr] probe $dir '
            'model=${File('$dir$sep${tierKind.needsEncoderDecoder ? tierKind.encoderFile : tierKind.singleModelFile}').existsSync()} '
            'tokens=${File('$dir$sep${tierKind.tokensFile}').existsSync()} -> $exists');
        if (exists) return dir;
      }
    }
    return found ?? '${roots.first}$sep${tierKind.modelDirName}';
  }

  @override
  Future<List<WordTimestamp>> transcribe(
    String wavPath, {
    String? language,
    required void Function(double progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    onProgress(0);
    final (currentTier, dir, usingZhModel) = await _resolveEffectiveTier(
      language,
    );
    // WP-H 诊断常驻可见日志（执行方案 §一第1板斧 + §二修复A-2）：
    // 中文课必须是 zh 系档，看到 en/nemo/fallback 就是元凶。
    // 用 print 确保 release/logcat 可见（debugPrint 在 release 被抑制）。
    // ignore: avoid_print
    print(
      '[ReadAlong][diag] language=${language ?? "(null)"} '
      'tier=${currentTier.label} kind=${currentTier.sherpaModelKind} dir=$dir '
      'usingZhModel=$usingZhModel',
    );
    if (usingZhModel) {
      debugPrint('[ListenLoop][asr] tier=${currentTier.label} (中文手机主力)');
    } else {
      // ignore: avoid_print
      print(
        '[ReadAlong][diag][warn] NOT using zh model '
        '(language=${language ?? "(null)"} tier=${currentTier.label})',
      );
    }
    if (!(await _tierFilesExist(currentTier, dir))) {
      final missing = currentTier.needsEncoderDecoder
          ? '${currentTier.encoderFile}, ${currentTier.decoderFile}, ${currentTier.tokensFile}'
          : '${currentTier.singleModelFile}, ${currentTier.tokensFile}';
      throw StateError('ASR model not installed in $dir (expected $missing)');
    }
    if (isCancelled()) return const [];

    final config = <String, Object>{
      'dir': dir,
      'modelKind': currentTier.sherpaModelKind,
      'encoder': currentTier.encoderFile,
      'decoder': currentTier.decoderFile,
      'singleModel': currentTier.singleModelFile,
      'tokens': currentTier.tokensFile,
      'byteLevelBpe': currentTier.tokensAreByteLevelBpe,
      'vad': vadModelFile,
      'threads': '${_threads()}',
      'language': language ?? '',
      // Whisper caps a single inference at 30 s; 25 s keep + 27 s hard max
      // keeps the 2 s context overlap inside the cap (90 s is the NeMo
      // bring-up value and no longer used by any shipped model).
      'windowTargetMs': '25000',
      'windowHardMaxMs': '27000',
    };
    final messages = ReceivePort();
    try {
      final jobs = await _workerFor(config);
      jobs.send(<String, Object>{
        'wav': wavPath,
        'port': messages.sendPort,
      });
      // Progress arrives as doubles; the single Map is the final result.
      Object? result;
      await for (final message in messages) {
        if (message is double) {
          onProgress(message);
        } else if (message is Map) {
          result = message;
          break;
        }
      }
      if (isCancelled()) return const [];
      if (result is! Map) {
        final failure = result == null ? null : (result as Map)['error'];
        if (failure != null) throw StateError('ASR decode failed: $failure');
        return const [];
      }

      final raw = (result['words'] as List?) ?? const [];
      final words = <WordTimestamp>[
        for (final entry in raw)
          WordTimestamp(
            word: (entry as List)[0] as String,
            startMs: entry[1] as int,
            endMs: entry[2] as int,
          ),
      ];
      debugPrint(
        '[ListenLoop][asr] windows=${result['windows']} '
        'audioMs=${result['audioMs']} words=${words.length}',
      );
      onProgress(1);
      return words;
    } finally {
      messages.close();
    }
  }
}

/// Upper bound on how far a word may be extended past its own last token.
///
/// sherpa-onnx reports the frame each CTC token FIRED on, i.e. its start, so a
/// word's end has to be inferred from the next boundary. Clamping the reach
/// keeps a real silence visible as a gap — without it every inter-word gap
/// would close to zero and the segmenter's 900 ms silence rule would never
/// fire again.
const int kMaxTokenMs = 320;

/// Sentencepiece / byte-level-BPE word-start markers.
final RegExp _wordStartMarker = RegExp(r'^[\u2581\u0120]');

/// Standalone whitespace piece.
final RegExp _leadingWhitespace = RegExp(r'^\s');

/// A piece carrying no word of its own — it attaches to the word it follows
/// ("music" + "." -> "music.").
final RegExp _punctuationOnly = RegExp(
  r'''^[\s.,!?;:'"()\[\]\u2019\u201c\u201d、。！？…—·～「」『』【】《》-]+$''',
);

/// CJK character pattern (Japanese kana/kanji, Chinese, Korean).
final RegExp _cjkPattern = RegExp(
  r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]',
);

/// Groups CTC token pieces into words.
///
/// Handles both English space-separated pieces and CJK (Japanese/Chinese)
/// continuous characters using punctuation, acoustic pauses (>250ms), and
/// CJK word-span limits.
///
/// When [timestamps] are omitted or empty (e.g. models without CIF/timestamp heads
/// like Paraformer small), [durationMs] is used to smoothly space words across
/// the audio window so alignment and midpoint bounding remain consistent.
List<WordTimestamp> tokensToWords(
  List<String> tokens,
  List<double> timestamps, {
  int? durationMs,
}) {
  final words = <WordTimestamp>[];
  if (tokens.isEmpty) return words;

  final hasRealTimestamps =
      timestamps.isNotEmpty && timestamps.any((t) => t > 0);
  final effectiveTimestamps = hasRealTimestamps
      ? timestamps
      : List<double>.generate(tokens.length, (i) {
          final totalMs = durationMs ?? (tokens.length * 200);
          return (i / tokens.length) * (totalMs / 1000.0);
        });

  final buffer = StringBuffer();
  var startMs = 0;
  var lastMs = 0;
  var open = false;
  var pendingBreak = false;

  void flush(int nextMs) {
    final text = buffer.toString().trim();
    if (text.isNotEmpty) {
      final reach = nextMs > lastMs ? (nextMs - lastMs).clamp(0, kMaxTokenMs) : 0;
      words.add(
        WordTimestamp(word: text, startMs: startMs, endMs: lastMs + reach),
      );
    }
    buffer.clear();
    open = false;
    pendingBreak = false;
  }

  for (var i = 0; i < tokens.length; i++) {
    final raw = tokens[i];
    final ms = i < effectiveTimestamps.length
        ? (effectiveTimestamps[i] * 1000).round()
        : lastMs;
    final body = raw.replaceFirst(_wordStartMarker, '').trim();
    if (body.isEmpty) {
      pendingBreak = true;
      continue;
    }

    final isPunct = _punctuationOnly.hasMatch(body);
    final isCjk = _cjkPattern.hasMatch(body);
    final prevIsCjk = buffer.isNotEmpty && _cjkPattern.hasMatch(buffer.toString());

    // In CJK (Japanese/Chinese), tokens have no leading space. We use acoustic pauses
    // (>= 300ms) or natural CJK span length to identify word boundaries.
    final cjkAcousticPause = open && (isCjk || prevIsCjk) && (ms - lastMs >= 300);
    final cjkLengthBreak = open && isCjk && prevIsCjk && buffer.length >= 4;

    final startsWord =
        pendingBreak ||
        _leadingWhitespace.hasMatch(raw) ||
        _wordStartMarker.hasMatch(raw) ||
        cjkAcousticPause ||
        cjkLengthBreak;

    if (open && startsWord && !isPunct) {
      flush(ms);
    }

    if (!open) {
      startMs = ms;
      open = true;
    }
    lastMs = ms;
    buffer.write(body);

    // If this token was punctuation, force next token to start anew.
    if (isPunct) {
      pendingBreak = true;
    }
  }
  flush(lastMs + kMaxTokenMs);
  return words;
}

