import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/lesson.dart';
import '../models/video_source.dart';
import '../storage/lesson_repository.dart';
import 'asr_engine.dart';
import 'audio_preprocessor.dart';
import 'bilibili_source.dart';
import 'creation_errors.dart';
import 'lesson_input.dart';
import 'lesson_job_stage.dart';
import 'lesson_packager.dart';
import 'segmentation_service.dart';
import 'translation_service.dart';
import 'word_timestamp.dart';
import 'youtube_relay.dart';

/// Minimum free bytes before a creation job may start (spec V1 §四十六):
/// decoded WAV + source media + the final package must coexist.
/// Set to 500 MB to comfortably support long media up to 3 hours
/// (16 kHz mono 16-bit WAV for 3h is ~345 MB).
const int kMinFreeDiskBytes = 500 * 1024 * 1024;

const MethodChannel _nativeChannel = MethodChannel(
  'listenloop/creation_native',
);

/// Orchestrates ONE Mobile Lesson Creation job (spec V1 §八–§十二).
///
/// Owned at app level (the shell), not by the creation screen — navigating
/// away never kills a running job (§四十二, v1 foreground scope). Strict
/// single-job rule (§四十八). The pipeline reuses the existing importer
/// (§二十八) and never touches playback or learning state (§五十八).
class CreationController extends ChangeNotifier {
  CreationController({
    required this.repository,
    required this.audioPreprocessor,
    required this.asrEngine,
    required this.translationEngine,
    Future<Directory> Function()? tempDirResolver,
    Future<int> Function()? freeDiskSpaceResolver,
    String Function()? youtubeRelayBaseUrlResolver,
    YouTubeRelayClient Function(String baseUrl)? youtubeRelayFactory,
  }) : tempDirResolver = tempDirResolver ?? _defaultTempDirResolver,
       freeDiskSpaceResolver = freeDiskSpaceResolver ?? _defaultFreeDiskSpace,
       youtubeRelayBaseUrlResolver =
           youtubeRelayBaseUrlResolver ??
           (() => YouTubeRelayClient.defaultBaseUrl),
       _youtubeRelayFactory =
           youtubeRelayFactory ??
           ((baseUrl) => YouTubeRelayClient(baseUrl: baseUrl));

  final LessonRepository repository;
  final AudioPreprocessor audioPreprocessor;
  final AsrEngine asrEngine;
  final TranslationEngine translationEngine;

  /// Where derived job files (decoded WAV) live. Injectable for tests.
  final Future<Directory> Function() tempDirResolver;

  /// Free-bytes probe for the pre-flight check. Injectable for tests.
  final Future<int> Function() freeDiskSpaceResolver;

  /// Resolves the PC-side YouTube relay base URL (e.g. from AppPreferences).
  final String Function() youtubeRelayBaseUrlResolver;

  /// Builds the relay client — a seam so tests can simulate an unreachable or
  /// healthy relay without a real PC.
  final YouTubeRelayClient Function(String baseUrl) _youtubeRelayFactory;

  static Future<Directory> _defaultTempDirResolver() => getTemporaryDirectory();

  static Future<int> _defaultFreeDiskSpace() async =>
      await _nativeChannel.invokeMethod<int>('getFreeDiskSpace') ?? 0;

  LessonJobStage _stage = LessonJobStage.completed; // idle == no active job
  double _stageProgress = 0;
  Lesson? _result;
  LessonInput? _currentInput;
  DateTime? _startedAt;
  String? _errorMessage;
  CreationError? _errorCode;
  final List<String> _logLines = [];
  bool _cancelRequested = false;
  int _jobSeq = 0;

  LessonJobStage get stage => _stage;
  double get stageProgress => _stageProgress.clamp(0.0, 1.0);
  Lesson? get result => _result;

  /// The input of the current/most recent job (shown on the creation page).
  LessonInput? get currentInput => _currentInput;

  /// When the current/most recent job started (elapsed timer on the UI).
  DateTime? get startedAt => _startedAt;

