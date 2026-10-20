// 读页 UI 实验室（独立入口）—— 2026-10-21。
//
// 为什么有这个东西：日常改 UI 不该走「flutter build apk → 装机 → 手点导航」
// 这条 3~4 分钟的路（GPT 镜像站评审：把反馈循环从 180~240 秒压到 1~5 秒）。
// 本入口**不启动 sqflite、不初始化讯飞 ASR、不加载音频**，只喂固定数据，
// 于是：
//   · 改一个 widget ⇒ flutter run -t lib/dev/reading_preview.dart ⇒ 按 r
//     ⇒ 1~5 秒看到效果，不用装机、不用导航。
//   · 配合 test/ 里的 paint smoke + golden，paint 断言不再依赖肉眼。
//
// 用法：
//   flutter run -d <设备ID> -t lib/dev/reading_preview.dart
//   flutter run -d chrome   -t lib/dev/reading_preview.dart
//
// ⚠️ 这个文件只在开发期使用，不进 release 包的路径（它不在 main.dart 的
// 依赖链上，release 构建不会带上它）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/sentence.dart';
import '../theme/listenloop_theme.dart';
import '../training/continuous_reading_session.dart';
import '../training/reading_alignment.dart';
import '../widgets/lesson_reading_document.dart';

/// 开发期用的真实课文（69 句，取自真机课包 xiaokedou-b-dual）。
const String kDevSentencesAsset = 'assets/data/dev_preview_sentences.json';

Future<List<Sentence>> loadDevSentences() async {
  final raw = await rootBundle.loadString(kDevSentencesAsset);
  final decoded = jsonDecode(raw) as List;
  return decoded.map((e) {
    final m = e as Map<String, dynamic>;
    return Sentence(
      id: m['id'] as String? ?? 's',
      index: m['index'] as int? ?? 0,
      startMs: m['startMs'] as int? ?? 0,
      endMs: m['endMs'] as int? ?? 1,
      english: m['english'] as String? ?? '',
      chinese: m['chinese'] as String? ?? '',
    );
  }).toList();
}

void main() {
  runApp(const ReadingPreviewApp());
}

class ReadingPreviewApp extends StatefulWidget {
  const ReadingPreviewApp({super.key});

  @override
  State<ReadingPreviewApp> createState() => _ReadingPreviewAppState();
}

class _ReadingPreviewAppState extends State<ReadingPreviewApp> {
  List<Sentence>? _sentences;
  int _visibleToken = 0;
  double _charSize = 23.0;
  bool _fontSong = true;
  bool _simulateWrong = false;

  @override
  void initState() {
    super.initState();
    loadDevSentences().then((s) {
      if (mounted) setState(() => _sentences = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sentences = _sentences;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildListenLoopTheme(Brightness.light),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('读页 UI 实验室'),
          actions: [
            IconButton(
              tooltip: '下一句',
              onPressed: sentences == null || sentences.isEmpty
                  ? null
                  : () => setState(() {
                        final session =
                            ContinuousReadingSession(sentences: sentences);
                        final next = _visibleToken + 1;
                        _visibleToken =
                            next >= session.tokens.length ? 0 : next;
                      }),
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
        body: sentences == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _controls(sentences),
                  const Divider(height: 1),
                  Expanded(
                    child: LessonReadingDocument(
                      sentences: sentences,
                      tokens: _session(sentences).tokens,
                      tokenStates: _states(sentences),
                      visibleToken: _visibleToken,
                      charSize: _charSize,
                      charStyle: TextStyle(
                        fontSize: _charSize,
                        fontFamily: _fontSong ? 'SongTi' : 'FangSong',
                      ),
                      pinyinScale: 1.0,
                      chineseFontFamily: _fontSong ? 'SongTi' : 'FangSong',
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  ContinuousReadingSession _session(List<Sentence> sentences) =>
      ContinuousReadingSession(sentences: sentences);

  /// 逐字状态：正常是「未读」，模拟错词时把部分字标成「读错」。
  List<ReadingTokenStatus> _states(List<Sentence> sentences) {
    final tokens = _session(sentences).tokens;
    return [
      for (var i = 0; i < tokens.length; i++)
        _simulateWrong && i % 7 == 3
            ? ReadingTokenStatus.substituted
            : ReadingTokenStatus.pending,
    ];
  }

  Widget _controls(List<Sentence> sentences) {
    final session = _session(sentences);
    final maxToken = session.tokens.isEmpty ? 0 : session.tokens.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('句子 ${session.tokens.length} 句 · token $_visibleToken/$maxToken',
              style: const TextStyle(fontSize: 12)),
          Row(
            children: [
              const Text('字号', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _charSize,
                  min: 14,
                  max: 40,
                  onChanged: (v) => setState(() => _charSize = v),
                ),
              ),
              Text('${_charSize.round()}', style: const TextStyle(fontSize: 12)),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              _chip('宋体', _fontSong, () => setState(() => _fontSong = true)),
              _chip('仿宋', !_fontSong, () => setState(() => _fontSong = false)),
              _chip('模拟错词', _simulateWrong,
                  () => setState(() => _simulateWrong = !_simulateWrong)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: on,
      onSelected: (_) => onTap(),
    );
  }
}
