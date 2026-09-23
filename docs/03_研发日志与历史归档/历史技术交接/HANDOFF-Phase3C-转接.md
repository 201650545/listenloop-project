# HANDOFF · Phase 3C（Audio / Video 双模式切换）转接

> 上一会话额度耗尽前中断。本文件是**唯一权威交接**，接手后先读它，再读 `HANDOFF-v0.2.1-转接.md` 与 `开发日志.md`。
> 日期：2026-09-16 夜 | 分支 `main` | HEAD `f274214`（工作树**不干净**，见 §1）

---

## 0. 一句话现状

Phase 3C **尚未开始写代码**（只新建了 1 个文件，未接线、未提交）。
上一个「默认循环改 ×1」需求**已全部完成、真机验收、已提交**（`f274214`），不要再动。

---

## 1. 当前 git 状态（接手第一步请核对）

```
分支: main
HEAD: f274214  feat(listening): default to ×1 repeat instead of infinite
工作树: ?? lib/player/playback_mode.dart   ← 我在中断前刚新建、还是 untracked
```

`lib/player/playback_mode.dart` 内容（**已写好，可直接用**）：

```dart
/// Which playback source the listening screen is currently driving
/// (Phase 3C §3).
enum PlaybackMode {
  /// Local audio engine (always available — the default on entry).
  audio,

  /// Embedded video player (only selectable when the lesson carries a
  /// [VideoSource]).
  video,
}
```

> 接手建议：保留该文件（正是 Phase 3C §3 要求的单枚举状态模型），继续往下做；或先 `git stash`/删除后重写亦可。**不要**把它误当成已完成的接线。

---

## 2. Phase 3C 目标（用户规格书摘要）

同一 Lesson 支持 **Audio（默认）/ Video（可选）** 两种播放模式，共享**唯一** `currentSentenceIndex` 与 Repeat Mode。

硬性要求（完整规格见用户消息，此处提炼必须落地的点）：

| # | 要求 | 关键 |
|---|---|---|
| 2 | 进课程**默认 Audio** | 有 `video_json` 也**不自动进视频** |
| 3 | Media Area 附近加 `Audio \| Video` 轻量切换 UI | 当前模式高亮；无有效视频源时**不显示或 disabled**（不许点了才报错） |
| 4 | Audio→Video | ①pause 音频 ②保持 index ③初始化/激活 video ④`video.seekTo(sentence[i].startMs)` ⑤启动视频 ⑥字幕仍显示当前句 |
| 5 | Video→Audio | ①pause video ②保持 index ③audio.seekTo(startMs) ④播放 ⑤保持 repeat |
| 6 | **唯一** `currentSentenceIndex` | 禁止 `audioSentenceIndex`/`videoSentenceIndex` 双份 |
| 7 | Repeat Mode 跨模式共享 | 不许 audio/video 各存一份 |
| 8 | ×1 Video 行为 | 播到 end → 进下一句 → seek → 继续；**验证 index 不漂移** |
| 9 | ∞ Video 行为 | 播到 end → seek 回本句 start → 继续 |
| 10 | Prev/Next + 左右滑动 | Video Mode 同样有效 |
| 11 | 字幕共用现有 Fluid/Single/Transcript | `currentSentence → UI`；**视频不得自维护字幕** |
| 12 | 倍速 | Video 若可靠支持则同倍速，否则**不改架构**；报告标 `PASS/PARTIAL/UNSUPPORTED` |
| 13 | 状态用 `PlaybackMode.audio`/`.video` 枚举 | **禁止多布尔组合** |
| 14 | Source Ownership | 切模式**旧播放器先 pause 再激活新播放器**，任意时刻只有一个 Active Source |
| 15 | 生命周期 | Video→Home 必须停；Video→Background 循既定策略（不得偷偷继续出声）；Lesson 切换须释放旧 Video Player，旧 WebView/JS callback 不得干扰新课 |
| 16 | 进度字段不变 | 继续只存 lessonId/currentSentenceIndex/repeatTarget/playbackRate/subtitleMode/displayMode；`lastPlaybackMode` **第一版不保存**（重进仍 Audio） |
| 17 | 无视频课程 | 行为与本版**完全一致**（Regression Requirement） |
| 18 | Video 初始化失败 | 非阻塞错误 + 允许 Return to Audio；Audio 仍可用 |
| 19 | **禁止修改** | faster-whisper / 制课 Pipeline / Translation / `.lllesson` 核心格式 / SQLite migration（除非真需要字段）/ Local Audio 已验收边界算法 / Sentence 数据模型核心 / Library UI 大改 / 循环算法大重构 |
| 22 | 质量门禁 | `dart format .` + `flutter analyze`（0）+ `flutter test`（**≥80 全绿**，且**必须为 PlaybackMode/切换行为新增测试**） |
| 23 | 真机验收 | 必须在**小米 14** |
| 24 | DoD | 规格书 §24 的 19 项清单全过 |
| 25 | 完成后**只提交 Phase 3C Report** | 停止，不碰 YouTube/Studio/Qwen/WhisperX/单词/云同步 |

