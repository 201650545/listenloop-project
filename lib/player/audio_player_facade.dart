/// Minimal abstraction over the concrete audio engine.
///
/// The playback *control logic* lives in `SentencePlayerController`, which
/// depends only on this interface. That keeps the controller fully unit
/// testable (see `test/`) without needing a real audio device or the
/// `just_audio` platform plugin, while production code uses
/// `JustAudioFacade`. This is the single seam added for testability — no
/// extra repository/use-case layers.
library;

/// Engine-agnostic description of an asynchronous playback error.
///
/// Concrete facades map their native error types (e.g. just_audio's
/// `PlayerException`) onto this record so the controller never has to know
/// which audio engine is in use.
class AudioPlaybackError {
  const AudioPlaybackError({required this.code, required this.message});

  /// Engine-specific numeric code (`NSError.code` / `ExoPlaybackException.type`
  /// / `MediaError.code` for just_audio).
  final int code;

  /// Human-readable diagnostic message from the underlying engine.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioPlaybackError &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'AudioPlaybackError(code: $code, message: $message)';
}

/// Identifies WHICH sentence clip a native completion belongs to.
///
/// The controller compares [clipEndMs] against the current sentence's `endMs`
/// to drop stale completions emitted after a manual switch or auto-advance
/// — the epoch guard, expressed in clip identity (more precise than a bare
/// counter: a duplicate from the previous sentence cannot collide with the
/// new sentence's completion even at equal repeat counts).
class PlaybackCompletionEvent {
  const PlaybackCompletionEvent({required this.clipStartMs, required this.clipEndMs});

  final int clipStartMs;
  final int clipEndMs;

  @override
  String toString() => 'PlaybackCompletionEvent($clipStartMs..$clipEndMs)';
}

abstract class AudioPlayerFacade {
  /// Emits the real playback position over time, always on the lesson
  /// timeline — implementations that clip playback internally add the clip
  /// start back so callers never see clip-relative values.
  ///
  /// This is a UI/progress signal. When [enforcesClipEnd] is true it must
  /// **not** be used to decide that a sentence has finished; [completionStream]
  /// is authoritative there.
  Stream<Duration> get positionStream;

  /// Emits one event each time playback reaches the end of the current
  /// [setClip] window (or the end of the source when no clip is set).
  ///
  /// This is the authoritative "the sentence finished sounding" signal for
  /// sources that stop at the clip end themselves ([enforcesClipEnd] == true).
  /// It may arrive later than the audible stop; that latency is harmless
  /// because the audio has already been held at the boundary by the engine.
  Stream<PlaybackCompletionEvent> get completionStream;

  /// Whether this source stops playback at the [setClip] end by itself.
  ///
  /// When true, the engine guarantees no audio past the clip end ever sounds,
  /// so [completionStream] alone drives sentence completion and the position
  /// stream is demoted to a UI signal. When false (e.g. the embedded web video
  /// player, which has no clip concept), the caller keeps watching the
  /// position stream and must stop the source itself.
  bool get enforcesClipEnd;

  /// Emits asynchronous playback errors (decode failures, I/O errors, invalid
  /// codecs, etc.).
  ///
  /// Transient interruptions caused by rapid user switching — e.g. a seek
  /// cancelled by the next seek — MUST be absorbed by the implementation and
  /// MUST NOT appear on this stream. Only real, user-visible failures belong
  /// here.
  Stream<AudioPlaybackError> get errorStream;

  /// The latest known playback position.
  Duration get position;

  /// Loads an audio asset (path relative to the project root).
  ///
  /// Should throw if the asset cannot be loaded so the controller can surface
  /// a friendly error instead of crashing.
  Future<void> setAsset(String assetPath);

  /// Loads an audio file from an absolute file path (imported lesson media
  /// living in app storage).
  ///
  /// Should throw if the file cannot be loaded so the controller can surface
  /// a friendly error instead of crashing.
  Future<void> setFilePath(String filePath);

  /// Restricts playback to `start..end` of the lesson timeline.
  ///
  /// Sources whose [enforcesClipEnd] is true implement this natively and
  /// therefore guarantee that no audio outside the range is ever heard —
  /// this is what makes per-sentence playback exact. Sources that cannot clip
  /// seek to [start] and leave the end to the caller.
  ///
  /// Positions passed to [seek] and read from [position]/[positionStream]
  /// remain absolute on the lesson timeline; the clip offset is absorbed
  /// inside the implementation.
  Future<void> setClip(Duration start, Duration end);

  /// Moves the play head to [position] (absolute, on the lesson timeline).
  Future<void> seek(Duration position);

  /// Starts playback from the current position. Resolves once playback has
  /// been *started* (not when it finishes).
  Future<void> play();

  /// Pauses playback, keeping the current position.
  Future<void> pause();

  /// Sets the playback rate (1.0 = normal speed). Engine-pass-through only;
  /// sentence timing logic is unaffected (the controller rescales its own
  /// watchdog).
  Future<void> setSpeed(double rate);

  /// Emits the active playlist clip index when playing in playlist/gapless mode.
  Stream<int> get currentIndexStream => const Stream<int>.empty();

  /// Current playlist index in the engine, or null if not in playlist mode.
  int? get currentPlaylistIndex => null;

  /// Loads the entire sentence playlist for gapless playback.
  Future<void> loadPlaylist({
    required String path,
    required bool isFile,
    required List<SentenceClip> clips,
    int initialIndex = 0,
  }) async {
    if (isFile) {
      await setFilePath(path);
    } else {
      await setAsset(path);
    }
    if (clips.isNotEmpty && initialIndex >= 0 && initialIndex < clips.length) {
      await setClip(clips[initialIndex].start, clips[initialIndex].end);
    }
  }

  /// Seeks to a specific sentence in the playlist at [position] (absolute on lesson timeline).
  Future<void> seekSentence(int index, Duration position) => seek(position);

  /// Configures whether the engine loops the current sentence clip natively (e.g. LoopMode.one).
  Future<void> setLoopOne(bool loopOne) async {}

  /// Releases the underlying player resources.
  Future<void> dispose();
}

/// Range of a sentence clip on the lesson timeline.
class SentenceClip {
  const SentenceClip({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final Duration start;
  final Duration end;

  @override
  String toString() =>
      'SentenceClip(#$index: ${start.inMilliseconds}..${end.inMilliseconds}ms)';
}

