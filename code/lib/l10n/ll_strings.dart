import 'package:flutter/widgets.dart';

import '../creation/creation_errors.dart';
import '../creation/lesson_job_stage.dart';
import '../lesson/lesson_package_exception.dart';
import '../preferences/app_preferences.dart';

/// Minimal hand-rolled UI copy table (follow-up: 中/英界面切换).
///
/// Deliberately NOT flutter_localisations codegen — the surface is small and
/// the brand voice is part of the design. The wordmark `ListenLoop` and font
/// names (Sans/Serif/System) stay untranslated in both languages.
class LLStrings {
  const LLStrings(this.uiLanguage);

  final AppLanguage uiLanguage;

  static LLStrings of(BuildContext context) =>
      LLStrings(PreferencesScope.maybeOf(context).uiLanguage);

  bool get _isZh => uiLanguage == AppLanguage.chinese;

  // ------------------------------------------------------------ shell ----
  String get tabLibrary => _isZh ? '课程' : 'Library';
  String get tabListen => _isZh ? '精听' : 'Listen';
  String get tabCreate => _isZh ? '创建' : 'Create';
  String get tabSettings => _isZh ? '设置' : 'Settings';

  String get listenEmptyTitle => _isZh ? '还没有正在学习的课程' : 'No active lesson.';
  String get listenEmptyBody => _isZh ? '去课程页选一课吧' : 'Choose one from Library.';

  // ----------------------------------------------------------- library ---
  String get import => _isZh ? '＋ 导入' : '＋ Import';
  String get importLesson => _isZh ? '＋ 导入课程' : '＋ Import Lesson';
  String get continueLearning => _isZh ? '继续学习' : 'CONTINUE';
  String get allLessons => _isZh ? '全部课程' : 'LESSONS';
  String get continueCta => _isZh ? '继续 →' : 'Continue →';
  String get filterAll => _isZh ? '全部' : 'ALL';
  String get viewGrid => _isZh ? '海报网格' : 'Grid view';
  String get viewList => _isZh ? '列表视图' : 'List view';
  String get noLessonsInLanguage =>
      _isZh ? '该语种下暂无课程' : 'No lessons in this language.';
  String get noLessonsTitle => _isZh ? '还没有课程' : 'No lessons yet.';
  String get noLessonsBody =>
      _isZh ? '导入第一课，开始精听。' : 'Import your first lesson\nto start listening.';

  String get importing => _isZh ? '正在导入课程…' : 'Importing lesson…';
  String get cannotImportTitle => _isZh ? '无法导入课程' : "Can't import lesson";
  String get importFailed =>
      _isZh ? '导入失败，请重试。' : 'Import failed. Please try again.';
  String imported(Object title) => _isZh ? '导入成功：《$title》' : 'Imported: $title';
  String deleted(Object title) => _isZh ? '已删除《$title》' : 'Deleted: $title';
  String get lessonMissing =>
      _isZh ? '课程不存在，可能已被删除' : 'Lesson not found. It may have been deleted.';

  String get info => _isZh ? '查看信息' : 'Info';
  String get deleteLessonMenu => _isZh ? '删除课程' : 'Delete lesson';
  String get deleteTitle => _isZh ? '删除课程？' : 'Delete lesson?';
  String get deleteBody => _isZh
      ? '将同时删除课程与本地学习进度。'
      : 'This removes the lesson and local learning progress.';
  String get cancel => _isZh ? '取消' : 'Cancel';
  String get delete => _isZh ? '删除' : 'Delete';
  String get close => _isZh ? '关闭' : 'Close';
  String get know => _isZh ? '知道了' : 'OK';
  String get lessonIdLabel => _isZh ? '课程 ID' : 'Lesson ID';
  String get sentenceCountLabel => _isZh ? '句数' : 'Sentences';
  String get audioDurationLabel => _isZh ? '音频时长' : 'Audio duration';
  String get importedAtLabel => _isZh ? '导入时间' : 'Imported';
  String audioDurationMinSec(int minutes, int seconds) =>
      _isZh ? '$minutes 分 $seconds 秒' : '$minutes min $seconds sec';

  String errorText(LessonPackageError code) => switch (code) {
    LessonPackageError.notFound =>
      _isZh ? '找不到所选文件，请重新选择。' : 'The selected file could not be found.',
    LessonPackageError.unreadable => _isZh ? '无法读取该文件，它可能已损坏或不是课程文件。' : 'The file could not be read. It may be damaged or not a lesson package.',
    LessonPackageError.missingManifest =>
      _isZh
          ? '课程包缺少 manifest.json，不是有效的课程文件。'
          : 'The package is missing manifest.json.',
    LessonPackageError.badManifest =>
      _isZh ? '课程信息格式不正确，无法导入。' : 'The lesson manifest is malformed.',
    LessonPackageError.unsupportedVersion =>
      _isZh
          ? '课程包版本不受支持（当前仅支持版本 1）。'
          : 'Unsupported package version (only version 1).',
    LessonPackageError.missingSentences =>
      _isZh ? '课程包缺少句子数据文件。' : 'The package is missing the sentence data file.',
    LessonPackageError.badSentences =>
      _isZh ? '句子数据格式不正确，无法导入。' : 'The sentence data is malformed.',
    LessonPackageError.sentenceCountMismatch =>
      _isZh
          ? '课程信息与句子数量不一致，文件可能已损坏。'
          : 'Sentence count mismatch — the package may be damaged.',
    LessonPackageError.missingAudio =>
      _isZh ? '课程包缺少音频文件。' : 'The package is missing the audio file.',
    LessonPackageError.emptySentences =>
      _isZh ? '这个课程没有任何句子。' : 'This lesson has no sentences.',
  };

