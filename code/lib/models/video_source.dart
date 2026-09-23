/// Where the video for a lesson lives (Phase 3A, spec V0.3 §3A).
///
/// A lesson's audio is always present locally, so the app stays fully offline
/// and usable without a network. When [VideoSource] is present it is an
/// *enhancement*: the same sentence timeline is also shown against the source
/// video. The prototype supports embedded Bilibili players only.
///
/// The lesson audio timeline and the video timeline are aligned by [offsetMs]:
/// `videoTimeMs == lessonTimeMs + offsetMs`. For a lesson whose audio was
/// ripped straight from one Bilibili page this is simply 0.
class VideoSource {
  const VideoSource({
    required this.provider,
    required this.bvid,
    required this.page,
    this.cid,
    this.offsetMs = 0,
  });

  /// Providers understood by this build.
  static const String providerBilibili = 'bilibili';
  static const String providerYoutube = 'youtube';

  /// The providers this build can render.
  static const Set<String> supportedProviders = {
    providerBilibili,
    providerYoutube,
  };

  final String provider;

  /// Video identifier: Bilibili BV id (e.g. `BV1Gf4y1y7wc`) or YouTube video id.
  final String bvid;

  /// One-based page (part) number within the multi-part video (always 1 for YouTube).
  final int page;

  /// Optional content id of the page; informational, used for diagnostics.
  final int? cid;

  /// Milliseconds to add to a lesson timestamp to get the video timestamp.
  final int offsetMs;

  /// The embeddable player URL for [atMs] on the lesson timeline.
  ///
  /// For Bilibili: `autoplay=1` starts playback and `danmaku=0` hides bullet comments.
  /// For YouTube: `autoplay=1&enablejsapi=1` with start seconds.
  String playerUrlAt(int lessonMs) {
    final videoSeconds = ((lessonMs + offsetMs) / 1000).floor().clamp(
      0,
      1 << 31,
    );
    if (provider == providerYoutube) {
      return Uri.https('www.youtube-nocookie.com', '/embed/$bvid', {
        'autoplay': '1',
        'start': '$videoSeconds',
        'enablejsapi': '1',
        'playsinline': '1',
        'rel': '0',
      }).toString();
    }
    return Uri.https('player.bilibili.com', '/player.html', {
      'bvid': bvid,
      'p': '$page',
      if (cid != null) 'cid': '$cid',
      't': '$videoSeconds',
      'autoplay': '1',
      'danmaku': '0',
    }).toString();
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'bvid': bvid,
    'page': page,
    if (cid != null) 'cid': cid,
    if (offsetMs != 0) 'offsetMs': offsetMs,
  };

  /// Inverse of [toJson]; tolerates malformed data by returning null.
  static VideoSource? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final provider = raw['provider'];
    final bvid = raw['bvid'];
    final page = raw['page'];
    if (provider is! String || !supportedProviders.contains(provider)) {
      return null;
    }
    if (bvid is! String || bvid.isEmpty) return null;
    if (page is! int || page < 1) return null;
    final cid = raw['cid'];
    final offsetMs = raw['offsetMs'];
    return VideoSource(
      provider: provider,
      bvid: bvid,
      page: page,
      cid: cid is int ? cid : null,
      offsetMs: offsetMs is int ? offsetMs : 0,
    );
  }

  @override
  String toString() =>
      'VideoSource($provider, $bvid, page $page, offset ${offsetMs}ms)';
}
