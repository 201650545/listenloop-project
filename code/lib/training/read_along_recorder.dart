/// 跟读验收录音器（WP-H 阶段 1：收音 + 临时 wav + 能量法端点检测）。
///
/// 设计依据 `05_任务书\WP-H_跟读验收模式_可执行实现方案_2026-10-10.md`：
///   * §二 关键架构洞察：`AsrEngine.transcribe` 吃 wav 文件路径，不吃实时流
///     ——录完一句存个临时 wav 喂给引擎即可，不需要流式识别。
///   * §三 判读完：尾部静音 ≥ 600ms 判定孩子读完；录音兜底上限 = 该句音频
///     时长 × 3 + 2000ms；全程没检出语音不算失败。
///   * §4.5 端点检测：能量法 RMS（不引模型），阈值 0.02 满量程保守起步，
///     **真机再调**。
///   * §九.6：临时 wav 识别完即删——不长期留存、不进 SQLite、不进备份导出、
///     不进 Anki。
///   * §九.5：录音前播放侧已 pause（门在 `sentence_player_controller`），
///     外放不会录进自己。
///
/// **2026-10-13 采样率根因（修"只吐 1 个音节 ii / 0.05 分"）**：
/// 安卓 `AudioRecord` 只把请求的 sampleRate 当建议，设备按原生率交付
/// （小米14 = 48000）且不告知真实值。此前请求 16k 拿到的是 16k 头 +
/// 48k 身的 PCM：声音被拉慢 3 倍、频谱下移 3 倍（实测 91% 能量 <1kHz、
/// 峰值 290Hz），CTC 模型听到一滩糊声 → 整句只解出 "ii"。
/// 修法：明确请求 48000 + 管线内 [PcmDecimator] 低通抽取到 16k，
/// 采样率从此确定、可测。别再退回"请求 16k 赌设备"。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 麦克风权限被拒（方案 §三：降级「仅跟读不评分」，绝不死锁）。
class ReadAlongMicPermissionDenied implements Exception {
  const ReadAlongMicPermissionDenied();

  @override
  String toString() => '麦克风权限被拒：跟读验收降级为仅跟读不评分';
}

/// 收音事件（UI 只跟这一个流）。
sealed class ReadAlongRecorderEvent {}

/// 音量级（RMS 满量程 0~1）：驱动录音态脉冲圈。
final class RecorderLevel extends ReadAlongRecorderEvent {
  RecorderLevel(this.rms);

  final double rms;
}

/// 收音结束，临时 wav 已落盘（用完即删，见 [ReadAlongRecorder.deleteWav]）。
final class RecorderStopped extends ReadAlongRecorderEvent {
  RecorderStopped(this.wavPath, {required this.timedOut});

  final String wavPath;

  /// 是否触及兜底上限强制收尾（孩子一直不吭声/环境噪音挂住）。
  final bool timedOut;
}

/// 全程没检出语音（方案 §三「噪音/没读」行）：不算失败、不计重试次数，
/// 提示「没听到你，再来一次」。空文件已删，不会进判分链路。
final class RecorderSilent extends ReadAlongRecorderEvent {}

/// 收音链路出错（采集流中断等）：不死锁，回到「再来一次」。
final class RecorderFailed extends ReadAlongRecorderEvent {
  RecorderFailed(this.error);

  final Object error;
}

/// 麦克风抽象——录音包的接缝，测试注入假实现。
abstract class ReadAlongMic {
  /// 检查并（按平台策略）请求录音权限。false = 被拒。
  Future<bool> hasPermission();

  /// 开始 PCM16 单声道 16kHz 块流。
  Future<Stream<Uint8List>> startStream();

  /// 正常收尾（保留已采数据）。
  Future<void> stop();

  /// 丢弃本次收音。
  Future<void> cancel();

  Future<void> dispose();
}