  String? get errorMessage => _errorMessage;
  CreationError? get errorCode => _errorCode;
  List<String> get logLines => List.unmodifiable(_logLines);
  bool get isBusy => _stage.isActive;
  bool get isReady => _stage == LessonJobStage.completed && _result != null;
  bool get isFailed => _stage == LessonJobStage.failed;
  bool get isCancelled => _stage == LessonJobStage.cancelled;
  Lesson? get lastLesson => _result;

  /// Retries the most recent job using the same input.
  Future<Lesson?> retry() async {
    final input = _currentInput;
    if (input == null || isBusy) return null;
    return start(input);
  }

  /// Resets the controller back to idle.
  void reset() => resetToIdle();

  /// True when a job is currently running or a recent job's result/error is displayed.
  bool get hasActiveOrRecentJob => _startedAt != null;

  /// Resets the controller so the creation tab returns to the idle creation form.
  void resetToIdle() {
    if (isBusy) return;
    _startedAt = null;
    _result = null;
    _errorMessage = null;
    _errorCode = null;
    _currentInput = null;
    notifyListeners();
  }

  /// Starts a job. Returns the imported lesson, or null when the job failed
  /// / was cancelled / was rejected because another job is active (§四十八).
  Future<Lesson?> start(LessonInput input) async {
    if (isBusy) return null;
    _cancelRequested = false;
    _jobSeq += 1;
    _currentInput = input;
    _startedAt = DateTime.now();
    final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}-$_jobSeq';
    _stage = LessonJobStage.queued;
    _stageProgress = 0;
    _result = null;
    _errorMessage = null;
    _errorCode = null;
    _logLines
      ..clear()
      ..add('Job: $jobId');
    notifyListeners();

