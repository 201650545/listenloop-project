import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/video_source.dart';

/// Phase 3A spike screen (V0.3 §3A).
///
/// Throwaway diagnostic harness that proves the two things the whole Video
/// Mode design rests on, on real hardware:
///
///  1. `player.bilibili.com/player.html` embeds and plays inside a
///     `webview_flutter` [WebViewWidget] with no black screen.
///  2. The `<video>` element lives in the *top-level* document, so we can
///     read and set `video.currentTime` with injected JavaScript — meaning
///     sentence seeking needs no iframe reload (the old HANDOFF note that
///     "reloading resets the position" is obsolete).
///
/// It also measures seek latency and accuracy so the real controller can pick
/// a sane seek-confirmation timeout. Not part of the product surface.
class VideoPrototypeScreen extends StatefulWidget {
  const VideoPrototypeScreen({super.key, required this.source});

  final VideoSource source;

  @override
  State<VideoPrototypeScreen> createState() => _VideoPrototypeScreenState();
}

class _VideoPrototypeScreenState extends State<VideoPrototypeScreen> {
  late final WebViewController _controller;
  final List<String> _log = [];
  bool _ready = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel('LLProbe', onMessageReceived: _onProbeMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _log.add('页面加载完成，开始探测 <video>…');
            _setStateIfMounted();
            _attachHarness();
          },
          onWebResourceError: (error) {
            // Sub-resource noise (poster CORS, ad beacons) is expected on the
            // Bilibili player; only main-frame failures are fatal.
            final tag = error.isForMainFrame == true ? '主文档错误' : '资源警告';
            _log.add('$tag: ${error.description}');
            _setStateIfMounted();
          },
        ),
      );
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // Autoplay without a user tap — the player must start on its own so the
      // video tracks the sentence timeline. Its own play() is unreliable
      // behind a gesture gate on Android WebView.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    final url = widget.source.playerUrlAt(0);
    _log.add('加载: $url');
    _controller.loadRequest(Uri.parse(url));
  }

  void _setStateIfMounted() {
    if (mounted) setState(() {});
  }

  void _onProbeMessage(JavaScriptMessage message) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(message.message);
    } catch (_) {
      _log.add('原始: ${message.message}');
      _setStateIfMounted();
      return;
    }
    if (decoded is! Map) return;
    switch (decoded['type']) {
      case 'video-found':
        _ready = true;
        _log
          ..add('找到 video 元素 (${decoded['ms']} ms)')
          ..add(
            '时长: ${decoded['duration']} s · readyState: '
            '${decoded['readyState']} · src: ${decoded['srcScheme']}',
          )
          ..add('媒体加载完成: ${decoded['mediaReadyMs']} ms');
      case 'seek':
        _log.add(
          'seek ${decoded['target']}s → 实际 ${decoded['actual']}s · '
          '延迟 ${decoded['latencyMs']} ms · 误差 '
          '${decoded['errorMs']} ms',
        );
      case 'rate':
        _log.add(
          '播放速率设为 ${decoded['requested']} → 生效 '
          '${decoded['applied']}',
        );
      case 'done':
        _running = false;
        _log.add('— 探测结束 —');
      case 'error':
        _log.add('探测错误: ${decoded['message']}');
    }
    _setStateIfMounted();
  }

  /// Injected into the page: wait for the video, then seek to 10 targets and
  /// report latency/accuracy for each. Runs in the top-level document.
  void _attachHarness() {
    _controller.runJavaScript(_harnessJs);
  }

  static const String _harnessJs = r'''
(function () {
  var startedAt = performance.now();
  function post(obj) {
    if (window.LLProbe) window.LLProbe.postMessage(JSON.stringify(obj));
  }
  var waited = 0;
  var timer = setInterval(function () {
    var v = document.querySelector('video');
    if (!v) {
      waited += 200;
      if (waited > 20000) {
        clearInterval(timer);
        post({type: 'error', message: '20s 内未找到 video 元素'});
      }
      return;
    }
    clearInterval(timer);
    var found = performance.now();
    post({
      type: 'video-found',
      ms: Math.round(found - startedAt),
      duration: Math.round((v.duration || 0) * 100) / 100,
      readyState: v.readyState,
      srcScheme: (v.currentSrc || v.src || '').split(':')[0],
      mediaReadyMs: Math.round(found - startedAt)
    });
    waitForMetadata(v, found);
  }, 200);

  // The <video> element exists before its metadata does; duration is NaN until
  // loadedmetadata fires. Force a load and wait for it before seeking.
  function waitForMetadata(v, t0) {
    var waited = 0;
    var timer = setInterval(function () {
      if (v.readyState >= 1 && v.duration > 0 && isFinite(v.duration)) {
        clearInterval(timer);
        post({
          type: 'video-found',
          ms: Math.round(performance.now() - t0),
          duration: Math.round(v.duration * 100) / 100,
          readyState: v.readyState,
          srcScheme: (v.currentSrc || v.src || '').split(':')[0],
          mediaReadyMs: Math.round(performance.now() - t0)
        });
        runSeekHarness(v, t0);
        return;
      }
      waited += 300;
      if (waited === 3000) { try { v.load(); } catch (e) {} }
      if (waited > 30000) {
        clearInterval(timer);
        post({
          type: 'error',
          message: '30s 内媒体元数据未就绪 (readyState=' + v.readyState + ')'
        });
      }
    }, 300);
  }

  function runSeekHarness(v, t0) {
    var dur = v.duration || 0;
    if (!dur || !isFinite(dur)) {
      // A 287s lesson page; fall back to a fixed span so seek still gets tested.
      dur = 287;
    }
    var targets = [10, 30, 55, 80, 110, 140, 170, 200, 230, 260];
    var idx = 0;
    // Confirm playbackRate is settable (used by the speed control).
    try {
      v.playbackRate = 1.25;
      post({type: 'rate', requested: 1.25, applied: v.playbackRate});
      v.playbackRate = 1.0;
    } catch (e) {
      post({type: 'error', message: 'playbackRate 设置失败: ' + e});
    }

    function next() {
      if (idx >= targets.length) {
        post({type: 'done'});
        return;
      }
      var target = Math.min(targets[idx], Math.max(0, dur - 1));
      idx += 1;
      var seekStart = performance.now();
      function onSeeked() {
        v.removeEventListener('seeked', onSeeked);
        var latency = performance.now() - seekStart;
        post({
          type: 'seek',
          target: Math.round(target * 100) / 100,
          actual: Math.round(v.currentTime * 100) / 100,
          latencyMs: Math.round(latency),
          errorMs: Math.round((v.currentTime - target) * 1000)
        });
        setTimeout(next, 150);
      }
      v.addEventListener('seeked', onSeeked);
      v.pause();
      v.currentTime = target;
      // Guard against a seeked event that never fires.
      setTimeout(function () {
        if (v.currentTime !== target) return;
        onSeeked();
      }, 3000);
    }
    next();
  }
})();
''';

  Future<void> _runManualSeek(int seconds) async {
    setState(() => _running = true);
    final result = await _controller.runJavaScriptReturningResult(
      'document.querySelector("video") ? '
      'document.querySelector("video").currentTime = $seconds : -1',
    );
    _log.add('手动 seek → $seconds s (返回 $result)');
    _setStateIfMounted();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Phase 3A · 视频原型'),
        actions: [
          IconButton(
            tooltip: '重跑探测',
            onPressed: _running
                ? null
                : () {
                    setState(() {
                      _log.clear();
                      _ready = false;
                      _running = true;
                    });
                    _controller.reload();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (!_ready) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in const [10, 55, 140, 260])
                  OutlinedButton(
                    onPressed: _running ? null : () => _runManualSeek(s),
                    child: Text('跳到 ${s}s'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFF111111),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _log.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _log[i],
                    style: const TextStyle(
                      color: Color(0xFFB0BEC5),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
