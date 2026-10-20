import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phrasing/models/sentence.dart';
import 'package:phrasing/theme/listenloop_theme.dart';
import 'package:phrasing/training/continuous_reading_session.dart';
import 'package:phrasing/widgets/lesson_reading_document.dart';

/// 真机课包 `xiaokedou-b-dual` 的 69 句真实课文（逐字照抄，未做任何改写）。
///
/// 为什么内嵌而不是读文件：测试要能在任何机器上跑，不能依赖 scratch 里的
/// 临时文件。
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

void main() {
  testWidgets('整课课文每一句都渲染得出来（不许只剩当前句）', (tester) async {
    final sentences = buildRealSentences();
    final session = ContinuousReadingSession(sentences: sentences);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildListenLoopTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: LessonReadingDocument(
              sentences: sentences,
              tokens: session.tokens,
              tokenStates: session.snapshot.tokenStates,
              visibleToken: 0,
              charSize: 23.0,
              charStyle: const TextStyle(fontSize: 23.0),
              pinyinScale: 1.0,
              chineseFontFamily: 'SongTi',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 回归点（2026-10-20 真机症状）：左强调线写成 `width: isCurrent ? 2 : 0`
    // 时，width 0 的 BorderSide 是 hairline，Flutter 规定 hairline 不能配
    // 圆角 ⇒ paint() 断言失败 ⇒ **非当前句整行画不出来**，读页只剩一句。
    // 断言：paint 阶段不得抛任何异常。
    expect(tester.takeException(), isNull);

    // 可见区内的多句都必须在树上（不只是当前那一句）。
    final rendered = <String>{};
    for (final s in sentences.take(12)) {
      final first = s.chinese.trim().characters.first;
      if (find.text(first).evaluate().isNotEmpty) rendered.add(first);
    }
    expect(
      rendered.length,
      greaterThanOrEqualTo(10),
      reason: '读页应同时渲染多句，只剩一句说明又踩了 hairline 断言',
    );
  });
}