/// 真实实现：record 包的 [AudioRecorder]。
class RecordMic implements ReadAlongMic {
  RecordMic([AudioRecorder? recorder]) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream() => _recorder.startStream(
        const RecordConfig(
          // 48000 主动请求（2026-10-13 真机结论）：安卓 AudioRecord 只把
          // sampleRate 当"请求值"，设备可能按原生率交付（小米14 = 48k）且
          // 不告诉你真实值。请求 16k 会拿到 16k 头 + 48k 身的 PCM，
          // 声音被拉慢 3 倍，ASR 只能吐乱码。主动要 48k、自己抽取到 16k，
          // 采样率从此是确定的，不再赌设备。
          //
          // ⚠️ 2026-10-21：**"请求值"不等于"实际交付值"**（不同机型会给别的
          //   采样率）⇒ 转换器参数必须对应实际采集的数据；见 [ReadAlongRecorder]
          //   的诊断日志。
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 48000,
          numChannels: 1,
          // ⚠️ 2026-10-21：删掉 `bitRate: 16000` —— PCM16 是**无压缩**采集，
          //   这个值对采集毫无作用，却会被后来人误读成"音量/码率增益"。
          //
          // autoGain / noiseSuppress 全部**关掉**，音频源改 `unprocessed`：
          //   · record 包自己的文档对这三个开关都写着
          //     "Recording volume may be lowered by using this."（用了会**压低音量**）
          //   · record_android 的实现是系统级音频效果
          //     （`agc.enabled = config.autoGain` / `ns.enabled = …`），
          //     Android 的 AGC 会把"够响"的帧压下去 ⇒ 孩子轻声/离远一点时
          //     反而被压得更弱 —— 这正是"必须好大好大的声音"的最可能来源。
          //   · `unprocessed`（API 24+）连硬件端的 AGC/NS/AEC 都不要，
          //     我们自己用**固定增益 + 软限幅**控制（见 [PcmGain]），
          //     增益恒定、不在句中跳变，比系统的双向 AGC 稳。
          //   · 代价：环境底噪会一起进来 ⇒ 判读仍以「音节级对齐」为准，
          //     底噪只会造成少量误识别，不会卡死整句。
          autoGain: false,
          noiseSuppress: false,
          // 回授（页面自动播放课文 ⇒ 麦克风录进手机自己的声音）**不开 AEC**：
          // Android 的 AEC 依赖扬声器参考信号与精确延迟对齐，Flutter 的
          // 播放/录音异步管线对不齐，收敛不好时反而伤近端语音。
          // 回授靠**半双工**（播放时不判读）解决。
          echoCancel: false,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.unprocessed,
          ),
        ),
      );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

/// PCM16 小端单声道块的 RMS（满量程 0~1）。方案 §4.5 能量法，不引模型。
double rmsOfPcm16(Uint8List bytes) {
  final count = bytes.length ~/ 2;
  if (count == 0) return 0;
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    final packed = bytes[i * 2] | (bytes[i * 2 + 1] << 8);
    final sample = packed >= 32768 ? packed - 65536 : packed;
    sum += sample * sample;
  }
  return math.sqrt(sum / count) / 32768;
}

/// PCM16 块的峰值（满量程 0~1）与削波比例（2026-10-21 诊断用）。
///
/// 削波比例 ＝ 幅度达到 0.99 以上的样本占比 ⇒ 能看出"是不是录太响削顶了"。
({double peak, double clipped}) peakOfPcm16(Uint8List bytes) {
  final count = bytes.length ~/ 2;
  if (count == 0) return (peak: 0.0, clipped: 0.0);
  var peak = 0.0;
  var clipped = 0;
  for (var i = 0; i < count; i++) {
    final packed = bytes[i * 2] | (bytes[i * 2 + 1] << 8);
    final sample = packed >= 32768 ? packed - 65536 : packed;
    final a = sample.abs() / 32768.0;
    if (a > peak) peak = a;
    if (a >= 0.99) clipped++;
  }
  return (peak: peak, clipped: clipped / count);
}

/// **固定增益 + 软限幅**（2026-10-21）。
///
/// 放在 `PcmDecimator` 之后、送 wav/端点检测/ASR 之前 —— 三条线共用同一份
/// 处理过的 PCM，不会出现"落盘的 wav 与送 ASR 的声音不一样"。
///
/// 软限幅用 tanh 的有理近似（|x|≤1 区间误差 < 0.01）：超过拐点后平滑压缩，
/// 不会像硬截断那样产生谐波失真。
class PcmGain {
  PcmGain({this.gain = 1.0, this.softLimit = 0.92});

  /// 增益倍数（1.0 = 不动）。
  final double gain;

  /// 软限幅拐点（满量程 1.0 的比例）。
  final double softLimit;

  bool get enabled => gain != 1.0;

  /// 就地处理一块 PCM16（小端）。
  void apply(Uint8List pcm) {
    if (!enabled) return;
    final limit = softLimit * 32767.0;
    final count = pcm.lengthInBytes ~/ 2;
    final view = ByteData.view(pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes);
    for (var i = 0; i < count; i++) {
      final s = view.getInt16(i * 2, Endian.little);
      var y = s * gain;
      // ⚠️ tanh 本身保号 ⇒ 只用一条分支；写成 `y = limit * tanh(y/limit)`
      //    负信号也会被正确压回负数（曾写成 `-limit * tanh(...)` ⇒ 符号翻反）。
      if (y > limit || y < -limit) {
        y = limit * _tanh(y / limit);
      }
      if (y > 32767) y = 32767;
      if (y < -32768) y = -32768;
      view.setInt16(i * 2, y.round(), Endian.little);
    }
  }