**Phase 3C Report 必须含**：修改文件 / 状态模型 / 新增测试 / 测试总数 / 真机验证结果 / 视频倍速支持情况（PASS·PARTIAL·UNSUPPORTED）/ 已知问题 / Git commit。

---

## 3. 已收敛的架构方向（推荐方案，已论证）

**在 `SentencePlayerController` 内做切换，不新建独立代理 facade。**

关键理由：`_currentIndex`、`_repeatTarget`、watchdog、`_generation` 都是 controller 字段 → index 与 repeat **天然共享**，无需跨对象同步。视频侧的 `VideoPlaybackFacade` 已经 `implements AudioPlayerFacade`（Phase 3B 成果），所以"切换播放源"就是切换 controller 持有的 facade 引用。

### 3.1 改动点

**`lib/player/sentence_player_controller.dart`**（515 行）

- `final AudioPlayerFacade _facade;` → 改为可变 `AudioPlayerFacade _facade;`
- 新增字段：`final AudioPlayerFacade? _videoFacade;`、`PlaybackMode _mode;`
  （建议把 audio 侧也显式命名 `_audioFacade`，可读性更好）
- 构造签名改为：
  ```dart
  SentencePlayerController({
    required AudioPlayerFacade audioFacade,
    AudioPlayerFacade? videoFacade,          // 新增
    PlaybackMode initialMode = PlaybackMode.audio,  // 新增
    required List<Sentence> sentences,
    required String audioAsset,
    this.audioIsFile = false,
    this.initialSentenceIndex = 0,
    this.initialPlaybackRate = 1.0,
    this.initialRepeatTarget = 1,
  })
  ```
- 新增公开 getter：`PlaybackMode get playbackMode => _mode;`、`bool get hasVideoSource => _videoFacade != null;`
- 新增 `Future<void> setPlaybackMode(PlaybackMode mode)`：
  1. 若 `mode == _mode` 或（`mode == video` 且 `_videoFacade == null`）→ **忽略 return**
  2. `_generation++`；取消 `_watchdog`；记录 `wasPlaying = _isPlaying`
  3. `await _facade.pause()`（**旧源先 pause**，满足 §14）
  4. 取消旧 facade 的 `_positionSub`/`_errorSub`（同步 cancel）
  5. `_facade = (mode == video ? _videoFacade! : _audioFacade)`
  6. 重新 `_facade.positionStream.listen(_onPosition)` / `_facade.errorStream.listen(_onAudioError)`
  7. 若目标 facade **未初始化** → `audioIsFile ? setFilePath(_assetPath) : setAsset(_assetPath)`
     （视频侧 `setAsset` 会 load URL + 注入 harness + 等 metadata；audio 侧正常加载）
  8. `await _facade.seek(Duration(milliseconds: currentSentence.startMs))`
  9. `_currentPosition = start`；(若 `_playbackRate != 1.0`) `await _facade.setSpeed(_playbackRate)` ← 保证倍速跨模式保持
  10. `wasPlaying ? (play + _startWatchdog) : (_isPlaying = false)`
  11. `_mode = mode; notifyListeners();`
