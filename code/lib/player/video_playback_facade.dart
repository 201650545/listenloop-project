import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/video_source.dart';
import 'audio_player_facade.dart';

/// Transport used by [VideoPlaybackFacade] to drive an embedded web player.
///
/// Keeping the transport abstract lets the facade be unit-tested without the
/// `webview_flutter` platform plugin: production injects [WebViewVideoBridge],
/// tests inject an in-memory fake.
abstract class VideoBridge {
  /// Messages posted from the page harness back to Dart.
  Stream<Map<String, dynamic>> get messages;

  /// Executes a snippet in the page.
  Future<void> send(String javaScript);

  /// Loads [url] into the page, replacing the current document.
  Future<void> load(String url);

  /// Completes once the page harness reports a usable media element,
  /// i.e. `readyState >= 1` and `duration > 0`.
  Future<void> get ready;

  /// Releases resources held by the bridge.
  Future<void> dispose();
}

/// Message channel shared by the harness JS and [WebViewVideoBridge].
const String kVideoBridgeChannel = 'LLVideo';

/// The harness that is (re)injected on every `onPageFinished`.
///
/// It exposes `window.LLVideo` with a tiny command protocol and pushes playhead
/// updates on an interval. Commands carry an `id` and are acknowledged so the
/// Dart side never has to rely on `runJavaScriptReturningResult`, whose Promise
/// resolution is unreliable on Android.
const String _harnessJs = r'''
(function () {
  if (window.LLVideo && window.LLVideo.__installed) { return; }

  var startedAt = performance.now();
  var pendingSeek = null;
  var lastPost = 0;
  var video = null;
  var metaReady = false;
  var metaWaiters = [];

  function channel() { return window.LLVideo; }
  function emit(obj) {
    try {
      var ch = channel();
      if (ch && ch.postMessage) { ch.postMessage(JSON.stringify(obj)); }
    } catch (e) { /* channel not bound yet */ }
  }

  function findVideo() {
    var list = document.getElementsByTagName('video');
    for (var i = 0; i < list.length; i++) {
      if (list[i].duration > 0 || list[i].readyState >= 1) { return list[i]; }
    }
    return list.length ? list[0] : null;
  }

  function ensureVideo() {
    if (video && video.parentNode) { return video; }
    video = findVideo();
    return video;
  }

  // Metadata may lag far behind the element appearing: bilibili resolves the
  // media of a full-length film (~2h45m) in 13s+ even though the <video> tag
  // lands in ~1.3s. Commands must therefore gate on this, not on presence.
  function hasMetadata(v) {
    return !!v && ((v.duration > 0 && isFinite(v.duration)) || v.readyState >= 1);
  }

  // Phase 1 — announce the page as usable as soon as a media element exists.
  function waitForElement() {
    var v = ensureVideo();
    if (v) {
      window.LLVideo.__ready = true;
      emit({ type: 'video-attached', ms: Math.round(performance.now() - startedAt) });
      return;
    }
    if (performance.now() - startedAt > 30000) {
      emit({ type: 'video-timeout', readyState: -1 });
      return;
    }
    setTimeout(waitForElement, 100);
  }

  // Phase 2 — announce real metadata so Dart can drop its loading cue.
  function waitForMetadata() {
    var v = ensureVideo();
    if (hasMetadata(v)) {
      window.LLVideo.__metaReady = true;
      emit({ type: 'video-found', ms: Math.round(performance.now() - startedAt),
             durationMs: Math.round((v.duration || 0) * 1000), readyState: v.readyState });
      flushMetaWaiters();
      return;
    }
    if (performance.now() - startedAt > 60000) {
      emit({ type: 'metadata-timeout', readyState: v ? v.readyState : -1 });
      flushMetaWaiters();
      return;
    }
    setTimeout(waitForMetadata, 120);
  }

  function flushMetaWaiters() {
    metaReady = true;
    var list = metaWaiters.slice();
    metaWaiters.length = 0;
    for (var i = 0; i < list.length; i++) {
      try { list[i](ensureVideo()); } catch (e) { /* caller reports its own ack */ }
    }
  }

  // Runs fn once metadata is available, and keeps the Dart-side caller from
  // timing out silently while a long source is still resolving.
  function runWhenReady(id, fn) {
    var v = ensureVideo();
    if (hasMetadata(v)) {
      try { fn(v); } catch (e) { emit({ type: 'ack', id: id, ok: false, reason: 'exec-failed' }); }
      return;
    }
    var settled = false;
    metaWaiters.push(function (vv) {
      settled = true;
      try { fn(vv); } catch (e) { emit({ type: 'ack', id: id, ok: false, reason: 'exec-failed' }); }
    });
    setTimeout(function () {
      if (!settled) { emit({ type: 'ack', id: id, ok: false, reason: 'metadata-timeout' }); }
    }, 45000);
  }

  function seekDeadlineFor(targetMs) {
    var v = ensureVideo();
    var durationMs = (v && v.duration && isFinite(v.duration)) ? v.duration * 1000 : targetMs;
    // Seeking deep into a long 4K source costs seconds; the old flat 4s window
    // was tuned for short clips and misfired on full-length films.
    if (durationMs > 1800000) { return 12000; }
    if (durationMs > 600000) { return 8000; }
    return 4000;
  }

  function tick() {
    var v = ensureVideo();
    if (v) {
      var now = performance.now();
      if (now - lastPost >= 100) {
        lastPost = now;
        var ms = Math.round(v.currentTime * 1000);
        if (pendingSeek) {
          var drift = Math.abs(ms - pendingSeek.targetMs);
          if (drift <= 150 || now >= pendingSeek.deadline) {
            pendingSeek = null;
            emit({ type: 'seeked', ms: ms });
          }
        } else {
          emit({ type: 'pos', ms: ms, playing: !v.paused, rate: v.playbackRate });
        }
      }
    }
    setTimeout(tick, 100);
  }

  window.LLVideo = window.LLVideo || {};
  window.LLVideo.__installed = true;
  window.LLVideo.__ready = false;
  window.LLVideo.__metaReady = false;
  window.LLVideo.cmd = function (json) {
    var req;
    try { req = (typeof json === 'string') ? JSON.parse(json) : json; }
    catch (e) { return; }
    var args = req.args || {};
    var id = req.id;
    switch (req.op) {
      case 'seek': {
        var targetMs = args.ms || 0;
        runWhenReady(id, function (v) {
          pendingSeek = { targetMs: targetMs, deadline: performance.now() + seekDeadlineFor(targetMs) };
          try {
            v.currentTime = targetMs / 1000;
            emit({ type: 'ack', id: id, ok: true });
          } catch (e) {
            pendingSeek = null;
            emit({ type: 'ack', id: id, ok: false, reason: 'seek-failed' });
          }
        });
        return;
      }
      case 'play': {
        runWhenReady(id, function (v) {
          try {
            var p = v.play();
            if (p && p.catch) { p.catch(function () {}); }
          } catch (e) {}
          emit({ type: 'ack', id: id, ok: true });
        });
        return;
      }
      case 'pause': {
        runWhenReady(id, function (v) {
          try { v.pause(); } catch (e) {}
          emit({ type: 'ack', id: id, ok: true });
        });
        return;
      }
      case 'rate': {
        runWhenReady(id, function (v) {
          try { v.playbackRate = args.rate || 1; } catch (e) {}
          emit({ type: 'ack', id: id, ok: true });
        });
        return;
      }
      case 'position': {
        var v0 = ensureVideo();
        if (!hasMetadata(v0)) {
          emit({ type: 'ack', id: id, ok: false, reason: 'no-metadata' });
          return;
        }
        emit({ type: 'ack', id: id, ok: true,
               ms: Math.round(v0.currentTime * 1000),
               playing: !v0.paused, rate: v0.playbackRate });
        return;
      }
      default:
        emit({ type: 'ack', id: id, ok: false, reason: 'unknown-op' });
    }
  };

  waitForElement();
  waitForMetadata();
  tick();
})();
''';

