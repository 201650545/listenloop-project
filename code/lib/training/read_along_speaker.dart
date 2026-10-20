/// 跟读纠错语音播报（v2：用户 2026-10-12 亲定 —— 读错了要用语音说出错
/// 在哪、拼音怎么拼；1~2 年级孩子看不懂拼音对照行，必须听）。
///
/// 设计：`ReadAlongSpeaker` 只管"说"，说什么由纯函数
/// [buildCorrectionSpeech] 定（可单测）；播报失败（无中文语音包、插件
/// 缺失）静默降级——文字版纠错一直在面板上，不依赖播报。
/// 全程离线：系统 TTS 不走网络（不断 VPN 也能播）。
library;

import 'package:flutter_tts/flutter_tts.dart';

import 'dictation_engine.dart';
import 'read_along_session.dart';

/// TTS 后端抽象——测试注入假实现，生产走系统 TTS。
abstract class ReadAlongTts {
  Future<void> speak(String text);
  Future<void> stop();
}

/// 系统 TTS（Android/iOS 自带引擎 + 中文语音包）。
class SystemReadAlongTts implements ReadAlongTts {
  FlutterTts? _tts;

  /// 通道调用加超时：插件未注册（widget 测试）或设备无 TTS 引擎
  /// （部分定制 ROM）时，invokeMethod 可能既不返回也不抛错——
  /// 绝不能让一次播报卡死跟读流程（v2 真机前测试挂起定位）。
  static const Duration _channelTimeout = Duration(seconds: 2);

  Future<void> _guard(Future<dynamic> Function() fn) async {
    try {
      await fn().timeout(_channelTimeout);
    } catch (_) {}
  }

  @override
  Future<void> speak(String text) async {
    try {
      _tts ??= FlutterTts();
      await _tts!.setLanguage('zh-CN').timeout(_channelTimeout);
      await _tts!.setSpeechRate(0.85).timeout(_channelTimeout);
      await _guard(() => _tts!.speak(text));
    } catch (_) {
      // 无中文语音包 / 引擎异常：静默降级，只显示文字。
    }
  }

  @override
  Future<void> stop() async {
    final tts = _tts;
    if (tts == null) return;
    await _guard(() => tts.stop());
  }
}

/// 跟读纠错播报器。UI 层持有，按判分结果播报，不感知播放器与录音器。
class ReadAlongSpeaker {
  ReadAlongSpeaker({ReadAlongTts? backend})
      : _backend = backend ?? SystemReadAlongTts();

  final ReadAlongTts _backend;

  /// 播报一次纠错（取结果里前 2 个错处）。播不动就静默返回。
  Future<void> speakCorrection(
    ReadAlongResult result,
    String sentenceText,
  ) =>
      _backend.speak(buildCorrectionSpeech(result, sentenceText));

  /// 播报任意文本（预留：满星鼓励语等）。
  Future<void> speak(String text) => _backend.speak(text);

  /// 打断当前播报（重播原声 / 进下一句 / 退出前先停，避免和原声打架）。
  Future<void> stop() => _backend.stop();

  /// 把判分结果翻成孩子能听懂的纠错话：
  /// 「第 N 个字 C 读成了 X，应该读 Y（拼音第几声）」，最多说 2 处，
  /// 末尾接一句「再听一遍原声跟读」。
  ///
  /// 拼音用「字母 + 第几声」口播（如 mā → "ma第三声"），不用带声调
  /// 符号原文——TTS 读 "mā" 会含糊，读 "ma第三声" 孩子能复述。
  static String buildCorrectionSpeech(
    ReadAlongResult result,
    String sentenceText,
  ) {
    final chars = <String>[];
    for (final r in sentenceText.runes) {
      final ch = String.fromCharCode(r);
      final code = ch.codeUnitAt(0);
      if (code >= 0x4E00 && code <= 0x9FA5) chars.add(ch);
    }
    final expToned = result.expectedPinyin
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    final positional =
        result.ops.where((op) => op.expected != null).toList(growable: false);

    final parts = <String>[];
    var syllable = 0;
    for (var i = 0; i < chars.length && parts.length < 2; i++) {
      final op = syllable < positional.length ? positional[syllable] : null;
      final idx = syllable;
      syllable++;
      if (op == null || op.type == DictationDiffType.matched) continue;
      final exp = idx < expToned.length ? expToned[idx] : (op.expected ?? '');
      final spoken = _speakable(exp);
      if (op.type == DictationDiffType.missing) {
        parts.add('第${i + 1}个字${chars[i]}漏读了，应该读$spoken');
      } else {
        parts.add('第${i + 1}个字${chars[i]}读成了${op.actual ?? ''}，'
            '应该读$spoken');
      }
    }
    if (parts.isEmpty) return '再听一遍原声，跟读一次';
    return '${parts.join('，')}，再听一遍原声跟读';
  }

  /// 单字读音的口播文本（2026-10-15「读错的字」卡片点字听读音用）：
  /// 「蝌」+「kē」→「蝌，ke第一声」。
  ///
  /// 复用 [_speakable] 的音节口播口径——只念一个音节时孩子要的是「这个字
  /// 怎么读」，所以字在前、读音在后，中间一顿。
  static String speakableSyllable(String char, String tonedPinyin) =>
      '$char，${_speakable(tonedPinyin)}';

  /// 带声调拼音 → 可口播形式：「mǎ」→「ma第三声」，
  /// 无声调（如轻声 men）→「men轻声」。
  static String _speakable(String toned) {
    var tone = 0;
    final letters = StringBuffer();
    for (final r in toned.runes) {
      final ch = String.fromCharCode(r);
      final t = _toneOf[ch];
      if (t != null) {
        tone = t;
        letters.write(ReadAlongSession.stripTones(ch));
      } else {
        letters.write(ch);
      }
    }
    const names = ['', '第一声', '第二声', '第三声', '第四声'];
    final toneName = tone >= 1 && tone <= 4 ? names[tone] : '轻声';
    return '$letters$toneName';
  }

  /// 声调符号 → 声调序号（只收五组元音 + ü 系；ê/ḿ/ń 等罕见标按轻声处理）。
  static const Map<String, int> _toneOf = {
    'ā': 1, 'á': 2, 'ǎ': 3, 'à': 4,
    'ē': 1, 'é': 2, 'ě': 3, 'è': 4,
    'ī': 1, 'í': 2, 'ǐ': 3, 'ì': 4,
    'ō': 1, 'ó': 2, 'ǒ': 3, 'ò': 4,
    'ū': 1, 'ú': 2, 'ǔ': 3, 'ù': 4,
    'ǖ': 1, 'ǘ': 2, 'ǚ': 3, 'ǜ': 4,
  };
}