  /// tanh 的有理近似：x*(27+x²)/(27+9x²)，|x|≤1 时误差 < 0.01。
  static double _tanh(double x) {
    final x2 = x * x;
    return x * (27 + x2) / (27 + 9 * x2);
  }
}

/// 采样率抽取器（2026-10-13 真机根因修复）：设备交付 48k PCM，引擎只吃
/// 16k——直接按 16k 头写出 = 声音拉慢 3 倍，CTC 只能吐乱码（"ii"）。
///
/// 做法：**先低通抗混叠、再整数倍抽取**（不是裸抽，裸抽会把 8~24kHz
/// 内容折回 0~8kHz 听感带）。33 阶加窗 sinc FIR，截止 = 输出奈奎斯特
/// （8k/48k = 1/6），汉明窗压旁瓣，DC 增益归一化到 1。群延 16 样本
/// @48k ≈ 0.33ms，对判分无感；流式跨块保持相位与历史，任意切块结果
/// 与一次性处理逐样本一致。
///
/// **拖尾注意**：语音戛然而止时（测试理想方波），FIR 最后 33 个样本
/// 会落进下一个纯静音块，块 RMS ≈ 0.03 > 端点门限 0.008 → 该块被计为
/// 语音，尾静音计时迟一块（100ms）。真实语音自然衰减时拖尾伴着真实
/// 样本，无此现象；喂块测试请按 11 块静音排预算（见
/// `read_along_recorder_test.dart`「读完停」注释）。
class PcmDecimator {
  PcmDecimator({
    this.inputRate = 48000,
    this.outputRate = 16000,
  })  : assert(
          inputRate > 0 && outputRate > 0 && inputRate % outputRate == 0,
          'inputRate 须整除 outputRate（当前管线 48000→16000 = ×3）',
        ),
        factor = inputRate ~/ outputRate,
        _taps = _buildTaps(inputRate ~/ outputRate);

  /// 输入采样率（设备交付速率）。
  final int inputRate;

  /// 输出采样率（引擎约定 16k）。
  final int outputRate;

  /// 抽取倍数（inputRate / outputRate）。
  final int factor;

  final Float64List _taps;

  /// 环形缓冲：始终保留最近 _taps.length 个输入样本。
  final Float64List _line = Float64List(kDecimatorTaps);
  int _linePos = 0;

  /// 下一个输出样本对应的输入相位（0..factor-1）。
  int _phase = 0;

  /// FIR 阶数（奇数，群延 (N-1)/2 样本）。33 阶对语音足够。
  static const int kDecimatorTaps = 33;

  /// 33 阶加窗 sinc：截止 0.5/factor（= 输出奈奎斯特折算到输入率），
  /// 汉明窗，DC 归一化。
  static Float64List _buildTaps(int factor) {
    final fc = 0.5 / factor; // 归一化截止（cycles/sample）
    final taps = Float64List(kDecimatorTaps);
    final center = (kDecimatorTaps - 1) / 2;
    var sum = 0.0;
    for (var n = 0; n < kDecimatorTaps; n++) {
      final x = n - center;
      final sinc = x == 0 ? 2 * fc : math.sin(2 * math.pi * fc * x) /
          (math.pi * x);
      final w = 0.54 - 0.46 * math.cos(2 * math.pi * n / (kDecimatorTaps - 1));
      taps[n] = sinc * w;
      sum += taps[n];
    }
    if (sum != 0) {
      for (var n = 0; n < kDecimatorTaps; n++) {
        taps[n] /= sum;
      }
    }
    return taps;
  }

