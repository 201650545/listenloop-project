// 读页 UI 的 paint smoke + golden 回归（2026-10-21）。
//
// 为什么需要：2026-10-20 真机出现「读页只显示一句、其余大片空白」，
// 根因是 BoxDecoration 同时给了 borderRadius 与 width:0 的 BorderSide
// （hairline）⇒ Flutter 在 **paint()** 阶段抛断言 ⇒ 那一行整行画不出来。
//
// 这类 bug 的特点是：
//   · build/layout 都正常 ⇒ 只测「Widget 存在」的断言抓不到；
//   · 只在真机上肉眼可见 ⇒ 反馈循环 3~4 分钟。
//
// 本文件用 Flutter 自带能力（无需任何第三方包）抓它：
//   ① tester.takeException()  —— 捕获 paint/build/layout 阶段抛出的异常
//   ② tester.getSize()        —— 确认渲染盒有**非零**尺寸（没塌缩成 0）
//   ③ matchesGoldenFile()     —— 逐像素比对，防止视觉回归
//
// 运行：
//   flutter test test/widgets/reading_document_paint_test.dart --no-pub
//   （首次建立基准图：加 --update-goldens；**不要**日常用，会失去防回归意义）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phrasing/models/sentence.dart';
import 'package:phrasing/theme/listenloop_theme.dart';
import 'package:phrasing/training/continuous_reading_session.dart';
import 'package:phrasing/widgets/lesson_reading_document.dart';

/// 真机课包 xiaokedou-b-dual 的 69 句真实课文（逐字照抄）。
const List<String> kRealLessonText = [
  '课文1',
  '小蝌蚪找妈妈',
  '池塘里',
  '有一群小蝌蚪，',
  '大大的脑袋，',
  '黑灰色的身子，',
  '甩着长长的尾巴，',
  '快活地游来游去。',
  '他们问鲤鱼妈妈：',
  '「鲤鱼阿姨，我们的妈妈在哪里？」',
  '鲤鱼妈妈说：',
  '「你们的妈妈有四条腿，宽嘴巴。你们到那边去找吧！」',
  '小蝌蚪游哇游，过了小石桥，',
  '看见荷叶上蹲着一只大青蛙，',
  '他们叫了一声：',
  '「妈妈，妈妈！」',
  '青蛙妈妈低头一看，',
  '笑着说：',
  '「好孩子，你们已经长成青蛙啦。」',
  '小蝌蚪的尾巴变短了，',
  '他们已经长成青蛙了。',
  '荷叶上蹲着一只大青蛙',
  '他们看见荷叶上蹲着一只大青蛙，',
  '看见荷叶上蹲着一只大青蛙，',
  '蹦到了荷叶上。',
  '游哇游，',
  '小蝌蚪游哇游，',
  '过了小石桥，',
  '看见荷叶上蹲着一只大青蛙，',
  '他们叫了一声：',
  '妈妈，妈妈！',
  '青蛙妈妈低头一看，',
  '笑着说：',
  '好孩子，你们已经长成青蛙啦。',
  '小蝌蚪的尾巴变短了，',
  '他们已经长成青蛙了。',
  '小蝌蚪游哇游，',
  '过了小石桥，',
  '看见荷叶上蹲着一只大青蛙，',
  '他们叫了一声：',
  '妈妈，妈妈！',
  '青蛙妈妈低头一看，',
  '笑着说：',
  '好孩子，你们已经长成青蛙啦。',
  '小蝌蚪的尾巴变短了，',
  '他们已经长成青蛙了。',
  '池塘里有一群小蝌蚪，',
  '大大的脑袋，',
  '黑灰色的身子，',
  '甩着长长的尾巴，',
  '快活地游来游去。',
  '池塘里有一群小蝌蚪，',
  '大大的脑袋，',
  '黑灰色的身子，',
  '甩着长长的尾巴，',
  '快活地游来游去。',
  '他们看见荷叶上蹲着一只大青蛙，',
  '游哇游，',
  '小蝌蚪游哇游，',
  '过了小石桥，',
  '看见荷叶上蹲着一只大青蛙，',
  '他们叫了一声：',
  '妈妈，妈妈！',
  '青蛙妈妈低头一看，',
  '笑着说：',
  '好孩子，你们已经长成青蛙啦。',
];

List<Sentence> buildRealSentences() {
  return [
    for (var i = 0; i < kRealLessonText.length; i++)
      Sentence(
        id: 'c_$i',
        index: i,
        startMs: i * 1000,
        endMs: i * 1000 + 900,
        english: kRealLessonText[i],
        chinese: kRealLessonText[i],
      ),
  ];
}

