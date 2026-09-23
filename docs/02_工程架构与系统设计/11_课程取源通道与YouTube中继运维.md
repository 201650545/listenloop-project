---
summary: "课程取源通道（B 站 / YouTube）的依赖、失败分类与运维步骤"
read_when:
  - 用户报告"创建课程失效 / 链接创建不工作"
  - 改动 creation_controller 的链接分支
  - 换电脑或重装环境后要恢复 YouTube 制课
---

# 课程取源通道与 YouTube 中继运维

> **一句话**：B 站链接手机自己能解析；YouTube 链接必须借电脑 —— 因为
> YouTube 从本机网络直连不通，只能由 PC 借用**手机的代理出口**去取。

## 一、两条取源通道的依赖差异

| | B 站链接 | YouTube 链接 |
|:--|:--|:--|
| 解析方 | **手机自己**（`BilibiliClient`，公开 API） | **PC 中继**（`tool/youtube_relay.py`） |
| 需要电脑 | ❌ | ✅ |
| 需要 USB | ❌ | ✅（`adb reverse 8793` + `adb forward 7892`） |
| 需要 yt-dlp | ❌ | ✅（PC 上的 `python -m yt_dlp`） |
| 需要 PO-token | ❌ | ✅（bgutil，`127.0.0.1:4416`） |
| 需要手机代理出口 | ❌ | ✅（PC 走 `127.0.0.1:7892` = 手机代理的 adb forward） |

## 二、2026-09-23 用户报障的完整因果链

用户输入 YouTube 链接 → 「失败 / 输入无效」。

实测四条事实：

1. `netstat` 显示 **8793 无人监听** —— PC 中继根本没启动；
2. `python -c "import yt_dlp"` **失败** —— 即使启动中继，`yt-dlp` 也缺失；
3. `adb forward --list` 有 `7892` 且 `curl -x 127.0.0.1:7892 youtube → 200` —— 手机在、出口通；
4. 补齐 `yt-dlp` 并启动中继后，`POST /resolve` **返回 200 与真实音频字节** —— 端到端打通。

结论：**不是代码回归，是环境缺件 + 报错文案把原因吞了**。

## 三、本轮修的两件事

### 1. 错误分类（`CreationError.sourceUnavailable`）

以前中继不可达被归到 `inputError` → 界面显示「输入无效」。**用户没输错**，
这个归类会把他往错误方向带（重贴链接、换链接，都不会好）。

现在区分开：链接有效但**取源通道**不可用。文案直说「链接没有问题，是拿不到音频」。

### 2. 提交前预检 + 失败页给出可照做的步骤

* `CreationController` 在 YouTube 分支**先 `checkHealth()` 再开工**：
  中继不在线时**秒级**失败，不再等 ASR/翻译跑到一半才发现（原实现会在深层报错，
  用户看到的是含糊的「无法处理该媒体文件」）。
* 失败页新增两块：
  * **操作清单**（三步：启动中继 → 保持 USB → 或改用 B 站链接）；
  * **技术细节**（如 `youtube relay unreachable at http://127.0.0.1:8793`）。
  以前 `errorCode` 非空时只显示通用文案，`errorMessage` 被丢弃 —— 这是
  「失效却不知为何」的直接原因。

## 四、运维清单（出问题时照着走）

1. 手机插 USB（确认 `adb devices` 有设备且已授权）；
2. 电脑上**双击 `tool/start_youtube_relay.ps1`** —— 它会：
   ① 自检 yt-dlp（缺了自动 `pip install -U yt-dlp`）
   ② `adb reverse 8793` + `adb forward 7892`
   ③ 起 bgutil POT（4416）与中继（8793）
   ④ *最后自检一次 `/ping`*，给出确定的 ✅/❌
3. 手机 App 里贴 YouTube 链接制课。

只做了一部分时，症状各不相同：

| 缺什么 | 症状 |
|:--|:--|
| 中继没启动 | 秒级失败，提示 `unreachable at http://127.0.0.1:8793` |
| 手机没连 | 同上（`adb reverse` 丢失 → 手机侧 8793 不通） |
| yt-dlp 缺失 | `/ping` 正常但取源失败，细节里出现 `No module named yt_dlp` |
| POT 没起 | `/ping` 正常，取源报 bot 校验类错误 |

> ⚠️ **后台进程不持久**：中继与 POT 都是普通进程，重启电脑 / 关窗口就没了。
> 每次要下 YouTube 之前先跑一遍 `start_youtube_relay.ps1`（脚本里已做了重复启动保护）。

## 五、为什么不让手机直接下 YouTube

手机能上 YouTube，但**装不了 yt-dlp / PO-token**（无 Python 环境）。
反过来 PC 有工具链，却从本机网络访问不到 YouTube。于是只能组合：
**PC 出工具，手机出出口**，用 `adb forward 7892` 把两者接起来。

## 六、相关文件

| 文件 | 作用 |
|:--|:--|
| `lib/creation/creation_controller.dart` | 链接分支与预检（`youtubeRelayFactory` 为测试缝） |
| `lib/creation/youtube_relay.dart` | 中继客户端（`/ping`、`/resolve`） |
| `lib/creation/creation_errors.dart` | `sourceUnavailable` 错误码 |
| `tool/youtube_relay.py` | PC 端中继（yt-dlp + `--proxy 7892`） |
| `tool/start_youtube_relay.ps1` | 一键启动 + 自检 |
| `tool/phone_ports.bat` | 仅做端口映射（3100 / 8793 / 7892） |
