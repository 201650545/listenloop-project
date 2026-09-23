# Phase 3C Report · Audio / Video 双模式切换

> 日期：2026-09-16 深夜 | 分支 `main` | 基线 `f274214` → **`32ab82b`**
> 验收设备：小米 14（bf6ef967）| 门禁：format ✓ · analyze 0 ✓ · test 95 全绿 ✓

---

## 1. 修改文件

| 文件 | 改动 |
|---|---|
| `lib/player/playback_mode.dart` | **新增**。`PlaybackMode {audio, video}` 单枚举状态模型（§13，禁止多布尔组合） |
| `lib/player/sentence_player_controller.dart` | 核心改动（515 → 727 行）：双 facade 持有 + `setPlaybackMode` + 失败回滚 + 双释放（详见 §2） |
| `lib/screens/listening_screen.dart` | initState 默认 Audio（修复 §2 违规）；媒体槽按 `playbackMode` 渲染；媒体区下方新增 `Audio\|Video` SegmentedButton（仅 `hasVideoSource` 时渲染）；`_retry` 先 `clearError()`；新增测试注入参数 `videoFacade` |
| `test/player/playback_mode_test.dart` | **新增**。12 个切换行为单测 |
| `test/screens/playback_mode_ui_test.dart` | **新增**。3 个切换控件 widget 测试 |
| `lib/screens/library_screen.dart` | **未改**（videoSource 透传不变，符合预期） |

未触及冻结项：faster-whisper / 制课 Pipeline / Translation / `.lllesson` 格式 / SQLite migration / Local Audio 边界算法 / Sentence 模型 / Library UI / 循环算法——全部原样。

## 2. 状态模型

- `SentencePlayerController` 持有 `final _audioFacade` + `final _videoFacade?`，`_facade` 指向当前活跃源。**index / repeatTarget / playbackRate 都在 controller 里 → 跨模式天然共享（§6/§7），无任何跨对象同步。**
- 构造新增 `AudioPlayerFacade? videoFacade` 与 `PlaybackMode initialMode = PlaybackMode.audio`（assert：video 初始模式必须有 videoFacade）。
- 新增公开接口：`playbackMode` / `hasVideoSource` / `isSwitchingSource` / `setPlaybackMode(mode)` / `clearError()`。
- `setPlaybackMode` 时序（§4/§5/§14）：守卫（disposed / 在途 / 同模式 / 无视频源）→ `_isSwitchingSource=true` + 旧源 `pause()` → 同步摘除旧订阅 → 换 `_facade` + `_mode` 并提前 notify（UI 立即切媒体槽 + loading）→ 目标源**惰性加载**（已加载则跳过，视频页首次切换才 fetch）→ seek 当前句 `startMs` → 重放 `_playbackRate`（§12）→ `wasPlaying` 才续播 + watchdog。
- 失败处理（§18）：任何一步抛错 → `_restoreAfterFailedSwitch`：摘订阅 → 还原旧 facade/mode → seek 回当前句 → 置非阻塞错误条；`clearError()` 供 UI 重试恢复，Audio 始终可用。
- `dispose()`：双 facade 都释放（§15）。
- 备选方案 `SwitchingAudioFacade`（交接 §3.2）未采用，与推荐方案一致。

## 3. 新增测试（15 个）

`test/player/playback_mode_test.dart`：默认 audio 且视频惰性不加载 / 无视频源忽略切换 / 同模式 no-op / video 初始模式缺 facade 被 assert 拒绝 / A→V 保持 index + 懒加载 / 旧源先 pause（§14）/ 倍速跨模式重放（双向）/ V→A 不重载已加载音频 / repeat 共享 + ∞ 原地循环不漂移 / ×1 视频下推进不漂移 / 加载失败回滚 + 可恢复（§18）/ dispose 双释放。

`test/screens/playback_mode_ui_test.dart`：纯音频课不渲染切换控件（§17 回归）/ 视频课默认 audio + 控件选择态 + 懒加载断言 / A→V→A 往返不重载。

## 4. 测试总数

