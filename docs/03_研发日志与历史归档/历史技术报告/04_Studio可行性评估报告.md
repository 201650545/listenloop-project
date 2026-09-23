# ListenLoop Studio Feasibility Report

> Architecture Feasibility Review · 2026-09-16 · 只读评估，未改动任何环境/代码/模型

## 1. Executive Summary

**总体判断：构想现实，且当前电脑可以支撑——但只能以 CPU-only 低资源架构支撑。**

- 当前管道（faster-whisper small CPU int8）今天已在真机上完整跑通并产出第一个正式课程，**默认视为 Stable Baseline，保留**。
- 本机 CPU（Ryzen 7 6800H，8C/16T，AVX2）对 int8 推理相当强，ASR 不是瓶颈。
- **决定性硬件事实：无 NVIDIA 显卡、无 CUDA**（仅 AMD Radeon 680M 核显，共享内存）。因此一切依赖 CUDA 的路线（Qwen GPU 推理、WhisperX GPU 加速）在当前机器上**只能以 CPU 模式评估**，速度与显存结论都需要未来 benchmark 确认。
- 最有价值的架构动作不是换模型，而是**把今天的管道模块化**：落盘 Canonical Word Timeline（words.json）、各阶段产物分离（Non-destructive）、缓存失效规则。这些是纯文本层改动，零硬件代价。
- Qwen3-ASR 0.6B / Qwen3-ForcedAligner 0.6B 值得**未来作为实验 Provider**（CPU 可行性初步判断为 Possible），但本轮不安装、不验证。

---

## 2. Current Machine

```text
OS:            Windows 11 Home China 25H2 (build 26200)
CPU:           AMD Ryzen 7 6800H with Radeon Graphics
CPU cores:     8 cores / 16 threads (Zen3+, AVX2)
RAM:           16 GB（可用约 15.2GB；日常被 WorkBuddy/CodeBuddy/浏览器等占用后仅剩 0.7~1GB 空闲）
GPU:           AMD Radeon 680M 核显（无独立显卡）；另有 GameViewer 虚拟显示适配器（无关）
GPU VRAM:      无独立 VRAM（核显共享系统内存，专用显存约 0.5GB）
GPU Driver:    AMD 31.0.22000.11008
CUDA:          不可用（nvidia-smi 不存在，无 NVIDIA 硬件）
Disk free:     C: 20.4GB / 146.5GB（偏紧）
               D: 174.9GB / 329.1GB（充裕）
Disk type:     NVMe SSD（KIOXIA KBG50ZNV512G）
Python:        3.12.8（全局环境，无独立 venv；faster-whisper 等已装在全局 site-packages）
Existing venvs: 无
```

**硬件等级归档：Tier 0～Tier 1 之间，偏 Tier 1（CPU Practical）。**
理由：CPU 强、SSD 快、内存够但紧张；无 CUDA 使其无法进入 Tier 2（GPU 路线全部关闭）。

---

## 3. Current Pipeline（现在实际在用什么）

| 层 | 实际方案 | 来源 |
|---|---|---|
| Current ASR | faster-whisper **small**，int8，CPU，word_timestamps=True，VAD(≥400ms 静音) | `tool/whisper_to_lesson.py`，模型本地 `dist/models/faster-whisper-small` |
| Current Alignment | faster-whisper 内置词级时间戳（Whisper 交叉注意力 DTW） | 同上 |
| Current Segmentation | 纯规则：句号/问号/叹号断句 ∪ 停顿>0.9s 断句 ∪ 35 词上限；<5 词碎句前并 | `whisper_to_lesson.py: transcribe_sentences()` |
| Current Translation | 网关 `:3100` deepseek-v4-flash（OpenAI 兼容 API），36 句一次批量 JSON | 本地网关，API key 落盘 |
| Current Media Processing | PyAV（faster-whisper 捆绑）解码；curl 直连下载（B站 DASH m4s 实测可被 just_audio/ExoPlayer 播放）；无独立 ffmpeg、无音频归一化 | 今日实测 |

