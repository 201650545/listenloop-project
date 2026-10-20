import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sentence.dart';
import 'audio_player_facade.dart';
import 'playback_mode.dart';

/// 逐句 clip 播放列表的句数上限（2026-09-21 用户反馈渲染卡顿）：
/// 超过该句数的课程（如《你的名字》1161 句）不再为每一句构建
/// [ClippingAudioSource]——1161 个 clip 会让 ExoPlayer 的 setAudioSource
/// 在主线程上卡顿明显。大课程退回单一音源 + 绝对 seek 的位置驱动模式，
/// 与视频模式共用同一套 controller 逻辑（原声连贯的空隙流动、跳过空白、
/// watchdog 兜底全部基于 position stream，天然兼容）。
const int kClipPlaylistMaxSentences = 300;

/// Controls per-sentence playback for a list of [Sentence]s.
///
/// Responsibilities:
///  * keep track of the current sentence index, playing state and position;
///  * play exactly `startMs -> endMs` of the current sentence and stop at
///    `endMs` (primary signal: the real position stream; an auxiliary watchdog
///    timer guards against a coarse/laggy stream — never the other way round);
///  * move to the next / previous sentence, preserving whether playback was
///    running (auto-play the new sentence) or paused (only seek);
///  * surface asynchronous engine errors (decode / I/O failures reported on
///    `errorStream`) as a friendly UI banner, while transient interruptions
///    from rapid switching are absorbed inside the facade and never reach
///    this class;
///  * never crash on boundary presses or audio errors;
///  * in debug builds, log per-sentence seek / pause timing so Milestone 1B
///    can quantify real-device end-error against `endMs`.
///
/// It talks to playback sources only through [AudioPlayerFacade], so all of
/// the above is unit testable with a fake facade.
///
/// Since Phase 3C the controller owns up to two sources — the local audio
/// engine and, for lessons with a video, an embedded video player — and
/// switches between them with [setPlaybackMode] while keeping a single
/// `currentSentenceIndex`, repeat target and speed across both (a lesson has
/// exactly one timeline; only the sounding source changes).
class SentencePlayerController extends ChangeNotifier {
  SentencePlayerController({
    required AudioPlayerFacade audioFacade,
    AudioPlayerFacade? videoFacade,
    PlaybackMode initialMode = PlaybackMode.audio,
    required List<Sentence> sentences,
    required String audioAsset,
    this.audioIsFile = false,
    this.initialSentenceIndex = 0,
    this.initialPlaybackRate = 1.0,
    this.initialRepeatTarget = 1,
  }) : assert(sentences.isNotEmpty, 'sentences must not be empty'),
       assert(
         initialSentenceIndex >= 0,
         'initialSentenceIndex must be >= 0',
       ),
       assert(
         initialMode == PlaybackMode.audio || videoFacade != null,
         'video mode requires a videoFacade',
       ),
       _audioFacade = audioFacade,
       _videoFacade = videoFacade,
       _facade = initialMode == PlaybackMode.video ? videoFacade! : audioFacade,
       _mode = initialMode,
       _sentences = List<Sentence>.unmodifiable(sentences),
       _assetPath = audioAsset,
       _currentIndex =
           initialSentenceIndex.clamp(0, sentences.length - 1).toInt(),
       _playbackRate = initialPlaybackRate.clamp(0.5, 2.0).toDouble(),
       _repeatTarget = initialRepeatTarget < 0 ? 0 : initialRepeatTarget;

  /// The always-available local audio engine. One of the two sources owned by
  /// the controller (Phase 3C); the active one is [_facade].
  final AudioPlayerFacade _audioFacade;

  /// The embedded video player for lessons that carry a video source, or
  /// null for audio-only lessons. Its page is only loaded on the first
  /// switch to video mode (lazy load, Phase 3C §2).
  final AudioPlayerFacade? _videoFacade;

  /// The currently active playback source — always one of the two above.
  /// Swapping this reference is the whole mode switch (Phase 3C §3).
  AudioPlayerFacade _facade;

  /// Which source [_facade] currently is.
  PlaybackMode _mode;

  /// Whether each source has been loaded at least once (lazy video load:
  /// re-entering a loaded source must not re-fetch its page/asset).
  bool _audioLoaded = false;
  bool _videoLoaded = false;

  /// True while a source switch is in flight (a video load can take
  /// seconds); user playback commands are absorbed meanwhile.
  bool _isSwitchingSource = false;
  List<Sentence> _sentences;
  String _assetPath;

  /// When true, [_assetPath] is an absolute file path on disk (imported
  /// lesson media); otherwise it is a bundled asset path.
  bool audioIsFile;

  /// Sentence to open (V0.2.1 恢复学习).
  final int initialSentenceIndex;

  /// Playback rate at construction (V0.2.1 恢复学习).
  final double initialPlaybackRate;

  /// Repeat target at construction (V0.2.1 恢复学习; 0 = infinite).
  final int initialRepeatTarget;

  /// Extra time the auxiliary watchdog waits past `endMs` before forcing a
  /// pause. The position stream remains the primary stop trigger; this only
  /// catches the rare case where the stream under-reports.
  static const Duration _watchdogBuffer = Duration(milliseconds: 400);

  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _disposed = false;
  Duration _currentPosition = Duration.zero;
  String? _errorMessage;
  double _playbackRate = 1.0;

  /// Repeat target for the current sentence: 0 = infinite loop, N = play the
  /// sentence N times then advance (default 1 — play through once).
  int _repeatTarget = 1;

  /// Plays left for the current sentence (-1 = infinite). Reset on every
  /// user-initiated play / sentence switch.
  int _repeatRemaining = 0;

  /// When true, the lesson loops back to sentence 0 after the last sentence
  /// finishes, instead of auto-advancing to the next lesson.
  bool _lessonLoop = false;

  /// Bumped on every user-intended playback action (play / pause / switch /
  /// dispose). Async loop-restarts capture it and abort when it changed, so
  /// a stale completion can never restart the wrong sentence (V0.2 §11).
  int _generation = 0;

  /// True while an auto-loop / auto-next restart is in flight. The position
  /// stream keeps emitting for a short window after we seek back, and those
  /// stale past-end samples must not trigger extra completions (they would
  /// burn repeat counts faster than the audible playback).
  bool _restartPending = false;

  /// Target millisecond of an in-flight seek. Used to ignore stale position samples
  /// emitted by the platform engine before the seek settles, preventing cascading auto-advances.
  int? _pendingSeekTargetMs;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlaybackCompletionEvent>? _completionSub;
  StreamSubscription<int>? _currentIndexSub;
  StreamSubscription<AudioPlaybackError>? _errorSub;
  Timer? _watchdog;

