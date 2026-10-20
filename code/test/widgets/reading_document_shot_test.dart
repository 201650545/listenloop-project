// 读页三屏视觉基线（首屏 / 中段 / 末屏）—— 2026-10-21。
//
// ⚠️ 本文件最初想用 `RenderRepaintBoundary.toImage()` 直接写 PNG 到 scratch，
//    但在 flutter_test 里**会卡住不返回**（844px 也卡：flutter_tester 占
//    200MB 但 CPU 不动，跑 2 分钟无输出）⇒ 改走 **golden** 机制。
//    现役实现见同目录 `reading_document_shots_test.dart`（三张基线图，
//    跑一次 1.5 秒）。
//
// 看图：
//   explorer D:\listenloop\test\widgets\goldens
//   · reading_document_head.png    首屏
//   · reading_document_middle.png  中段（当前句在中间）
//   · reading_document_tail.png    末屏
//
// 运行：
//   flutter test test/widgets/reading_document_shots_test.dart --no-pub
//   （重建基线加 --update-goldens）
//
// 为什么值得做：2026-10-20 真机出过「读页只显示一句、其余大片空白」的
// bug ⇒ 现在**不装真机也能一眼肉眼验收**整篇渲染是否正常。

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('说明：本文件只留指针，实现在 reading_document_shots_test.dart', () {
    // ignore: avoid_print
    print(
      '读页三屏视觉基线见 '
      'test/widgets/reading_document_shots_test.dart；'
      '基线图在 test/widgets/goldens/reading_document_{head,middle,tail}.png',
    );
  });
}