**Working Well（今天实测证据）：**
- TED-Ed 286s 干净旁白：700 词转写、语言置信度 1.00、36 句切分边界来自真实发音时间；全程 CPU 约 1~2 分钟
- 端到端一条龙（下载→转写→分句→翻译→打包 .lllesson→推手机）当日打通
- 网关翻译质量良好（"We live in a society obsessed with music." → "我们生活在一个痴迷于音乐的社会中。"）
- 零 API 成本做 ASR，翻译走免费网关，符合成本原则

**Needs Improvement（诚实清单）：**
- 词级时间轴（words.json）目前**用完即弃**，没有落盘——这是当前架构最大缺口
- 分句纯规则，没有语义检查（长难句、口语断句可能不理想）
- 无 confidence 输出、无自动 QA
- 嘈杂/带音乐/快语速素材未验证（目前只测过干净旁白）
- TED-Ed 课程的边界质量还**没有经过人耳验收**（用户试听进行中）——在此之前的"边界质量好"只是推断

---

## 4. Feasibility Matrix

| Component | Hardware Fit | Risk | Recommendation |
|---|---|---|---|
| Current ASR（faster-whisper small int8 CPU） | **Excellent**（今天实测跑通） | 低：仅内存紧张时需独占运行 | **保留为默认** |
| Current Alignment（whisper 内置词级时间戳） | **Good** | 中：噪声/音乐场景未验证 | 保留；加 QA 兜底 |
| Qwen3-ASR 0.6B | **Possible**（CPU PyTorch 可跑；无 CUDA） | 中：时间戳能力未知、依赖栈未知 | 以后实验，不装 |
| Qwen3-ASR 1.7B | **Questionable**（CPU 可行但慢，RAM 峰值无把握） | 中高 | 仅在 0.6B 证明价值后 |
| Qwen3-ForcedAligner 0.6B | **Possible**（长音频需切 chunk，方式待查证） | 中：Windows/CPU 实测缺失 | Route A 实现时的首选实验对象 |
| LLM Segmentation（语义分句/短语模式） | **Excellent**（纯文本 API，资源≈0） | 低 | 建议纳入 Studio V1 |
| Translation（网关 API） | **Excellent** | 低 | 保留，可换 Provider |

显存风险专项（§12 要求）：**本机无 CUDA，四个候选的"显存需求"全部不适用/不适用即不评估**——Qwen 系列在本机一律按 CPU 内存评估（0.6B 推测 2~4GB 峰值、1.7B 推测 4~7GB 峰值，**需 benchmark 确认，此处不虚构精确数字**）。

---

## 5. Recommended Architecture（基于本机的默认管道）

```text
下载/导入媒体（curl / 本地文件）
  ↓
faster-whisper small int8 CPU（词级时间戳 + VAD）
  ↓
words.json 落盘 ← 【Canonical Word Timeline，本机最值得做的一步】
  ↓
规则分句（现有三规则）
  ↓
（可选）LLM 语义复核：只给 fromWord/toWord，时间由程序从 words.json 计算
  ↓
网关翻译（deepseek-v4-flash，可换 Provider）
  ↓
QA 规则扫描（低置信词/超长句/句内长静音/重叠）
  ↓
dart 打包 → .lllesson
```

原则：**模型顺序加载、用完释放、永不同时驻留**；翻译/分句走文本 API。

## 6. Alternative Architecture

- **Quality Pipeline**（未来，需 benchmark 批准）：+ Qwen3-ForcedAligner（Route A 已有 transcript 时做词级对齐）+ LLM 分句 + 全量 QA；ASR 仍 faster-whisper，或 medium int8（6800H 可承受，速度约慢 2 倍）
- **Low-resource Pipeline**（就是现状 + 纪律）：small int8、一次一个模型、翻译走 API、视频素材下载后即刻释放、任务在前台大应用空闲时跑

## 7. What NOT To Change

1. **手机端整套**（Flutter App、.lllesson 格式、dart 打包工具、57 个测试）——刚验收完，与 Studio 演进完全解耦
2. **faster-whisper small CPU 基线**——没有 benchmark 证明更好之前是 Production 默认
3. **网关翻译通路**（含 API key 管理）——已验证、零成本
4. **B站 curl 下载路径**（cookie+Referer）——今天刚打通，yt-dlp 反而会被 412 掐
5. **规则分句**（对干净语音已够好）——LLM 分句是增量，不是替换
6. **禁止为 AMD 核显折腾 ROCm/DirectML**——收益不确定，纯粹的环境风险