  /// True once the current sentence cycle's completion has been consumed.
  ///
  /// Both the native completion event and the watchdog funnel into
  /// [_finishCurrentSentence]; this flag (plus the clip identity check in
  /// [_onClipCompleted]) guarantees one cycle is consumed exactly once, no
  /// matter how the engine doubles its events.
  bool _completionHandled = true;

  // ---------------------------------------------------------------- state ---

  Sentence get currentSentence => _sentences[_currentIndex];

  /// Zero-based index of the current sentence.
  int get currentSentenceIndex => _currentIndex;

  /// Human-friendly 1-based position, e.g. `2` for "2 / 5".
  int get displayIndex => _currentIndex + 1;

  int get sentenceCount => _sentences.length;

  List<Sentence> get sentences => _sentences;

  bool get isPlaying => _isPlaying;

  bool get isInitialized => _isInitialized;

  /// Which playback source is currently driving the lesson (Phase 3C).
  PlaybackMode get playbackMode => _mode;

  /// Whether the lesson carries a video source; the Audio|Video toggle is
  /// only rendered when this is true.
  bool get hasVideoSource => _videoFacade != null;

  /// True while a source switch is in flight — the UI shows a loading cue
  /// (a video load typically needs 1–3 s).
  bool get isSwitchingSource => _isSwitchingSource;

  /// Absolute playback position within the audio asset (clamped so it never
  /// reads past the current sentence's `endMs` in loop mode).
  Duration get currentPosition => _currentPosition;

  /// True when the playhead has passed the current sentence's endMs and is
  /// currently sounding the gap/interlude before the next sentence.
  bool get isInGap {
    if (!_isPlaying || !canGoNext) return false;
    final curEnd = currentSentence.endMs;
    final nextStart = _sentences[_currentIndex + 1].startMs;
    final posMs = _currentPosition.inMilliseconds;
    return posMs >= curEnd && posMs < nextStart;
  }

  /// Milliseconds between current sentence endMs and next sentence startMs.
  int get currentGapMs {
    if (!canGoNext) return 0;
    final gap = _sentences[_currentIndex + 1].startMs - currentSentence.endMs;
    return gap > 0 ? gap : 0;
  }

  /// Whether to automatically skip silence / interludes between sentences
  /// (compact listen mode vs cinema natural mode).
  /// Default is false (cinema natural mode: audio/video flows naturally without skipping).
  bool _skipSilence = false;

  bool get skipSilence => _skipSilence;

  void setSkipSilence(bool value) {
    if (_disposed || _skipSilence == value) return;
    _skipSilence = value;
    // 模式切换立即重排 watchdog：Mode A 的兜底终点是下一句起点（clip 扩展
    // 终点），Mode B 则回到本句 endMs（提前 finish = 跳过空白）。
    if (_isPlaying && _isInitialized && !hasError) {
      _startWatchdog(currentSentence, from: _currentPosition);
    }
    notifyListeners();
  }

  void toggleSkipSilence() {
    setSkipSilence(!_skipSilence);
  }

  /// Skips the current interlude / music and jumps directly to the next sentence.
  void skipGap() {
    if (canGoNext) {
      selectSentence(_currentIndex + 1);
    }
  }

  bool get hasError => _errorMessage != null;

  String? get errorMessage => _errorMessage;

  bool get canGoNext => _currentIndex < _sentences.length - 1;

  bool get canGoPrevious => _currentIndex > 0;

  /// 公开可设置的回调。非 null 时，每句播完停在句末并回调，不再自动跳下一句。
  /// 由跟读会话开启时设置、退出时清 null（清 null 即恢复原行为）。
  ///
  /// WP-H 跟读验收（方案 §五）：「读完一句自动停下等孩子读」这个行为原本
  /// 不存在——本句读完不是循环本句就是自动跳下一句。这道门是 WP-B 名下
  /// 唯一需要的改动：只停住 + 回调，时间戳/高亮/定位一律不动。
  Future<void> Function(int finishedSentenceIndex)? readAlongGate;

  /// 当在首句触发「上一句」时，若外部注册了切课回调，则切换至「上一课」
  VoidCallback? onPreviousLessonRequested;

  /// 当在末句触发「下一句」或整篇课文自然播完最后一句时，若外部注册了切课回调，则自动切换至「下一课」
  VoidCallback? onNextLessonRequested;

  /// 本会话是否采用逐句 clip 播放列表。
  ///
  /// 2026-09-22 用户裁定（樱花草反馈"能不能像正常听歌一样"）：音频课程
  /// 一律走单一音源 + 绝对 seek 的位置驱动路径（与视频模式同一套逻辑），
  /// 播放是连续的一条流，字幕只跟时间轴走，句间零切换痕迹。
  /// clip playlist 的逐句边界重载会产生可闻/可见的切痕；其句尾强制能力
  /// 由单音源路径的主动 seek 等价承担：Mode B 跳空白 = 句尾主动 seek，
  /// 单句循环 = seek 回跳（kClipPlaylistMaxSentences 退役）。
  final bool _useClipPlaylist = false;

  /// Current playback rate (UI speed selector; default 1.0).
  double get playbackRate => _playbackRate;

  /// Repeat target for the current sentence: 0 = infinite (default), N =
  /// play N times per sentence.
  int get repeatTarget => _repeatTarget;

  /// When true, the whole lesson loops back to sentence 0 after the last
  /// sentence finishes (no auto-advance to the next lesson).
  bool get lessonLoop => _lessonLoop;

  /// Sets how many times each sentence repeats: 0 = infinite, N = N times.
  /// Applies to the running sentence immediately (the play in progress counts
  /// as repetition #1) — verified necessary on device 2026-09-16: without
  /// this, changing the target mid-playback had no effect until the next
  /// manual play.
  Future<void> setRepeatTarget(int target) async {
    if (_disposed || target < 0 || target == _repeatTarget) return;
    _repeatTarget = target;
    _repeatRemaining = target == 0 ? -1 : target;
    if (_useClipPlaylist) {
      await _facade.setLoopOne(target == 0 || _repeatRemaining > 1);
    }
    notifyListeners();
  }

  /// Toggles whole-lesson looping. When enabled, playback wraps back to
  /// sentence 0 after the last sentence completes instead of stopping or
  /// auto-advancing to the next lesson.
  void setLessonLoop(bool enabled) {
    _lessonLoop = enabled;
    notifyListeners();
  }

  /// 句间循环间隔（v0.9.1 课堂需求 2026-09-29）：两次播放之间静默等待的
  /// 时长。课堂带读场景（如二年级课文）：老师控制节奏，句与句之间留 1-10
  /// 秒给学生跟读。0 = 无间隔（默认，行为与旧版完全一致）。
  ///
  /// 生效点：[_finishCurrentSentence] 的循环重启与自动跳下一句——两个「句
  /// 尾」决策点在继续播放前先等待 [sentenceGap] 毫秒。等待期间可以被任何
  /// 用户操作（暂停/切句/dispose）打断（generation 校验）。
  int _sentenceGapMs = 0;

