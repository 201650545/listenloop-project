---
tags: [ListenLoop, 工程架构, 取源通道, Termux, 移动端]
状态: 已实现（含 Termux:Boot 开机自启）
更新: 2026-09-24
---

# 12_手机端自足化：中继从电脑搬进手机 Termux

> 承接 [[11_课程取源通道与YouTube中继运维]]。第 11 篇的架构是"PC 出工具链 + 手机出出口"，
> 依赖 USB 与电脑在场。本篇解决它的根本缺陷：**电脑不在身边时应用就废了**。

## 一、问题定义

用户原话：

> "要不然电脑不在身边，那手机上的应用不就废了吗"

### 依赖审计（先量再改）

| 功能 | 实际配置 | 依赖电脑 |
|---|---|---|
| AI 伴学 | `https://api.xiaomimimo.com/v1`（MiMo，公网直连） | 否 |
| 字幕翻译 | 同上 | 否 |
| B 站制课 | App 内 `BilibiliClient` 自行解析 | 否 |
| **YouTube 制课** | `http://127.0.0.1:8793` → adb reverse → PC 中继 | **是** |

**"电脑不在就废了"精确等于"YouTube 制课不可用"** —— 只有一处依赖，不必推翻架构。

## 二、为什么不是"用 ADB 就行"

这是最容易混淆的一点，必须写清：

| | 定位 | 电脑不在时 |
|---|---|---|
| **ADB** | 电脑 ↔ 手机的**调试通道** | 直接不存在 |
| **Termux** | 手机上的**运行环境** | 照常工作 |

真正的卡点是：**`yt-dlp` 是 Python 程序，而安卓系统本身没有 Python**。
所以取源中继必须住在"能给 Python"的地方。Termux 提供的正是这个环境，
于是中继可以住在手机里 —— 这才是"不依赖电脑"的可行解。

> 关键收益：中继端口仍是 `127.0.0.1:8793`，**App 侧代码与配置一个字都不用改**。
> 手机端与电脑端两份中继是同契约、同端口的**可互换实现**。

## 三、架构对比

```
【旧】依赖电脑
  App ──adb reverse──▶ PC 中继:8793 ──yt-dlp──▶ adb forward 7892 ──▶ 手机代理 ──▶ YouTube
       (USB 必须插着)      (PC 必须开着)          (还要借手机的出口)

【新】手机自足
  App ──▶ 手机 Termux 中继:8793 ──yt-dlp──▶ 手机自己的代理/VPN ──▶ YouTube
           (中继就住在手机里，全程不碰电脑)
```

## 四、实现

新增 `code/tool\termux\`：

| 文件 | 作用 |
|---|---|
| `ll_relay.py` | 手机端中继；HTTP 契约与 PC 版逐字一致（`/ping`、`/resolve`），另加 `/diag`、`/probe`、`/exec` |
| `ll_relay_ctl.sh` | `start / stop / restart / status / check / setup` |
| `README.md` | 运维手册：为什么、怎么起、故障对照表 |
| `ll_setup1.sh` `ll_node_setup.sh` `ll_js_probe.sh` | 环境探测与实验脚本 |

### 端口互斥（务必记住）

同一端口只能有一个监听者。**手机端中继在跑时，不要执行 `adb reverse tcp:8793 tcp:8793`**，
否则设备侧端口被 adbd 占住，手机端中继绑定失败。（本次实测踩过这个坑。）

## 五、手机环境实测

| 项 | 值 |
|---|---|
| Python | 3.14.6 / pip（2026-09-24 F-Droid 版重建后） |
| Node | v24.18.0 / npm（同上） |
| yt-dlp | 2026.08.19（与 PC 同版本） |
| 唤醒锁 | `termux-wake-lock` 可用（不取则息屏被冻结） |
| 存储 | Termux 可读写 `/sdcard`（新装需先 `termux-setup-storage` 授权） |

最后一条很重要：它让"PC 写脚本 → push → 手机执行 → 日志 pull 回读"这条
**完全不用触碰屏幕**的回路成立。

## 六、验证结果

### 已验证 ✅
1. 中继在手机内启动：`listening on 127.0.0.1:8793`，`/ping` → `{"ok":true}`；
2. 该端口**从手机普通进程可访问** → App 的预检（`checkHealth`）会通过；
3. **手机经自己的代理能访问 YouTube**：`youtube=200`、境外出口 IP、模式 `direct/vpn-tun`；
4. **端到端拿到真实音频**：`POST /resolve` → HTTP 200、309,288 字节、
   4.5 秒、文件头 `ftyp dash iso6 mp41`（真实 m4a）。

### 反机器人校验：已解决 ✅

中继在线后 `/resolve` 最初报 `Sign in to confirm you're not a bot`。
排查结论（全部实测）：