## 8. Main Risks

| 风险 | 说明 | 缓解 |
|---|---|---|
| **RAM 紧张（最大风险）** | 16GB 日常仅剩 <1GB；Qwen 实验可能与用户大应用争内存 | 模型顺序加载用完即释；实验任务安排在应用空闲时 |
| **无 CUDA** | Qwen/WhisperX 的 GPU 路线全关，只能 CPU | 接受"慢但稳"；Studio 非实时（§14） |
| C 盘仅 20GB | 模型/缓存误装 C 盘会爆 | 一切放 D:；pip/模型缓存目录指向 D: |
| Python 全局环境污染 | Qwen（torch 系）与现有全局包可能冲突 | 未来实验用独立 venv（这是计划，本轮不建） |
| 模型镜像可用性 | 今日 hf-mirror 直连超时，ModelScope 可用 | 下载路由优先级：ModelScope > hf-mirror(代理) > HF(代理) |
| **过度工程** | 6 个 Provider 抽象接口对单人单机是超前设计 |现阶段用**文件即契约**（每阶段独立脚本+落盘 JSON），等某层真出现第 2 个实现再上接口 |
| 边界质量未人耳验收 | whisper 词级时间戳在噪声素材上未验证 | TED-Ed 试听 + 未来 benchmark 的 Boundary Quality 指标 |

## 9. Future Experiment Plan（仅设计，不执行）

**触发条件**：TED-Ed 试听验收后，若边界/文本质量有可感知短板，或需要 Route A（已有 transcript 的素材成为主力）。

**固定测试集**（每类 5~10 分钟）：干净旁白（TED-Ed）/ 快语速 / 对话 / 带背景音乐 / 长静音 / 不同口音，各配人工参考 transcript。

**对比项**：Transcript Accuracy（WER）、Boundary Accuracy（下）、耗时、峰值 RAM/VRAM、磁盘占用、**人工修正句数**。

**ListenLoop 特有指标**（比 WER 更重要）：每句人工标注 Good / Start Too Early / Start Too Late / End Too Early / End Too Late / Wrong Text / Bad Segmentation，统计**每模型人工修正次数**。

**A/B 纪律**：同一音频分别跑 Pipeline A（现管道）与 Pipeline B（Qwen 系），各自导出 words.json + sentences.json，**并排比较，禁止一方覆盖另一方**。

## 10. Final Recommendation

**组合结论：KEEP CURRENT + KEEP + MODULARIZE + TEST QWEN LATER**

- **KEEP CURRENT**：现管道今天刚产出第一个正式课程，Working System > Interesting New Technology
- **KEEP + MODULARIZE**：下一步唯一值得做的架构动作 = words.json 落盘 + 阶段产物分离 + 缓存失效规则（纯文本层，零风险）；QA 扫描规则随后；Provider 代码接口暂缓（文件即契约）
- **TEST QWEN LATER**：Qwen3-ASR 0.6B 与 Qwen3-ForcedAligner 0.6B 进入"未来实验池"，触发条件见 §9；1.7B 排在 0.6B 之后
- **HARDWARE UPGRADE MAY HELP（但非必要）**：若未来批量制课成为常态，加一块 NVIDIA 卡（≥8GB VRAM）可解锁 GPU 路线；当前个人制课频率下不值得为此花钱

---

### 附：三条输入路线的评估结论（§6 要求）

| 路线 | 结论 |
|---|---|
| **Route A 已有 Transcript** | **价值最高**（TED-Ed/B站 CC/官方文稿大量存在），但当前**没有**独立对齐工具支撑（faster-whisper 是"边听边写"，不是给定文本对齐）。Qwen3-ForcedAligner 是最值得未来实验的对位方案。实现前 Route A 暂不可用 |
| **Route B 无 Transcript** | 当前管道就是这个路线，已跑通，保持 |
| **Route C 不完美字幕** | **值得做但不急**：冲突检测+纠错流程复杂度高，而 Route B 在干净素材上质量已好。留到 Studio 后续版本 |
