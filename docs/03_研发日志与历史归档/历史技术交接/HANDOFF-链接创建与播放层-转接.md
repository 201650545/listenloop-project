# 转接：ListenLoop · 播放层修复 + Whisper 双档 + 从链接创建（B站/YouTube）

> 转接时间：2026-09-18 晚 | 前序会话上下文将尽
> 本文档自包含，接手方无需回溯聊天记录。
> 仓库：`D:\listenloop`（main @ `c1fbc04`，**34 改 + 12 新文件全部未提交**，提交需用户许可）
> 项目文档：`docs/`（`开发日志.md` 已更新 2026-09-18 条目，是生命线）

---

## 〇、接手方第一件事

1. 读本文档
2. 读 `D:\记忆\调度大脑记忆\用户\传话筒铁律_与强模型协作准则.md` —— 决定你怎么工作
3. 读 `D:\记忆\调度大脑记忆\反馈\feedback_browser_session.md` 和 `feedback_opencli_one_lease.md` —— 怎么跟镜像站通信
4. 脚本与模型都在 `D:\临时文件夹\`（清单见 §五）

## 一、角色定位：「传话筒」（用户 2026-09-06 确立，全程有效）

职责上限 = 整理需求 + 核实事实（逐条证据）+ 按强模型方案实现 + 实测数据回传校准。
架构决策**问镜像站**（先切 Extended，会话「⑭ 英语听力软件方案」），不自作主张；小决策自己办；汇报直给结论；真机操作前知会一声。

## 二、2026-09-18 全天完成（全部已装机验证代码层，真机验收部分完成）

### 1. 播放层：自动续句首词重复（用户痛点，代码完结）
根因：Dart positionStream 过冲 +88~189ms 溢入下一句 → seek 重播。
修复（强模型 48 条方案落地）：Audio 模式改 `just_audio setClip`（ExoPlayer ClippingMediaSource 物理播不过句尾）+ `completionStream`（带 clip 身份防串句）+ `_completionHandled` 消费去重 + 统一 `_transitionToSentence`；Video 模式原样。
**⚠ 用户真机反馈新缺陷：clip 切句有平台重载 → 句间可闻停顿，连贯语音听感割裂（用户原话"耳朵要疯"）。修法已定未实施**：ConcatenatingAudioSource + 逐句 ClippingAudioSource 播放列表（引擎级 gapless，×∞ 用 LoopMode.one）——**这是接手后第一优先**。

### 2. Whisper 双档（用户拍板，全链路落地）
- 快速档=whisper base（154M），精确档=whisper small（359M），**多语言版**（用户："不要把路走窄"），选择器在 Library「＋」菜单顶（`AppPreferences.asrTier`）。
- **M1 结论坐实**：官方发布版 whisper ONNX 无 cross-attention → 时间戳全 0（token/segment 双开关联测）。
- **破局**：官方 `export-onnx-with-attention.py` 自行导出，**必须 torch ≤2.8**（2.14 dynamo 导出器烤死动态 T 维 → 运行时 Reshape 崩；这是当天最大的坑）。DTW 词级时间戳实测 base 40/40、small 41/41 全 distinct。
- 引擎 whisper-only（nemo_ctc 分支已删），whisper 窗长 25s/27s（30s 硬上限）；手机上 tiny.en + Parakeet 已删。

### 3. 从链接创建（用户原始目标，B站+YouTube 双通）
- `lib/creation/bilibili_source.dart`：URL/裸BV/`?p=N`/`b23.tv` 短链（手动逐跳 Location，package:http 不回传终点 URL）+ 混排分享文本提取 + view/playurl API（匿名可用）+ DASH 音频下载。
- `lib/creation/youtube_relay.dart` + `tool/youtube_relay.py` + `tool/start_youtube_relay.ps1`：手机无法跑 yt-dlp → **PC 中继**（yt-dlp + bgutil POT 插件 + 流量走手机 VPN 出口 `adb forward tcp:7892`，YouTube 的 PC-IP 拉黑失效），音频流回 App 走自家管线。**App 侧连接靠 `adb reverse tcp:8793 tcp:8793`**，USB 断了要重配。
- 课程自动带 `VideoSource`（B站课 = WebView 播放器 + 句时间轴；YouTube 课暂无画面）。
- 制课中取消已实时生效（下载进度回调里查取消标志）。

### 4. 体验与储存
- 开屏：MainActivity 请求峰值刷新率（MIUI 默认锁 60Hz 是帧率低根因）+ RepaintBoundary + 文字标缩放。
- **悬浮胶囊**（用户需求）：制作中可退出制作页 → 胶囊浮于所有路由之上（MaterialApp.builder 层 + `creationViewActive` 标志），进度环+百分比，可拖动、松手吸最近左右边缘、**只露 1/3**，点击回制作页。控制器已提升到 App 层（`RootShell.creationController` 可选注入）。
- 储存：清了 ~900MB（file_picker 326M + 制课死 PCM 298M + 旧模型 271M + tmp 537M）；自愈补丁（任务启动清 creation_jobs 残留、结束清 picker 缓存）。
- manifest 加 `usesCleartextTraffic`（App 访问中继的 http 被系统拦过，这是 YouTube 首败根因）。

### 5. 数据修复
- `teded-greek-music` 课程的 video_json 是旧版导入的 NULL → 已直接写回（`D:\临时文件夹\fix_teded_video.py` 有整套 DB 拉改推方法）。

## 三、当前状态

- **门禁**：analyze 0 · **218 测试全绿** · 最新 APK 已装小米 14（`bf6ef967`）
- **中继**：PC 8793 在跑（`node D:\bgutil-pot\server\build\main.js` 4416 + `python tool/youtube_relay.py` 8793）；`adb reverse` 已配（USB 重连后需重配）
- 用户尚待验收：双链接制课端到端、悬浮胶囊手感、首词重复是否消失（×1 连听 30 句）

## 四、未完成任务（按优先级）

1. **播放列表 gapless 改造**（用户最高优先）：消切句停顿，见 §二.1 的既定方案；改动集中在 `JustAudioFacade` + `SentencePlayerController`，video 路径不动。
2. **双链接制课 + 胶囊真机验收**：用户刚拿到修复版，等结果；失败先 `adb logcat` 抓 `[ListenLoop] creation` 行。
3. **YouTube 课视频画面**：需 YouTube iframe 播放器 harness（类比 `video_playback_facade.dart` 的 B 站 WebView 方案）。
4. **中继体验**：设置页无中继地址配置（写死 `http://127.0.0.1:8793` + adb reverse）；可加 AppPreferences 字段 + Wi-Fi 局域网直连模式。
5. **T2 SeamReconciler 序列对齐**（镜像站方案 §四 T2，暂停中）：raw overlap → pairwise 对齐 → duplicate/insertion/deletion/substitution；防误删 fixture（very very / had had）。
6. **git 提交**：46 个文件未提交（34 改 + 12 新），需用户许可；`.analyze.log` 等 4 个垃圾文件不要提交。
7. 旧待办：视频导入 M2、Share Intent、翻译网关手机直连设置化。