    Directory? jobDir;
    final startedAt = DateTime.now();
    // Creation V2 §十三: measure the pipeline as it runs. Log-only — it must
    // never change what the pipeline does.
    final bench = _Benchmark()..startSampling();
    int? sentenceCount;
    try {
      // ---- input ----------------------------------------------------------
      // M3 从链接创建 (2026-09-18 用户指令): bilibili first — the PC pipeline
      // proved the anonymous view/playurl API flow on 2026-09-16. The
      // downloaded audio feeds the exact same pipeline as a local file; the
      // video picture rides on the existing WebView VideoSource.
      BiliVideoRef? biliRef;
      String? rawLink;
      if (input.kind == LessonInputKind.link) {
        // extractUrl handles share blobs like 「【标题】 https://b23.tv/x」;
        // b23.tv short links carry no BV and are resolved over the network
        // during acquisition.
        rawLink = extractUrl(input.source ?? '') ??
            (input.source ?? '').trim();
        biliRef = parseBilibiliUrl(rawLink);
        final looksLikeLink = biliRef != null || rawLink.startsWith('http');
        if (!looksLikeLink) {
          throw const CreationException(
            CreationError.inputError,
            'unrecognised or unsupported link (bilibili only for now)',
          );
        }
        _logLines.add('Input: link ${rawLink.length > 60 ? '${rawLink.substring(0, 60)}…' : rawLink}');
      } else {
        final sourceFile = File(input.path!);
        if (!await sourceFile.exists()) {
          throw const CreationException(
            CreationError.inputError,
            'the selected file does not exist',
          );
        }
        _logLines.add('Input: ${p.basename(input.path!)}');
      }

      // ---- storage pre-flight (§四十六) ------------------------------------
      final freeBytes = await freeDiskSpaceResolver();
      _logLines.add('Free storage: ${(freeBytes / (1024 * 1024)).round()} MB');
      if (freeBytes < kMinFreeDiskBytes) {
        throw const CreationException(
          CreationError.storageError,
          'not enough free storage',
        );
      }

      // ---- working directory (§四十五) -------------------------------------
      final tmpDir = await tempDirResolver();
      // Single active job (§四十八): anything left under creation_jobs is a
      // corpse from a job whose process died mid-run (real-device evidence:
      // 298 MB of dead PCM after a few long background jobs were killed).
      // Purge it before this job starts — there is nothing concurrent.
      final jobsRoot = Directory(p.join(tmpDir.path, 'creation_jobs'));
      if (jobsRoot.existsSync()) {
        try {
          jobsRoot.deleteSync(recursive: true);
        } catch (error) {
          debugPrint('[ListenLoop] stale job purge failed: $error');
        }
      }
      jobDir = Directory(p.join(tmpDir.path, 'creation_jobs', jobId));
      final audioDir = Directory(p.join(jobDir.path, 'audio'));
      await audioDir.create(recursive: true);
      final wavPath = p.join(audioDir.path, 'source.wav');

      // ---- source acquisition (download for links) -------------------------
      final String sourcePath;
      VideoSource? videoSource;
      BiliVideoInfo? biliInfo;
      var linkTitle = '';
      if (input.kind == LessonInputKind.link) {
        _setStage(LessonJobStage.preparingAudio);
        final isYoutube = RegExp(
          r'youtube\.com|youtu\.be',
        ).hasMatch(input.source ?? '');
        try {
          if (isYoutube) {
            // PC relay: yt-dlp + PO-token machinery lives on the PC, with its
            // traffic exiting through the phone's VPN (the PC-IP blacklist
            // does not apply to the phone's exit). Audio only — a YouTube
            // video picture needs an iframe harness and arrives later.
            final relayBaseUrl = youtubeRelayBaseUrlResolver();
            final relay = _youtubeRelayFactory(relayBaseUrl);
            final ytUrl = extractUrl(input.source ?? '') ?? input.source!;

            // 先探活再开工：中继不在线时**立刻**失败，不要等 ASR/翻译
            // 跑到一半才发现拿不到音频。用户拿到的是"该去做什么"，
            // 而不是一段跑了几十秒后的含糊错误。
            if (!await relay.checkHealth()) {
              throw CreationException(
                CreationError.sourceUnavailable,
                'youtube relay unreachable at $relayBaseUrl',
              );
            }
            final ytId = _extractYouTubeId(ytUrl);
            if (ytId != null && ytId.isNotEmpty) {
              videoSource = VideoSource(
                provider: VideoSource.providerYoutube,
                bvid: ytId,
                page: 1,
              );
            }
            sourcePath = p.join(audioDir.path, 'source.m4a');
            linkTitle = await relay.downloadAudio(
              ytUrl,
              sourcePath,
              onProgress: (progress) {
                _stageProgress = progress;
                notifyListeners();
                _cancelDuringDownload();
              },
            );
            _logLines.add(
              'YouTube: ${linkTitle.isEmpty ? 'audio downloaded' : linkTitle}',
            );
          } else {
            final client = BilibiliClient();
            final ref = biliRef ?? await client.resolve(rawLink ?? '');
            biliInfo = await client.fetchVideoInfo(ref);
            _logLines.add(
              'Bilibili: ${biliInfo.title} '
              '(${_mmss(biliInfo.durationSec * 1000)})',
            );
            final streams = await client.fetchStreams(biliInfo);
            sourcePath = p.join(audioDir.path, 'source.m4s');
            final known = streams.audio.sizeBytes > 0
                ? streams.audio.sizeBytes
                : null;
            await client.download(
              streams.audio.url,
              sourcePath,
              total: known,
              onProgress: (progress) {
                _stageProgress = progress;
                notifyListeners();
                _cancelDuringDownload();
              },
            );
            videoSource = VideoSource(
              provider: VideoSource.providerBilibili,
              bvid: ref.bvid,
              page: ref.page,
              cid: biliInfo.cid,
            );
          }
        } on BilibiliException catch (error) {
          throw CreationException(CreationError.inputError, error.message);
        } on YouTubeRelayException catch (error) {
          // 链接是好的，坏的是取源通道 —— 归类为 sourceUnavailable，
          // 文案由界面给出「插线 / 启中继 / 换 B 站」三步（见 l10n）。
          throw CreationException(
            CreationError.sourceUnavailable,
            'youtube relay: ${error.message}',
          );
        }
        await _checkCancel();
      } else {
        sourcePath = input.path!;
      }

      // ---- audio preparation (§二十一) -------------------------------------
      _setStage(LessonJobStage.preparingAudio);
      final prepared = await bench.stage(
        'decode',
        () => audioPreprocessor.toMono16kWav(sourcePath, wavPath),
      );
      // O(1) memory: use length() instead of readAsBytes() to avoid
      // spiking hundreds of MB of RAM on long audio (3h ≈ 345 MB).
      final wavLength = await File(prepared).length();
      final audioDurationMs = ((wavLength - 44) / 2 / 16000 * 1000)
          .round();
      bench.audioDurationMs = audioDurationMs;
      _logLines.add('Audio prep: OK (${_mmss(audioDurationMs)})');

      // ---- ASR (§十六) ------------------------------------------------------
      _setStage(LessonJobStage.transcribing);
      final words = await bench.stage(
        'asr',
        () => asrEngine.transcribe(
          prepared,
          language: input.language,
          onProgress: (progress) {
            _stageProgress = progress;
            notifyListeners();
          },
          isCancelled: () => _cancelRequested,
        ),
      );
      await _checkCancel();
      _logLines.add('Words: ${words.length}');
      _logLines.add('ASR: OK');

      final resolvedLanguage = resolveDetectedLanguage(words, hint: input.language);
      _logLines.add('Language: $resolvedLanguage');

      // ---- segmentation (§二十二) -------------------------------------------
      _setStage(LessonJobStage.segmenting);
      final drafts = await bench.stage(
        'segment',
        () async => SegmentationService.segment(words),
      );
      sentenceCount = drafts.length;
      if (drafts.length < 3) {
        // Same guard as the PC pipeline: unusable transcription.
        throw CreationException(
          CreationError.asrError,
          'only ${drafts.length} sentences, transcription unusable',
        );
      }
      _logLines.add('Sentences: ${drafts.length}');

      // ---- translation (§二十四/§二十五) ------------------------------------
      _setStage(LessonJobStage.translating);
      List<String> translations;
      try {
        translations = await bench.stage(
          'translate',
          () => translationEngine.translate(
            [for (final draft in drafts) draft.text],
            sourceLanguage: resolvedLanguage,
          ),
        );
        _logLines.add('Translation: OK');
      } catch (error, stackTrace) {
        // PC-parity behaviour: a translation failure keeps the lesson with
        // empty Chinese instead of throwing the whole lesson away.
        debugPrint('[ListenLoop] translation failed: $error\n$stackTrace');
        translations = List.filled(drafts.length, '');
        _logLines.add('Translation: FAILED (empty chinese kept)');
      }
      await _checkCancel();

      // ---- packaging + import (§二十七/§二十八) ------------------------------
      _setStage(LessonJobStage.packaging);
      // Link inputs have NO local path — basename would crash on `input.path!`
      // (real-device crash 2026-09-18: the whole YouTube pipeline ran to the
      // end and died here).
      final baseName =
          linkTitle.isNotEmpty
          ? linkTitle
          : biliInfo?.title ??
                (input.path != null
                    ? p.basenameWithoutExtension(input.path!)
                    : '链接课程');
      final lessonId =
          'mobile-${DateTime.now().millisecondsSinceEpoch}-$_jobSeq';
      final title = input.titleHint ?? baseName;
      final audioFileName = input.kind == LessonInputKind.link
          ? 'audio.m4a'
          : 'audio${p.extension(input.path!).toLowerCase()}';
      LessonPackager.validate(
        drafts: drafts,
        translations: translations,
        audioDurationMs: audioDurationMs,
      );
      final package = LessonPackager.package(
        lessonId: lessonId,
        title: title,
        drafts: drafts,
        translations: translations,
        audioBytes: await File(sourcePath).readAsBytes(),
        audioFileName: audioFileName,
        language: resolvedLanguage,
        video: videoSource,
        audioDurationMs: audioDurationMs,
      );
      final lesson = await bench.stage(
        'package',
        () => repository.importPackage(package),
      );
      _logLines.add('Packaging: OK');
      final elapsed = DateTime.now().difference(startedAt);
      _logLines.add('Total: ${_mmss(elapsed.inMilliseconds)}');

      _result = lesson;
      _setStage(LessonJobStage.completed);
      return lesson;
    } on CreationException catch (error) {
      _fail(error.code, error.message);
      return null;
    } catch (error, stackTrace) {
      debugPrint('[ListenLoop] creation job failed: $error\n$stackTrace');
      _fail(CreationError.mediaError, '$error');
      return null;
    } finally {
      // Creation V2 §十三: one benchmark line per job, success or failure —
      // a failed job's stage timings are exactly what tells us where it
      // stalled. Emitted before cleanup so the numbers survive the temp purge.
      bench.stopSampling();
      final benchLine = bench.toLogLine(
        totalMs: DateTime.now().difference(startedAt).inMilliseconds,
        sentenceCount: sentenceCount,
      );
      _logLines.add('Bench: $benchLine');
      debugPrint('[ListenLoop][bench] $benchLine');

      // §四十四/§四十五: clean the derived temp files, never the user's
      // original media file.
      final dir = jobDir;
      if (dir != null) {
        try {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } catch (error) {
          debugPrint('[ListenLoop] job cleanup failed: $error');
        }
      }
      // file_picker keeps a full COPY of every picked file in its own cache
      // (real-device evidence: 326 MB after a few imports). The job is over —
      // the copy is dead weight and the plugin offers the removal API.
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (error) {
        debugPrint('[ListenLoop] picker cache cleanup failed: $error');
      }
      notifyListeners();
    }
  }

  /// §四十四: cancel is best-effort — honoured between pipeline steps and
  /// polled by the ASR engine where supported.
  void cancel() {
    if (!isBusy) return;
    _cancelRequested = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ internals --

  void _setStage(LessonJobStage stage) {
    _stage = stage;
    _stageProgress = 0;
    notifyListeners();
  }

  Future<void> _checkCancel() async {
    if (!_cancelRequested) return;
    throw const CreationException(CreationError.cancelled, 'job cancelled');
  }

  /// Cancel guard usable INSIDE the download progress callbacks: throwing
  /// here aborts the streaming transfer immediately (await-for closes the
  /// HTTP stream), instead of letting a minutes-long download run to the end
  /// before the next stage boundary notices (user report 2026-09-18).
  void _cancelDuringDownload() {
    if (!_cancelRequested) return;
    throw const CreationException(CreationError.cancelled, 'job cancelled');
  }

  void _fail(CreationError code, String message) {
    // The raw message goes to the debug log; the UI translates the CODE via
    // LLStrings so error copy follows the UI language.
    debugPrint('[ListenLoop] creation failed (${code.name}): $message');
    _errorCode = code;
    _errorMessage = message;
    _stage = code == CreationError.cancelled
        ? LessonJobStage.cancelled
        : LessonJobStage.failed;
    _logLines.add('Failed: $message');
    debugPrint('[ListenLoop] creation log:\n${_logLines.join('\n')}');
    notifyListeners();
  }
}

