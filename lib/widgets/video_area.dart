import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders the embedded web video player owned by [VideoPlaybackFacade].
///
/// This is the video counterpart of `MediaArea`: the same vertical slot at the
/// top of the listening screen, but hosting the WebView that the playback
/// facade drives. Keeping it a thin, stateless host means the WebView is owned
/// by the facade (and therefore survives widget rebuilds) rather than by the
/// widget tree.
class VideoArea extends StatelessWidget {
  const VideoArea({super.key, required this.controller, this.loading = false});

  /// The controller that owns the player page.
  final WebViewController controller;

  /// Shows a loading cue until the media metadata is ready.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: scheme.surfaceContainerLow,
          child: WebViewWidget(controller: controller),
        ),
        if (loading)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}
