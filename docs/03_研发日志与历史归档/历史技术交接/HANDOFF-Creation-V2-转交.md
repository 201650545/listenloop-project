# 转交：ListenLoop Creation V2 · 长音频分窗 + 接缝拼接 · 链接导入待启动

> 转交时间：2026-09-18 上午 | 前序 Agent 额度将尽
> 本文档自包含，接手方无需回溯聊天记录。
> 仓库：`D:\listenloop`（main @ `c1fbc04`，**14 个改动文件 + 12 个未跟踪文件未提交**）
> 项目文档：`docs/`（`开发日志.md` 为生命线）

---

## 〇、接手方第一件事

1. 读本文件
2. 读 `D:\记忆\调度大脑记忆\用户\传话筒铁律_与强模型协作准则.md` —— **这决定了你怎么工作，比技术细节更重要**
3. 读 `D:\记忆\调度大脑记忆\反馈\feedback_browser_session.md` 和 `feedback_opencli_one_lease.md` —— 决定你怎么跟镜像站通信
4. 然后看 `D:\临时文件夹\` 下的脚本清单（§五）

---

## 一、我的角色定位：「传话筒」，不是指挥者

**这是用户 2026-09-06 确立的第一原则，本次会话全程遵守。** 用户原话（转述）：

> "事实是，它是一个比你还强的模型。你给它设置了一大堆限制，按照你的思路走，这就相当于一个差生教优生去做事。我只是让你去提问，应当让它自由去发挥。"

**我的职责上限** = 把用户需求整理清楚 + 提供上下文 + 逻辑化描述目标效果 + 让双方理解保持一致。

**我做的事**：GitHub / 本地仓库核实事实（落到逐条证据，不能只给推断）→ 把真实情况完整回传给它 → 按它给的方案实现 → 把实测数据回传给它校准。

**我绝不做的事**：不给它下"用某技术/某结构/某规模"的指令；不替它判断产出物形态。

**用户明确要求**：遇到问题**去问它，不要反复问用户**（`feedback-stop-nagging-route-to-gpt`）。只有"非常重大 / 破坏共享运行时"才停下来，且是**陈述**而非提问。

**它这次纠正了我两个实现选择**（很好的例子，说明为什么不能自作主张）：
- 我按"保留较早的那次"去重 → 它否掉：「"earlier" 不是质量信号」→ 改成"保留离自己窗口边缘更远的（上下文更多）"
- 我把两个时间戳拉伸合并 → 它否掉：「会造出 920ms 的假长词，污染停顿和句尾」→ 改成"原样采用胜者的 start/end"

---

## 二、本会话完成了什么（按时间顺序）

### 1. M1 制课链路打通（接手前已在进行）

前序遗留：ASR 时间戳坍缩（`Words: 1`）。**根因**：whisper 的 token 时间戳依赖 cross-attention，而 sherpa-onnx 官方导出的 ONNX **不含 cross-attention 输出**，`enableTokenTimestamps` 是静默空操作。同时 whisper 实现**只处理前 30 秒**（`Only waves less than 30 seconds are supported`），4:46 的音频有 4 分 16 秒一直在被静默丢弃。

**解法**：换成 **Parakeet CTC 110m**（`sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8`，126MB，单图 + tokens.txt）。CTC 的时间戳来自 token 发射帧，不需要 cross-attention，也没有 30 秒限制。

### 2. 翻译配置化 + 设置页

- 端点原本硬编码 `http://127.0.0.1:3100` —— 手机上这是手机自己，永远失败；且失败被降级成空中文，`logLines` **收集了但从未在任何界面显示**，所以用户看不到原因。
- 改为设备端可配置：`AppPreferences.translationBaseUrl / translationApiKey / translationModel`；设置页新增 TRANSLATION 段（端点 / 密钥 / **实时拉取模型列表** / **测试连接**）。
- OpenRouter key 由用户从其本地网关（`D:\项目\ai-hub\search_gateway\data\channels.json`）取，**只写入手机 SharedPreferences，未进仓库**。

### 3. 字幕左右切换去动画、长文本卡片化

