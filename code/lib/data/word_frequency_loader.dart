/// 词频表的**装载与持有**（Flutter 层，唯一一处碰 `rootBundle`）。
///
/// 与 `lib/training/word_frequency.dart`（纯 Dart）分开：
///   * 纯函数解析器可被单元测试直接喂字符串，**不依赖 asset bundle**；
///   * 本类负责把 asset 从磁盘加载、解析、缓存，**失败静默降级为空表**。
///
/// 设计依据：`docs/02_工程架构与系统设计/10_生词本与Anki记忆卡设计.md` §20.4 P0。
///
/// 使用方式：`RootShell.initState` 里 `unawaited(WordFrequencyHolder.load())`；
/// 之后 UI 层（生词本页 / Library 入口）build 时读 [WordFrequencyHolder.current]。
/// **加载完成前 current 为 null**，UI 照常渲染，只是不做词频排序 ——
/// 词频是增强信号，绝不能让 asset 加载失败阻塞生词本主功能。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../training/word_frequency.dart';

/// NGSL asset 在 pubspec 里注册的路径。
const String kNgslAssetPath = 'assets/data/ngsl3000.tsv';

/// 全局词频表持有者。
///
/// 为什么用静态而不是 InheritedWidget：WordFrequency 是**只读的不可变数据**，
/// 装载一次就不再变；用静态字段让生词本页 / Library 入口无需改构造签名就能读，
/// 也避免为一份静态数据搭一条 widget 注入链路。
/// 测试可用 [inject] 直接塞，或 [load] 时传 `source` 换掉 `rootBundle`。
class WordFrequencyHolder {
  WordFrequencyHolder._();

  /// 已加载的词频表；未加载 / 加载失败时为 null（调用方按空表处理）。
  static WordFrequency? current;

  /// 加载并缓存。幂等：已有内容时直接返回。
  ///
  /// [source] 可注入以绕过 `rootBundle`（测试用）；缺省读 [kNgslAssetPath]。
  /// **任何异常都吞掉**：词频是增强信号，不能让 asset 缺失影响生词本主链路。
  static Future<WordFrequency?> load({
    Future<String> Function()? source,
  }) async {
    if (current != null) return current;
    try {
      final raw = await (source ?? _fromAsset)();
      final parsed = WordFrequency.parse(raw);
      if (!parsed.isEmpty) current = parsed;
    } catch (e) {
      debugPrint('[WordFrequencyHolder] load failed (frequency off): $e');
    }
    return current;
  }

  /// 测试注入：直接塞一份表（绕过 asset），返回旧值便于还原。
  static WordFrequency? inject(WordFrequency? value) {
    final prev = current;
    current = value;
    return prev;
  }

  static Future<String> _fromAsset() =>
      rootBundle.loadString(kNgslAssetPath);
}