| 组合 | 结果 |
|---|---|
| 无 JS 运行时 | ❌ |
| 7 种 `player_client` 逐个试 | ❌ **全部失败** → 换 client 绕不过去 |
| **`--js-runtimes node`** | ✅ 成功 |
| 再加 `--remote-components ejs:npm` / `ejs:github` | ✅ 成功（但非必需） |
| 强制 `player_client=web` | ❌ 反而失败 → 不要强制 web |

**根因**：yt-dlp 2026.08 起，YouTube 的挑战必须由**外部 JS 运行时**来解。
手机里已有 Node v24，加一个 `--js-runtimes node` 就够，
**不需要搬运 bgutil PO-token 服务**（PC 上那份是含 `canvas` 的原生模块 183MB，
不适合搬去安卓）。

### 残留风险 ⏳
* **手机代理不稳定**：观测到"半拆"状态（`tun0` 地址消失、Clash `:background`
  进程消失、只剩路由表残留 → 报 `Connection refused`）。属环境问题，需用户重连；
  `/diag` 的 `youtube` 字段可直接判定。
* ~~Termux 未装 Termux:Boot → 手机重启后需手动启动中继~~
  → **已解决（2026-09-24）**：迁移 F-Droid 版生态并落地开机自启，详见 §九。

## 七、副产品：不碰屏幕的操作通道

`input text` 依赖 Termux 保持前台。用户在用手机时极易误触 ——
本次实测就把命令打进过用户正在用的聊天输入框（幸未发出）。

两条纪律：

1. **优先走中继的 `/exec`**（`POST {"cmd":[...]}`，需 `X-LL-Token`）。
   因为 127.0.0.1 对本机所有 App 可见，**必须有令牌**，否则任意应用都能执行命令；
   令牌每次启动随机生成并落盘 `/sdcard/Download/ll_relay.token`；
   配 `adb forward tcp:18793 tcp:8793` 即可从电脑驱动（注意方向与 reverse 相反）。
2. 必须开新终端时，用**原子校验**：启动 Termux → 检查 `topResumedActivity`
   确认前台真是 Termux → 才输入；不是就放弃，绝不盲打。

## 八、产品侧的配套改动

故障提示原先让用户"双击 `start_youtube_relay.ps1`、保持 USB 连接" ——
**在新架构下这是错误指引**。两种取源故障的处置动作完全不同，不能共用一份清单：

| 故障 | 判定 | 该给用户的动作 |
|---|---|---|
| 中继没在监听 | `checkHealth()` 失败 | 去 Termux 启动中继 |
| 中继在线但拿不到音频 | `/resolve` 报错 | 去检查**代理**是否已连接 |

实现：`CreationError` 旁新增 `SourceHint { relayDown, relayBlocked }`，
由 `CreationException.hint` 携带，界面据此选择清单；两份清单都保留
**B 站替代路径**（永远留一条不需要代理的路）。

相关：[[09_听写引擎设计与实现]]、[[10_生词本与Anki记忆卡设计]]、[[11_课程取源通道与YouTube中继运维]]

## 九、开机自启：迁移 F-Droid 版 Termux 生态（2026-09-24）