  /// 喂入一块 [inputRate] PCM16 小端单声道，返回 [outputRate] 块。
  /// 无输出时返回空列表（不是 null——调用方只管 for-in）。
  List<Uint8List> push(Uint8List pcm16) {
    final count = pcm16.length ~/ 2;
    if (count == 0) return const [];
    final view = ByteData.sublistView(pcm16);
    final out = <int>[]; // 16bit 样本（int）暂存，稍后打包
    for (var i = 0; i < count; i++) {
      _line[_linePos] = view.getInt16(i * 2, Endian.little) / 32768.0;
      _linePos = (_linePos + 1) % _line.length;
      // 历史缓冲初始为零 = 前端补 32 个 0 样本：输出数严格等于
      // 输入/3，wav 时长与真实收音时长逐样本对齐。
      if (_phase == 0) {
        var acc = 0.0;
        for (var t = 0; t < _line.length; t++) {
          // 最新样本在 _linePos-1；h[t] 配 x[n-t]
          final idx = (_linePos - 1 - t + 2 * _line.length) % _line.length;
          acc += _taps[t] * _line[idx];
        }
        final clamped = (acc * 32767).round().clamp(-32768, 32767);
        out.add(clamped);
      }
      _phase = (_phase + 1) % factor;
    }
    if (out.isEmpty) return const [];
    final bytes = Uint8List(out.length * 2);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < out.length; i++) {
      bd.setInt16(i * 2, out[i], Endian.little);
    }
    return <Uint8List>[bytes];
  }

  /// 复位（新一轮收音前调；测试也可用）。
  void reset() {
    _line.fillRange(0, _line.length, 0);
    _linePos = 0;
    _phase = 0;
  }
}

/// 尾部静音端点检测（方案 §4.5）。
///
/// [feed] 每个 PCM 块调一次；返回 true = 尾部静音已达 [windowMs] 且此前
/// 检出过语音 → 判定孩子读完。全程无语音由 [heardAnySpeech] 事后判断
/// （方案 §三：不算失败，不计重试次数）。
class SilenceTracker {
  SilenceTracker({
    this.windowMs = 1000,
    this.threshold = 0.008,
    this.sampleRate = 16000,
  });

  /// 尾部静音判定窗。方案 §三写 ≥ 600ms；v2 真机结论（2026-10-12：
  /// 孩子逐字读时字间停顿常超 600ms，会被腰斩）放宽到 1000ms。
  /// 代价只是收尾慢 0.4 秒，误截一条的代价是整句重读。
  final int windowMs;

  /// RMS 阈值（满量程 0~1）。方案 §4.5 建议 0.02 起步，**真机再调**；
  /// 2026-10-11 小米14 实测：手机上正常朗读（含孩子俯身读）的 RMS 常在
  /// 0.01 以下，0.02 会整句漏检 → 判成「全程无语音」直接丢弃、不进 ASR。
  /// 调至 0.008（仍高于安静室内底噪约一个量级）。
  final double threshold;

  final int sampleRate;

  int _lastLoudMs = -1;
  int _samplesFed = 0;
  double _lastRms = 0;
  double _maxRms = 0;

  /// 是否检出过语音。
  bool get heardAnySpeech => _lastLoudMs >= 0;

  /// 最近一个块的 RMS。
  double get lastRms => _lastRms;

  /// 本次收音见过的最大块 RMS（v2 真机调参依据：写进收尾日志，
  /// 下次调阈值不再靠猜——正常朗读 vs 底噪差几个量级一目了然）。
  double get maxRms => _maxRms;

  /// 已采集音频时长（ms，按采样数算，不吃墙钟漂移）。
  int get elapsedMs => _samplesFed * 1000 ~/ sampleRate;

  /// 喂入一个 PCM16 单声道块。返回 true = 读完，可以结束录音。
  bool feed(Uint8List pcm) {
    _lastRms = rmsOfPcm16(pcm);
    if (_lastRms > _maxRms) _maxRms = _lastRms;
    _samplesFed += pcm.length ~/ 2;
    if (_lastRms >= threshold) {
      _lastLoudMs = elapsedMs;
    }
    return heardAnySpeech && elapsedMs - _lastLoudMs >= windowMs;
  }
}

/// 16kHz 单声道 16bit PCM → 标准 44 字节头 WAV（临时件，识别完即删）。
class ReadAlongWavBuilder {
  final BytesBuilder _pcm = BytesBuilder(copy: false);

  /// 已累积 PCM 字节数。
  int get pcmByteLength => _pcm.length;

  void add(Uint8List bytes) => _pcm.add(bytes);

  /// 生成完整 WAV 字节（头 + 数据）。可重复调用（每次重新打包）。
  Uint8List finish({required int sampleRate}) {
    final data = _pcm.toBytes();
    final byteRate = sampleRate * 1 * 2;
    final out = Uint8List(44 + data.length);
    final bd = ByteData.sublistView(out);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        out[offset + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    bd.setUint32(4, 36 + data.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little); // fmt 块大小
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, 1, Endian.little); // 单声道
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, 2, Endian.little); // block align
    bd.setUint16(34, 16, Endian.little); // 位深
    ascii(36, 'data');
    bd.setUint32(40, data.length, Endian.little);
    out.setRange(44, out.length, data);
    return out;
  }
}