String _mmss(int durationMs) {
  final minutes = durationMs ~/ 60000;
  final seconds = (durationMs % 60000) ~/ 1000;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// One Creation Benchmark sample (spec Creation V2 §十三/§三十九).
///
/// Records per-stage wall clock, the peak resident set size observed while
/// the job ran, and the derived real-time factor. The baseline this produces
/// is the only thing that may justify a later optimisation (§五十三:
/// "Measure first, optimize second"), so it is deliberately passive —
/// no behaviour depends on it.
class _Benchmark {
  final Map<String, int> _stageMs = {};
  int _peakRssBytes = 0;
  int _ticks = 0;
  Timer? _sampler;

  /// Total WAV duration, known once decoding finished.
  int audioDurationMs = 0;

  /// Sampling on a timer rather than at stage boundaries: the memory spike
  /// lives *inside* the ASR decode, so a boundary-only reading would miss it.
  ///
  /// It also LOGS every ~2 s. A job that gets killed by the system never
  /// reaches [toLogLine], so for those the only record of how far memory
  /// climbed is what was printed on the way up.
  void startSampling() {
    _sampleRss();
    _sampler = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _sampleRss();
      if (++_ticks % 4 == 0) {
        debugPrint(
          '[ListenLoop][rss] ${(_peakRssBytes / (1024 * 1024)).round()} MB',
        );
      }
    });
  }

  void stopSampling() {
    _sampler?.cancel();
    _sampler = null;
    _sampleRss();
  }

  void _sampleRss() {
    final rss = ProcessInfo.currentRss;
    if (rss > _peakRssBytes) _peakRssBytes = rss;
  }

  /// Times one pipeline stage. Stages repeat (the audio stage has a decode
  /// and a probe) so durations accumulate rather than overwrite.
  Future<T> stage<T>(String name, Future<T> Function() body) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await body();
    } finally {
      stopwatch.stop();
      _stageMs[name] = (_stageMs[name] ?? 0) + stopwatch.elapsedMilliseconds;
    }
  }

  /// `audio=286000ms decode=2100ms asr=32400ms ... total=43600ms rtf=0.152`
  String toLogLine({required int totalMs, int? sentenceCount}) {
    final stages = _stageMs.entries
        .map((entry) => '${entry.key}=${entry.value}ms')
        .join(' ');
    final rtf = audioDurationMs <= 0
        ? 0.0
        : totalMs / audioDurationMs;
    final sentences = sentenceCount == null ? '' : ' sentences=$sentenceCount';
    return 'audio=${audioDurationMs}ms $stages total=${totalMs}ms '
        'rtf=${rtf.toStringAsFixed(3)}$sentences '
        'peakRssMb=${(_peakRssBytes / (1024 * 1024)).round()}';
  }
}

