import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 一篇课文的标准化句子表（2026-09-29 中文切句新方案）。
///
/// 用户方案四步流：① 全文识别 → ② 匹配课文 → ③ 按课文标准句切分字幕
/// → ④ 按字幕切分音频。[TextbookTrack] 承载第②③步所需的「标准句」。
///
/// [sentences] 是**带标点的原句**——它既是匹配用的标准文本，也是
/// 字幕最终展示的文本（ASR 有错时字幕仍显示课文原文）。
@immutable
class TextbookTrack {
  const TextbookTrack({
    required this.id,
    required this.unit,
    required this.title,
    required this.sentences,
  });

  factory TextbookTrack.fromJson(Map<String, dynamic> json) => TextbookTrack(
        id: (json['id'] as String? ?? '').trim(),
        unit: (json['unit'] as String? ?? '').trim(),
        title: (json['title'] as String? ?? '').trim(),
        sentences: [
          for (final s in (json['sentences'] as List? ?? const []))
            (s as String).trim(),
        ].where((s) => s.isNotEmpty).toList(growable: false),
      );

  final String id;
  final String unit;
  final String title;

  /// 按朗读顺序切好的标准句（含标点）。空列表表示该课文文本尚未录入
  /// （现代版权课文默认留空，由用户对照课本补录）。
  final List<String> sentences;

  /// 是否可用于对齐：至少要有一句可比较的标准文本。
  bool get isAlignable => sentences.isNotEmpty;

  @override
  String toString() => 'TextbookTrack($id, $unit $title, '
      '${sentences.length} 句)';
}

/// 课文句子索引：内置的「标准课文文本库」，脱离网络与 AI 也能匹配。
@immutable
class TextbookIndex {
  const TextbookIndex({required this.textbook, required this.tracks});

  /// 从 JSON 字符串解析（测试注入用）。
  factory TextbookIndex.parse(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('textbook index must be a JSON object');
    }
    final tracks = <TextbookTrack>[];
    for (final item in (data['tracks'] as List? ?? const [])) {
      if (item is Map<String, dynamic>) {
        final track = TextbookTrack.fromJson(item);
        if (track.id.isNotEmpty && track.title.isNotEmpty) {
          tracks.add(track);
        }
      }
    }
    return TextbookIndex(
      textbook: (data['textbook'] as String? ?? '').trim(),
      tracks: List.unmodifiable(tracks),
    );
  }

  final String textbook;
  final List<TextbookTrack> tracks;

  /// 可参与对齐的课文（文本已录入的）。
  List<TextbookTrack> get alignableTracks =>
      tracks.where((t) => t.isAlignable).toList(growable: false);

  static const String defaultAssetPath =
      'assets/data/textbook_grade2_term1.json';

  /// 生产加载入口：读内置 asset。
  static Future<TextbookIndex> loadDefault() =>
      loadFromAsset(defaultAssetPath);

  static Future<TextbookIndex> loadFromAsset(String assetPath) async =>
      TextbookIndex.parse(await rootBundle.loadString(assetPath));
}
