import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Client for the YouTube audio relay.
///
/// 中继是唯一需要 yt-dlp（Python）的一环，而安卓自身没有 Python，所以它住在
/// 能跑 Python 的地方。同一份 HTTP 契约有**两个可互换的实现**，都监听
/// `127.0.0.1:8793`，因此本客户端与 App 配置对两者完全无感：
///
///  1. **手机端（默认，不依赖电脑）** —— `tool/termux/ll_relay.py`，跑在手机的
///     Termux 里，直接用手机自己的网络/代理访问 YouTube。
///  2. **电脑端（可选）** —— `tool/youtube_relay.py`，配 `adb reverse
///     tcp:8793 tcp:8793` 把同一端口映到 PC；也可直接填局域网 IP。
///
/// 两者互斥（同一端口只能有一个监听者）：手机端中继在跑时不要再做 8793 的
/// adb reverse，否则设备侧端口被占用，手机端中继会绑定失败。
class YouTubeRelayClient {
  YouTubeRelayClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  static const String defaultBaseUrl = 'http://127.0.0.1:8793';

  final String baseUrl;
  final http.Client _client;

  /// Checks whether the PC relay is reachable and healthy.
  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/ping'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Downloads bestaudio for [url] into [savePath]. Returns the video title
  /// (empty when the relay did not send one).
  Future<String> downloadAudio(
    String url,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('POST', Uri.parse('$baseUrl/resolve'))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({'url': url});
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final reason = await response.stream.bytesToString();
      throw YouTubeRelayException(
        reason.isEmpty ? 'relay HTTP ${response.statusCode}' : reason,
      );
    }
    final rawTitle = response.headers['x-ll-title'];
    final title = rawTitle == null ? '' : Uri.decodeComponent(rawTitle);
    final total = response.contentLength;
    final sink = File(savePath).openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total != null && total > 0 && onProgress != null) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return title;
  }
}

class YouTubeRelayException implements Exception {
  const YouTubeRelayException(this.message);
  final String message;

  @override
  String toString() => 'YouTubeRelayException: $message';
}