  /// 当前句间循环间隔（毫秒）。
  int get sentenceGapMs => _sentenceGapMs;

  /// 设置句间循环间隔（毫秒，0/1000/3000/5000 等）。
  Future<void> setSentenceGap(int ms) async {
    if (_disposed || ms < 0 || ms == _sentenceGapMs) return;
    _sentenceGapMs = ms;
    notifyListeners();
  }

  /// 别名：支持 setSentenceGapMs
  Future<void> setSentenceGapMs(int ms) => setSentenceGap(ms);

  /// 是否处于句间等待（UI 可显示「等待中」提示）。
  bool get waitingInGap => _gapTimer != null;

  /// 句间等待激活中：等待期间 position 流推送的值无意义——底层 pause()
  /// 是 fire-and-forget（视频源音频会继续流过句间停顿），若不整体忽略，
  /// 「自然过渡」分支会在等待期间把下标悄悄 +1，gap 计时器触发后回调
  /// 又 +1，用户看到的就是「停顿 3 秒后直接跳到第三句」（v0.9.2 实机
  /// 反馈 2026-09-29）。等待结束（触发/打断/换句）一律置回 false。
  bool _gapWaitActive = false;

  Timer? _gapTimer;

  /// 句间等待：等 [ms] 毫秒后执行 [then]。generation 校验保证用户中途
  /// 暂停/切句/dispose 时不会恢复播放。立即返回 false 表示被打断。
  Future<bool> _waitForGap(int ms, int gen, VoidCallback then) async {
    if (ms <= 0) {
      then();
      return true;
    }
    final completer = Completer<bool>();
    _gapTimer = Timer(Duration(milliseconds: ms), () {
      _gapTimer = null;
      _gapWaitActive = false; // 无论触发还是被 generation 作废，等待都结束了
      if (_disposed || gen != _generation) {
        completer.complete(false);
        return;
      }
      then();
      completer.complete(true);
    });
    return completer.future;
  }

  void _cancelGapTimer() {
    _gapTimer?.cancel();
    _gapTimer = null;
    _gapWaitActive = false;
  }

  /// Sets the playback rate and rescales the auxiliary watchdog so a slowed
  /// sentence is not force-paused before its real end (the position stream
  /// remains the authoritative stop signal).
  Future<void> setSpeed(double rate) async {
    final clamped = rate.clamp(0.5, 2.0).toDouble();
    if (_disposed || clamped == _playbackRate || _isSwitchingSource) return;
    _playbackRate = clamped;
    notifyListeners();
    if (_isPlaying && _isInitialized && !hasError) {
      _startWatchdog(currentSentence);
    }
    try {
      await _facade.setSpeed(_playbackRate);
    } catch (error, stackTrace) {
      _handlePlaybackError('setSpeed', error, stackTrace);
    }
  }

  /// Switches the active playback source (Phase 3C).
  ///
  /// The sentence index, repeat target and speed live in this controller, so
  /// they survive the switch by construction (spec §6/§7). The sequence per
  /// spec §4/§5: pause the old source first (single Active Source rule, §14),
  /// swap the facade, lazily load the target source (the video page is only
  /// fetched on the first switch), seek to the current sentence's `startMs`,
  /// re-apply the configured speed (§12), then resume if the old source was
  /// playing.
  ///
  /// Switching to video without a video facade is ignored, as is a no-op
  /// switch. A failed target load is non-blocking (§18): the previous source
  /// is restored and the error surfaces through the regular banner — audio
  /// stays usable and the user can retry.
  Future<void> setPlaybackMode(PlaybackMode mode) async {
    if (_disposed || _isSwitchingSource) return;
    if (mode == _mode) return;
    if (mode == PlaybackMode.video && _videoFacade == null) return;

    final previousFacade = _facade;
    final wasPlaying = _isPlaying;
    _generation++;
    final gen = _generation;
    _watchdog?.cancel();
    _restartPending = false;
    _isSwitchingSource = true;
    _isPlaying = false;
    notifyListeners();
    try {
      // §14 Source Ownership: the old source is paused before the new one
      // becomes active.
      await previousFacade.pause();
      if (_disposed || gen != _generation) return;

      await _detachSourceListeners();
      _facade = mode == PlaybackMode.video ? _videoFacade! : _audioFacade;
      _mode = mode;
      _attachSourceListeners();
      notifyListeners();

      // Lazy load (Phase 3C §2): a loaded source is only re-seeked, never
      // re-fetched.
      if (!_isSourceLoaded(mode)) {
        if (_useClipPlaylist) {
          final clips = [
            for (final s in _sentences)
              SentenceClip(
                index: s.index,
                start: Duration(milliseconds: s.startMs),
                end: Duration(milliseconds: s.endMs),
              ),
          ];
          await _facade.loadPlaylist(
            path: _assetPath,
            isFile: audioIsFile,
            clips: clips,
            initialIndex: _currentIndex,
          );
        } else {
          if (audioIsFile) {
            await _facade.setFilePath(_assetPath);
          } else {
            await _facade.setAsset(_assetPath);
          }
        }
        if (_disposed || gen != _generation) return;
        _markSourceLoaded(mode);
      }
      _isInitialized = true;

      final start = Duration(milliseconds: currentSentence.startMs);
      if (_useClipPlaylist) {
        await _facade.setLoopOne(_repeatTarget == 0);
        await _facade.seekSentence(_currentIndex, start);
      } else {
        await _facade.seek(start);
      }
      if (_disposed || gen != _generation) return;
      _currentPosition = start;
      _errorMessage = null;

      // Keep the configured speed across the mode boundary (spec §12).
      if (_playbackRate != 1.0) {
        await _facade.setSpeed(_playbackRate);
        if (_disposed || gen != _generation) return;
      }

      _isSwitchingSource = false;
      if (wasPlaying) {
        _isPlaying = true;
        _completionHandled = false;
        notifyListeners();
        await _facade.play();
        if (_disposed || gen != _generation) return;
        _startWatchdog(currentSentence);
      } else {
        notifyListeners();
      }
    } catch (error, stackTrace) {
      // §18: a failed load must never take the lesson down — restore the
      // previous source and surface a non-blocking, retryable error.
      await _restoreAfterFailedSwitch(previousFacade, error, stackTrace);
    } finally {
      if (!_disposed && _isSwitchingSource) {
        _isSwitchingSource = false;
        notifyListeners();
      }
    }
  }