String? _extractYouTubeId(String input) {
  final url = extractUrl(input) ?? input.trim();
  final uri = Uri.tryParse(url);
  if (uri != null) {
    if (uri.host.contains('youtu.be')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) return segments.first;
    }
    if (uri.host.contains('youtube.com')) {
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }
      for (final segment in ['embed', 'shorts', 'live']) {
        final idx = uri.pathSegments.indexOf(segment);
        if (idx != -1 && idx + 1 < uri.pathSegments.length) {
          return uri.pathSegments[idx + 1];
        }
      }
    }
  }
  final match = RegExp(r'(?:v=|\/)([0-9A-Za-z_-]{11})(?:[?&/#]|$)').firstMatch(url);
  return match?.group(1);
}

/// Resolves lesson language code based on transcription words or explicit hint.
String resolveDetectedLanguage(List<WordTimestamp> words, {String? hint}) {
  if (hint != null && hint.trim().isNotEmpty) return hint.trim().toLowerCase();
  var kanaCount = 0;
  var cjkCount = 0;
  var latinCount = 0;
  for (final w in words) {
    for (final rune in w.word.runes) {
      // Hiragana: 0x3040-0x309F, Katakana: 0x30A0-0x30FF
      if ((rune >= 0x3040 && rune <= 0x309F) || (rune >= 0x30A0 && rune <= 0x30FF)) {
        kanaCount++;
      } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
        cjkCount++;
      } else if ((rune >= 0x0041 && rune <= 0x005A) || (rune >= 0x0061 && rune <= 0x007A)) {
        latinCount++;
      }
    }
  }
  // Presence of Japanese Kana indicates Japanese speech
  if (kanaCount >= 2) return 'ja';
  // Predominantly Chinese characters without Kana
  if (cjkCount > latinCount * 2 && cjkCount > 10) return 'zh';
  return 'en';
}