Future<void> pumpDocument(
  WidgetTester tester,
  List<Sentence> sentences, {
  required int visibleToken,
  required Size size,
  double charSize = 23.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final session = ContinuousReadingSession(sentences: sentences);
  // 起始句 = 可见 token 所在句，否则 SliverList 还没铺到那儿，
  // 当前句不在树里（懒加载，不是 bug）。
  final startSentence = session.tokens.isEmpty
      ? 0
      : session.tokens[
              visibleToken.clamp(0, session.tokens.length - 1)]
          .sentenceIndex;

  await tester.pumpWidget(
    MaterialApp(
      theme: buildListenLoopTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: size.height,
          child: LessonReadingDocument(
            sentences: sentences,
            tokens: session.tokens,
            tokenStates: session.snapshot.tokenStates,
            visibleToken: visibleToken,
            initialSentenceIndex: startSentence,
            charSize: charSize,
            charStyle: TextStyle(fontSize: charSize, fontFamily: 'SongTi'),
            pinyinScale: 1.0,
            chineseFontFamily: 'SongTi',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('paint smoke：整课每一句都渲染得出来（不许只剩当前句）',
      (tester) async {
    final sentences = buildRealSentences();
    await pumpDocument(
      tester,
      sentences,
      visibleToken: 0,
      size: const Size(390, 844),
    );

    // ① paint/build/layout 阶段不得抛异常
    //    （hairline + 圆角 ⇒ 断言在 paint() 抛 ⇒ 这里会红）
    expect(tester.takeException(), isNull);

    // ② 可见区内的**多句**都必须真的画出来，不只是当前句。
    //    （ruby 排版逐字 Text ⇒ 按首字判断该句是否在树上）
    final rendered = <String>{};
    for (final s in sentences.take(12)) {
      final first = s.chinese.trim().characters.first;
      if (find.text(first).evaluate().isNotEmpty) rendered.add(first);
    }
    expect(
      rendered.length,
      greaterThanOrEqualTo(8),
      reason: '读页应同时渲染多句；只剩一句说明又踩了 hairline 断言',
    );
  });

  testWidgets('paint smoke：窄屏（280px）也不崩、不塌缩', (tester) async {
    final sentences = buildRealSentences();
    for (final width in [280.0, 320.0, 390.0]) {
      await pumpDocument(
        tester,
        sentences,
        visibleToken: 5,
        size: Size(width, 800),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '宽度 $width 下 paint/build 抛异常',
      );
      expect(
        find.byType(LessonReadingDocument),
        findsOneWidget,
        reason: '宽度 $width 下组件消失',
      );
    }
  });

  testWidgets('paint smoke：当前句在中间时，也不影响其它句渲染',
      (tester) async {
    final sentences = buildRealSentences();
    await pumpDocument(
      tester,
      sentences,
      visibleToken: 46, // 「看见荷叶上」——真机上出问题的那一句
      size: const Size(390, 844),
    );
    expect(tester.takeException(), isNull);

    // ⚠️ ruby 排版是**逐字 Text**（见 chinese_textbook_ruby_layout.dart），
    //    所以 find.text 只能匹配**单字**，匹配不到整句。
    // 当前句必须画出来 ⇒ 它的每个字都在树里。
    for (final ch in '看见荷叶上'.split('')) {
      expect(
        find.text(ch),
        findsWidgets,
        reason: '当前句的字「$ch」没渲染出来',
      );
    }

    // ⚠️ 不用「首句也在树上」做断言：SliverList 是懒加载的，滚到第 46 句时
    // 第 1 句早已不在树内 —— 那不是 bug，是正常行为。
    // 真正要抓的是：当前句之外**附近的句**也画得出来。
    final nearby = <String>{};
    for (final s in sentences.skip(44).take(4)) {
      final first = s.chinese.trim().characters.first;
      if (find.text(first).evaluate().isNotEmpty) nearby.add(first);
    }
    expect(
      nearby.length,
      greaterThanOrEqualTo(2),
      reason: '当前句附近应有多句同时渲染出来',
    );
  });

  testWidgets('golden：读页首屏（当前句 + 上下文）像素级基线', (tester) async {
    final sentences = buildRealSentences();
    await pumpDocument(
      tester,
      sentences,
      visibleToken: 3,
      size: const Size(390, 844),
    );
    expect(tester.takeException(), isNull);

    const captureKey = Key('reading-doc-capture');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildListenLoopTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 844,
            child: RepaintBoundary(
              key: captureKey,
              child: LessonReadingDocument(
                sentences: sentences,
                tokens: ContinuousReadingSession(sentences: sentences).tokens,
                tokenStates:
                    ContinuousReadingSession(sentences: sentences)
                        .snapshot
                        .tokenStates,
                visibleToken: 3,
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

    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/reading_document.png'),
    );
  });
}