/// 固定容量 PCM 环形缓冲（整课连续收音的**滑动识别窗口**）。
///
/// 2026-10-20 读页重构 §四：整课连续识别不能每次都重跑**整段累计音频**
/// （那是 O(n²)：越读到后面越慢）。改成固定容量的环，只留最近 N 毫秒，
/// 每次识别一个滑动窗口 —— 识别量恒定，延迟恒定。
class PcmRingBuffer {
  PcmRingBuffer(int capacityBytes)
      : _buf = Uint8List(capacityBytes < 1 ? 1 : capacityBytes);

  final Uint8List _buf;
  int _write = 0;
  int _filled = 0;

  /// 当前缓冲里的字节数（最多 = 容量）。
  int get length => _filled;

  /// 写入一块 PCM。
  void add(Uint8List bytes) {
    final cap = _buf.length;
    for (var i = 0; i < bytes.length; i++) {
      _buf[_write] = bytes[i];
      _write = _write + 1 >= cap ? 0 : _write + 1;
      if (_filled < cap) _filled++;
    }
  }

  /// 按写入顺序拷出当前内容。
  Uint8List toBytes() {
    final out = Uint8List(_filled);
    if (_filled == 0) return out;
    final cap = _buf.length;
    final start = (_write - _filled + cap) % cap;
    if (start + _filled <= cap) {
      out.setRange(0, _filled, _buf, start);
    } else {
      final first = cap - start;
      out.setRange(0, first, _buf, start);
      out.setRange(first, _filled, _buf, 0);
    }
    return out;
  }

  /// 清空（重开一段时用）。
  void clear() {
    _write = 0;
    _filled = 0;
  }
}

/// 跟读收音器（方案 §六.3）：录音 + 临时 wav + 能量法端点检测的封装。
///
/// 生命周期由上层（跟读控制器）持有；每次 [start] 产出一个新临时 wav，
/// 用完即删（方案 §九.6）。session 不感知具体录音包，只收事件流。
class ReadAlongRecorder {
  ReadAlongRecorder({
    ReadAlongMic? mic,
    this.silenceWindowMs = 1000,
    this.rmsThreshold = 0.008,
    this.inputSampleRate = 48000,
    this.inputGain = 1.0,
    Future<Directory> Function()? tempDir,
    this.onPcm,
  })  : _mic = mic ?? RecordMic(),
        _tempDir = tempDir ?? _defaultTempDir,
        _gain = PcmGain(gain: inputGain);

  /// 固定增益 + 软限幅（见 [PcmGain]）。
  final PcmGain _gain;

  /// **输入增益**（固定倍数，2026-10-21）。
  ///
  /// 为什么需要它：系统的 AGC 是**双向**的（觉得"够响"就压）⇒ 孩子轻声、
  /// 离远一点时反而被压弱 ⇒ 表现就是"必须好大好大的声音"。
  /// 我们把 AGC 关掉（见 [RecordMic]），改用**固定增益 + 软限幅**：
  /// 固定增益不会在句中跳变 ⇒ ASR 前端更稳；软限幅只处理近讲的峰值。
  ///
  /// ⚠️ 默认 **1.0（不动）**：增益不提高信噪比，放大了也会放大环境噪声。
  ///   先用 [ReadAlongRecorder] 的诊断日志量出真实电平，再决定要不要调。
  final double inputGain;

  /// **PCM 旁路**（2026-10-21 流式识别）：每收到一块 16kHz 单声道 PCM 就
  /// 回调一次。
  ///
  /// 为什么需要：流式识别（[StreamingAsrSession]）要**逐块**吃原始 PCM，
  /// 而旧的滑动窗口方案要攒成 wav 再离线转写。两者可以并存 ——
  /// 旁路是"额外一条线"，不改变 wav 落盘与端点检测的原有行为。
  ///
  /// 回调在**采集 isolate 的事件循环**里被调用 ⇒ 里面**绝不能**做重活
  /// （推给流式引擎即可，解码在引擎自己的 isolate 里）。
  ///
  /// 可变：读页在「开始录音」时挂上流式引擎的推流；暂停时置空。
  void Function(Uint8List pcm16k)? onPcm;

  /// 采样率：与 sherpa 中文引擎固定约定（16kHz 单声道）。
  static const int sampleRate = 16000;

  final ReadAlongMic _mic;
  final Future<Directory> Function() _tempDir;

