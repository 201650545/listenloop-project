import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Bilibili link source (M3 从链接创建, Bilibili first).
///
/// The PC pipeline proved the flow on 2026-09-16 (tool/whisper_to_lesson.py):
/// view API → playurl API with `fnval=16` (DASH) → download the audio m4s
/// with Referer + UA headers. Anonymous access works for these endpoints;
/// the CC-subtitle API is what needed a cookie, and we do not use it.
///
/// HTTP is injectable so every decision here is unit-testable without
/// touching the network.

/// A parsed bilibili video reference.
@immutable
class BiliVideoRef {
  const BiliVideoRef({required this.bvid, this.page = 1});

  /// AV/BV identifier, e.g. `BV1Gf4y1y7wc`.
  final String bvid;

  /// 1-based part number (`?p=N`); defaults to the first part.
  final int page;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BiliVideoRef &&
          other.bvid == bvid &&
          other.page == page;

  @override
  int get hashCode => Object.hash(bvid, page);

  @override
  String toString() => 'BiliVideoRef($bvid?p$page)';
}

class BiliVideoInfo {
  const BiliVideoInfo({
    required this.bvid,
    required this.title,
    required this.coverUrl,
    required this.cid,
    required this.durationSec,
  });

  final String bvid;
  final String title;
  final String coverUrl;

  /// cid of the selected part — playurl's media key.
  final int cid;

  /// Duration of the selected part, seconds.
  final int durationSec;
}

/// One downloadable DASH stream.
class BiliStream {
  const BiliStream({required this.url, required this.sizeBytes});

  final String url;
  final int sizeBytes;
}

class BiliStreamSet {
  const BiliStreamSet({required this.audio, this.video});

  /// Best audio stream (highest bandwidth).
  final BiliStream audio;

  /// Best video stream, or null when the response carries audio only.
  final BiliStream? video;
}

/// Extracts a [BiliVideoRef] from a URL or a bare BV id.
///
/// Accepted: full bilibili.com/b23.tv video URLs (`?p=N` honoured), bare
/// `BV…`/`av…` ids. Returns null for anything else — the caller turns that
/// into a friendly input error.
BiliVideoRef? parseBilibiliUrl(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;

  // Bare id forms.
  final bareBv = RegExp(r'^(BV[0-9A-Za-z]{10})$').firstMatch(value);
  if (bareBv != null) return BiliVideoRef(bvid: bareBv.group(1)!);
  final bareAv = RegExp(r'^av(\d+)$', caseSensitive: false).firstMatch(value);
  if (bareAv != null) return BiliVideoRef(bvid: 'av${bareAv.group(1)!}');

  final bvid = RegExp(r'(BV[0-9A-Za-z]{10})').firstMatch(value)?.group(1);
  if (bvid == null) return null;
  final page =
      int.tryParse(
        RegExp(r'[?&]p=(\d+)').firstMatch(value)?.group(1) ?? '',
      ) ??
      1;
  return BiliVideoRef(bvid: bvid, page: page < 1 ? 1 : page);
}

/// Extracts the first http(s) URL from a pasted blob of text.
///
/// Users paste share text like 「【标题-哔哩哔哩】 https://b23.tv/NOylPL4」 —
/// the URL rides inside arbitrary text, so scanning beats strict matching.
String? extractUrl(String input) {
  // Only match valid URL ASCII characters, excluding Chinese characters/punctuation
  final match = RegExp(
    r'https?://[a-zA-Z0-9\-._~:/?#\[\]@!$&*+,;=%]+',
  ).firstMatch(input.trim());
  if (match == null) return null;
  var url = match.group(0)!;
  // Strip trailing punctuation often appended by users or copy-paste
  while (url.isNotEmpty &&
      (url.endsWith(',') ||
          url.endsWith('.') ||
          url.endsWith(';') ||
          url.endsWith('?') ||
          url.endsWith('!') ||
          url.endsWith(')') ||
          url.endsWith(']'))) {
    url = url.substring(0, url.length - 1);
  }
  return url.isEmpty ? null : url;
}

class BilibiliException implements Exception {
  const BilibiliException(this.message);
  final String message;

  @override
  String toString() => 'BilibiliException: $message';
}

class BilibiliClient {
  BilibiliClient({
    http.Client? client,
    Future<Uri> Function(Uri url)? redirectResolver,
  }) : _client = client ?? http.Client(),
       _redirectResolverOverride = redirectResolver;

  static const _referer = 'https://www.bilibili.com';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static const _headers = {
    'Referer': _referer,
    'User-Agent': _userAgent,
  };

  final http.Client _client;
  final Future<Uri> Function(Uri url)? _redirectResolverOverride;

  /// Walks the Location chain on THIS client so tests inject a fake and the
  /// production instance shares its connection pooling.
  Future<Uri> Function(Uri) get _redirectResolver =>
      _redirectResolverOverride ?? _followRedirects;