  /// Rolls back after a failed [setPlaybackMode]: the previously active
  /// source becomes active again (seeked to the current sentence start) and
  /// the failure is reported through the sticky error banner, which the UI
  /// retry button can clear.
  Future<void> _restoreAfterFailedSwitch(
    AudioPlayerFacade previousFacade,
    Object error,
    StackTrace stackTrace,
  ) async {
    if (_disposed) return; // tearing down — both sources are released anyway
    debugPrint(
      '[ListenLoop] switch to $_mode failed, restoring previous source: '
      '$error\n$stackTrace',
    );
    try {
      await _detachSourceListeners();
      _facade = previousFacade;
      _mode = identical(previousFacade, _audioFacade)
          ? PlaybackMode.audio
          : PlaybackMode.video;
      _attachSourceListeners();
      final start = Duration(milliseconds: currentSentence.startMs);
      await _facade.seek(start);
      _currentPosition = start;
    } catch (restoreError, restoreTrace) {
      debugPrint(
        '[ListenLoop] restoring the previous source failed too: '
        '$restoreError\n$restoreTrace',
      );
    }
    _restartPending = false;
    _watchdog?.cancel();
    _watchdog = null;
    _isPlaying = false;
    _errorMessage = 'Unable to switch playback mode.';
    notifyListeners();
  }

