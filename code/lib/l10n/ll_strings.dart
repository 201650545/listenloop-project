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

  /// 界面语言判定（供新页面复用，避免各自硬编码中英判断）。
  bool get isZh => _isZh;

  // -------------------------------------------------------------- vocab ----
  // 生词本（附属层）：入口开在三级。文案遵循 10 号文档红线 ——
  // 点词只「存」不「查」；释义必须由用户第二个主动动作打开。
  String get more => _isZh ? '更多' : 'More';
  String get vocabAccumulation => _isZh ? '生词积累模式' : 'Vocabulary mode';
  String get vocabAccumulationHint => _isZh
      ? '开启后字幕逐词可点：点一下存入候选，再点取消。不暂停、不弹释义'
      : 'Tap words to collect them; tap again to remove. Playback never stops';
  String get vocabSaved => _isZh ? '已存' : 'Saved';
  String get vocabPhraseHint => _isZh
      ? '长按拖动还能圈短语（2–5 个词），如 take off'
      : 'Long-press and drag to collect a phrase (2–5 words), e.g. take off';
  String get vocabRemoved => _isZh ? '已取消' : 'Removed';

  String vocabCandidateCount(int count) =>
      _isZh ? '候选池 $count 个词' : '$count candidates';

  // 生词本管理页（Library 二级）。枚举一律走 key 映射 —— l10n 不依赖模型层。
  String get vocabBook => _isZh ? '生词本' : 'Vocabulary';
  String get vocabTodayPlan => _isZh ? '今日计划' : "Today's plan";
  String get vocabAll => _isZh ? '全部' : 'All';
  String get vocabEmpty => _isZh
      ? '还没有生词。在精听页「更多」里开生词积累模式，点字幕里的词即可保存。'
      : 'Nothing saved yet. Turn on Vocabulary mode under More in the listening page, then tap words.';
  String get vocabNoItemsForFilter => _isZh ? '这一栏还是空的' : 'Nothing in this filter yet';
  String get vocabTodayPlanEmpty => _isZh
      ? '今天没有需要练的词 —— 只有出现听写错误、或已到复习期的词才会进入计划'
      : 'Nothing to drill today — only words with dictation evidence or a due review enter the plan';
  String get vocabEvidence => _isZh ? '上下文证据' : 'Evidence';
  String get vocabReason => _isZh ? '依据' : 'Why';
  String get vocabSuggest => _isZh ? '建议' : 'Suggested';
  String get vocabOpenOriginal => _isZh ? '回原声' : 'Play original';
  String get vocabLessonMissing =>
      _isZh ? '这门课程已不在本机' : 'That lesson is no longer on this device';
  String get vocabStartLearning => _isZh ? '加入学习' : 'Start learning';
  String get vocabMarkKnown => _isZh ? '标记已掌握' : 'Mark known';
  String get vocabIgnore => _isZh ? '忽略' : 'Ignore';
  String get vocabDelete => _isZh ? '删除词条' : 'Delete';
  String get vocabRestore => _isZh ? '移回候选池' : 'Back to candidates';

  /// 汇总条：三个数字一次说清。
  String vocabSummary(int candidates, int learning, int known) => _isZh
      ? '候选 $candidates · 学习中 $learning · 已掌握 $known'
      : '$candidates candidates · $learning learning · $known known';

  String vocabSeenTimes(int count) =>
      _isZh ? '遇到 $count 次' : 'seen $count×';

  String vocabSentenceAt(String lesson, int index) =>
      _isZh ? '$lesson · 第 $index 句' : '$lesson · sentence $index';

  String vocabStatusLabel(String key) {
    switch (key) {
      case 'candidate':
        return _isZh ? '候选池' : 'Candidates';
      case 'learning':
        return _isZh ? '学习中' : 'Learning';
      case 'known':
        return _isZh ? '已掌握' : 'Known';
      case 'ignored':
        return _isZh ? '已忽略' : 'Ignored';
      default:
        return '';
    }
  }

  String vocabSourceLabel(String key) {
    switch (key) {
      case 'tap':
        return _isZh ? '点存' : 'tapped';
      case 'dictation':
        return _isZh ? '听写' : 'dictation';
      case 'ai':
        return _isZh ? 'AI' : 'AI';
      default:
        return '';
    }
  }

  /// 学习组件名（v1 白名单）。
  String planComponentLabel(String key) {
    switch (key) {
      case 'originalRelisten':
        return _isZh ? '回原声' : 'Relisten';
      case 'dictationRetry':
        return _isZh ? '重听写' : 'Dictate again';
      case 'clozeRecall':
        return _isZh ? 'Cloze 回忆' : 'Cloze recall';
      case 'morphologyNote':
        return _isZh ? '形态纠错' : 'Word form';
      case 'srsReview':
        return _isZh ? 'SRS 复习' : 'SRS review';
      default:
        return '';
    }
  }

  /// 计划原因 —— 每条建议都必须说得出依据（验收标准 2）。
  String planReasonLabel(String key) {
    switch (key) {
      case 'reliableHearing':
        return _isZh ? '听写漏词/替换' : 'missed or swapped in dictation';
      case 'extraOnly':
        return _isZh ? '听写多写了原文没有的词' : 'wrote words that were not there';
      case 'spellingOnly':
        return _isZh ? '只是拼写，不代表没听清' : 'spelling only — hearing is fine';
      case 'morphologyOnly':
        return _isZh ? '词尾形态没听出' : 'word form missed';
      case 'uncertainOnly':
        return _isZh ? '听写对齐不可靠，只回原声' : 'dictation alignment unreliable — relisten only';
      case 'tapOnly':
        return _isZh ? '仅手动收藏，先留在候选池' : 'saved by hand only — stays in candidates';
      case 'knownDue':
        return _isZh ? '已掌握且到了复习期' : 'known and due for review';
      default:
        return '';
    }
  }


  // ------------------------------------------------------------- drill ----
  // 学习组件执行页（附属层，v1 全部本地判定）。两条文案纪律：
  //   ① 自评必须写成自评，不得伪装成测量结果；
  //   ② 听写回执要区分「拼写差一点」与「写成别的词」——两类问题不同。
  String get drillTitle => _isZh ? '练习' : 'Practice';
  String get drillRelistenTitle => _isZh ? '先听原声' : 'Listen first';
  String get drillRelistenBody => _isZh
      ? '用原片音频再听一遍。这一步没有客观对错，按你的自评记录。'
      : 'Replay the original audio. There is no objective check here — recorded as your own call.';
  String get drillSelfReported => _isZh ? '自评' : 'self-reported';
  String get drillListenedOk => _isZh ? '听清了' : 'Got it';
  String get drillNotYet => _isZh ? '还有没听出的' : 'Not yet';
  String get drillPlay => _isZh ? '播放原声' : 'Play original';
  String get drillReplay => _isZh ? '再播一遍' : 'Play again';
  String get drillNoAudio =>
      _isZh ? '这一课的音频不在本机，无法回听' : 'Audio is not on this device';
  String get drillDictationTitle => _isZh ? '听写这一句' : 'Dictate this sentence';
  String get drillDictationBody =>
      _isZh ? '提交之前不会显示原文' : 'The original stays hidden until you submit';
  String get drillWriteHere => _isZh ? '写下你听到的句子…' : 'Type what you hear…';
  String get drillSubmit => _isZh ? '提交' : 'Submit';
  String get drillRetry => _isZh ? '再写一次' : 'Try again';
  String get drillNext => _isZh ? '下一步' : 'Next';
  String get drillFinish => _isZh ? '完成' : 'Done';
  String get drillStart => _isZh ? '开始' : 'Start';

  // ------------------------------------------------------------ review ----
  // 闪卡复习（Item 级，一个词一张卡）。文案纪律同上：不夸大、不假装测量。
  String get reviewTitle => _isZh ? '闪卡复习' : 'Flashcards';
  String get reviewReveal => _isZh ? '看答案' : 'Show answer';
  String get reviewAgain => _isZh ? '忘了' : 'Again';
  String get reviewHard => _isZh ? '有点难' : 'Hard';
  String get reviewGood => _isZh ? '记得' : 'Good';
  String get reviewEasy => _isZh ? '太简单' : 'Easy';
  String get reviewEmptyTitle => _isZh ? '今天没有到期的卡' : 'Nothing due today';
  String get reviewEmptyBody => _isZh
      ? '把候选词加入学习队列后，到期的卡会出现在这里。'
      : 'Move candidates into the learning queue and due cards show up here.';
  String get reviewDone => _isZh ? '完成' : 'Done';
  String get reviewSkip => _isZh ? '跳过' : 'Skip';
  String get reviewNewCard => _isZh ? '新卡' : 'New';
  String get reviewNoContext => _isZh
      ? '这张卡没有上下文，只能凭记忆回想。'
      : 'No context on this card — recall from memory.';
  String get reviewStart => _isZh ? '复习' : 'Review';
  String get reviewFrontHint =>
      _isZh ? '先回想，再翻面' : 'Recall first, then flip';

  String reviewProgress(int current, int total) =>
      _isZh ? '第 $current / $total 张' : '$current / $total';

  String reviewEntry(int count) =>
      _isZh ? '闪卡复习 · $count 张到期' : 'Flashcards · $count due';

  String reviewSummary(int count) =>
      _isZh ? '本轮复习了 $count 张' : 'Reviewed $count this round';

  /// 下次到期时间：`again` 是 10 分钟，其余按天。
  String reviewNextDue(int days) => days <= 0
      ? (_isZh ? '下次：10 分钟后' : 'Next: in 10 min')
      : (_isZh ? '下次：$days 天后' : 'Next: in $days d');
  String get drillClozeTitle => _isZh ? '回忆这个词' : 'Recall the word';
  String get drillClozeBody =>
      _isZh ? '把空填上（只判这个词）' : 'Fill the blank (only this word is judged)';
  String get drillClozeHere => _isZh ? '填写这个词…' : 'Type the word…';
  String get drillMorphTitle => _isZh ? '词尾形态' : 'Word form';
  String get drillMorphBody => _isZh
      ? '这次错在词尾形态，不是没听出来 —— 重听帮不上忙。'
      : 'This was a word-form slip, not a listening miss — replaying will not help.';
  String get drillMorphYouWrote => _isZh ? '你写的是' : 'You wrote';
  String get drillMorphCorrect => _isZh ? '正确形态' : 'Correct form';
  String get drillAck => _isZh ? '记住了' : 'Got it';
  String get drillNoSteps =>
      _isZh ? '这个词现在不需要练习' : 'Nothing to drill for this word yet';
  String get drillUncertainNote => _isZh
      ? '对齐不可靠，只给整体结果'
      : 'Alignment unreliable — overall result only';

  String drillProgress(int current, int total) =>
      _isZh ? '第 $current / $total 步' : 'Step $current / $total';

  String drillAccuracy(int percent) =>
      _isZh ? '准确率 $percent%' : '$percent% correct';

  String drillHint(String key) {
    switch (key) {
      case 'exact':
        return _isZh ? '正确' : 'Correct';
      case 'spelling':
        return _isZh ? '差一点拼写 —— 听清了，是词形没记准' : 'Spelling — you heard it, the form slipped';
      case 'wrongWord':
        return _isZh ? '写成了别的词' : 'That was a different word';
      case 'blank':
        return _isZh ? '没有作答' : 'Left blank';
      case 'partial':
        return _isZh ? '对了一部分' : 'Partly right';
      case 'alignment':
        return _isZh ? '对齐不可靠，只给整体结果' : 'Alignment unreliable — overall only';
      default:
        return '';
    }
  }

  // --------------------------------------------------------- dictation ----
  // 听写（核心层 P1）：句级录入、段级集中批改。文案遵循 08 定调——
  // 第二层原因只能写成「可能与…有关」，不得渲染成确定结论。
  String get dictation => _isZh ? '听写' : 'Dictation';
  String get dictationIntro => _isZh
      ? '听不清就留空，写完整段再对答案'
      : 'Leave blanks for what you miss — answers come after the segment';
  String get dictationUnknown => _isZh ? '没听出来' : "Couldn't catch it";
  String get done => _isZh ? '完成' : 'Done';
  String get dictationClearUnknown => _isZh ? '取消留空' : 'Unmark';
  String get dictationSubmit => _isZh ? '提交本段' : 'Submit segment';
  String get dictationReplay => _isZh ? '重放本句' : 'Replay';
  String get dictationPrevious => _isZh ? '上一句' : 'Previous';
  String get dictationNext => _isZh ? '下一句' : 'Next';
  String get dictationRewrite => _isZh ? '重写本段' : 'Redo segment';
  String get dictationNextSegment => _isZh ? '下一段' : 'Next segment';
  String get dictationAccuracy => _isZh ? '准确率' : 'Accuracy';
  String get dictationBlankCount => _isZh ? '留空' : 'Blank';
  String get dictationWriteHere => _isZh ? '写下你听到的句子…' : 'Type what you hear…';
  String get dictationAllAnswered => _isZh ? '每句都已交代，可以提交' : 'All lines answered — ready to submit';
  String get dictationRemaining => _isZh ? '还有未交代的句子' : 'Some lines still unanswered';
  String get dictationUncertain => _isZh
      ? '这一段无法精确定位，只给出整体结果'
      : 'Alignment unreliable — overall result only';
  String get dictationYourAnswer => _isZh ? '你的答案' : 'Your answer';
  String get dictationExpected => _isZh ? '原文' : 'Original';
  /// 短标签版（生词本证据行用），与长句版同源但更省空间。
  String get dictationUncertainShort => _isZh ? '对齐不可靠' : 'alignment n/a';
  String get dictationNoPeek => _isZh ? '本段批改前不显示原文' : 'Original hidden until you submit';

  String dictationSegment(int current, int total) =>
      _isZh ? '第 $current / $total 段' : 'Segment $current / $total';

  /// 第二层提示统一出口——**永远带「可能」**。
  String dictationCause(String key) {
    switch (key) {
      case 'weakForm':
        return _isZh ? '可能与弱读有关' : 'possibly weak form';
      case 'liaison':
        return _isZh ? '可能与连读有关' : 'possibly liaison';
      case 'plosion':
        return _isZh ? '可能与失爆有关' : 'possibly incomplete plosive';
      case 'flap':
        return _isZh ? '可能与闪音有关' : 'possibly flap T/D';
      default:
        return '';
    }
  }

  String dictationDiffType(String key) {
    switch (key) {
      case 'missing':
        return _isZh ? '漏词' : 'missed';
      case 'extra':
        return _isZh ? '多写' : 'extra';
      case 'spelling':
        return _isZh ? '拼写近似' : 'spelling';
      case 'morphology':
        return _isZh ? '词尾形态' : 'word form';
      case 'merged':
        return _isZh ? '词边界(合并)' : 'word boundary';
      case 'split':
        return _isZh ? '词边界(拆分)' : 'word boundary';
      case 'replaced':
        return _isZh ? '替换' : 'replaced';
      default:
        return '';
    }
  }

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