  /// Walks the Location chain on THIS client so tests inject a fake and the
  /// production instance shares its connection pooling.
  Future<Uri> _followRedirects(Uri url) async {
    // package:http never exposes the FINAL url after its internal
    // redirect-following (response.request.url stays the original), so
    // walk the Location chain manually — b23.tv is exactly this case
    // (real-device failure 2026-09-18: the short link resolved back to
    // itself and BV extraction failed).
    var current = url;
    for (var hop = 0; hop < 6; hop++) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(_headers);
      final response = await _client.send(request);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) return current;
        final next = Uri.parse(location);
        current = next.isAbsolute ? next : current.resolve(location);
        await response.stream.drain<void>();
        continue;
      }
      await response.stream.drain<void>();
      return current;
    }
    return current;
  }

  /// Resolves ANY accepted input form to a video reference: full URL, bare
  /// BV/av id, or a b23.tv short link (network 302 follow).
  Future<BiliVideoRef> resolve(String rawInput) async {
    final candidate = extractUrl(rawInput) ?? rawInput.trim();
    final direct = parseBilibiliUrl(candidate);
    if (direct != null) return direct;
    final host = Uri.tryParse(candidate)?.host.toLowerCase() ?? '';
    if (host.endsWith('b23.tv') || host.endsWith('bilibili.com')) {
      final resolveRedirect = _redirectResolver;
      final finalUrl = await resolveRedirect(Uri.parse(candidate));
      final ref = parseBilibiliUrl(finalUrl.toString());
      if (ref != null) return ref;
    }
    throw BilibiliException('无法识别链接——支持 bilibili 链接 / BV 号');
  }

  /// View API: title / cover / cid of part [ref.page] / duration.
  Future<BiliVideoInfo> fetchVideoInfo(BiliVideoRef ref) async {
    final response = await _client.get(
      Uri.https('api.bilibili.com', '/x/web-interface/view', {
        if (ref.bvid.startsWith('av')) 'aid': ref.bvid.substring(2)
        else 'bvid': ref.bvid,
      }),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw BilibiliException('view API HTTP ${response.statusCode}');
    }
    final body = _jsonObject(response.body);
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw BilibiliException('view API code $code (${body['message']})');
    }
    final data = body['data'] as Map<String, dynamic>? ?? const {};
    final pages = (data['pages'] as List?) ?? const [];
    final pageIndex = ref.page - 1;
    if (pageIndex < 0 || pageIndex >= pages.length) {
      throw BilibiliException('part ${ref.page} out of range');
    }
    final page = pages[pageIndex] as Map<String, dynamic>;
    return BiliVideoInfo(
      bvid: (data['bvid'] as String?) ?? ref.bvid,
      title: (page['part'] as String?) ?? (data['title'] as String? ?? ''),
      coverUrl: (data['pic'] as String?) ?? '',
      cid: (page['cid'] as num).toInt(),
      durationSec: ((page['duration'] as num?) ?? data['duration'] as num? ?? 0)
          .toInt(),
    );
  }

  /// playurl API (DASH): best audio + best video for [info.cid].
  Future<BiliStreamSet> fetchStreams(BiliVideoInfo info) async {
    final response = await _client.get(
      Uri.https('api.bilibili.com', '/x/player/playurl', {
        if (info.bvid.startsWith('av')) 'aid': info.bvid.substring(2)
        else 'bvid': info.bvid,
        'cid': '${info.cid}',
        'fnval': '16', // DASH
        'qn': '64',
      }),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw BilibiliException('playurl API HTTP ${response.statusCode}');
    }
    final body = _jsonObject(response.body);
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw BilibiliException('playurl code $code (${body['message']})');
    }
    final data = body['data'] as Map<String, dynamic>? ?? const {};
    final dash = data['dash'] as Map<String, dynamic>?;
    if (dash == null) {
      throw BilibiliException('no DASH streams (legacy-only video?)');
    }
    final audio = _best((dash['audio'] as List?) ?? const []);
    if (audio == null) {
      throw BilibiliException('no audio stream in DASH response');
    }
    return BiliStreamSet(
      audio: audio,
      video: _best((dash['video'] as List?) ?? const []),
    );
  }

  /// Streams [url] into [savePath] with progress in 0..1 when [total] is
  /// known. Media CDN requires the Referer or it returns 403.
  Future<void> download(
    String url,
    String savePath, {
    int? total,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url))
      ..headers.addAll(_headers);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw BilibiliException('media HTTP ${response.statusCode}');
    }
    final known = total ?? response.contentLength;
    final sink = File(savePath).openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (known != null && known > 0 && onProgress != null) {
          onProgress((received / known).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  BiliStream? _best(List<dynamic> streams) {
    BiliStream? best;
    var bestBandwidth = -1;
    for (final raw in streams) {
      if (raw is! Map<String, dynamic>) continue;
      final baseUrl = (raw['baseUrl'] ?? raw['base_url']) as String?;
      if (baseUrl == null || baseUrl.isEmpty) continue;
      final bandwidth = (raw['bandwidth'] as num?)?.toInt() ?? 0;
      final size = (raw['size'] as num?)?.toInt() ?? 0;
      if (bandwidth > bestBandwidth) {
        bestBandwidth = bandwidth;
        best = BiliStream(url: baseUrl, sizeBytes: size);
      }
    }
    return best;
  }

  Map<String, dynamic> _jsonObject(String raw) {
    // The APIs sometimes prefix anti-hotlink guards; find the first '{'.
    final start = raw.indexOf('{');
    if (start < 0) throw const BilibiliException('response is not JSON');
    try {
      final decoded = const JsonDecoder().convert(raw.substring(start));
      if (decoded is! Map<String, dynamic>) {
        throw const BilibiliException('response is not a JSON object');
      }
      return decoded;
    } on FormatException {
      throw const BilibiliException('response is not valid JSON');
    }
  }
}
