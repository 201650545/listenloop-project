# ListenLoop Mobile v0.2.1 — 任务转接文档

**交接时间**：2026-09-16 晚
**交接人**：Claude Code（调度大脑会话）
**接手人**：下一个 Coding Agent
**用户**：郭老师（启迪潇湘培训学校），非技术，中文沟通，讨厌反复确认，UAC 敏感，禁压测/烧额度。**用户直接对话提的需求 > 外部 AI 写的方案文档（须先审验再执行）。**
**Obsidian 记录义务**：每完成一个阶段，必须更新本目录 `开发日志.md`（产品生命线），用户在 Obsidian 里看项目生命。

---

## 0. P0 紧急缺陷（先修这个）

**现象**：用户手机（小米14）升级 v0.2.1 后，打开课程显示 `Unable to load audio`；资料库可能为空（数据回退）。

**根因定位**：`SqfliteLessonRepository.open()` 抛异常（logcat 已捕获栈尾）：

```
SqfliteDatabaseMixin.txnSynchronized → doOpen → openDatabase
← SqfliteLessonRepository.open (lesson_repository.dart:70)
← main (main.dart:12)
```

异常**首行**没抓到（logcat 缓冲被 MIUI 噪音冲掉），需要复现抓全栈：

```bash
ADB="D:/android-sdk/platform-tools/adb.exe"
"$ADB" logcat -c
"$ADB" shell am force-stop com.listenloop.listenloop
"$ADB" shell monkey -p com.listenloop.listenloop -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 4
"$ADB" logcat -d | grep -E "flutter" | head -40   # 看 sqlite 错误首行
```

**最大嫌疑**：`_onUpgrade`（lesson_repository.dart:121-142）v1→v2 的 ALTER TABLE。
v1 真机库由 2A 版创建（learning_progress 当时已有 subtitle_mode + playback_rate），v2 迁移只加 repeat_target + display_mode，理论上不会 duplicate column——但 sqflite 的迁移失败细节以 logcat 首行为准。
**稳妥修法**：每条 ALTER 单独 try-catch（或先 `PRAGMA table_info(learning_progress)` 查列存在再加），保证迁移永不炸掉整个 open()。

**次要后果链**：open() 失败 → main.dart catch → 降级 InMemoryLessonRepository → 资料库空 → 用户此前看到的 "Unable to load audio" 可能是降级前的残留会话/或旧课程音频路径失效。修好 DB 后这些自动消失。

**注意**：git tag `listenloop-mobile-v0.2.1` 打在了**含此 bug** 的 commit（629a46e）上。修完 P0 后：新 commit + 删旧 tag 重打（`git tag -d listenloop-mobile-v0.2.1 && git tag listenloop-mobile-v0.2.1`），并在 Obsidian 开发日志补记 bug 修复。

---

## 1. 项目是什么（30 秒）

AI 精听训练器（ListenLoop）：电脑制课 → 手机离线逐句精听。核心 = Sentence Timeline（完整音频+句时间范围）。当前 v0.2.1 = 可用基线（Library/导入/SQLite/精听页/自动循环/变速/手势/双字幕模式/进度恢复）。

**项目文档（Obsidian 库内）**：`docs/`
- README.md（索引+路径速查）/ 01_项目定义 / 02_项目结构 / 03_规划与路线 / 04_Studio可行性评估 / **开发日志.md（生命线，必须持续更新）**
- 本转接文档也在这个目录。

## 2. 代码与产物

- 代码：`D:\listenloop`（Flutter，git main @ 629a46e + tag，含 .gitignore 忽略 build/dist 大文件）
- APK：`code/build\app\outputs\flutter-apk\app-debug.apk`（已装小米14）
- 课程包：`dist\teded-greek-music.lllesson`（36 句 whisper 真时间轴 + dots3-note-prev 中文 + B站封面）已推手机 `Claude 测试` 和 `Download` 文件夹——**用户需重新导入一次才有封面**
- 测试：70/70 全绿（宿主机），analyze 0 issue

## 3. 环境硬规则（每次开终端都要重来）

```bash
export PUB_CACHE="D:/pub-cache"        # 必须 D 盘，否则 Kotlin 跨盘崩
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export JAVA_HOME="D:/jdk17"
export ANDROID_SDK_ROOT="D:/android-sdk" ANDROID_HOME="D:/android-sdk"
# 代理 7890 只给无国内镜像的国外源；B站/阿里云直连
export JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7890 -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7890 -Dhttp.nonProxyHosts=*.aliyun.com|*.tencent.com|*.flutter-io.cn|*.tsinghua.edu.cn|*.huaweicloud.com|localhost|127.0.0.1|::1"
```

- Flutter：`"D:/flutter/bin/flutter.bat"`；adb：`"D:/android-sdk/platform-tools/adb.exe"`
- **adb push 手机路径必须 `export MSYS_NO_PATHCONV=1`**（否则 Git Bash 把 /sdcard 改写成 D:/Git/sdcard，文件推到不可见位置——血泪教训）
- 手机：小米14（id bf6ef967）；锁屏需用户亲手解指纹（`svc power stayon usb` 可防中途锁）
- 测试文件在手机 `/sdcard/Claude 测试/`（用户自己建的）