### 为什么必须整体迁移（三项实证，别再试错）

原 Termux 是 **Google Play 版**（`versionName=googleplay.2026.06.21`，installer=com.android.vending），
官方 Termux:Boot 在该生态上无解：

1. 官方 Termux:Boot 插件 **2024-07-18 已从 Google Play 下架**（F-Droid 侧仍维护，0.8.1）；
2. 官方明令 **禁止 Play 版与 F-Droid 版混装**（签名不同）—— F-Droid 版 Boot 驱动不了 Play 版主 App；
3. 2026 版 Play 版 Termux **收掉了外部执行接口**：包内无 `RunCommandService`，
   仅剩 signature 级 `com.termux.permission.TERMUX_INTERNAL` ——
   App 内 `RUN_COMMAND` 拉起、Tasker/MacroDroid 等外部触发全部不可行。

结论：真·开机自启的唯一路径 = **整体迁移 F-Droid 版生态**（主 App + API + Boot 同签名）。

### 迁移记录

| 项 | 值 |
|---|---|
| 卸载 | `com.termux`（Play 版，私有环境随之清空）+ `com.termux.api` |
| 新装（F-Droid 同签名三件套） | Termux 0.118.3 (1002) · Termux:API 0.53.0 (1002) · Termux:Boot 0.8.1 (1000) |
| APK 来源 | NJU 镜像 `https://mirror.nju.edu.cn/fdroid/repo/com.<pkg>_<versionCode>.apk`（当日 f-droid.org 直连抽风） |
| 环境重建 | `ll_fdroid_rebuild.sh` 一键完成（见下） |
| 中继文件 | `/sdcard/Download` 的 `ll_relay.py` / `ll_relay.token` / `ll_relay_ctl.sh` 全程未动，App 侧零改动 |

重建脚本流程：apt 源切换（新版 pkg 会自动测速选镜像，本次选中 freedif）
→ `pkg install python nodejs-lts termux-api` → pip 装 yt-dlp
（TUNA 镜像 SSL 被掐，换阿里云源装成）→ 部署 boot 脚本 → 拉起中继自检。

### 新增脚本（已入 repo `tool/termux/`）

| 文件 | 作用 |
|---|---|
| `ll_relay_boot.sh` | 开机脚本：`termux-wake-lock` → `sleep 15` → `ll_relay_ctl.sh start` |
| `ll_fdroid_rebuild.sh` | F-Droid 版环境一键重建（含存储权限前置自检、tee 双写日志） |

boot 脚本部署在两个目录（兼容新旧版本读法）：
`~/.termux/boot/ll-relay.sh` 与 `~/.config/termux/boot/ll-relay.sh`，均已 `chmod +x`。

### 踩坑两枚（后来者直接绕开）

1. **MIUI USB 安装确认**：`adb install` 会弹手机端确认框，无人点则
   `INSTALL_FAILED_USER_RESTRICTED`。装机时盯着手机点"允许"。
2. **新装 Termux 必须先 `termux-setup-storage`**：否则 `/sdcard/Download` 对其不可见，
   `bash /sdcard/Download/xxx.sh` **无声退出**（表象是"贴了命令啥反应都没有"）。
   重建脚本已加前置自检：读不到中继文件时直接提示先授权。

### 验证证据（2026-09-24 重启实测）

- logcat：`Start proc 15622:com.termux.boot/u0a1040 for broadcast {com.termux.boot/com.termux.boot.BootReceiver}`
  —— 开机广播真实送达 Boot 插件；
- 进程时间线：开机 13:25:03 → 中继 13:25:47 被拉起（= sleep 15 + 启动耗时，吻合）；
- `/ping` → `{"ok":true}`；`/diag`：yt-dlp 2026.08.19、node 运行时在位、境外出口 IP；
- MIUI 侧：三件套均已设「自启动 + 省电无限制」，`AurogonImmobulusMode` 日志确认
  termux 全家位于无限制名单，开机未被拦截。