  /// Clears the sticky error so playback can resume (UI retry button).
  void clearError() {
    if (_disposed || _errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  // ------------------------------------------------------------- lifecycle ---

  /// Loads the audio asset and starts listening to the position + error
  /// streams.
  ///
  /// Never throws: on failure it records [errorMessage] so the UI can show a
  /// friendly message while the detailed cause goes to the debug console.
  Future<void> initialize() async {
    if (_disposed || _isInitialized) return;
    try {
      if (_useClipPlaylist) {
        final clips = [
          for (final s in _sentences)
            SentenceClip(
              index: s.index,
              start: Duration(milliseconds: s.startMs),
              end: Duration(milliseconds: s.endMs),
            ),
        ];
        await _facade.loadPlaylist(
          path: _assetPath,
          isFile: audioIsFile,
          clips: clips,
          initialIndex: _currentIndex,
        );
        await _facade.setLoopOne(_repeatTarget == 0);
      } else {
        if (audioIsFile) {
          await _facade.setFilePath(_assetPath);
        } else {
          await _facade.setAsset(_assetPath);
        }
      }
      _markSourceLoaded(_mode);
      _attachSourceListeners();
      _isInitialized = true;

      final start = Duration(milliseconds: currentSentence.startMs);
      if (_useClipPlaylist) {
        await _facade.seekSentence(_currentIndex, start);
      } else {
        await _facade.seek(start);
      }
      _currentPosition = start;
      _errorMessage = null;
      notifyListeners();
    } catch (error, stackTrace) {
      _isInitialized = false;
      _isPlaying = false;
      _errorMessage = 'Unable to load audio.';
      debugPrint(
        '[ListenLoop] initialize failed for asset "$_assetPath": '
        '$error\n$stackTrace',
      );
      notifyListeners();
    }
  }

  /// Play button semantics (V0.2.1 §3): paused mid-sentence → resume from
  /// the paused position; fresh or finished sentence → start from startMs.
  /// The repeat counter resets either way.
  Future<void> playCurrentSentence() async {
    if (!_isInitialized || hasError || _disposed || _isSwitchingSource) return;
    if (_errorMessage == 'Unable to switch playback mode.') {
      _errorMessage = null;
      notifyListeners();
    }
    final sentence = currentSentence;
    _generation++;
    final gen = _generation;
    _repeatRemaining = _repeatTarget == 0 ? -1 : _repeatTarget;
    _watchdog?.cancel();
    _cancelGapTimer(); // 播放键作废进行中的句间等待
    _restartPending = false;
    try {
      final start = Duration(milliseconds: sentence.startMs);
      final end = Duration(milliseconds: sentence.endMs);
      final midSentence = _currentPosition > start && _currentPosition < end;

      if (midSentence) {
        // Resume: keep the play head where it is.
        _isPlaying = true;
        _completionHandled = false;
        notifyListeners();

        await _facade.play();
        if (_disposed || gen != _generation) return;
        _startWatchdog(sentence, from: _currentPosition);
        return;
      }

      if (_useClipPlaylist) {
        await _facade.setLoopOne(_repeatTarget == 0);
        _pendingSeekTargetMs = sentence.startMs;
        await _facade.seekSentence(_currentIndex, start);
        if (_disposed || gen != _generation) return;
      } else {
        _pendingSeekTargetMs = sentence.startMs;
        await _facade.seek(start);
        if (_disposed || gen != _generation) return;
      }
      _currentPosition = start;
      _logSeekTiming(sentence, reason: 'play');
      _isPlaying = true;
      _completionHandled = false;
      notifyListeners();

      await _facade.play();
      if (_disposed || gen != _generation) return;
      _startWatchdog(sentence);
    } catch (error, stackTrace) {
      _handlePlaybackError('play', error, stackTrace);
    }
  }

  /// Replay: restart the current sentence from its startMs regardless of the
  /// play head (triggered by tapping the subtitle — user request 2026-09-16).
  Future<void> replaySentence() async {
    if (!_isInitialized || hasError || _disposed || _isSwitchingSource) return;
    if (_errorMessage == 'Unable to switch playback mode.') {
      _errorMessage = null;
      notifyListeners();
    }
    _generation++;
    final gen = _generation;
    _repeatRemaining = _repeatTarget == 0 ? -1 : _repeatTarget;
    _restartPending = false;
    _cancelGapTimer(); // 重播作废进行中的句间等待
    _watchdog?.cancel();
    try {
      final start = Duration(milliseconds: currentSentence.startMs);
      if (_useClipPlaylist) {
        await _facade.setLoopOne(_repeatTarget == 0);
        _pendingSeekTargetMs = currentSentence.startMs;
        await _facade.seekSentence(_currentIndex, start);
        if (_disposed || gen != _generation) return;
      } else {
        _pendingSeekTargetMs = currentSentence.startMs;
        await _facade.seek(start);
        if (_disposed || gen != _generation) return;
      }
      _currentPosition = start;
      _isPlaying = true;
      _completionHandled = false;
      notifyListeners();

      await _facade.play();
      if (_disposed || gen != _generation) return;
      _startWatchdog(currentSentence);
    } catch (error, stackTrace) {
      _handlePlaybackError('replay', error, stackTrace);
    }
  }

  /// Pauses playback at the current position.
  Future<void> pause() async {
    if (!_isInitialized || _disposed || _isSwitchingSource) return;
    _generation++;
    _watchdog?.cancel();
    _cancelGapTimer(); // 句间等待也可被暂停打断
    try {
      _isPlaying = false;
      await _facade.pause();
      notifyListeners();
    } catch (error, stackTrace) {
      _handlePlaybackError('pause', error, stackTrace);
    }
  }

  /// Advances to the next sentence. If already on the last sentence and
  /// [onNextLessonRequested] is provided, triggers navigation to next lesson.
  Future<void> nextSentence() async {
    if (!canGoNext) {
      onNextLessonRequested?.call();
      return;
    }
    await _transitionToSentence(_currentIndex + 1, play: false, reason: 'next');
  }

  /// Moves to the previous sentence. If already on the first sentence and
  /// [onPreviousLessonRequested] is provided, triggers navigation to previous lesson.
  Future<void> previousSentence() async {
    if (!canGoPrevious) {
      onPreviousLessonRequested?.call();
      return;
    }
    await _transitionToSentence(_currentIndex - 1, play: false, reason: 'previous');
  }

  /// Jumps to the sentence at [index]. Out-of-range indices are ignored.
  ///
  /// Playback state is preserved: if audio was playing it keeps playing the new
  /// sentence, otherwise it only seeks and stays paused.
  Future<void> selectSentence(int index) =>
      _transitionToSentence(index, play: false, reason: 'select');

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _watchdog?.cancel();
    _watchdog = null;
    _cancelGapTimer();
    // Cancel listeners synchronously so no callback fires after teardown
    // (avoids leaked / duplicate listeners and post-dispose notifyListeners).
    final posSub = _positionSub;
    _positionSub = null;
    posSub?.cancel();
    final errSub = _errorSub;
    _errorSub = null;
    errSub?.cancel();
    final compSub = _completionSub;
    _completionSub = null;
    compSub?.cancel();
    final idxSub = _currentIndexSub;
    _currentIndexSub = null;
    idxSub?.cancel();
    // Fire-and-forget release of both sources (Phase 3C: the controller owns
    // the video facade too, so leaving the screen stops video sound and
    // frees the WebView bridge — spec §15).
    unawaited(_audioFacade.dispose());
    unawaited(_videoFacade?.dispose());
    super.dispose();
  }

  // ------------------------------------------------------------- internals ---

  /// (Re)subscribes the controller to the active facade's position + error
  /// streams. Exactly one pair of subscriptions is alive at any time.
  void _attachSourceListeners() {
    _positionSub = _facade.positionStream.listen(_onPosition);
    _completionSub = _facade.completionStream.listen(_onClipCompleted);
    _currentIndexSub = _facade.currentIndexStream.listen(_onEngineSentenceIndex);
    _errorSub = _facade.errorStream.listen(_onAudioError);
  }

  /// Cancels the subscriptions to the currently attached facade.
  ///
  /// Cancellation is synchronous (not awaited): for broadcast streams the
  /// listener is detached immediately, so no stale position/error can reach
  /// [_onPosition]/[_onAudioError] after the swap — mirroring [dispose].
  /// (Awaiting the cancel futures is also unnecessary ordering-wise and
  /// deadlocks an in-flight switch chain under the test binding's FakeAsync
  /// pumping.)
  Future<void> _detachSourceListeners() async {
    final posSub = _positionSub;
    _positionSub = null;
    unawaited(posSub?.cancel());
    final compSub = _completionSub;
    _completionSub = null;
    unawaited(compSub?.cancel());
    final idxSub = _currentIndexSub;
    _currentIndexSub = null;
    unawaited(idxSub?.cancel());
    final errSub = _errorSub;
    _errorSub = null;
    unawaited(errSub?.cancel());
  }

  /// 动态热切换句子切分模式（2026-09-30 方案B：初学意群 ⇄ 熟读分句）：
  /// 保持当前底层音频播放与位置不中断，平滑将播放器句列表切换为目标列表，
  /// 并自动将当前句下标对齐到覆盖当前播放时间（或指定的 targetIndex）的句子。
  void switchSentenceList(List<Sentence> newSentences, {int? targetIndex}) {
    if (newSentences.isEmpty) return;
    _sentences = List<Sentence>.unmodifiable(newSentences);
    if (targetIndex != null) {
      _currentIndex = targetIndex.clamp(0, _sentences.length - 1);
    } else {
      final posMs = _currentPosition.inMilliseconds;
      int match = 0;
      for (var i = 0; i < _sentences.length; i++) {
        if (posMs >= _sentences[i].startMs && posMs < _sentences[i].endMs) {
          match = i;
          break;
        } else if (posMs < _sentences[i].startMs) {
          match = (i > 0) ? i - 1 : 0;
          break;
        }
      }
      _currentIndex = match.clamp(0, _sentences.length - 1);
    }
    notifyListeners();
  }

  /// 原地平滑切换音频源与句子序列（精听页面直接切课支持）：
  /// 停止旧音频，重设音频底层源、更新句子序列并归零位置，保持同一个控制器实例。
  Future<void> replaceAudioSource({
    required String audioAsset,
    required bool isFile,
    required List<Sentence> sentences,
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    assert(sentences.isNotEmpty, 'sentences must not be empty');
    if (_disposed) return;
    _generation++;
    final gen = _generation;
    _watchdog?.cancel();
    _cancelGapTimer();
    _restartPending = false;
    _isPlaying = false;
    _assetPath = audioAsset;
    audioIsFile = isFile;
    _sentences = List<Sentence>.unmodifiable(sentences);
    _currentIndex = initialIndex.clamp(0, _sentences.length - 1);
    _repeatRemaining = _repeatTarget == 0 ? -1 : _repeatTarget;
    _errorMessage = null;
    notifyListeners();

    try {
      await _facade.pause();
      if (_disposed || gen != _generation) return;

      if (_useClipPlaylist) {
        final clips = [
          for (final s in _sentences)
            SentenceClip(
              index: s.index,
              start: Duration(milliseconds: s.startMs),
              end: Duration(milliseconds: s.endMs),
            ),
        ];
        await _facade.loadPlaylist(
          path: _assetPath,
          isFile: audioIsFile,
          clips: clips,
          initialIndex: _currentIndex,
        );
        await _facade.setLoopOne(_repeatTarget == 0);
      } else {
        if (audioIsFile) {
          await _facade.setFilePath(_assetPath);
        } else {
          await _facade.setAsset(_assetPath);
        }
      }
      if (_disposed || gen != _generation) return;

      final start = Duration(milliseconds: currentSentence.startMs);
      _pendingSeekTargetMs = currentSentence.startMs;
      if (_useClipPlaylist) {
        await _facade.seekSentence(_currentIndex, start);
      } else {
        await _facade.seek(start);
      }
      if (_disposed || gen != _generation) return;

      _currentPosition = start;
      _isInitialized = true;
      if (_playbackRate != 1.0) {
        await _facade.setSpeed(_playbackRate);
        if (_disposed || gen != _generation) return;
      }

      if (autoPlay) {
        _isPlaying = true;
        _completionHandled = false;
        notifyListeners();
        await _facade.play();
        if (_disposed || gen != _generation) return;
        _startWatchdog(currentSentence);
      } else {
        notifyListeners();
      }
    } catch (error, stackTrace) {
      _handlePlaybackError('replaceAudioSource', error, stackTrace);
    }
  }

  void _onEngineSentenceIndex(int index) {
    if (_disposed || !_isPlaying || _restartPending) return;
    // 单音源（连续流）路径：engine 的 playlist index 恒为 0，与句索引无关。
    // 不忽略的话，每次 seek（跳空白/滑栏跳句）都会触发一次 index=0 事件，
    // 把字幕拍回第一句再逐句爬回来（2026-09-22 用户报告的严重 bug）。
    // engine index 只在 clip playlist 模式下与句索引一一对应，才有意义。
    if (!_useClipPlaylist) return;
    if (index < 0 || index >= _sentences.length || index == _currentIndex) return;
    _currentIndex = index;
    _repeatRemaining = _repeatTarget == 0 ? -1 : _repeatTarget;
    _currentPosition = Duration(milliseconds: currentSentence.startMs);
    _completionHandled = false;
    unawaited(_facade.setLoopOne(_repeatTarget == 0 || _repeatRemaining > 1));
    notifyListeners();
    _startWatchdog(currentSentence);
  }

  bool _isSourceLoaded(PlaybackMode mode) =>
      mode == PlaybackMode.audio ? _audioLoaded : _videoLoaded;

  void _markSourceLoaded(PlaybackMode mode) {
    if (mode == PlaybackMode.audio) {
      _audioLoaded = true;
    } else {
      _videoLoaded = true;
    }
  }

  /// The single sentence-transition path. Manual navigation and the
  /// auto-advance both land here — only [play] (start sounding immediately,
  /// regardless of the current playing state) and [reason] differ.
  Future<void> _transitionToSentence(
    int targetIndex, {
    required bool play,
    String reason = 'manual',
  }) async {
    if (!_isInitialized || hasError || _disposed || _isSwitchingSource) return;
    _cancelGapTimer(); // 切句作废进行中的句间等待（含 _gapWaitActive）
    if (_errorMessage == 'Unable to switch playback mode.') {
      _errorMessage = null;
      notifyListeners();
    }
    if (targetIndex < 0 || targetIndex >= _sentences.length) return; // boundary

    final wasPlaying = _isPlaying;
    final shouldPlay = play || wasPlaying;
    _generation++;
    final gen = _generation;
    _repeatRemaining = _repeatTarget == 0 ? -1 : _repeatTarget;
    _watchdog?.cancel();
    _restartPending = true;
    _completionHandled = true;
    _currentIndex = targetIndex;
    final sentence = currentSentence;
    final start = Duration(milliseconds: sentence.startMs);

    final alreadyAtTarget = _useClipPlaylist &&
        reason == 'auto' &&
        _facade.currentPlaylistIndex == targetIndex;

    final shouldLoopNative = _repeatTarget == 0 || _repeatRemaining > 1;
    try {
      if (_useClipPlaylist) {
        await _facade.setLoopOne(shouldLoopNative);
        if (!alreadyAtTarget) {
          _pendingSeekTargetMs = sentence.startMs;
          await _facade.seekSentence(targetIndex, start);
          if (_disposed || gen != _generation) return;
        }
      } else {
        _pendingSeekTargetMs = sentence.startMs;
        await _facade.seek(start);
        if (_disposed || gen != _generation) return;
      }
      _currentPosition = start;
      _logSeekTiming(sentence, reason: reason);

      if (shouldPlay) {
        _isPlaying = true;
        _completionHandled = false;
        notifyListeners();
        if (!alreadyAtTarget) {
          await _facade.play();
          if (_disposed || gen != _generation) return;
        }
        _restartPending = false;
        _startWatchdog(sentence);
      } else {
        _isPlaying = false;
        _restartPending = false;
        notifyListeners();
      }
    } catch (error, stackTrace) {
      _handlePlaybackError('seek', error, stackTrace);
    }
  }

  void _onPosition(Duration position) {
    if (_disposed || _restartPending) return;
    if (_gapWaitActive) return; // 句间静默等待：position 无意义，整体忽略

    // 卫兵：底层引擎刚发起 seek 时，若 positionStream 仍抛出旧位置的陈旧采样，予以过滤
    if (_pendingSeekTargetMs != null) {
      final diff = (position.inMilliseconds - _pendingSeekTargetMs!).abs();
      if (diff > 1000) {
        return; // 过滤 stale position，防止触发错误跳句
      }
      _pendingSeekTargetMs = null; // 已进入新区间，解除卫兵
    }

    final cur = currentSentence;
    final end = Duration(milliseconds: cur.endMs);
    final shouldLoop = _repeatRemaining == -1 || _repeatRemaining > 1;

    // 1. Single-sentence loop mode: loop immediately at sentence end.
    if (shouldLoop && _isPlaying && position >= end) {
      _finishCurrentSentence(position);
      return;
    }

    // 2. Continuous playback mode (Play All / finite repeat exhausted on this sentence):
    if (!shouldLoop && canGoNext) {
      final next = _sentences[_currentIndex + 1];
      final nextStart = Duration(milliseconds: next.startMs);
      final gapMs = next.startMs - cur.endMs;

      // Mode A: Cinema Natural Mode (_skipSilence == false, default):
      // NEVER seek across sentence boundaries! Audio and video stream naturally.
      // The subtitle of current sentence remains on screen throughout the gap
      // until the next sentence actually begins speaking (position >= nextStart).
      if (!_skipSilence) {
        // 句间间隔（v0.9.1 课堂带读）：用户显式设置间隔后，句子读完即停，
        // 等待间隔后由 [_finishCurrentSentence] 跳下一句——覆盖「自然流动」
        // 行为，否则课文原声的句间停顿长度不可控。
        if (_sentenceGapMs > 0 && _isPlaying && position >= end && canGoNext) {
          _finishCurrentSentence(position);
          return;
        }
        if (position >= nextStart) {
          _advanceToNextSentenceNatural(position);
          return;
        }
        if (position >= end && position < nextStart) {
          _currentPosition = _useClipPlaylist ? end : position;
          notifyListeners();
          return;
        }
      } else {
        // Mode B: Compact Listening Mode (_skipSilence == true):
        // Automatically skip pauses and interludes (gap > 500ms).
        if (gapMs > 500) {
          if (!_useClipPlaylist && _isPlaying && position >= end) {
            _finishCurrentSentence(position);
            return;
          }
        } else {
          // Rapid dialogue turns (gap <= 500ms): always flow naturally without stutter.
          if (position >= nextStart) {
            _advanceToNextSentenceNatural(position);
            return;
          }
          if (position >= end && position < nextStart) {
            _currentPosition = _useClipPlaylist ? end : position;
            notifyListeners();
            return;
          }
        }
      }
    }

    // 3. For sources that cannot stop themselves (video), stop when the last sentence finishes.
    if (!_useClipPlaylist && _isPlaying && position >= end && !canGoNext) {
      _finishCurrentSentence(position);
      return;
    }

    // Clamp the displayed position so it never reads past the sentence end.
    _currentPosition = position > end ? end : position;
    notifyListeners();
  }

  /// Natural transition when continuous playback flows across sentence boundaries.
  /// Advances the index without calling seek(), keeping audio and video completely gapless.
  void _advanceToNextSentenceNatural(Duration position) {
    if (_disposed || _restartPending || !canGoNext) return;
    final next = _sentences[_currentIndex + 1];
    final posMs = position.inMilliseconds;
    // 防御性校验：如果 position 严重超前下一句（例如大于下句结束 1500ms），
    // 表明 position 发生突跳或拖拽，直接精准定位到包含该 position 的目标句，杜绝每帧++级联滚屏
    if (posMs > next.endMs + 1500) {
      final targetIdx = _findSentenceIndexForPosition(posMs);
      if (targetIdx != -1 && targetIdx != _currentIndex) {
        _currentIndex = targetIdx;
      } else {
        return;
      }
    } else {
      _currentIndex++;
    }
    _repeatRemaining = _repeatTarget == 0 ? -1 : _repeatTarget;
    _currentPosition = position;
    _completionHandled = false;
    _restartPending = false;
    notifyListeners();
    _startWatchdog(currentSentence);
  }

  /// 根据时间戳毫秒数精准定位句子下标
  int _findSentenceIndexForPosition(int posMs) {
    for (int i = 0; i < _sentences.length; i++) {
      if (posMs >= _sentences[i].startMs && posMs <= _sentences[i].endMs) {
        return i;
      }
      if (i < _sentences.length - 1 &&
          posMs > _sentences[i].endMs &&
          posMs < _sentences[i + 1].startMs) {
        return i; // 落在两句之间的停顿空白
      }
    }
    return -1;
  }

  /// Native completion from a clip-enforcing source: the engine has already
  /// stopped at the clip end; this only advances the state machine.
  void _onClipCompleted(PlaybackCompletionEvent event) {
    if (_disposed || !_useClipPlaylist) return;
    // A completion belongs to exactly one sentence clip. A different clipEnd
    // is a stale emission from a sentence we already left (manual switch or
    // an earlier auto-advance) — the epoch guard, in clip identity.
    if (event.clipEndMs != currentSentence.endMs) return;
    if (_completionHandled) return;
    _completionHandled = true;
    _finishCurrentSentence();
  }

  Future<void> _finishCurrentSentence([Duration? triggerPosition]) async {
    _completionHandled = true;
    _watchdog?.cancel();
    _watchdog = null;
    final sentence = currentSentence;
    _logPauseTiming(sentence, triggerPosition);
    _currentPosition = Duration(milliseconds: sentence.endMs);

    _logAutoAdvance(sentence, triggerPosition);

    // WP-H 跟读验收门（方案 §五）：非 null 时每句播完停在句末并回调，
    // 不再自动跳下一句、也不再循环本句——节奏全部交给跟读会话。
    // 位置刻意在「循环本句」分支之前：repeatTarget=0（无限循环）时
    // shouldLoop 恒真并从循环分支提前 return，门若只在自动推进分支前
    // 插入，无限循环用户的跟读门将永远不触发。gate 为 null 时本段
    // 完全不执行，非跟读路径时序零改变（时间戳/高亮/定位一律不动）。
    if (readAlongGate != null) {
      _isPlaying = false;
      _restartPending = false;
      notifyListeners();
      try {
        await _facade.pause();
      } catch (_) {}
      await readAlongGate!(_currentIndex);
      return; // 不自动推进，节奏交给跟读会话
    }

    // Auto-loop (V0.2 §4): unless the repeat target is exhausted, restart the
    // sentence from startMs. A captured generation aborts the restart if the
    // user did something else meanwhile (pause / switch / dispose).
    final shouldLoop = _repeatRemaining == -1 || _repeatRemaining > 1;
    if (shouldLoop) {
      if (_repeatRemaining > 1) _repeatRemaining--;
      final gen = _generation;

      // Native loop optimization for clip-enforcing sources (ExoPlayer LoopMode.one):
      // The native player has ALREADY looped back to start of the clip and is
      // already sounding. Calling seek() and play() here forces a redundant seek,
      // creating an audible stutter / double-reading the first word.
      //
      // 句间间隔例外：间隔 > 0 时原生循环必须让位——间隔的意义就是两次播放
      // 之间静默等待，原生即时循环会跳过等待，所以此时走通用 seek+play 路径。
      if (_useClipPlaylist &&
          _sentenceGapMs <= 0 &&
          (_repeatTarget == 0 || _repeatRemaining > 0)) {
        _currentPosition = Duration(milliseconds: sentence.startMs);
        _isPlaying = true;
        _completionHandled = false;
        _restartPending = false;
        _startWatchdog(sentence);
        if (_repeatRemaining == 1) {
          unawaited(_facade.setLoopOne(false));
        }
        notifyListeners();
        return;
      }

      unawaited(_facade.pause()); // 间隔期间静音（video 源音频仍在播）
        // 句间间隔（v0.9.1）：先静默等待，再重启本句。
      if (_sentenceGapMs > 0) {
        _isPlaying = false;
        _restartPending = false;
        _currentPosition = Duration(milliseconds: sentence.endMs);
        _gapWaitActive = true;
        notifyListeners();
        await _waitForGap(_sentenceGapMs, gen, () async {
          _gapWaitActive = false;
          _restartPending = true;
          try {
            final start = Duration(milliseconds: sentence.startMs);
            await _facade.seek(start);
            if (_disposed || gen != _generation) return;
            _currentPosition = start;
            _isPlaying = true;
            _completionHandled = false;
            notifyListeners();
            await _facade.play();
            if (_disposed || gen != _generation) return;
            _restartPending = false;
            _startWatchdog(sentence);
          } catch (error, stackTrace) {
            _restartPending = false;
            _handlePlaybackError('loop', error, stackTrace);
          }
        });
        return;
      }

      _restartPending = true;
      try {
        final start = Duration(milliseconds: sentence.startMs);
        await _facade.seek(start);
        if (_disposed || gen != _generation) return;
        _currentPosition = start;
        _isPlaying = true;
        _completionHandled = false;
        notifyListeners();

        await _facade.play();
        if (_disposed || gen != _generation) return;
        _restartPending = false;
        _startWatchdog(sentence);
        return;
      } catch (error, stackTrace) {
        _restartPending = false;
        _handlePlaybackError('loop', error, stackTrace);
        return;
      }
    }
    if (_repeatRemaining > 0) _repeatRemaining--;

    // Finite target exhausted: auto-advance to the next sentence with a
    // fresh repeat count (user request 2026-09-16); on the last sentence,
    // stop. Auto-advance always keeps playing — the unified transition with
    // play: true.
    if (canGoNext && !_disposed) {
      unawaited(_facade.pause()); // 间隔期间静音
      // 句间间隔（v0.9.1）：跳下一句前也等待（课堂带读的句间停顿）。
      if (_sentenceGapMs > 0) {
        final gen = _generation;
        // 目标下标在等待开始时就固定：等待期间任何下标漂移都不允许改变
        // 这次自动推进的落点（2026-09-29 实测：位置流在等待期间触发自然
        // 过渡 +1，回调再 +1 → 从第 1 句直接跳到第 3 句）。
        final nextIndex = _currentIndex + 1;
        _isPlaying = false;
        _restartPending = false;
        _gapWaitActive = true;
        notifyListeners();
        await _waitForGap(_sentenceGapMs, gen, () async {
          _gapWaitActive = false;
          await _transitionToSentence(nextIndex, play: true, reason: 'auto');
        });
        return;
      }
      await _transitionToSentence(_currentIndex + 1, play: true, reason: 'auto');
      return;
    }
    _isPlaying = false;
    _restartPending = false;
    notifyListeners();
    try {
      await _facade.pause();
    } catch (error, stackTrace) {
      _handlePlaybackError('auto-pause', error, stackTrace);
    }
    // 课文最后一句自然播完：若外部注册了下一课回调，则自动切入下一课
    if (!canGoNext) {
      if (_lessonLoop) {
        // 整课循环：回到第一句继续播放，不切课
        unawaited(_facade.pause());
        await _transitionToSentence(0, play: true, reason: 'lesson-loop');
      } else {
        onNextLessonRequested?.call();
      }
    }
  }

  /// One-line per-sentence-boundary diagnostic (Milestone 1B / 2026-09-18
  /// first-word-duplication fix). With a clip-enforcing source the overshoot
  /// is expected to collapse to ~0 ms: the engine stops at the clip end and
  /// the completion event is only bookkeeping.
  void _logAutoAdvance(Sentence sentence, Duration? triggerPosition) {
    if (!kDebugMode) return;
    final facadePos = _facade.position.inMilliseconds;
    final nextStart = canGoNext
        ? _sentences[_currentIndex + 1].startMs
        : null;
    debugPrint(
      '[ListenLoop][auto] sentence=${sentence.index} end=${sentence.endMs}ms '
      'triggerPosition=${triggerPosition?.inMilliseconds ?? 'n/a'} '
      'enginePosition=${facadePos}ms '
      'overshoot=${_signed(facadePos - sentence.endMs)}ms '
      'nextStart=${nextStart ?? 'last'} repeatRemaining=$_repeatRemaining '
      'epoch=$_generation',
    );
  }

  void _onAudioError(AudioPlaybackError error) {
    if (_disposed) return;
    _watchdog?.cancel();
    _watchdog = null;
    _isPlaying = false;
    _errorMessage = 'Unable to play audio.';
    debugPrint(
      '[ListenLoop] async player error on sentence idx=$_currentIndex: $error',
    );
    notifyListeners();
  }

  /// Auxiliary safety net. The position stream is authoritative; this only
  /// forces a pause if playback somehow ran past the sentence's effective end
  /// without the stream reporting it (e.g. a very coarse stream).
  ///
  /// 2026-09-21 用户反馈修复（原声连贯跳变）：audio playlist 模式下 clip end
  /// 会被扩展到下一句的 startMs（[JustAudioFacade.loadPlaylist] 的 gapless
  /// 扩展），原声连贯模式（Mode A）依赖这段自然流动的空隙。watchdog 若仍按
  /// `sentence.endMs` 计时，会在空隙刚开始时强制 finish → seek 到下一句，
  /// 造成"上一句播完瞬间跳到下一句"的跳变（如 your-name-full idx143→144，
  /// 27.8s 空隙被直接跳过）。因此 Mode A 且还有下一句时，watchdog 终点与
  /// clip 扩展终点对齐（next.startMs）；Mode B（跳过空白）保持 endMs ——
  /// 提前 finish 正是跳过空白想要的行为。
  void _startWatchdog(Sentence sentence, {Duration? from}) {
    _watchdog?.cancel();
    final fromMs = from?.inMilliseconds ?? sentence.startMs;
    var endMs = sentence.endMs;
    if (!_skipSilence && canGoNext) {
      final next = _sentences[_currentIndex + 1];
      if (next.startMs > endMs) endMs = next.startMs;
    }
    final remainingMs = ((endMs - fromMs) / _playbackRate).round();
    _watchdog = Timer(
      Duration(milliseconds: remainingMs) + _watchdogBuffer,
      () {
        if (_disposed) return;
        if (_isPlaying) {
          // No stream trigger — pass null so the log records the watchdog path.
          _finishCurrentSentence();
        }
      },
    );
  }

  void _handlePlaybackError(String op, Object error, StackTrace stackTrace) {
    _restartPending = false;
    _watchdog?.cancel();
    _isPlaying = false;
    _errorMessage = 'Unable to play audio.';
    debugPrint('[ListenLoop] $op failed: $error\n$stackTrace');
    notifyListeners();
  }

  // -------------------------------------------------------- timing logging ---
  //
  // Debug-only diagnostic logs used by Milestone 1B to quantify real-device
  // seek and pause precision. Each line is prefixed with `[ListenLoop][timing]`
  // so it can be filtered out of `adb logcat` / `flutter run` output.

  void _logSeekTiming(Sentence sentence, {required String reason}) {
    if (!kDebugMode) return;
    final expected = sentence.startMs;
    final actual = _facade.position.inMilliseconds;
    final err = actual - expected;
    debugPrint(
      '[ListenLoop][timing] idx=${sentence.index} reason=$reason '
      'expectedStart=${expected}ms seekPosition=${actual}ms '
      'startError=${_signed(err)}ms',
    );
  }

  void _logPauseTiming(Sentence sentence, Duration? streamPosition) {
    if (!kDebugMode) return;
    final expected = sentence.endMs;
    final facadePos = _facade.position.inMilliseconds;
    final streamPos = streamPosition?.inMilliseconds;
    // The "pause position" of record is the facade's current position, which
    // is the closest we can get to where the decoder actually was when we
    // decided to pause. The stream-trigger value (if any) is logged alongside
    // so granularity vs. real position can be compared.
    final err = facadePos - expected;
    debugPrint(
      '[ListenLoop][timing] idx=${sentence.index} '
      'expectedEnd=${expected}ms streamPosition=${streamPos ?? 'n/a'} '
      'pausePosition=${facadePos}ms endError=${_signed(err)}ms',
    );
  }

  static String _signed(int v) => v >= 0 ? '+$v' : '$v';
}
