// 读页三屏视觉基线（首屏 / 中段 / 末屏）—— 2026-10-21。
//
// 用途：不用装真机就能**肉眼验收**读页整篇渲染是否正常。
//   2026-10-20 真机出过「只显示一句、其余大片空白」的 bug，
//   这三张图就是它的对照物 —— 一眼能看出整篇是不是都画出来了。
//
// ⚠️ 走 **golden** 机制而不是 `RenderRepaintBoundary.toImage()`：
//    后者在 flutter_test 里会卡住不返回（实测 844px 也卡，flutter_tester
//    占 200MB 但 CPU 不动）。golden 内部走的是可用的离屏渲染路径。
//
// 运行：
//   flutter test test/widgets/reading_document_shots_test.dart --no-pub
//   （重建基线加 --update-goldens）
//
// 看图：
//   explorer D:\listenloop\test\widgets\goldens

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:phrasing/models/sentence.dart';
import 'package:phrasing/theme/listenloop_theme.dart';
import 'package:phrasing/training/continuous_reading_session.dart';
import 'package:phrasing/widgets/lesson_reading_document.dart';

/// 真机课包 xiaokedou-b-dual 的 69 句真实课文（逐字照抄）。
const List<String> kLessonText = [
  '课文1', '小蝌蚪找妈妈', '池塘里', '有一群小蝌蚪，', '大大的脑袋，',
  '黑灰色的身子，', '甩着长长的尾巴，', '快活地游来游去。',
  '他们问鲤鱼妈妈：', '「鲤鱼阿姨，我们的妈妈在哪里？」', '鲤鱼妈妈说：',
  '「你们的妈妈有四条腿，宽嘴巴。你们到那边去找吧！」',
  '小蝌蚪游哇游，过了小石桥，', '看见荷叶上蹲着一只大青蛙，',
  '他们叫了一声：', '「妈妈，妈妈！」', '青蛙妈妈低头一看，', '笑着说：',
  '「好孩子，你们已经长成青蛙啦。」', '小蝌蚪的尾巴变短了，', '他们已经长成青蛙了。',
  '荷叶上蹲着一只大青蛙', '他们看见荷叶上蹲着一只大青蛙，', '看见荷叶上蹲着一只大青蛙，',
  '蹦到了荷叶上。', '游哇游，', '小蝌蚪游哇游，', '过了小石桥，',
  '看见荷叶上蹲着一只大青蛙，', '他们叫了一声：', '妈妈，妈妈！', '青蛙妈妈低头一看，',
  '笑着说：', '好孩子，你们已经长成青蛙啦。', '小蝌蚪的尾巴变短了，', '他们已经长成青蛙了。',
  '小蝌蚪游哇游，', '过了小石桥，', '看见荷叶上蹲着一只大青蛙，', '他们叫了一声：',
  '妈妈，妈妈！', '青蛙妈妈低头一看，', '笑着说：', '好孩子，你们已经长成青蛙啦。',
  '小蝌蚪的尾巴变短了，', '他们已经长成青蛙了。',
  '池塘里有一群小蝌蚪，', '大大的脑袋，', '黑灰色的身子，', '甩着长长的尾巴，',
  '快活地游来游去。', '池塘里有一群小蝌蚪，', '大大的脑袋，', '黑灰色的身子，',
  '甩着长长的尾巴，', '快活地游来游去。', '他们看见荷叶上蹲着一只大青蛙，', '游哇游，',
  '小蝌蚪游哇游，', '过了小石桥，', '看见荷叶上蹲着一只大青蛙，', '他们叫了一声：',
  '妈妈，妈妈！', '青蛙妈妈低头一看，', '笑着说：', '好孩子，你们已经长成青蛙啦。',
];

List<Sentence> buildSentences() => [
      for (var i = 0; i < kLessonText.length; i++)
        Sentence(
          id: 'c_$i',
          index: i,
          startMs: i * 1000,
          endMs: i * 1000 + 900,
          english: kLessonText[i],
          chinese: kLessonText[i],
        ),
    ];

Future<void> loadChineseFont() async {
  final loader = FontLoader('SongTi')
    ..addFont(rootBundle.load('assets/fonts/SongTi.ttf'));
  await loader.load();
}

void main() {
  // 三屏：首屏 / 中段（当前句在中间）/ 末屏
  const cases = <String, int>{
    'head': 0,
    'middle': 30,
    'tail': 60,
  };

  for (final entry in cases.entries) {
    testWidgets('读页视觉基线 · ${entry.key}', (tester) async {
      await loadChineseFont();

      final sentences = buildSentences();
      final session = ContinuousReadingSession(sentences: sentences);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final startSentence = session.tokens.isEmpty
          ? 0
          : session.tokens[
                  entry.value.clamp(0, session.tokens.length - 1)]
              .sentenceIndex;

      const captureKey = Key('shot');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildListenLoopTheme(Brightness.light),
          home: Scaffold(
            body: RepaintBoundary(
              key: captureKey,
              child: SizedBox(
                height: 844,
                child: LessonReadingDocument(
                  sentences: sentences,
                  tokens: session.tokens,
                  tokenStates: session.snapshot.tokenStates,
                  visibleToken: entry.value,
                  initialSentenceIndex: startSentence,
                  charSize: 23.0,
                  charStyle:
                      const TextStyle(fontSize: 23.0, fontFamily: 'SongTi'),
                  pinyinScale: 1.0,
                  chineseFontFamily: 'SongTi',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile('goldens/reading_document_${entry.key}.png'),
      );
    });
  }
}