## 4. 已完成 vs 待办

### 已完成（v0.2.1 全部功能）
- .lllesson ZIP 包（manifest/sentences 校验、路径穿越防护）+ 导入（FileType.any+内容校验，因小米"安全访问"藏未知扩展名）
- SQLite 四表 + 进度持久化（schema v2：repeat_target/playback_rate/subtitle_mode/display_mode）
- Library：继续学习/我的课程/完整标题/+导入/长按删除/音符图标封面（纯音频规则）
- Listening V0.1 深色重设计：英文主焦点/中文次级/媒体区/顶栏计数+呈现模式切换
- **自动循环**：1(隐)/3/5/10/∞（默认∞）×N 播完自动进下一句，最后一句停；播放中改次数**立即生效**；_restartPending 防位置残留烧次数；playbackGeneration 防竞态
- **Pause/Resume**（V0.2.1）：Pause 停现场，Play 续播；**点字幕=回句首重播**（重听按钮已删）
- 变速：0.75/1.0/1.25 + 长按滑条 0.5~2×（看门狗随倍速缩放）
- 左右滑动切句（右=上一句/左=下一句，整屏手势）
- 字幕双呈现：流体文本⇄单页文本（顶栏按钮，列表点句跳转/当前句点=重播/自动跟随）
- 恢复学习：打开课程回上次句子+自动播放+全部偏好恢复
- 封面规则：视频课=源站封面（B站 view API pic，已入 TED-Ed 包）；纯音频=音符图标
- 封面入包管道：B站 `x/web-interface/view?bvid=` → data.pic → 下载 → manifest.coverFile + dart tool --cover

### 待办（按优先级）
1. **P0：修 DB 迁移 bug**（见 §0）→ 重建 tag → 用户重装验证
2. 用户重导入 TED-Ed 包（B站封面版已推手机）
3. 系统 K 线验证：后台/前台、锁屏解锁、电话中断、耳机断开（不 crash 即可，spec §9）
4. **Phase 3 Video Mode**（外部方案 §13-32 已审验采纳）：先做 Video Playback Prototype（3A：webview 嵌 B站 iframe `player.bilibili.com/player.html?bvid=...&t=秒`，测 10 个时间点 seek 延迟/误差）→ 3B VideoPlaybackController → 3C 模式切换（Audio 默认）。已知限制：iframe 无 JS seek，逐句切换=重载跳时间（1~2s 黑屏）；不做双音轨同步；视频课封面用源站封面
5. v0.3 冻结后 → v0.4 Studio 结构化（words.json/QA/语义分句，见 04 可行性报告）

### 不做（外部方案 §33-34 冻结令）
Qwen/WhisperX/新 ASR/云/登录/同步/YouTube 下载依赖/词汇/SRS/笔记。管道只修明确 bug，不换模型。

## 5. 制课管道（当前冻结，只修 bug）

```
B站视频 → curl(cookie+Referer, 直连) 下 DASH 音频(m4s) → tool/whisper_to_lesson.py
  (faster-whisper small CPU int8, 模型在 dist/models/faster-whisper-small)
  → 词级转写 → 3规则分句(标点/停顿0.9s/35词) → :3100 网关翻译 → 打包 .lllesson
```
- 翻译模型：**dots3-note-prev**（小红书 Dots Note 渠道，免费内测，:3100 统一组已有）。**数数不牢：必须 12 句一批+条数断言+重试**
- yt-dlp 对 B站会被 412/SSL reset 掐死——用 curl（cookie jar 先访问首页获取 buvid3）
- YouTube：出口 IP 被 bot 检测拉黑（9 客户端+PO Token+Invidious+cobalt 全灭）；本会话有 23 分钟重试 cron（会话死即停，接手后如需重建自行 cron）；方向=官方播放而非下载（外部方案 §32）

## 6. 用户偏好铁律

- 中文、简洁、只汇报待决策事项；小决策自己办
- **外部 AI 方案必须先审验再执行**（它只能看到汇报，不一定匹配用户真实意图）
- 免费渠道优先（网关 :3100 统一组；翻译 dots3-note-prev；不碰付费）
- Working Code > 新技术；一次只加一个主要风险；真机验收才算数
- 禁：UAC 弹窗、压测、烧额度、越阶段扩张

## 7. 关键文件速查

| 文件 | 说明 |
|---|---|
| lib/player/sentence_player_controller.dart | 循环/续播/重播/竞态防护全在这（v0.2.1 刚重写，重点审） |
| lib/storage/lesson_repository.dart | SQLite v2 + **P0 bug 的 _onUpgrade 在这里** |
| lib/screens/listening_screen.dart | 精听页（恢复/自动播放/双模式/手势） |
| lib/screens/library_screen.dart | Library |
| tool/whisper_to_lesson.py | 制课一条龙 |
| tool/build_lesson_package.dart | 打包（支持 --cover） |
| test/player/repeat_mode_test.dart | 循环/续播/重播测试 |

祝顺利。修好 P0 记得在开发日志补一笔。