  /// 尾部静音窗（v2：1000ms，见 SilenceTracker 注释）。
  final int silenceWindowMs;

  /// RMS 阈值（方案 §4.5：0.02 起步，真机再调）。
  final double rmsThreshold;

  /// 设备实际交付的采样率（2026-10-13 小米14 实测：请求 16k 也交付 48k，
  /// AudioRecord 不保证请求值）。进管线前先经 [PcmDecimator] 抽到
  /// [sampleRate]——下游（wav 头 / RMS / 时长）一律按 16k 算。
  final int inputSampleRate;

  final _events = StreamController<ReadAlongRecorderEvent>();

  /// UI 订阅这一个流：音量级 / 结束 / 静音 / 失败。
  Stream<ReadAlongRecorderEvent> get events => _events.stream;

  final _wav = ReadAlongWavBuilder();

  /// 连续收音模式用的**滑动窗口**环形缓冲（整课一直开着时）。
  PcmRingBuffer? _ring;
  SilenceTracker? _tracker;

  /// 本次收音的兜底上限（_onChunk 用它判超时，_finish 用它写诊断日志）。
  int _maxDurationMs = 0;
  PcmDecimator? _decimator;
  StreamSubscription<Uint8List>? _sub;
  String? _lastWavPath;
  bool _running = false;
  bool _finishing = false;

  /// 连续模式：静音**不**结束收音（整课一个流程，麦克风一直开着）。
  bool _continuous = false;

  bool get isRecording => _running;

  /// 目前已检出过语音（边读边显示的门：没声时不空跑一次解码）。
  bool get hasSpeechSoFar => _tracker?.heardAnySpeech ?? false;

  /// 开始一次跟读收音。权限被拒抛 [ReadAlongMicPermissionDenied]——
  /// 上层接到它就走「仅跟读不评分」降级，页面不死锁。
  ///
  /// [maxDurationMs] 兜底上限 = 该句音频时长 × 3 + 2000ms（方案 §三）。
  ///
  /// [continuous] = 整课连续收音（2026-10-20 读页重构）：静音**不**结束录音，
  /// 麦克风一直开着；识别改走 [snapshotWindowWav] 的滑动窗口。
  /// [windowBytes] 是那个窗口的字节容量（16kHz×2byte = 32KB/秒）。
  Future<void> start({
    required int maxDurationMs,
    bool continuous = false,
    int windowBytes = 0,
  }) async {
    if (_running) return;
    if (!await _mic.hasPermission()) {
      throw const ReadAlongMicPermissionDenied();
    }
    _finishing = false;
    _continuous = continuous;
    _tracker = SilenceTracker(
      windowMs: silenceWindowMs,
      threshold: rmsThreshold,
      sampleRate: sampleRate,
    );
    _ring = continuous && windowBytes > 0 ? PcmRingBuffer(windowBytes) : null;
    _maxDurationMs = maxDurationMs;
    _decimator = PcmDecimator(
      inputRate: inputSampleRate,
      outputRate: sampleRate,
    );
    final stream = await _mic.startStream();
    _sub = stream.listen(
      (chunk) => _onChunk(chunk, maxDurationMs),
      onDone: () => _finish(timedOut: false),
      onError: (Object error) {
        _fail(error);
      },
      cancelOnError: true,
    );
    _running = true;
  }

  void _onChunk(Uint8List chunk, int maxDurationMs) {
    final tracker = _tracker;
    if (!_running || _finishing || tracker == null) return;
    // 48k 设备 PCM → 16k（低通+抽取）再进 wav/端点检测，下游只认 16k。
    var readDone = false;
    for (final pcm16 in _decimator?.push(chunk) ?? const <Uint8List>[]) {
      // 固定增益 + 软限幅（2026-10-21）：系统的 AGC 已关（见 [RecordMic]），
      // 电平改由我们自己控制 ⇒ 增益恒定、不会在句中跳变。
      _gain.apply(pcm16);
      _wav.add(pcm16);
      _ring?.add(pcm16);
      // 流式识别的旁路（2026-10-21）：同一块 16k PCM 也直接推给流式引擎。
      // 放在这里 ⇒ 与端点检测、wav 落盘**完全解耦**，旧的离线链路不受影响。
      onPcm?.call(pcm16);
      if (tracker.feed(pcm16)) readDone = true;
      _diagAccumulate(pcm16);
    }
    if (tracker.lastRms > 0 || readDone) {
      _events.add(RecorderLevel(tracker.lastRms));
    }
    if (readDone && !_continuous) {
      _finish(timedOut: false);
    } else if (!_continuous && tracker.elapsedMs >= maxDurationMs) {
      // 2026-10-21 修：连续模式（整课常驻收音）**不能**被单句录音的
      // 时长兜底结束 —— 否则"麦克风一直开着"的设计会在 maxDurationMs
      // 到点时静默断掉（而读页又把它当"到点重开"，于是麦克风断断续续）。
      // 连续模式只由显式 stop() / 页面退出 / 应用生命周期结束。
      _finish(timedOut: true);
    }
  }

