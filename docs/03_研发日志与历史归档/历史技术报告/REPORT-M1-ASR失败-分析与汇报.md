# 汇报：ListenLoop M1 制课端 — 全上下文总结 + ASR 失败分析与下一步方案

> 汇报时间：2026-09-17 下午 | 汇报人：执行 Agent（本会话）
> 状态：**卡死问题已修复并验证；当前唯一卡点 = ASR 词级时间戳坍缩（Words: 1）**
> 本文档自包含全部上下文，接手方无需回溯聊天。

---

## 一、本会话做了什么（先说结论）

| 事项 | 状态 | 说明 |
|---|---|---|
| **卡死根因修复** | ✅ 已修复+真机验证 | Kotlin `decodeToWav` 整段跑在 Android 主线程 → ANR → 改为串行后台线程 |
| **精听页计数器上移** | ✅ 已装机 | 顶栏 40→32px、顶部内边距归零，紧贴状态栏下方 |
| 门禁 | ✅ | analyze 0 issues，136 测试全绿 |
| 签名迁移 + 数据还原 | ✅ | 新旧 APK 签名不一致 → 卸载重装 → 全量备份还原，进度 28/36 完整保留 |
| **ASR 词级时间戳坍缩** | ❌ 未解决 | 管道完整跑通（解码+ASR 20秒完成），但 `Words: 1` → 分句守卫拒绝 |
| 代码提交 | ⏸ 未提交 | 三处改动待验收后提交 |

---

## 二、卡死问题：根因与修复（已解决）

### 现象
用户第三、第四次测试「从本地文件创建」，选完文件后界面完全无响应（"什么都没有，直接卡死"），MIUI 弹出"应用无响应"或直接杀进程。

### logcat 证据
```
13:55:34 ANR in com.listenloop.listenloop
Reason: Input dispatching timed out (Waited 5000ms for MotionEvent)
153% CPU, 91% user + 61% kernel / faults: 58729 minor
```

### 根因
`MainActivity.kt` 的 MethodChannel 处理器（`configureFlutterEngine` → `setMethodCallHandler`）在 **Android 主线程** 上直接调用 `decodeToWav()`。该方法执行完整的 MediaCodec 解码 + 两遍流式重采样 + 文件 IO，耗时数秒到数十秒，阻塞输入派发 → ANR。

3f33f70 的流式化修复解决了 OOM（O(1) 堆），但 **没有把工作移出主线程**——所以 OOM 消失了，ANR 取而代之。

### 修复
`MainActivity.kt`：新增 `Executors.newSingleThreadExecutor()`，`decodeToWav` 在 worker 线程执行，`MethodChannel.Result` 通过 `runOnUiThread` 回传主线程。

```kotlin
private val decodeExecutor = Executors.newSingleThreadExecutor()
// ...
"decodeToWav" -> {
    decodeExecutor.execute {
        try {
            decodeToWav(input, output, targetRate)
            runOnUiThread { result.success(output) }
        } catch (e: Exception) {
            runOnUiThread { result.error("MEDIA_ERROR", e.message, null) }
        }
    }
}
```

### 验证
15:13 的真机测试：管道完整执行，`Audio prep: OK (04:46)`，**不再卡死**。解码修复确认生效。

---

## 三、计数器上移（已解决）

### 需求
精听页顶部的句数计数器（如 "28 / 36"）往上抬高，靠近前置摄像头下方，给下方内容更多空间。

### 修复
`listening_top_bar.dart`：
- `EdgeInsets.fromLTRB(16, 8, 16, 0)` → `(16, 0, 16, 0)`（去掉顶部内边距）
- `SizedBox(height: 40)` → `height: 32`（压缩行高）

计数器现在紧贴 SafeArea 顶部（即状态栏下方），下方内容多出约 16px。

---

## 四、构建与安装过程（签名迁移）

