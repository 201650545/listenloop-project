import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Client for the PC-side YouTube audio relay (tool/youtube_relay.py).
///
/// The phone cannot run yt-dlp (no Python, no PO-token machinery). The PC
/// can — with its traffic exiting through the phone's VPN via adb forward,
/// YouTube's PC-IP blacklist no longer applies. The relay streams the audio
/// back; this pipeline continues exactly as with a local file.
///
/// Reachability: with the phone plugged in, `adb reverse tcp:8793 tcp:8793`
/// maps the app's 127.0.0.1:8793 onto the PC relay (default below). A LAN
/// base URL works equally well.
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