  Future<void> _finish({required bool timedOut}) async {
    if (_finishing) return;
    _finishing = true;
    _running = false;
    // 刻意不 await 取消采集：取消的 future 完成时机取决于订阅所在 zone
    // （widget 测试的假异步里会被挂住），绝不能让它卡住后面的判分链。
    // 收尾（stop → 写盘 → 出事件）与停止采集本来就是两件事。
    unawaited(_sub?.cancel());
    _sub = null;
    try {
      await _mic.stop();
    } catch (_) {
      // 收尾失败不阻断后续流程：该给的判定照给。
    }

    if (_tracker?.heardAnySpeech != true) {
      // 全程没检出语音：删文件、发静音事件（§三：不计失败）。
      debugPrint('[read-along] silent: no speech in window, giving up');
      await _deleteLastWav();
      _events.add(RecorderSilent());
      _finishing = false;
      return;
    }
    final path = await _writeWav();
    final tracker = _tracker;
    // WP-H 诊断常驻可见（执行方案 §一第2板斧）：wav 路径 + 大小 + 最大电平。
    // 用 print 确保 release/logcat 可见；文件仍按 §九.6 用完即删。
    // ignore: avoid_print
    print(
      '[ReadAlong][diag] wav=$path bytes=${_wav.pcmByteLength} '
      'maxRms=${tracker?.maxRms.toStringAsFixed(4) ?? '-'}',
    );
    // 收尾原因（timedOut / maxRms / 阈值 / 静音窗 / 已采时长）：判定链只能
    // 看到「录了多久」，看不到「为什么录这么久」。2026-10-15 真机实测：
    // 4 字初读行录出 14.7 秒（撞兜底上限）、ASR 听进前几句 → 光看结果分
    // 辨不出是孩子读得长，还是尾静音没触发。这几个数让结论可复算。
    // ignore: avoid_print
    print(
      '[ReadAlong][diag] stop: timedOut=$timedOut '
      'maxRms=${tracker?.maxRms.toStringAsFixed(4) ?? '-'} '
      'threshold=${rmsThreshold.toStringAsFixed(4)} '
      'silenceWindowMs=$silenceWindowMs '
      'elapsedMs=${tracker?.elapsedMs ?? '-'} maxDurationMs=$_maxDurationMs',
    );
    debugPrint('[read-along] stopped: wav=$path bytes=${_wav.pcmByteLength} '
        'maxRms=${tracker?.maxRms.toStringAsFixed(4) ?? '-'}');
    _events.add(RecorderStopped(path, timedOut: timedOut));
    _finishing = false;
  }

  void _fail(Object error) {
    if (!_running) return;
    _running = false;
    unawaited(_sub?.cancel());
    _sub = null;
    unawaited(_mic.cancel());
    unawaited(_deleteLastWav());
    _events.add(RecorderFailed(error));
    _finishing = false;
  }

  /// 麦克风权限是否已 granted。
  ///
  /// 2026-10-21：读页要「进页就常驻监听口令」⇒ 自动开麦前先问权限，
  /// 没权限就**不自动开**（免得每次进页都弹权限框），仍可点按钮手动开始。
  Future<bool> hasPermission() => _mic.hasPermission();

  /// 诊断：累计的块数 / RMS 平方和 / 峰值 / 削波样本数（2026-10-21）。
  ///
  /// 为什么要它：用户报「必须好大好大的声音、离远一点就不识别」——
  /// **先量出真实电平**（RMS / 峰值 / 削波率），才知道是"麦克风没收到"
  /// 还是"收到了但被压弱"还是"模型识别不了"。没有这些数字，调增益就是瞎调。
  int _diagBlocks = 0;
  double _diagSumSq = 0;
  double _diagPeak = 0;
  int _diagClipped = 0;