- 残影根因：`AnimatedSwitcher` + `FadeTransition` + `SlideTransition`，新旧两句同时在场交叉淡入淡出。
- 跳动根因：`SentenceDisplay` 里两个 `AnimatedSize` 在动画文字块高度。
- 改为：直接换内容（零动画）+ `LayoutBuilder` + `ConstrainedBox(minHeight)` + `Center` 固定占位。
- 横屏溢出同期修复：制课页运行中界面在 `849×382 dp` 下溢出 11px，改为阶段清单可滚动、按钮钉底。

### 4. 长音频必崩 → 分窗架构（本次最大成果）

**问题**：601 秒音频在 ASR 阶段进程直接死（SIGABRT），RSS 5.3GB，系统 lowmemorykiller 连杀 5 个无关应用。286 秒稳定。

**取证**：`Ort::Exception ... '/layers.0/self_attn/Add_2' ... Attempting to broadcast an axis by a dimension other than 1. 2513 by 7513`

**PC 二分定位**（每档独立进程，失败会终止进程）：

```
286s PASS  300s PASS  360s PASS  375s PASS  390s PASS
400s PASS  405s FAIL  420s FAIL  480s FAIL  540s FAIL  600s FAIL  601s FAIL
=> 边界：400 秒 PASS / 405 秒 FAIL
```

**关键细节**：第二个数字恒等于 `时长 ÷ 0.08`（405→5063，601→7513）；**第一个数字不固定**（405 秒是 63，601 秒是 2513）——**不存在固定的 2513 上限**，两个维度都随输入变。失败一律 2.5–5 秒速崩，不是内存问题。

**实现**（按镜像站方案《Creation V2》§五–§三十一）：
- `lib/creation/asr_window_planner.dart` —— `SpeechRegion` / `AsrWindow`（read 可重叠、keep 严格不重叠且覆盖全时间轴）/ `AsrWindowPlanner.plan()`
- `lib/creation/vad_segmenter.dart` —— Silero VAD，**只作为 Boundary Adviser**（只报告停顿，绝不切音频、绝不产生句子边界）
- `lib/creation/sherpa_onnx_asr_engine.dart` —— 逐窗解码，`global = readStart + local`，按 token midpoint 归属，Per-window Float32List
- 核心不变量：**分句永远在完整 Global Word Timeline 建成之后**

**真机实测**：

| 素材 | 结果 |
|---|---|
| 601s（10:01） | 7 窗，95 句，span 400..600160，total 76.4s，RTF 0.127，peak 2108MB |
| 1940s（32:20） | 22 窗，385 句，span 320..1939729，中文 385/385，total 685.8s，RTF 0.354，peak 2230MB |

**内存与媒体长度基本解耦**（3.2× 时长只涨 3%）——这是 DoD 里那条。锁屏状态下也跑完了。

**顺带发现**：分窗比整段单趟**快 3 倍**（400s 素材 19.9s vs 58.7s），因为 90 秒窗口的注意力序列短得多。

### 5. 接缝重复词（用户直接听出来的缺陷）

**症状**（用户原话）：切到下一句会重复读两次开头 1–2 个单词，听感很差。

**取证**（同一段 20 秒音频，跨 90 秒边界，两种解法）：

```
单窗:  ... 'The', 'banzoo', 'traps', ...
分窗:  ... 'The', 'Banzoo', 'banzoo', 'traps', ...     ← 凭空多一个
```

**机制**：midpoint 归属要求 token 中点落在本窗 keep 区间；但**两个窗口对同一个词的中点是各自独立估算的**，跨过边界线哪怕 1 毫秒就两侧都留。

**修复**（`lib/creation/seam_reconciler.dart`）：保留 `SeamWord` 的 provenance（windowId / readStart / readEnd），只在**窗口边界 ±1.5 秒**内、**跨窗口**、归一化文本相同且中点漂移 ≤500ms 时去重；**保留 contextMargin（离自己窗口边缘更远）更大的一方，时间戳原样采用不拉伸**。

**21 条接缝审计结果**（PC，`seam_audit.py`）：13 对重复被 ownership 泄漏，漂移 p50=200 / p90=280 / p99=2240ms。

**⚠️ 统计陷阱（接手方必读）**：n=13 时 p99 = max，而 max 由一个**很可能是假阳性**的样本决定（1080s 处同接缝 A 侧有两个 `sentence`、B 侧一个，最近邻配对配错了）。所以**没有**机械套用镜像站给的 `p99 + margin` 公式，而是按簇取值，并在代码注释里写明了理由。**镜像站 bring-up 拍的 500ms 容差是对的；3000ms 搜索半径比数据支持的松了 4 倍。**