## 五、环境与坑（新增加粗，旧的见 HANDOFF-Creation-V2 §五）

- **whisper 导出必须 torch 2.8**：环境在 `D:\临时文件夹\whisper-export\export-venv`，产物 `whisper-export\*.onnx`；重导命令 `python export-onnx-with-attention.py --model base|small`
- **权重下载**：openaipublic 直连/PC 代理全灭 → `adb forward tcp:7892 tcp:7892` + `curl -x http://127.0.0.1:7892`（PC 借手机网络万能；USB 断了重建 forward）
- **明文 HTTP**：App 访问 PC 中继需 manifest `usesCleartextTraffic`（已加）
- **adb 三件套**：`forward tcp:7892`（PC→手机代理）、`reverse tcp:8793`（手机→PC 中继）、USB 重连后两者都会丢
- **run-as 写文件**：`adb shell "run-as pkg sh -c 'cat /data/local/tmp/x > 相对路径'"` 必须整体单字符串传（多层引号会把 `>` 剥到外层 shell）；`/data/local/tmp` 对 App 不可读，先 `chmod 644` 再 `cat >` 重定向
- **DB 修数据**：`fix_teded_video.py` 模式（force-stop → exec-out cat 拉 → sqlite 改 → push tmp → run-as cat 回写）
- **老坑仍有效**：UTF-16 logcat（grep 落空）、截图 `cmd /c`、Python 别内联进 PowerShell、SQLite 游标物化、构建门禁完整环境变量块（HANDOFF-Creation-V2 §五）
- **边修边构建撞车**：构建后台跑时不要再改源码——Gradle 失败但 `install -r` 仍报 Success，装的是旧包（今天踩过两次）

## 六、跟镜像站通信

会话：`https://vip-21.67673.live/c/6aa8027e-1b44-83e8-ac27-a8ab74003985`（⑭ 英语听力软件方案）。脚本 `D:\临时文件夹\mirror_send_nav_free.py`（发）+ `mirror_watch.py`（收）。铁律：bind 永禁、pill 必须 Extended、一窗 ≤12 轮。

## 七、设备与数据

- 小米 14 `bf6ef967`；模型 `models/asr/whisper-base|whisper-small`（513M，唯一占用大头）
- 数据库现仅 1 课（teded-greek-music，video_json 已修）；测试素材在 `/sdcard/Claude 测试/`
- PC：中继 8793 + POT 4416 常驻；`D:\临时文件夹\` 有全部脚本/模型/venv

## 八、硬边界

冻结区：Sentence Timeline / SQLite 结构 / 单词系统 / 云同步（播放算法本次经用户交办已解冻两轮，后续改动仍需先问）。课程必须落在原始完整媒体时间轴上。用户偏好：讨厌反复确认、直给结论、真机操作前知会。