  // --------------------------------------------------------- listening ---
  String get prev => _isZh ? '上一句' : 'Prev';
  String get next => _isZh ? '下一句' : 'Next';
  String get retry => _isZh ? '重试' : 'Retry';
  String get fluidText => _isZh ? '流体文本' : 'Fluid text';
  String get singlePageText => _isZh ? '单页文本' : 'Single page';
  String get playbackSpeed => _isZh ? '滑动变速' : 'Playback speed';
  String get loopsPerSentence => _isZh ? '每句循环次数' : 'Loops per sentence';
  String loopTimes(int n) => _isZh ? '$n 次' : '$n×';
  String get loopForever => _isZh ? '无限' : '∞';

  // ---------------------------------------------------------- settings ---
  String get settingsTitle => _isZh ? '设置' : 'Settings';
  String get appearance => _isZh ? '外观' : 'APPEARANCE';
  String get typography => _isZh ? '排版' : 'TYPOGRAPHY';
  String get languageSection => _isZh ? '语言' : 'LANGUAGE';
  String get theme => _isZh ? '主题' : 'Theme';
  String get system => _isZh ? '跟随系统' : 'System';
  String get light => _isZh ? '浅色' : 'Light';
  String get dark => _isZh ? '深色' : 'Dark';
  String get font => _isZh ? '字体' : 'Font';
  String get textSize => _isZh ? '字号' : 'Text size';
  String get textSizeSheet => _isZh ? '滑动调整字号' : 'Text size';
  String get preview => _isZh ? '预览' : 'PREVIEW';

  // ------------------------------------------------------ translation ----
  String get translation => _isZh ? '翻译服务' : 'TRANSLATION';
  String get translationBaseUrl => _isZh ? '接口地址' : 'Endpoint';
  String get translationApiKey => _isZh ? 'API 密钥' : 'API key';
  String get translationModel => _isZh ? '模型' : 'Model';
  String get translationBaseUrlHint =>
      _isZh ? 'https://api.xiaomimimo.com/v1' : 'https://api.xiaomimimo.com/v1';
  String get translationApiKeyHint =>
      _isZh ? '未设置（接口无需鉴权）' : 'Not set (endpoint needs no key)';
  String get translationApiKeyMissing =>
      _isZh ? '未设置密钥，付费服务会返回 401' : 'No key set — paid endpoints will 401';
  String get translationModelSheet =>
      _isZh ? '选择模型' : 'Choose a model';
  String get translationModelSearch =>
      _isZh ? '搜索模型' : 'Search models';
  String get translationModelLoading =>
      _isZh ? '正在读取模型列表…' : 'Loading models…';
  String get translationModelRetry => _isZh ? '重试' : 'Retry';
  String get translationTest => _isZh ? '测试连接' : 'Test connection';
  String get translationTesting => _isZh ? '正在测试…' : 'Testing…';
  String translationTestOk(Object model) =>
      _isZh ? '连接正常 · $model' : 'OK · $model';
  String translationFailed(Object reason) =>
      _isZh ? '失败：$reason' : 'Failed: $reason';
  String get save => _isZh ? '保存' : 'Save';

  // ---------------------------------------------------- youtube relay ----
  String get youtubeRelayTitle =>
      _isZh ? 'YouTube 中继 (PC)' : 'YouTube Relay (PC)';
  String get youtubeRelayBaseUrl =>
      _isZh ? '中继服务地址' : 'Relay Base URL';
  String get youtubeRelayBaseUrlHint =>
      _isZh ? 'http://127.0.0.1:8793 或 局域网 IP' : 'http://127.0.0.1:8793 or LAN IP';
  String get youtubeRelayTest => _isZh ? '测试中继连通性' : 'Test Relay Connection';
  String get youtubeRelayTesting => _isZh ? '正在探测中继…' : 'Testing relay…';
  String get youtubeRelayTestOk =>
      _isZh ? '中继服务连通正常 (/ping 200)' : 'Relay reachable (/ping 200)';
  String youtubeRelayTestFailed(Object reason) =>
      _isZh ? '中继未响应：$reason' : 'Relay unreachable: $reason';
  String get youtubeRelayTip =>
      _isZh
          ? '电脑端运行 python tool/youtube_relay.py。USB 调试需执行 adb reverse tcp:8793 tcp:8793，同 Wi-Fi 局域网可直接填电脑 IP'
          : 'Run python tool/youtube_relay.py on PC. Use adb reverse tcp:8793 tcp:8793 over USB, or enter PC LAN IP over Wi-Fi.';

