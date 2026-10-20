// 预览入口的冒烟测试：保证 lib/dev/reading_preview.dart 一进去就能跑。
//
// 为什么测它：Preview 是开发期最常用的通道，如果它自己坏了（比如 asset
// 没声明、初始化代码写错），开发者会以为「项目坏了」，浪费很久。
//
// 运行：flutter test test/dev/reading_preview_smoke_test.dart --no-pub

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phrasing/dev/reading_preview.dart';

void main() {
  testWidgets('读页预览入口能起来，且能读到真实课文', (tester) async {
    await tester.pumpWidget(const ReadingPreviewApp());
    // 等 asset 加载 + setState
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);

    // 预览页的标题
    expect(find.text('读页 UI 实验室'), findsOneWidget);

    // 真实课文应已渲染（ruby 排版逐字 Text ⇒ 按单字找）
    expect(find.text('课'), findsWidgets);
  });
}
