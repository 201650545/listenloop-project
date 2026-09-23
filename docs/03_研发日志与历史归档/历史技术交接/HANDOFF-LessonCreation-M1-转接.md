# 任务转交：ListenLoop Lesson Creation M1 · 真机验证与后续里程碑

> 交接时间：2026-09-17 | 前序 Agent 已完成 M1 全部代码与两轮真机修复，**第三次用户测试尚未进行**
> 本文档自包含全部上下文，接手方无需回溯聊天记录。

---

## 一、项目与代码位置

- **代码仓库**：`D:\listenloop`（Windows / PowerShell；Flutter 小程序级个人应用）
- **项目文档**：`docs/`（开发日志.md 为生命线，倒序；本功能方案原文《ListenLoop Lesson Creation v1》共 67 节，以用户聊天为准）
- **当前分支**：main @ `c1fbc04`，工作树干净；提交链（今日）：
  `32ab82b`(Phase3C) → `c4e5202`(V1视觉) → `064becd`(V2导航/偏好) → `4f4af31`(修复) → `9cbeed8`(精修) → `e82170d`(中英切换) → `7c654e3`(Creation M1) → `3f33f70`(OOM+isolate+可视化) → `c1fbc04`(ENOENT) → `971d622`(顶栏右对齐)
- **门禁状态**：analyze 0 · **136 测试全绿**（含 22 个 creation 测试）

## 二、M1 是什么、做到哪了

**目标**（方案 §十四）：手机本地音频（MP3/M4A/WAV）→ 解码 16k 单声道 → 端侧 ASR → 词级时间戳 → PC 同款三规则分句 → 翻译 → 打包 → 走现有 importer 入库 → 直接精听。

**已实现**（全部已提交）：
- `lib/creation/` 完整模块：WordTimestamp / LessonInput / LessonJobStage / CreationError / AsrEngine 接口 / AudioPreprocessor / SegmentationService（PC `tool/whisper_to_lesson.py` 规则 1:1 移植）/ TranslationService（PC 网关复用 + 空中文降级）/ LessonPackager（安全 QA + ParsedLessonPackage 内存打包）/ CreationController（单任务状态机）/ CreationScreen（阶段清单 UI）。
- `SherpaOnnxAsrEngine`：sherpa-onnx whisper onnx（token timestamps → 词聚合），**后台 isolate 运行**（isolate 内必须 `sherpa.initBindings()`）。
- Kotlin `MainActivity.kt`：`listenloop/creation_native` 通道 — MediaCodec 解码任意媒体 → 单声道 16kHz WAV（**流式两遍，O(1) 堆**）+ 磁盘余量查询。
- Library ＋ 菜单：导入课程 / 从本地文件创建 / 从链接创建（M3 置灰"即将支持"）。

**真机验证进度（卡点）**：用户已测两次，均失败并已修复装机：
1. 首测：`OutOfMemoryError` at `MainActivity.decodeToWav`——`ArrayList<Short>` 攒全量 PCM 撑爆 256MB Java 堆 → 已改流式两遍解码（`3f33f70`）。
2. 二测：`ENOENT .../audio/source.wav.pcm.tmp`——`audio/` 子目录无人创建 → 控制器与 Kotlin 双层显式创建（`c1fbc04`）。
3. **第三次测试尚未进行** ← 接手方第一件事。

## 三、接手后第一件事：M1 真机验证（§六十六）

