import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_player_facade.dart';

/// Production [AudioPlayerFacade] backed by the `just_audio` plugin.
///
/// Supports gapless multi-sentence playback via `ConcatenatingAudioSource`
/// and per-sentence [ClippingAudioSource]s, as well as native zero-latency
/// single-sentence looping via `LoopMode.one`.
class JustAudioFacade implements AudioPlayerFacade {
  JustAudioFacade({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _errorSub = _player.errorStream.listen(_onPlayerException);
    _processingStateSub = _player.processingStateStream.listen(
      _onProcessingState,
    );
    _currentIndexSub = _player.currentIndexStream.listen(_onPlayerIndex);
    _discontinuitySub = _player.positionDiscontinuityStream.listen(
      _onDiscontinuity,
    );
  }

  final AudioPlayer _player;
  final StreamController<AudioPlaybackError> _errorController =
      StreamController<AudioPlaybackError>.broadcast();
  final StreamController<PlaybackCompletionEvent> _completionController =
      StreamController<PlaybackCompletionEvent>.broadcast();
  final StreamController<int> _currentIndexController =
      StreamController<int>.broadcast();

  StreamSubscription<PlayerException>? _errorSub;
  StreamSubscription<ProcessingState>? _processingStateSub;
  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<PositionDiscontinuity>? _discontinuitySub;

  /// Active clips when playing in playlist mode.
  List<SentenceClip>? _clips;
  int? _activeClipIndex;

  /// Active clip window in legacy single-clip mode.
  Duration? _clipStart;
  Duration? _clipEnd;
  bool _disposed = false;

  void _onPlayerException(PlayerException e) {
    if (_errorController.isClosed) return;
    _errorController.add(
      AudioPlaybackError(
        code: e.code,
        message: e.message ?? 'unknown just_audio error',
      ),
    );
  }

  void _onPlayerIndex(int? index) {
    if (_disposed || index == null) return;
    final prev = _activeClipIndex;
    _activeClipIndex = index;
    if (_currentIndexController.isClosed) return;
    _currentIndexController.add(index);

    // If we advanced from clip N to N+1 gaplessly, emit completion for clip N.
    if (prev != null && prev != index && _clips != null && prev >= 0 && prev < _clips!.length) {
      final finishedClip = _clips![prev];
      if (!_completionController.isClosed) {
        _completionController.add(
          PlaybackCompletionEvent(
            clipStartMs: finishedClip.start.inMilliseconds,
            clipEndMs: finishedClip.end.inMilliseconds,
          ),
        );
      }
    }
  }

  void _onDiscontinuity(PositionDiscontinuity discontinuity) {
    if (_disposed || _clips == null) return;
    // In LoopMode.one, ExoPlayer loops gaplessly back to start of the active item.
    if (discontinuity.reason == PositionDiscontinuityReason.autoAdvance) {
      final idx = _player.currentIndex ?? _activeClipIndex;
      if (idx != null && idx >= 0 && idx < _clips!.length) {
        final currentClip = _clips![idx];
        if (!_completionController.isClosed) {
          _completionController.add(
            PlaybackCompletionEvent(
              clipStartMs: currentClip.start.inMilliseconds,
              clipEndMs: currentClip.end.inMilliseconds,
            ),
          );
        }
      }
    }
  }

  void _onProcessingState(ProcessingState state) {
    if (state != ProcessingState.completed || _completionController.isClosed) {
      return;
    }
    if (_clips != null) {
      final idx = _player.currentIndex ?? _activeClipIndex ?? (_clips!.length - 1);
      if (idx >= 0 && idx < _clips!.length) {
        final lastClip = _clips![idx];
        _completionController.add(
          PlaybackCompletionEvent(
            clipStartMs: lastClip.start.inMilliseconds,
            clipEndMs: lastClip.end.inMilliseconds,
          ),
        );
      }
      return;
    }
    final start = _clipStart;
    final end = _clipEnd;
    if (start == null || end == null) return;
    _completionController.add(
      PlaybackCompletionEvent(
        clipStartMs: start.inMilliseconds,
        clipEndMs: end.inMilliseconds,
      ),
    );
  }

  @override
  Stream<Duration> get positionStream => _player.positionStream.map(_toLesson);

  @override
  Stream<PlaybackCompletionEvent> get completionStream =>
      _completionController.stream;

  @override
  Stream<int> get currentIndexStream => _currentIndexController.stream;

  @override
  int? get currentPlaylistIndex => _clips != null ? (_player.currentIndex ?? _activeClipIndex) : null;

  @override
  Stream<AudioPlaybackError> get errorStream => _errorController.stream;

  @override
  bool get enforcesClipEnd => true;

  @override
  Duration get position => _toLesson(_player.position);

  Duration _toLesson(Duration platformPosition) {
    if (_clips != null) {
      final idx = _player.currentIndex ?? _activeClipIndex ?? 0;
      if (idx >= 0 && idx < _clips!.length) {
        return platformPosition + _clips![idx].start;
      }
    }
    final start = _clipStart;
    return start == null ? platformPosition : platformPosition + start;
  }

  @override
  Future<void> loadPlaylist({
    required String path,
    required bool isFile,
    required List<SentenceClip> clips,
    int initialIndex = 0,
  }) async {
    if (_disposed) return;
    _clips = List<SentenceClip>.unmodifiable(clips);
    _clipStart = null;
    _clipEnd = null;
    _activeClipIndex = initialIndex;

    final children = <AudioSource>[];
    for (int i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final UriAudioSource child = isFile
          ? AudioSource.file(path)
          : AudioSource.asset(path);
      // For continuous natural playback, extend the clip end to next clip start if next starts after this clip
      final clipEnd = (i < clips.length - 1 && clips[i + 1].start > clip.end)
          ? clips[i + 1].start
          : clip.end;
      children.add(
        ClippingAudioSource(
          child: child,
          start: clip.start,
          end: clipEnd,
          tag: clip.index,
        ),
      );
    }

    // ignore: deprecated_member_use
    final playlist = ConcatenatingAudioSource(children: children);
    try {
      await _player.setAudioSource(
        playlist,
        initialIndex: initialIndex,
        initialPosition: Duration.zero,
      );
    } on PlayerInterruptedException {
      // Newer load supersedes
    }
  }

  @override
  Future<void> seekSentence(int index, Duration position) async {
    if (_disposed) return;
    _activeClipIndex = index;
    if (_clips != null && index >= 0 && index < _clips!.length) {
      final clip = _clips![index];
      final relMs = (position.inMilliseconds - clip.start.inMilliseconds).clamp(
        0,
        (clip.end - clip.start).inMilliseconds,
      );
      try {
        await _player.seek(Duration(milliseconds: relMs), index: index);
      } on PlayerInterruptedException {
        // Superseded
      }
      return;
    }
    await seek(position);
  }

  @override
  Future<void> setLoopOne(bool loopOne) async {
    if (_disposed) return;
    try {
      await _player.setLoopMode(loopOne ? LoopMode.one : LoopMode.off);
    } on PlayerInterruptedException {
      // Superseded
    }
  }

  @override
  Future<void> setAsset(String assetPath) async {
    if (_disposed) return;
    _clips = null;
    _clipStart = null;
    _clipEnd = null;
    try {
      await _player.setAsset(assetPath);
    } on PlayerInterruptedException {
      // Superseded
    }
  }

  @override
  Future<void> setFilePath(String filePath) async {
    if (_disposed) return;
    _clips = null;
    _clipStart = null;
    _clipEnd = null;
    try {
      await _player.setFilePath(filePath);
    } on PlayerInterruptedException {
      // Superseded
    }
  }

  @override
  Future<void> setClip(Duration start, Duration end) async {
    if (_disposed) return;
    if (_clipStart == start && _clipEnd == end) return;
    try {
      await _player.setClip(start: start, end: end);
      _clipStart = start;
      _clipEnd = end;
    } on PlayerInterruptedException {
      // Superseded
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_clips != null) {
      final idx = _player.currentIndex ?? _activeClipIndex ?? 0;
      await seekSentence(idx, position);
      return;
    }
    final start = _clipStart;
    final end = _clipEnd;
    final Duration target;
    if (start == null || end == null) {
      target = position;
    } else {
      final relMs = (position.inMilliseconds - start.inMilliseconds).clamp(
        0,
        end.inMilliseconds - start.inMilliseconds,
      );
      target = Duration(milliseconds: relMs);
    }
    try {
      await _player.seek(target);
    } on PlayerInterruptedException {
      // Superseded
    }
  }

  @override
  Future<void> play() {
    unawaited(
      _player.play().catchError((Object error) {
        if (error is PlayerInterruptedException) return;
        debugPrint('[ListenLoop] just_audio play() unexpected error: $error');
      }),
    );
    return Future<void>.value();
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } on PlayerInterruptedException {
      // Superseded
    }
  }

  @override
  Future<void> setSpeed(double rate) async {
    try {
      await _player.setSpeed(rate);
    } on PlayerInterruptedException {
      // Superseded
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final sub = _errorSub;
    _errorSub = null;
    await sub?.cancel();
    final stateSub = _processingStateSub;
    _processingStateSub = null;
    await stateSub?.cancel();
    final idxSub = _currentIndexSub;
    _currentIndexSub = null;
    await idxSub?.cancel();
    final discSub = _discontinuitySub;
    _discontinuitySub = null;
    await discSub?.cancel();

    if (!_errorController.isClosed) {
      await _errorController.close();
    }
    if (!_completionController.isClosed) {
      await _completionController.close();
    }
    if (!_currentIndexController.isClosed) {
      await _currentIndexController.close();
    }
    await _player.dispose();
  }
}