  void _diagAccumulate(Uint8List pcm16) {
    final rms = rmsOfPcm16(pcm16);
    final peak = peakOfPcm16(pcm16);
    _diagBlocks++;
    _diagSumSq += rms * rms;
    if (peak.peak > _diagPeak) _diagPeak = peak.peak;
    _diagClipped += (peak.clipped * (pcm16.length ~/ 2)).round();
    if (_diagBlocks % 50 == 0) {
      final avgRms = math.sqrt(_diagSumSq / _diagBlocks);
      // ignore: avoid_print
      print('[ReadAlong][diag] blocks=$_diagBlocks '
          'inRate=$inputSampleRate outRate=$sampleRate '
          'gain=${_gain.gain} '
          'rms=${avgRms.toStringAsFixed(4)} (${(20 * math.log(avgRms.clamp(1e-6, 1) / 0.1)).toStringAsFixed(1)}dBFS) '
          'peak=${_diagPeak.toStringAsFixed(3)} '
          'clipped=${(_diagClipped / (_diagBlocks * 256)).toStringAsFixed(4)}');
    }
  }

  /// 上层主动中止（用户跳过这句等）：丢弃数据，不发事件。
  Future<void> abort() async {
    if (!_running && _sub == null) {
      await _deleteLastWav();
      return;
    }
    _running = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _mic.cancel();
    } catch (_) {}
    await _deleteLastWav();
    _finishing = false;
  }

  /// 孩子点「我读完了」：立即收尾（不等 600ms 尾静音），走与自动收尾
  /// 完全相同的判定链路（有语音 → wav；全程没语音 → RecorderSilent）。
  Future<void> finishNow() => _finish(timedOut: false);

  Future<String> _writeWav({String prefix = 'listenloop_readalong'}) async {
    final dir = await _tempDir();
    final path =
        '${dir.path}${Platform.pathSeparator}${prefix}_'
        '${DateTime.now().microsecondsSinceEpoch}.wav';
    // 同步写：一句跟读的 PCM 很小（16kHz×16bit×最长约 30s ≈ 1MB），
    // 同步落块在 UI  isolate 上的耗时远低于一次采样时钟；换来的是
    /// 「写完即判」的确定性（widget 测试的假异步里真实 IO 不推进）。
    File(path).writeAsBytesSync(_wav.finish(sampleRate: sampleRate), flush: true);
    _lastWavPath = path;
    return path;
  }

  /// 录音中途快照：把**当前已采集**的 PCM 打包成临时 wav（边读边显示用）。
  ///
  /// 收音不中断、缓冲不清空——终判的主 wav 不受影响。尚无数据返回 null。
  /// 快照文件与主 wav 同纪律（§九.6）：调用方解完即用 [deleteWav] 删掉。
  Future<String?> snapshotWav() async {
    if (!_running || _wav.pcmByteLength == 0) return null;
    final path = await _writeWav(prefix: 'listenloop_readalong_partial');
    return path;
  }

  /// **滑动窗口**快照：只取最近 [windowMs] 毫秒的音频（整课连续识别用）。
  ///
  /// 2026-10-20 读页重构 §四：整课一直收音时，每次识别只跑最近 6~8 秒，
  /// 而不是整段累计音频 —— 识别量恒定，延迟不随时长增长。
  Future<String?> snapshotWindowWav({required int windowMs}) async {
    final ring = _ring;
    if (!_running || ring == null || ring.length == 0) return null;
    final dir = await _tempDir();
    final path =
        '${dir.path}${Platform.pathSeparator}listenloop_readalong_window_'
        '${DateTime.now().microsecondsSinceEpoch}.wav';
    final data = ring.toBytes();
    File(path).writeAsBytesSync(
      _wavBytes(data, sampleRate: sampleRate),
      flush: true,
    );
    _lastWavPath = path;
    return path;
  }

  /// 把裸 PCM 打包成 WAV 字节（头 + 数据）。
  static Uint8List _wavBytes(Uint8List data, {required int sampleRate}) {
    final byteRate = sampleRate * 1 * 2;
    final out = Uint8List(44 + data.length);
    final bd = ByteData.sublistView(out);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bd.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bd.setUint32(4, 36 + data.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bd.setUint32(40, data.length, Endian.little);
    out.setRange(44, 44 + data.length, data);
    return out;
  }

  /// 识别完即删（方案 §九.6）。删除失败不抛——临时目录本就该被系统清。
  Future<void> deleteWav(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
      if (_lastWavPath == path) _lastWavPath = null;
    } catch (_) {}
  }

  Future<void> _deleteLastWav() => deleteWav(_lastWavPath);

  Future<void> dispose() async {
    await abort();
    await _mic.dispose();
    await _events.close();
  }
}

Future<Directory> _defaultTempDir() async {
  final dir = await getTemporaryDirectory();
  return Directory(dir.path);
}