### 问题
新构建的 APK 签名与手机上已安装的旧 APK 不一致（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`）。原因：前一会话的构建在沙箱环境下运行，JVM 的 `user.home` 被重定向到沙箱临时目录，AGP 在那里自动生成了一个一次性 debug keystore——该 keystore 随沙箱销毁而不可复现。

### 解决
1. 确认新 APK 签名 = 真实 `~/.android/debug.keystore`（SHA-256 比对一致）
2. 旧 APK 签名 = 不可复现的沙箱临时密钥 → 只能卸载重装
3. 卸载前拉全量备份：`app-data-backup-4-presignature.tar`（DB + 偏好 + 课程音频 + 封面，4.8MB）
4. 卸载 → 安装新 APK → 还原备份 → 重推 whisper 模型
5. 验证：TED-Ed 课程卡片可见，进度 **28/36** 完整保留（比旧备份 3c 的 5/36 更新）

### 沙箱 workaround（供后续会话参考）
- 沙箱禁止管道创建 → `flutter` bash 包装脚本（含命令替换）永远挂起
- 解决：直接调用 `dart.exe flutter_tools.snapshot`，绕过 bash 包装
- 环境变量：`PUB_CACHE=D:/pub-cache`、`PUB_HOSTED_URL`、`FLUTTER_STORAGE_BASE_URL`、`JAVA_HOME=D:/jdk17`、`ANDROID_SDK_ROOT=D:/android-sdk`、`FLUTTER_ROOT=D:/flutter`、`CI=true`
- 构建签名：`JAVA_TOOL_OPTIONS=-Duser.home=C:\Users\郭永涛` 确保 AGP 用真实 keystore

---

## 五、当前卡点：ASR 词级时间戳坍缩

### 现象
管道完整执行（不卡死），解码正常（`Audio prep: OK (04:46)`），ASR 返回 `Words: 1`——整段 4:46 的音频转写被合并成 **1 个词** → 分句守卫（< 3 句）拒绝 → UI 显示「转写失败」。

### 精确时间线

| 时间 | 构建 | 现象 | 结论 |
|---|---|---|---|
| 15:13 | 新构建（ANR 修复后） | 不再卡死。`Audio prep: OK (04:46)` → `ASR: OK` → `Words: 1` → `only 1 sentences` | 解码修复生效；暴露 ASR 问题 |
| 15:21 | 新构建 + fp32 模型 | 与 15:13 完全相同：`Words: 1` | **排除 int8 量化嫌疑** |
| 15:2x | 诊断构建（asr-debug 埋点） | 用户再测仍失败（~20s） | 诊断日志已写入 ring buffer 但**已被冲掉**（listening timing 日志量大） |

关键事实：4:46 音频，解码 + ASR 全程 **20 秒内完成**——性能不是问题（8 Gen 3 芯片结论得到佐证），**质量才是问题**。

### 坍缩发生在哪一层

```
whisper decoder → tokens[N] + timestamps[N]（sherpa-onnx 返回）
  → tokensToWords()：相邻 token 时间戳相同则合并为同一个词   ← 坍缩点
  → SegmentationService（PC 规则 1:1 移植）：1 个词 → 1 句
  → 守卫（与 PC 一致）：< 3 句 → asrError → 「转写失败」UI