---

## 三、正在进行的任务（接手方要接的第一件事）

### ⚠️ 2026-09-18 中午更新：§三 的 32 分钟跑已完成，且发现新 BLOCKER 并已修复播放层

1. **32 分钟验证跑已完成**（`seam2.log`，UTF-16 编码，`grep` 查不到，需按 UTF-16 读）：
   `[asr] windows=22 words=5950`（−15 去重）；`[bench] sentences=385 peakRssMb=2183 rtf=0.418`。seam_check 通过。
2. **新 BLOCKER：每句首词被读两次（384/385 句）**，根因三层：
   - CTC 标点 token 在停顿中间发射，代码把标点附着到前词并以其时间戳为 lastMs → 词尾被拉伸深入静音；
   - `kMaxTokenMs=320` reach 把词尾延伸到下一 token 起点 → 句间边界 0ms 对接（PC whisper 同素材有 880ms 中位间隙）；
   - **播放端自动续句过冲 +88~+189ms** → 溢入下一句首词 → 切句时重播（A/B 证据：手动 Next 正常、自动播完双读）。
3. **播放层已按强模型方案改造完毕（2026-09-18，本会话）**：Audio 模式改 `just_audio setClip`（ExoPlayer 原生 ClippingMediaSource，物理播不过句尾）+ `processingState=completed` 作唯一完成权威（`completionStream` 携带 clip 身份做 epoch 防串）+ 统一 `_transitionToSentence` + 消费去重 `_completionHandled`；`positionStream` 降级为 UI 信号（Video 模式保持原 position 监听不动）。**analyze 0 issues，201 测试全绿**（191 旧 + 10 新增 clip 竞态/×3/∞/末句）。**待真机验收**：TED-Ed V2 原课程不重制课，×1 连续 30 句听首词是否单次；每句边界日志看 `[ListenLoop][auto] overshoot` 是否 ≈0ms。
4. **用户 2026-09-18 决定回切 Whisper 双档**（快速档=base.en，精确档=small.en，App 内用户可选）。前置风险：上表 M1 取证说 whisper ONNX 出不了词级时间戳——正在 PC 用 base.en 实测 token/segment 时间戳是否可用（`D:\临时文件夹\whisper_ts_test.py`），出结论后才囤手机。**注意 whisper 有 30 秒单窗上限**，若可用则 `AsrWindowPlanner` 需按模型选窗长（whisper≈28s，Parakeet 90s）。

---

**（以下为原始 §三，验证跑部分已由上方更新取代）**

**32 分钟验证跑正在进行**（用校准后的参数：搜索半径 1500ms、容差 500ms）：

- 采集日志：`D:\临时文件夹\seam2.log`（后台 logcat，任务 ID `wrrzzqk`）
- 手机上任务已驱动（Library ＋ → Create from File → 选 `ielts-writing-32min.m4a`）
- 预期在 `D:\临时文件夹\seam2.log` 里看到 `[ListenLoop][bench]` 行

**要验证的**：
1. `[ListenLoop][asr] words=` 是否比上一次（5965）**少约 13 个**（被去重掉）
2. 新课程的接缝处是否**不再有相邻重复词**——用 `D:\临时文件夹\seam_check.py` 查（它统计"上一句尾部 == 下一句头部"和"句内相邻重复"）
3. **真实重复有没有被误删**（`very very` / `had had` 这类）——这是它特别强调要防的

**注意**：`seam_check.py` 目前只查重复类。**MISSING / SUBSTITUTION / ONE_TO_MANY / TIMESTAMP_DRIFT 四类没有覆盖**（脚本按"归一化文本相同"配对，结构上发现不了 `gonna` vs `going to`）。

---

## 四、将来要做的任务（按优先级）

### T1. 链接导入 + 视频（**用户今晚的原始目标，未开始**）

用户要求：
1. 手机上导入一个链接 → 直接产出可精听课程
2. **10 分钟以内必须能处理；10–30 分钟也必须能处理**（长音频这块已解决）
3. **网页能播视频的话，产出课程也要带视频**——逐句精听 + 画面，字幕/进度/循环/seek 同一时间轴
4. 产出物与现有课程格式一致
5. 硬约束：**课程最终必须落在原始完整媒体的时间轴上**