- `dispose()`：**两个 facade 都要释放**（`unawaited(_audioFacade.dispose()); unawaited(_videoFacade?.dispose());`）
- 所有既有 `_facade.xxx` 调用**无需改动**（自然跟随当前源）
- 已有 `_isInitialized` 语义需复核：切换后若目标源未就绪，`isInitialized`/`isSwitchingSource` 要给 UI 一个 loading 信号（视频加载 1–3s）

**`lib/screens/listening_screen.dart`**（533 行）

- **现在的问题代码（`initState`，行 110–126）**：根据 `videoSource != null` **二选一** 决定 facade，视频课直接就用 VideoPlaybackFacade → 违反 §2「默认 Audio」。
  ```dart
  final facade = widget.audioFacade ??
      (videoSource != null
          ? (_videoFacade = VideoPlaybackFacade(source: videoSource))
          : JustAudioFacade());
  ```
- **改为**：始终创建 audio facade（`just_audio_facade`），若 `videoSource != null` **另外**惰性创建 `VideoPlaybackFacade` 传入 controller；`initialMode` 默认 `PlaybackMode.audio`。
  - 视频**延迟初始化**：默认 audio 时**不 load 视频**（产品原则），首次切到 video 才 `setAsset/load`。
- Media Area 附近（`Expanded(flex:24)` 段，行 250–267）加 `Audio | Video` 切换控件（建议放媒体区**下方**一条细段或媒体区右上角浮层，避免抢英文句子焦点、单手可点）。
  - 无视频源时不渲染该控件。
- 媒体区渲染（行 256–264）由 `_videoFacade != null` 改为 **`controller.playbackMode == PlaybackMode.video`** 决定显示 `VideoArea` 还是 `MediaArea`。
- 切换按钮 onTap → `await _controller.setPlaybackMode(...)`。
- 若需要 loading，用 `controller.isInitialized`/`hasError`（现有 `loading` 变量在行 200）配合新增 flag。

**`lib/screens/library_screen.dart`**（507 行）
- 行 206–213 已传 `audioAsset/audioIsFile/coverPath/videoSource`，**基本无需改**（只需确保 videoSource 仍透传，模式初始化仍在 screen 内完成即可）。

### 3.2 备选方案（若上面太侵入）

`SwitchingAudioFacade implements AudioPlayerFacade`，内部持有 audio+video 两个 delegate，转发全部方法；controller 完全不感知。**缺点**：位置/错误流要重映射，index/repeat 共享仍需 controller 侧保证，收益不明显。**不推荐**。

---

## 4. 已确认的关键事实（免重复侦察）

- **`AudioPlayerFacade` 接口**（`lib/player/audio_player_facade.dart`，87 行）：`setAsset` / `setFilePath` / `play` / `pause` / `seek(Duration)` / `setSpeed(double)` / `position` / `positionStream` / `errorStream` / `dispose`。`AudioPlaybackError.code` 是 **`int`**。
- **`VideoPlaybackFacade implements AudioPlayerFacade`**（432 行）：内部把 video ms ↔ lesson ms 通过 `offsetMs` 对齐；`controller` getter（行 283–287）仅在 production bridge 可用，否则 `throw StateError`；JS channel `LLVideo`。
- **视频倍速：底层已支持** —— harness JS 有 `case 'rate'` 分支设置 `v.playbackRate`（行 147），且 `tick` 回报 `rate: v.playbackRate`（行 108–109）；`VideoPlaybackFacade.setSpeed` 已 `_command('rate', {'rate': rate})`（行 415）。3A 真机已验证 `播放速率设为 1.25 → 生效 1.25`。→ **报告可标 PASS，但仍须在 3C 真机矩阵里复验一次跨模式保持。**
- **JS op 全集**：`seek / play / pause / rate / position`（行 126–152），未知 op 回 `ack ok:false reason:'unknown-op'`。
- `VideoArea`（50 行）渲染 `WebViewWidget(controller:)`；`MediaArea`（54 行）显示封面或默认音符图。
- 精听页已有开关：`initialSubtitleMode('hidden'/'english'/'bilingual')`、`initialPageMode`、`_loopBadge`（`repeatTarget==0 ? '∞ LOOP' : '×N LOOP'`）、`_showLoopSheet`（key `loop-option-$value`，选项 `1/3/5/10/无限`）、`autoPlay`、`_onControllerChanged`。