**80 → 95，全绿。**（新增 15，既有 80 全部原样通过——§17 无视频课程回归由既有测试保证）
门禁：`dart format`（改动文件 0 diff）· `flutter analyze` 0 issues · `flutter test` 95 pass / 0 fail。

## 5. 真机验证结果（小米 14 bf6ef967）

| 项目 | 结果 | 证据 |
|---|---|---|
| §2 进课默认 Audio（视频课不自动进视频） | **PASS** | 截图 shot-03：音符封面 + Audio 高亮 + 自动播放 |
| §3 切换控件仅视频课渲染、当前模式高亮 | **PASS** | shot-03/04/06/07/08 |
| §4 A→V：旧源先停、index 保持、视频 seek 续播、字幕共用 | **PASS** | shot-06：视频画面 + Video 高亮 + 顶栏 6/36 + 播放器 02:40 对齐第 6 句 |
| §5 V→A：视频停、WebView 卸载、index 保持 | **PASS** | shot-07：封面 + Audio 高亮 + 6/36 |
| §21 快速切换压力 A→V→A→V→A | **PASS** | shot-08：无崩溃/ANR/黑屏，状态一致；在途切换期连点被 `_isSwitchingSource` 守卫安全吸收 |
| §12 倍速跨模式保持 | **PARTIAL** | 见 §6 |
| §15 Video→Home 停止 / §16 重进仍默认 Audio | 未单独真机复验 | 代码路径与 3B/本版一致 + 单测覆盖（dispose 双释放、无 lastPlaybackMode 持久化） |
| §17 无视频课程行为一致 | **PASS（测试层面）** | 既有 80 测试全绿 + UI 测试断言纯音频课无切换控件；真机只有视频课，未单独跑 |

过程说明：新构建签名与设备旧包不一致，重装前已完整备份并还原 `databases/listenloop.db` + 课程音频（备份在 `docs/app-data-backup-3c\`），学习进度（6/36）完整保留。

## 6. 视频倍速支持情况：**PARTIAL**

- **底层支持：PASS（3A 已真机验证）**——harness JS `rate` 指令设 `v.playbackRate`，`播放速率 1.25 → 生效 1.25`。
- **跨模式重放路径：单测 PASS**——`setSpeed(1.5)` 后切 Video，video facade 收到 `setSpeed:1.5`；切回 Audio 同样重放。
- **真机 1.0× 重放：PASS**——切换后视频句循环间隔与音频基线一致（第 6 句 5860ms，实测 ~6.1s/轮）。
- **真机 1.25× 跨模式复验：未完成**——测试点击未命中 1.25× 分段（速度仍 1.0×），复测前用户指示停止验收。架构上该路径与已验证的 1.0× 重放完全相同，风险很低；如需闭环可后续单独复验（音频设 1.25× → 切 Video → 观察句循环间隔应缩短至 ~4.7s）。

## 7. 已知问题

1. 切 Video 时 WebView 平台视图可能晚于 `loadRequest` 挂载——沿用 3B 已真机验证的并发时序，实测正常。
2. `_retry` 现在先 `clearError()`——顺带修复了异步错误后重试按钮无效的旧问题（行为增强，非回归）。
3. 新版 `dart format` 会重排 5 个本次未触及文件（纯风格），未纳入本提交，保持 diff 聚焦；如需可另做 format-only 提交。
4. testWidgets FakeAsync 下 `await 广播订阅.cancel()` 会挂起 async 链（pump 不推进）——已改同步取消（与 `dispose()` 既有模式一致，广播流立即摘除监听，生产行为不变），记录在开发日志备查。

## 8. Git commit

```
32ab82ba034db5b302835a15946e8524c901b0f8  (main)
feat(listening): Audio/Video dual-mode playback sharing one timeline (Phase 3C)
5 files changed, 748 insertions(+), 30 deletions(-)
```

## 9. 边界声明（冻结令）

本次**未**开始：YouTube / Studio 重构 / Qwen / WhisperX / 单词系统 / 云同步。下一阶段事项以 `HANDOFF-v0.2.1-转接.md` §4 路线为准。