**待发消息已写好**：`D:\临时文件夹\ask-gpt-3.md`（含三轮实测数据 + 链接需求）。**但还没发出去**——见 §六 的发送方法。

可复用现状：App 已有 Video 模式（B 站课逐句 seek 真机误差 0ms）；已有本地制课全链路；创建入口第三项「从链接创建」目前置灰；PC 侧有 B 站下载经验（curl + cookie + Referer）。

### T2. SeamReconciler 升级为序列对齐（镜像站明确要求）

它的原话：

> 不要先 ownership filter 把证据删掉，再想办法修。每两个相邻窗口，都保留它们 overlap 区域的**原始识别结果**，然后只针对 overlap 做一次**单调序列对齐**（小型 DP / Levenshtein 就够，成本 = 归一化文本相等 + 时间接近度）。

流水线要从「decode → midpoint ownership → global sort → adjacent dedupe」改成「decode → **保留 raw overlap candidates** → **pairwise seam alignment** → resolve duplicate/insertion/deletion/substitution → ownership/canonical output → Global Word Timeline → Segmentation」。**ownership 要从"不可逆的第一刀"降级成 stitcher 的一个信号。**

三类它能统一解决：
- duplicate → alignment = Match → 输出一份
- missing → 两侧 anchors 都在 → 保住（ownership 恰好两侧都排除时不会丢）
- substitution（`gonna` vs `going to`）→ 把冲突区视为**一个 hypothesis span，整段选一边**，**绝不拼接**

**冲突兜底**：对齐分数低 / 连续 >N 个 token 无法匹配 / one-to-many 明显 / 时间戳分歧大 → **触发 seam-centered referee decode**（以边界为中心重新取一个很短的小窗，这次边界在输入中央而非边缘，作为第三方裁判）。只在冲突接缝上触发，成本小。

### T3. 参数校准的残余

- 搜索半径 1500ms / 容差 500ms 已按簇定值，但**样本只有 13 对**。多跑几段素材后应重新审计。
- 镜像站给的**四个指标**要建立起来：`seam duplicate residual` / `true repetition false deletion` / `seam edit distance vs single-window` / `seam timestamp deviation vs single-window`。
- 它强调要**专门造真实重复 fixture**：`very very` / `had had` / `no no` / `that that`，否则"一个激进的去重器很容易测试全绿，实际上把英语里的真实重复删了"。

### T4. 其他未做完的

- **任务 #8/#9**：Phase A benchmark 的完成（埋点已做，见下）
- 翻译批处理已按实测定为 50 句/批 + 退避重试（0.8s × 第几次，最多 4 次）。原因是实测**批越小越糟**（这条线路请求密集就断连）：一次发 95 句 → 95/95；每批 10 句 → 20/95（SSL EOF）；每批 12 句 → 83/95。**这条与镜像站文档的"1–10 句一批"相反**，需在下次通信时告知它。
- 32 分钟素材上**翻译占总耗时 64%**（388.8s / 605.6s），ASR 只占 11%。继续压总时长的话下一个该动的是它。
- VAD 在 32 分钟里只检出 7 处可切停顿（`minSilenceDuration` 设的 500ms），窗口数不变（22），代价约 33 秒。**边际收益有限但也没害处**。想更自然可把 `minSilenceDuration` 降到 250–300ms 试一档（**可测，别拍**）。
- `tiny.en` 三件套（152MB）仍在手机 `app_flutter/models/asr/`，已无用（结构上出不了时间戳），可清。

---

## 五、环境与踩坑（每条都血淋淋，别重踩）

### 构建门禁（PowerShell，不是 bash）

```powershell
cd D:\listenloop
$env:PUB_CACHE="D:/pub-cache"
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
$env:CI="true"
& D:\flutter\bin\cache\dart-sdk\bin\dart.exe D:\flutter\bin\cache\flutter_tools.snapshot analyze
& D:\flutter\bin\cache\dart-sdk\bin\dart.exe D:\flutter\bin\cache\flutter_tools.snapshot test
```

构建 APK 额外加：`JAVA_HOME=D:\jdk17`、`ANDROID_SDK_ROOT=D:\android-sdk`、`FLUTTER_ROOT=D:\flutter`、`JAVA_TOOL_OPTIONS=-Duser.home=C:\Users\郭永涛`（最后一条确保 AGP 用真实 keystore，否则签名不一致要卸载重装、丢数据）。