**前置已就绪**（无需重做）：
- whisper tiny.en int8 三件套已推入手机 `app_flutter/models/asr/`（encoder 12.9MB / decoder 89.9MB / tokens 835KB；源文件备份 `docs/dist\_models\sherpa-onnx-whisper-tiny.en\`，含 fp16 版本可选）。
- 测试音频已放 `/sdcard/Download/ted-ed-greek-music.m4a`（4.6MB，与现有课程同源，英文 TED-Ed）。
- 最新 APK 已装机。

**流程**：用户解锁手机 → Library ＋ → 从本地文件创建 → Download 选 m4a → 等待（预计转写 1–3 分钟）→ 课程完成 → 开始精听。

**通过标准**（§三十/§三十二）：记录 benchmark（RTF = 处理时长 ÷ 音频时长、句数、峰值表现、崩溃无）→ 与 PC 版课程对比（文本/句数/时间戳/体验）→ 达到"足够日用"则继续 M2/M3。

**已知预期**：中文翻译为空（见下）、tiny.en 质量略低于 PC 的 small——属实验预期而非缺陷。

## 四、挂起任务清单（按优先级与角色）

| # | 任务 | 角色 | 说明 |
|---|---|---|---|
| T1 | M1 真机全流程测试 + benchmark 记录 | 执行 Agent（需用户解锁手机配合，约 10 分钟） | 失败则拉 logcat 定位（每次失败都有 `[ListenLoop] creation failed (code): msg` + 完整 creation log 输出） |
| T2 | M1 判定 | 用户 | "足够日用" → 继续；质量不足 → 换 base.en/small 或调参 |
| T3 | 翻译打通 | 执行 Agent | PC 网关（PID 服务，监听 **127.0.0.1:3100**，模型 dots3-note-prev）需绑定 0.0.0.0 或改端点；手机端 `kDefaultCreationGateway`（translation_service.dart）设为 PC LAN IP **10.22.80.254**；当前降级为空中文（PC 同款行为，非 bug） |
| T4 | M2：本地视频 + Share Intent | 执行 Agent | 视频解封装复用 AudioPreprocessor；`audio/*` `video/*` `text/plain` intent-filter |
| T5 | M3：Bilibili URL → Lesson | 执行 Agent | UrlResolver / Downloader / 复用 M1；失败可降级（§四十）；**长期维护成本最高的模块，动手前再确认** |
| T6 | V2 真机 QA 矩阵补跑 | 执行 Agent | Dark/Light × Sans/Serif × S/M/L/XL 组合走查（可 T1 同场进行） |
| — | 冻结区 | 全员 | 不碰：Sentence Timeline / SQLite 结构 / 播放算法 / PC 管道重写 / 单词系统 / 云同步（方案 §四十五/§四十） |

## 五、环境与踩坑速查（本会话实测）

1. **Flutter 门禁环境**（每个新终端必设）：`PUB_CACHE=D:/pub-cache`、`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、`JAVA_HOME=D:/jdk17`、`ANDROID_SDK_ROOT=D:/android-sdk`、`JAVA_TOOL_OPTIONS`（代理 7890，nonProxyHosts 含镜像域）。
2. **命令**：测试 `flutter test`；构建 `flutter build apk --debug --target-platform android-arm64`；adb 位于 `D:\android-sdk\platform-tools\adb.exe`，设备小米 14 **bf6ef967**。
3. **手机会自动锁屏（安全锁，指纹级）**：`wm dismiss-keyguard` 大多无效，需用户解锁；`svc power stayon usb` 可减少中途锁定。uiautomator dump 对 Flutter 语义树不稳定——直接 screencap 截图目视定位坐标更可靠。
4. **写应用私有目录的正确姿势**：`adb shell "run-as com.listenloop.listenloop sh -c 'cat /data/local/tmp/x > app_flutter/...'"`——整条作为单个 adb shell 参数；拆开传参时重定向会被外层 shell 抢走（ENOENT 假象）。
5. **中文输出**：每条命令前 `chcp 65001` + `[Console]::InputEncoding/OutputEncoding = UTF8`。
6. **sherpa-onnx**：isolate 内必须 `initBindings()`；离线解码阻塞不可中途取消（v1 取消在阶段间生效，已在 UI 文案与日志注明）；APK 已含其 native 库（pub `sherpa_onnx: ^1.13.8`）。
7. **Kotlin 解码禁内存累积**：PCM 必须流式（现实现：解码→pcm.tmp→流式重采样回填头），任何"攒全量"写法都会 OOM。
8. **测试素材**：`/sdcard/Download/ted-ed-greek-music.m4a`；手机 DB 与音频备份在 `app-data-backup-3c\`（含历次 UI 截图）。

## 六、当前 App 内状态速览（用户可见）

- 三入口（课程/精听/设置）+ 黑白极简视觉（∞ 品牌、双主题、中英界面、字体/字号偏好）
- 精听页：双模式字幕、Audio/Video 切换、ZH 字幕模式、循环/变速、进度持久化
- 设置：主题（暗默认/浅/跟随系统）、字体、字号（四档+长按滑层 0.85–1.40）、语言
- Library：TED-Ed 课程（用户进度 5/36 附近）+ 新导入课程；视频课封面自动拉取
- 已知小尾巴：从链接创建置灰（M3）；翻译默认空中文（T3）；无后台任务持久化（M4）

## 七、交接边界

- 前序 Agent（本会话）已完成审查/实现/修复全链路并退出，可凭本文档随时召回上下文。
- 接手方建议阅读顺序：本文件 → `开发日志.md`（倒序三篇 V2/M1/语言切换）→ 方案原文相关节（§十三/§十四/§十六/§二十八/§六十六）→ `lib/creation/` 源码。
- 用户偏好提醒：讨厌反复确认；小决策自己办；真机操作前知会一声即可；汇报直给结论不绕弯。