/// Production [VideoBridge] backed by a [WebViewController].
class WebViewVideoBridge implements VideoBridge {
  WebViewVideoBridge(this.controller) {
    unawaited(
      controller.addJavaScriptChannel(
        kVideoBridgeChannel,
        onMessageReceived: _onMessage,
      ),
    );
  }

  final WebViewController controller;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  Completer<void> _readyCompleter = Completer<void>();
  bool _disposed = false;

  void _onMessage(JavaScriptMessage message) {
    if (_disposed) return;
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    _messages.add(decoded);
    // Readiness has two stages: `video-attached` means the media element
    // exists (fast — ~1.3s even for a full-length film), `video-found` means
    // its metadata resolved (up to 13s+ on bilibili for a 2h45m source). The
    // bridge unblocks on the first stage; commands wait for the second.
    final type = decoded['type'];
    if ((type == 'video-found' || type == 'video-attached') &&
        !_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Future<void> send(String javaScript) => controller.runJavaScript(javaScript);

  @override
  Future<void> load(String url) {
    if (_readyCompleter.isCompleted) {
      _readyCompleter = Completer<void>();
    }
    return controller.loadRequest(Uri.parse(url));
  }

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(StateError('bridge disposed'));
    }
    await _messages.close();
  }
}

/// [AudioPlayerFacade] implementation that drives an embedded web video player
/// (currently the bilibili player) instead of a local audio file.
///
/// The playback *control logic* is untouched: [SentencePlayerController] still
/// sequences sentences, loops and watches the playhead. This facade only
/// translates its interface onto page commands, absorbing the
/// [VideoSource.offsetMs] shift internally so the controller keeps working on
/// the lesson timeline.
class VideoPlaybackFacade implements AudioPlayerFacade {
  VideoPlaybackFacade({
    required this.source,
    VideoBridge? bridge,
    WebViewController? controller,
    // Only the *element* has to show up within this window (measured at ~1.3s
    // even for a full-length film); metadata resolution is awaited per command.
    this.readyTimeout = const Duration(seconds: 30),
  }) : _ownsBridge = bridge == null,
       _bridge =
           bridge ?? WebViewVideoBridge(controller ?? _createController()) {
    _messageSub = _bridge.messages.listen(_onMessage);
    final webViewBridge = _bridge;
    if (webViewBridge is WebViewVideoBridge) {
      webViewBridge.controller.setNavigationDelegate(
        NavigationDelegate(
          // Re-inject the harness whenever navigation replaces the document.
          onPageFinished: (_) => onPageFinished(),
          onWebResourceError: onResourceError,
        ),
      );
    }
  }

