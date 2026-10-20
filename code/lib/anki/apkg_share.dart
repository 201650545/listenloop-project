import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 分享 .apkg 时的异常类型。区分「用户取消」（无需提示）与「真失败」（要提示原因）。
class ApkgShareException implements Exception {
  ApkgShareException(this.message);
  final String message;
  @override
  String toString() => 'ApkgShareException: $message';
}

/// 把导出的 .apkg 字节写进临时目录并通过系统分享面板交出去。
///
/// 背景：`file_picker` 的 `saveFile()` 在 Android 上从未实现（基类直接
/// throw UnimplementedError），因此「保存到本地」这条路径在 Android 是死路。
/// 改用系统分享面板：用户可把 .apkg 发到 Anki 桌面端、微信文件助手或任意
/// 目标（Android 的「分享」面板本身提供"保存到文件"入口）。
///
/// 返回 true 表示用户真的发起了分享；用户取消（dismissed）抛 [ApkgShareException]。
Future<bool> shareApkgBytes({
  required String fileName,
  required Uint8List bytes,
  String? shareSubject,
  String? shareText,
}) async {
  final tmp = await getTemporaryDirectory();
  final file = File('${tmp.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);

  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/octet-stream')],
      subject: shareSubject ?? fileName,
      text: shareText,
    ),
  );
  if (result.status == ShareResultStatus.dismissed) {
    throw ApkgShareException('用户取消了分享');
  }
  return true;
}