**当前门禁：analyze 0 issues · 191 测试全绿。**

### 屏幕截图必须二进制安全

```powershell
cmd /c "D:\android-sdk\platform-tools\adb.exe exec-out screencap -p > D:\临时文件夹\x.png"
```

**PowerShell 的 `>` 是文本编码，会把 PNG 写坏**（表现为 `System.Drawing` 报 OutOfMemory）。

### Python 内联不要走 PowerShell 引号

内联 `python -c "..."` 里的引号会被 PowerShell 吃掉，**表现为脚本静默截断、不报错**。一律写成脚本文件再执行。

### SQLite 游标陷阱（我踩了两次）

```python
# ❌ 遍历游标时对同一 connection 发新查询 → 外层迭代器被顶掉，第一行之后静默结束
for lid, n in c.execute("select id, sentence_count from lessons"):
    rows = c.execute("select ... where lesson_id=?", (lid,)).fetchall()

# ✅ 先把外层结果物化成 list
for lid, n in list(c.execute("select id, sentence_count from lessons")):
```

### 跨窗口时间戳的单位

`AsrWindow.keepStartMs` 是**毫秒**，`Float32List` 索引是**采样点**（16 kHz → ×16）。我第一版把两者直接比较，结果"每个窗口都保留 0 个词"——**看起来像架构失败，其实是单位错**。写这类比较时务必在变量名上带单位。

### 不要用固定 sleep 等异步阶段

`test/creation/creation_controller_test.dart` 里那个 `cancel during transcription` 测试曾用 `sleep(20ms)` 等 ASR 启动，飘了三次（值每次不同：`queued` / `preparingAudio` / `transcribing`）。已改为等 `GateAsrEngine.entered` 这个可观测信号。**新增测试不要用 sleep 编码时序。**

### 手机模型目录

`/data/data/com.listenloop.listenloop/app_flutter/models/asr/`：`model.int8.onnx`(126MB) + `tokens.txt` + `silero_vad.onnx`(629KB) + 已废弃的 tiny.en 三件套。

推送方式：`adb push` 到 `/data/local/tmp/` 再 `run-as com.listenloop.listenloop cp ... app_flutter/models/asr/`。

### 写 SharedPreferences

`shared_prefs/FlutterSharedPreferences.xml`，key 带 `flutter.` 前缀。**写文件必须 UTF-8 无 BOM**（Android 解析器拒绝 BOM）。改前先 `am force-stop`，否则会被运行中的 app 覆盖。脚本：`D:\临时文件夹\set_threads.py`。

---

## 六、跟镜像站（GPT 镜像版）通信的方法

**用户原话**：「接下来当你遇到问题的时候，你就去问它……就在当前这个对话里跟它对话。」

目标会话：`https://vip-21.67673.live/c/6aa8027e-1b44-83e8-ac27-a8ab74003985`（标题 `⑭ 英语听力软件方案`）

### 工具与铁律

- 用 **opencli**（`opencli browser <session> <cmd>`），daemon 端口 19825，扩展连的是 Chrome `Default` 配置
- **`bind` 永久禁用**——它会把 session 槽位污染成 `about:blank`，此后连用户手动打开的标签也会被顶掉。**我开场跑了一次 `bind`，连累了用户另一个 Agent 的标签，被点名两次。**
- **`tab new` 在本环境不新建标签，而是导航当前活动标签**。所以执行前必须确认当前活动标签是**空白页或不重要的页**；否则会抢掉别人的东西（我抢过两次）
- session 只有**一条复用槽位**，`tab list` 永远只吐这一条。**没有"列出全部标签"的命令**（`doctor -v` / `daemon status` / daemon HTTP API / 状态文件 全查过）
- 如果槽位一直报 `about:blank`，先试 **`opencli daemon restart`**（我这次就是重启后 `tab new` 才真正新建了标签）

### 现成脚本（都在 `D:\临时文件夹\`）