### 关键行号速查（截至 `f274214`）

```
lib/screens/listening_screen.dart        533 行
  initState facade 二选一           110-126   ← 3C 核心改动
  _onControllerChanged              142-144
  dispose                           146-152   ← 需同时释放 video facade
  build 头部 / loading               188-200
  媒体区 Expanded(flex:24)           250-267   ← 切换 UI + 渲染分支
  控制区                             329-455
  _loopBadge                        429-453
  _showLoopSheet                    455-490
  错误条 + 重试                      492-533
lib/player/sentence_player_controller.dart 515 行
  构造                                28-46   ← 加 videoFacade/initialMode
  字段 _facade                        48
  _repeatTarget/_generation/_restartPending  80-95
  getters                            103-136
  setRepeatTarget                    144-148
  setSpeed                           153-166   ← 切换后需重放倍速
  initialize                         175-202
  playCurrentSentence                207-243
  replaySentence                     245-268
  pause                              270-289
  next/previousSentence              286-291
  dispose                            299-317  ← 释放两个 facade
  _goToSentence                      319-349
  _onPosition                        351-363
  _finishCurrentSentence             365-437  ← ×1/∞ 循环推进逻辑（复用，勿重构）
  _onAudioError                      439-452
  _startWatchdog                     454-468
lib/player/video_playback_facade.dart    432 行
lib/player/audio_player_facade.dart       87 行
lib/widgets/video_area.dart               50 行
lib/widgets/media_area.dart               54 行
lib/screens/library_screen.dart          507 行（传参 206-213）
```

---

## 5. 测试

现有 **80 tests 全绿**。相关文件：
```
test/player/repeat_mode_test.dart          （默认 ×1 断言已更新）
test/player/sentence_player_controller_test.dart
test/player/video_playback_facade_test.dart （含 FakeBridge）
test/screens/listening_ui_test.dart         （首行断言 ×1 LOOP）
test/screens/listening_screen_test.dart
test/screens/library_screen_test.dart
test/helpers/fake_audio_player_facade.dart  （FakeAudioPlayerFacade，记录 log[]，可 push position/error）
```
3C **必须新增**：`setPlaybackMode` 切换行为单测（默认 audio、audio→video 保持 index、video→audio 保持 index、repeat 跨模式共享、无视频源时忽略切换、切换时旧源先 pause、双 facade dispose、×1/∞ 在 video 下的推进不漂移）。建议新建 `test/player/playback_mode_test.dart`（用 `FakeAudioPlayerFacade` 当 videoFacade 即可，无需真 WebView）。

---

## 6. 环境与真机（每次开终端都要重设）