  // ------------------------------------------------------- ai tutor ------
  String get tutorOnlineTitle =>
      _isZh ? 'AI 伴学 (在线大模型)' : 'AI Tutor (Online LLM)';
  String get tutorBaseUrl => _isZh ? '网关地址' : 'Gateway endpoint';
  String get tutorApiKey => _isZh ? '网关密钥' : 'Gateway key';
  String get tutorModel => _isZh ? '伴学模型' : 'Tutor model';
  String get tutorBaseUrlHint =>
      _isZh ? 'https://api.xiaomimimo.com/v1' : 'https://api.xiaomimimo.com/v1';
  String get tutorApiKeyHint =>
      _isZh ? '未设置（网关无需鉴权时可留空）' : 'Not set (leave empty if unauthenticated)';
  String get tutorPrefillFree =>
      _isZh ? '恢复默认 MiMo 配置' : 'Reset to MiMo defaults';
  String get tutorPrefilled =>
      _isZh ? '已恢复默认 MiMo 配置' : 'MiMo defaults restored';
  String get tutorTest => _isZh ? '测试伴学对话' : 'Test tutor chat';
  String get tutorTesting => _isZh ? '正在等待模型回答…' : 'Awaiting model reply…';
  String tutorTestOk(Object model) =>
      _isZh ? '伴学链路正常 · $model' : 'Tutor reachable · $model';
  String tutorTestFailed(Object reason) =>
      _isZh ? '伴学链路异常：$reason' : 'Tutor unreachable: $reason';
  String get tutorFreeTip =>
      _isZh
          ? '默认直连小米 MiMo（mimo-v2.6-flash），手机无需电脑、无需 adb 映射，失败自动回退到同厂其它档位。翻译与伴学共用同一模型。'
          : 'Talks to Xiaomi MiMo (mimo-v2.6-flash) directly — no PC, no adb reverse — and falls back across MiMo tiers on failure. Translation shares the same model.';

  // --------------------------------------------------------- creation ----
  String get createLesson => _isZh ? '制作课程' : 'Create Lesson';
  String get creationMenuImport => _isZh ? '导入课程' : 'Import Lesson';
  String get creationMenuFromFile => _isZh ? '从本地文件创建' : 'Create from File';
  String get creationMenuFromLink => _isZh ? '从链接创建' : 'Create from Link';
  String get soon => _isZh ? '即将支持' : 'soon';
  String get creationBusy =>
      _isZh ? '已有课程正在制作' : 'A lesson is already being created.';
  String get viewProgress => _isZh ? '查看进度' : 'View Progress';
  String get cancelCreation => _isZh ? '取消制作' : 'Cancel';
  String get lessonReady => _isZh ? '课程完成' : 'Lesson Ready';
  String get startListening => _isZh ? '开始精听' : 'Start Listening';
  String get elapsed => _isZh ? '已用时' : 'elapsed';
  String sentencesReady(int n) => _isZh ? '$n 句' : '$n sentences';
  String get sourceLabel => _isZh ? '来源' : 'Source';

  String stageName(LessonJobStage stage) => switch (stage) {
    LessonJobStage.queued => _isZh ? '排队中' : 'Queued',
    LessonJobStage.acquiringMedia => _isZh ? '获取媒体' : 'Acquiring media',
    LessonJobStage.preparingAudio => _isZh ? '准备音频' : 'Preparing audio',
    LessonJobStage.transcribing => _isZh ? '转写中' : 'Transcribing',
    LessonJobStage.segmenting => _isZh ? '分句中' : 'Segmenting',
    LessonJobStage.translating => _isZh ? '翻译中' : 'Translating',
    LessonJobStage.packaging => _isZh ? '打包中' : 'Packaging',
    LessonJobStage.completed => _isZh ? '已完成' : 'Completed',
    LessonJobStage.failed => _isZh ? '失败' : 'Failed',
    LessonJobStage.cancelled => _isZh ? '已取消' : 'Cancelled',
  };

  String errorMessage(CreationError code) => switch (code) {
    CreationError.inputError => _isZh ? '输入无效。' : 'Invalid input.',
    CreationError.mediaError =>
      _isZh ? '无法处理该媒体文件。' : 'Could not process this media file.',
    CreationError.asrError => _isZh ? '转写失败。' : 'Transcription failed.',
    CreationError.translationError => _isZh ? '翻译失败。' : 'Translation failed.',
    CreationError.packageError => _isZh ? '打包失败。' : 'Packaging failed.',
    CreationError.storageError =>
      _isZh ? '存储空间不足。' : 'Not enough free storage.',
    CreationError.cancelled => _isZh ? '已取消。' : 'Cancelled.',
  };
}