| 脚本 | 用途 |
|---|---|
| `mirror_send_nav_free.py` | **推荐**：只读校验槽位 → 备份输入框 → 切 Extended → 分块注入 → 发送。**不做任何 tab 变更**，槽位不对就自己退出 |
| `mirror_watch.py` | 等回复输出完（`[data-message-author-role]` 长度连续两次不变）再抓全文 |
| `inject_and_send.py` | 早期的注入脚本（含旧的 re-anchor 逻辑，**不要用它的 anchor 部分**） |

**调用方式**：`python <脚本> <提示词.md>`。脚本内部用 `node <opencli 的 main.js>` 直调（`.ps1` 壳 Python 起不来）。

### 必须遵守的发问流程

```
1. 先只读校验：host 是 vip-21、标题是 ⑭ 英语听力软件方案   ← 脚本已内置，不对就退出
2. 发问闸门：pill 必须是 Extended（刷新/换对话都会掉回 Auto，Auto 下白烧一轮）← 脚本已内置
3. 注入前备份输入框（脚本会存到 composer-backup.md）
4. 发送后校验 users 计数增长
5. 抓回复：等输出完，不能抓流式
```

---

## 七、待发的消息（接手方直接用）

| 文件 | 内容 |
|---|---|
| `D:\临时文件夹\ask-gpt-3.md` | 三段实测结果（图形边界 400/405、报错双数字、接缝零漏词）+ 真机 601s/1940s 数据 + 翻译批处理反直觉结论 + **链接导入需求**（§四 T1） |
| `D:\临时文件夹\ask-gpt-seam.md` | **已发送**，接缝问题（它的回复在 `seamreply.txt`） |
| `D:\临时文件夹\reply-only.txt` | 它的《Creation V2》完整方案（17,932 字，我读完了） |
| `D:\临时文件夹\seamreply.txt` | 它对「保留较早 vs 保留上下文更多」「要不要拉伸时间戳」「还有哪些接缝缺陷」的完整回复 |

**发送前把它文档里那条与实测相反的结论也写进去**：翻译批处理**批越小越糟**（它文档写"1–10 句一批"，实测一次发 95 句最好）。

---

## 八、当前设备与数据状态

**手机**：小米 14 `bf6ef967`。应用数据完好。

**数据库**（`app_flutter/databases/listenloop.db`，`integrity: ok`）：

```
teded-greek-music            36 句  中文  36/36   span 6830..270210
mobile-…354479-1  (10min)    95 句  中文   0/95   span 400..600160     ← 旧代码产物
mobile-…121166-1  (32min)   384 句  中文 350/384  span 320..1939680
mobile-…4227144-1 (32min+VAD) 385 句 中文 385/385 span 320..1939729
```

**测试素材**：
- `/sdcard/Download/ted-ed-greek-music.m4a`（4:46）
- `/sdcard/Claude 测试/english-thinking-10min.m4a`（10:01）
- `/sdcard/Claude 测试/ielts-writing-32min.m4a`（32:20）

**YouTube 下载**：PC 直连被反爬（出口 IP 被拉黑，4 个播放器客户端全灭，oEmbed 都 Unauthorized）。**可行路径**：`adb forward tcp:7892 tcp:7892` 借手机 VPN 的本地代理（手机上是 Clash 类客户端，监听 `127.0.0.1:7892`）。这样出口 IP 变成手机的，可用。`yt-dlp --proxy http://127.0.0.1:7892 ...`

**PC 复现环境**：`D:\临时文件夹\asr-repro-venv`（sherpa-onnx 1.13.8 + 模型在 `D:\临时文件夹\parakeet\`）。可用脚本：`prefix_probe.py`（图形边界二分）、`windowed_proto.py`（分窗原型）、`seam_audit.py`（接缝审计）、`seam_probe.py`（单缝复现）、`translate_batch_test.py`（翻译批大小对照）。

---

## 九、硬边界

- **冻结区**（项目铁律）：Sentence Timeline / SQLite 结构 / 播放算法 / PC 管道重写 / 单词系统 / 云同步
- **课程最终必须落在原始完整媒体的时间轴上**——这是产品冻结原则，分窗只是 ASR 实现细节，**绝不能让 chunk 泄漏到 Sentence 层**
- **所有改动尚未提交**（14 改 + 12 新增）。接手方**不建议**急着提交：用户还没验收链路导入，而且提交需要用户许可
- 用户偏好：**讨厌反复确认**；小决策自己办或问镜像站；汇报直给结论不绕弯；**真机操作前知会一声**