```bash
export PUB_CACHE="D:/pub-cache"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn   # 缺失会致 Gradle 直连 googleapis 超时
export JAVA_HOME="D:/jdk17"
export ANDROID_SDK_ROOT="D:/android-sdk" ANDROID_HOME="D:/android-sdk"
export JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7890 -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7890 -Dhttp.nonProxyHosts=*.aliyun.com|*.tencent.com|*.flutter-io.cn|*.tsinghua.edu.cn|*.huaweicloud.com|localhost|127.0.0.1|::1"
```
- flutter：`D:/flutter/bin/flutter.bat`（用 `cmd //c "D:\\flutter\\bin\\flutter.bat ..."` 调用）
- adb：`D:/android-sdk/platform-tools/adb.exe`
- 项目根：`D:/listenloop`（**Windows 路径**；不要用 `/mnt/...`、`/c/...`）
- 质量门禁：`dart format .` → `flutter analyze`（要 0）→ `flutter test`（≥80）

**小米 14**：device id `bf6ef967`，app id `com.listenloop.listenloop`，库 `databases/listenloop.db`（**已** `user_version=3`、有 `video_json`、`repeat_target=1`、1 课/36 句、`integrity ok`）
- 装机：`adb install -r code/build/app/outputs/flutter-apk/app-debug.apk`
- 构建：`flutter build apk --debug --target-platform android-arm64`（约 22s）
- 安全改库：`adb push` 到 `/data/local/tmp/` + `adb shell "run-as com.listenloop.listenloop sh -c 'cat /data/local/tmp/x.db > databases/listenloop.db'"`。**严禁 stdin 管道覆盖（会 corrupt）**；`run-as` 读不到 `/sdcard`。
- 视频播放时 `uiautomator dump` 会报 `could not get idle state`（正常）；误触输入法会打断操作——用 `adb shell input keyevent KEYCODE_BACK` 清理（连按两次会退出 App，注意）。
- 精听页控件坐标（1200×2670）：字幕模式 `'隐藏'`(424,2569) / `'英文'`(600,2569) / `'双语'`(776,2569)；循环徽章约 (600,2269)。
- 图片读字用 `mcp__UniAI-Toolkit__analyze_image`。

---

## 7. 接手后建议的最短路径

1. 核对 §1 git 状态；决定如何处置已存在的 `playback_mode.dart`（建议保留）。
2. 按 §3.1 改 `sentence_player_controller.dart`（加 videoFacade/initialMode/setPlaybackMode/dispose 双释放）。
3. 改 `listening_screen.dart`：initState 不再二选一（audio 永远建、video 惰性）、媒体区渲染按 `playbackMode`、加 `Audio | Video` 切换控件（无视频源则不显示）。
4. 新增 `test/player/playback_mode_test.dart`；跑 §6 三门禁。
5. 小米 14 跑规格书 §20 测试矩阵（Audio Only / Video Lesson Audio Mode / Video Mode）+ §21 快速切换压力测试（A→V→A→V→A，查双声/黑屏/旧播放器续播/index 错位/JS 回调串台/Crash/ANR）。
6. 按 §19 复验 `video.playbackRate` 跨模式保持 → 报告标 PASS/PARTIAL/UNSUPPORTED。
7. 写 **Phase 3C Report**（§2 末字段），更新 `开发日志.md`（倒序追加），commit。
8. **停止**，不开始 YouTube/Studio/Qwen/WhisperX/单词/云同步。

---

## 8. 项目铁律 / 冻结令（勿越界）

- 用户：郭老师（启迪潇湘），非技术、中文、**讨厌反复确认**、UAC 敏感、**禁压测/烧额度**；每完成一阶段**必须更新 `开发日志.md`**。
- 文档优先级：**用户直接对话需求 > 外部 AI 方案文档**。
- 冻结不做：Qwen / WhisperX / 新 ASR / 云 / 登录 / 同步 / YouTube 下载依赖 / 词汇 / SRS / 笔记。
- 路线以 `HANDOFF-v0.2.1-转接.md` §4 为准（`03_规划与路线.md` 里 "Phase 3 = YouTube Mode" 已过时）。
- `.lllesson` manifest 保持 `formatVersion:1`；SQLite 现为 v3（幂等迁移）；制课管道冻结（B站→curl→`tool/whisper_to_lesson.py`）。