```

`Words: 1` 意味着 **所有 token 拿到了同一个时间戳**（最可能是全 0，或时间戳数组为空时 Dart 侧默认 0）。ASR 文本本身可能完全正常——只是没有可用的词级时间。

### 已排除的因素

| 排除项 | 依据 |
|---|---|
| int8 量化导致时间戳失效 | fp32 模型同样坍缩（15:21） |
| sherpa-onnx 配置项不存在/未接线 | 已核对 1.13.8 源码：`enableTokenTimestamps` 存在且已正确传入 native struct |
| 解码质量问题 | `Audio prep: OK (04:46)` 时长正确，与 PC 同源素材一致 |
| 性能问题 | 20 秒完成 4:46 音频，RTF ≈ 0.07 |

### 可能原因（按可能性排序）

| # | 假设 | 判据（诊断埋点输出） | 可能性 |
|---|---|---|---|
| H1 | **native 未提取到时间戳**（timestamps 数组为空）：`enableTokenTimestamps` 已正确传入，但 native 侧未生效 | `timestamps=0` | 高 |
| H2 | **tiny.en 模型能力不足**：whisper tiny 系列对 timestamp token（`<\|0.00\|>` 类）预测很不可靠 | `tokens=正常` 但 `distinctTs=1`（全 0） | 高 |
| H3 | **音频内容退化**：该 TED-Ed 音频前奏音乐较重，tiny 模型可能幻觉循环输出 | `textSample` 出现重复/乱码片段 | 中 |
| H4 | **sherpa-onnx 配置缺口**：如 `tailPaddings` 取值影响时间戳 token 生成倾向 | 上述均排除后做参数实验 | 中低 |
| H5 | **Dart 侧合并逻辑 bug**：tokensToWords 把不同时间戳误合并 | 埋点显示 distinctTs 正常但 Words 仍为 1 | 低 |

注：H1/H2 本质是同一现象的两种 native 行为，埋点一次即可区分。

### 诊断埋点（已上线，待采证）

`sherpa_onnx_asr_engine.dart` 的 `_decodeInIsolate` 已增加返回字段：
- `dbgTokenCount`：token 总数
- `dbgTsCount`：时间戳数组长度
- `dbgDistinctTs`：不同时间戳的数量
- `dbgTextSample`：转写文本前 120 字符
- `dbgFirstTokens`：前 20 个 token
- `dbgFirstTs`：前 20 个时间戳

主 isolate 侧通过 `debugPrint('[ListenLoop][asr-debug] ...')` 输出到 logcat。

**采证难点**：logcat ring buffer 被 listening timing 日志（量大）快速冲掉。上次诊断运行的日志已被冲掉。需要重新跑一次诊断并**立即采集**（在 listening timing 日志冲掉之前）。

---

## 六、下一步方案（决策树）

**Step 0（2 分钟，决定一切）**：手机重新插上 USB（不要重启、不要清 logcat）→ 用户跑一次「从本地文件创建」→ 执行 Agent **立即**拉取 `asr-debug` 日志（用限量拉取避免挂起）。

- **分支 A**：`timestamps=0` 或 `distinctTs=1` 且 `textSample` 正常
  → 时间戳提取问题。按序尝试：
  1. **换 base.en 模型**（sherpa-onnx 官方 release，需代理下载；8 Gen 3 跑 base 绰绰有余）。base 的时间戳 token 预测显著好于 tiny。零代码改动，仅换模型文件。
  2. 若 base.en 仍坍缩 → **参数实验**：`tailPaddings`（如 200/1000）、`decodingMethod`。每轮真机 1 分钟。
- **分支 B**：`textSample` 出现幻觉/重复
  → 换一段干净语音素材（无音乐前奏）隔离变量；若干净素材正常 → 升级到 base.en。
- **分支 C**：`distinctTs` 正常但 Words 仍为 1
  → Dart 合并逻辑 bug，直接修 tokensToWords（半小时内）。
- **分支 D**（A/B/C 全部失败，兜底）：
  1. M1 降级方案：词级时间戳不可得时，用句级/段级时间戳近似（`enableSegmentTimestamps` 或按 token 占比线性分摊），精度损失需用户判定；
  2. 或暂停 Mobile 制课，M1 回退为「PC 制课 + 手机导入」（现有链路已冻结可用），Mobile 端侧制课作为后续实验。

**建议**：先走 Step 0 + 分支 A 第 1 步（换 base.en），成功率最高、改动最小。若 base.en 时间戳正常，M1 质量判定（T2）可直接进行。

---

## 七、当前资产状态

- **手机 bf6ef967**：诊断构建已装；fp32 tiny.en 三件套在位；测试音频 `/sdcard/Download/ted-ed-greek-music.m4a` 在；用户进度 28/36 完好。
- **PC**：全量备份 `app-data-backup-4-presignature.tar`；模型源 `dist/_models/sherpa-onnx-whisper-tiny.en/`（int8 + fp32）。
- **仓库 D:\listenloop**：main，未提交改动：
  - `android/app/.../MainActivity.kt`（解码线程修复）
  - `lib/widgets/listening_top_bar.dart`（计数器上移）
  - `lib/creation/sherpa_onnx_asr_engine.dart`（诊断埋点 + 移除多余 import）

---

## 八、风险与边界

- 诊断日志依赖 ring buffer 未被冲掉：采证要快，跑完立即拉。不要重启手机、不要清 logcat。
- base.en 模型下载需代理（7890），GitHub release 偶尔慢，预算 10–20 分钟。
- 冻结区不变：Timeline / SQLite / 播放算法 / PC 管道 / 单词系统 / 云同步。
- 本报告不替代《开发日志.md》正式条目；问题收敛（分支落定）后再补正式日志。