  /// Builds a controller with autoplay allowed (Android gates media playback
  /// behind a user gesture otherwise and metadata never loads).
  static WebViewController _createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    return controller;
  }

  final VideoSource source;
  final Duration readyTimeout;
  final VideoBridge _bridge;
  final bool _ownsBridge;

  /// False until the page reports usable media metadata. Set back to false on
  /// every [setAsset]: the previous page's readiness says nothing about the new
  /// one, and for a full-length source this lags seconds behind element attach.
  bool _metadataReady = false;

  final _positionController = StreamController<Duration>.broadcast();
  final _errorController = StreamController<AudioPlaybackError>.broadcast();

  late final StreamSubscription<Map<String, dynamic>> _messageSub;

  final Map<int, Completer<void>> _pending = {};
  Completer<void>? _seekCompleter;
  int _nextId = 0;
  Duration _position = Duration.zero;
  bool _disposed = false;
  bool _harnessInjected = false;

  /// The WebView controller that owns the page; the UI renders it directly.
  WebViewController get controller {
    final bridge = _bridge;
    if (bridge is WebViewVideoBridge) return bridge.controller;
    throw StateError('controller is only available for the production bridge');
  }

  /// The player page the WebView should display.
  String get playerUrl => source.playerUrlAt(0);

  int _lessonMsToVideoMs(int lessonMs) => lessonMs + source.offsetMs;
  int _videoMsToLessonMs(int videoMs) => videoMs - source.offsetMs;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  // The embedded web player has no clip concept: it plays whatever the page
  // plays, and the controller stops it via position-stream watching (the
  // pre-clip behaviour). setClip therefore degrades to a plain seek.
  @override
  bool get enforcesClipEnd => false;

  @override
  int? get currentPlaylistIndex => null;

  @override
  Stream<PlaybackCompletionEvent> get completionStream =>
      const Stream<PlaybackCompletionEvent>.empty();

  @override
  Future<void> setClip(Duration start, Duration end) => seek(start);

  /// True once the embedded player resolved media metadata.
  ///
  /// False right after [setAsset] means "page is up, media still buffering" —
  /// the UI should keep showing a cue rather than assume a failure. Fake
  /// bridges used by tests report true so widgets stay deterministic.
  bool get hasMetadata => _metadataReady;

  @override
  Stream<AudioPlaybackError> get errorStream => _errorController.stream;

  @override
  Duration get position => _position;

  /// In video mode the audio asset is irrelevant; the page is loaded instead.
  @override
  Future<void> setAsset(String assetPath) async {
    if (_disposed) return;
    _harnessInjected = false;
    _metadataReady = false;
    try {
      await _bridge.load(playerUrl);
      await _injectHarness();
      await _bridge.ready.timeout(
        readyTimeout,
        onTimeout: () => throw StateError('video metadata unavailable'),
      );
    } on Object catch (error) {
      _errorController.add(AudioPlaybackError(code: -1, message: '$error'));
      rethrow;
    }
  }

  @override
  Future<void> setFilePath(String filePath) => setAsset(filePath);

  Future<void> _injectHarness() async {
    if (_harnessInjected || _disposed) return;
    _harnessInjected = true;
    await _bridge.send(_harnessJs);
  }

  /// Re-runs the harness after a navigation replaces the document.
  void onPageFinished() {
    _harnessInjected = false;
    unawaited(_injectHarness());
  }

  /// Reports a page load failure. Only main-frame failures surface as errors;
  /// sub-resource `ERR_FAILED` warnings (ads, trackers) are ignored.
  void onResourceError(WebResourceError error) {
    if (_disposed) return;
    if (error.isForMainFrame != true) return;
    _errorController.add(
      AudioPlaybackError(code: error.errorCode, message: error.description),
    );
  }

  Future<void> _command(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    if (_disposed) return;
    final id = _nextId++;
    final completer = Completer<void>();
    _pending[id] = completer;
    final payload = jsonEncode({'id': id, 'op': op, 'args': args});
    await _bridge.send('window.LLVideo && window.LLVideo.cmd($payload);');
    try {
      // Waiting-for-metadata is folded into this ack for long sources: a 2h45m
      // 4K title needs its fair share of seconds before the first seek lands.
      await completer.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // The page may still act on the command; do not fail the caller.
    } finally {
      _pending.remove(id);
    }
  }

  void _onMessage(Map<String, dynamic> message) {
    if (_disposed) return;
    switch (message['type']) {
      case 'ack':
        final id = message['id'];
        if (id is int) _pending.remove(id)?.complete();
      case 'video-found':
        _metadataReady = true;
      case 'pos':
        final ms = message['ms'];
        if (ms is num) {
          _position = Duration(milliseconds: _videoMsToLessonMs(ms.round()));
          _positionController.add(_position);
        }
      case 'seeked':
        final ms = message['ms'];
        if (ms is num) {
          _position = Duration(milliseconds: _videoMsToLessonMs(ms.round()));
          _positionController.add(_position);
        }
        _seekCompleter?.complete();
        _seekCompleter = null;
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _seekCompleter?.complete();
    final completer = Completer<void>();
    _seekCompleter = completer;
    await _command('seek', {'ms': _lessonMsToVideoMs(position.inMilliseconds)});
    try {
      await completer.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Fall through: the page suppresses playhead updates during the seek, so
      // a missed acknowledgement cannot resurrect a stale position.
    }
    if (identical(_seekCompleter, completer)) _seekCompleter = null;
    _position = position;
  }

  @override
  Future<void> play() => _command('play');

  @override
  Future<void> pause() => _command('pause');

  @override
  Future<void> setSpeed(double rate) => _command('rate', {'rate': rate});

  @override
  Stream<int> get currentIndexStream => const Stream<int>.empty();

  @override
  Future<void> loadPlaylist({
    required String path,
    required bool isFile,
    required List<SentenceClip> clips,
    int initialIndex = 0,
  }) async {
    // Video player plays via web player URL/bridge rather than audio files.
  }

  @override
  Future<void> seekSentence(int index, Duration position) => seek(position);

  @override
  Future<void> setLoopOne(bool loopOne) async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _messageSub.cancel();
    _seekCompleter?.complete();
    _seekCompleter = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _pending.clear();
    await _positionController.close();
    await _errorController.close();
    if (_ownsBridge) await _bridge.dispose();
  }
}
