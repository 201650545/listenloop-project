# Agent 快速检索索引 (Agent Gateway & Quick Links)

> [!IMPORTANT]
> **本文件专供 AI / Agent 快速导航与状态对齐。**
> 当需要向郭老师汇报或展示进展时，直接引用 `用户驾驶舱短链接`；当需要修改或扩展代码时，直接跳转 `源码与契约短链接`。

---

## 一、 用户驾驶舱短链接 (User Cockpit Short-links)
*汇报或向用户展示图表时，直接提供以下文件链接：*

| 看板类型 | 作用与内容 | 短链接 (Clickable Link) |
| :--- | :--- | :--- |
| 🗺️ **无限画布总览** | 四大赛道、全流程连线、状态色卡 | [项目演进大白板.canvas](../00_%E9%A1%B9%E7%9B%AE%E9%A9%BE%E9%A9%B6%E8%88%B1_%E5%8F%AF%E8%A7%86%E5%8C%96%E4%B8%AD%E5%BF%83/%E9%A1%B9%E7%9B%AE%E6%BC%94%E8%BF%9B%E5%A4%A7%E7%99%BD%E6%9D%BF.canvas) |
| 📊 **宏观全景看板** | 发展状态矩阵、思维导图、资产总数 | [01_项目全景与演进看板.md](../00_%E9%A1%B9%E7%9B%AE%E9%A9%BE%E9%A9%B6%E8%88%B1_%E5%8F%AF%E8%A7%86%E5%8C%96%E4%B8%AD%E5%BF%83/01_%E9%A1%B9%E7%9B%AE%E5%85%A8%E6%99%AF%E4%B8%8E%E6%BC%94%E8%BF%9B%E7%9C%8B%E6%9D%BF.md) |
| 🚀 **商业与里程碑** | 短/中/长期目标、甘特图排期 | [02_发展前景与里程碑路线.md](../00_%E9%A1%B9%E7%9B%AE%E9%A9%BE%E9%A9%B6%E8%88%B1_%E5%8F%AF%E8%A7%86%E5%8C%96%E4%B8%AD%E5%BF%83/02_%E5%8F%91%E5%B1%95%E5%89%8D%E6%99%AF%E4%B8%8E%E9%87%8C%E7%A8%8B%E7%A2%91%E8%B7%AF%E7%BA%BF.md) |
| 🌲 **WBS 任务全景** | Epic ➔ Feature ➔ Task 拆解树 | [03_WBS任务分解全景图.md](../00_%E9%A1%B9%E7%9B%AE%E9%A9%BE%E9%A9%B6%E8%88%B1_%E5%8F%AF%E8%A7%86%E5%8C%96%E4%B8%AD%E5%BF%83/03_WBS%E4%BB%BB%E5%8A%A1%E5%88%86%E8%A7%A3%E5%85%A8%E6%99%AF%E5%9B%BE.md) |
| ⚡ **特训闭环流程** | 尚雯婕法 ➔ Anki 记忆完整交互图 | [01_学习闭环与特训流程图.md](../00_%E9%A1%B9%E7%9B%AE%E9%A9%BE%E9%A9%B6%E8%88%B1_%E5%8F%AF%E8%A7%86%E5%8C%96%E4%B8%AD%E5%BF%83/%E5%8F%AF%E8%A7%86%E5%8C%96%E5%9B%BE%E8%A1%A8%E5%BA%93/01_%E5%AD%A6%E4%B9%A0%E9%97%AD%E7%8E%AF%E4%B8%8E%E7%89%B9%E8%AE%AD%E6%B5%81%E7%A8%8B%E5%9B%BE.md) |
| 📱 **页面三级拓扑** | L1 / L2 / L3 导航与路由跳转图 | [02_三级页面导航拓扑图.md](../00_%E9%A1%B9%E7%9B%AE%E9%A9%BE%E9%A9%B6%E8%88%B1_%E5%8F%AF%E8%A7%86%E5%8C%96%E4%B8%AD%E5%BF%83/%E5%8F%AF%E8%A7%86%E5%8C%96%E5%9B%BE%E8%A1%A8%E5%BA%93/02_%E4%B8%89%E7%BA%A7%E9%A1%B5%E9%9D%A2%E5%AF%BC%E8%88%AA%E6%8B%93%E6%89%91%E5%9B%BE.md) |

---

## 二、 核心源码与契约快速映射 (Code & Contract Mapping)

| 模块名称 | 路由 ID | 关键源码文件 (Source Code) | 架构设计文档 (Design Doc) |
| :--- | :--- | :--- | :--- |
| **课程书架** | `L1_LIBRARY` | [library_screen.dart](../../code/lib/screens/library_screen.dart) | [02_页面层级与路由契约.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/02_%E9%A1%B5%E9%9D%A2%E5%B1%82%E7%BA%A7%E4%B8%8E%E8%B7%AF%E7%BA%BF%E5%A5%91%E7%BA%A6.md) |
| **精听播放** | `L1_LISTEN` | [listening_screen.dart](../../code/lib/screens/listening_screen.dart) | [01_系统架构与运行时规范.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/01_%E7%B3%BB%E7%BB%9F%E6%9E%B6%E6%9E%84%E4%B8%8E%E8%BF%90%E8%A1%8C%E6%97%B6%E8%A7%84%E8%8C%83.md) |
| **AI 伴学抽屉** | `L2_AI_TUTOR` | [ai_tutor_sheet.dart](../../code/lib/widgets/ai_tutor_sheet.dart) | [01_学习闭环与特训流程图.md](../00_%E9%A1%B9%E7%9B%AE%E9%A9%BE%E9%A9%B6%E8%88%B1_%E5%8F%AF%E8%A7%86%E5%8C%96%E4%B8%AD%E5%BF%83/%E5%8F%AF%E8%A7%86%E5%8C%96%E5%9B%BE%E8%A1%A8%E5%BA%93/01_%E5%AD%A6%E4%B9%A0%E9%97%AD%E7%8E%AF%E4%B8%8E%E7%89%B9%E8%AE%AD%E6%B5%81%E7%A8%8B%E5%9B%BE.md) |
| **AI 管家服务** | Service | [ai_governor_service.dart](../../code/lib/data/ai_governor_service.dart) | [03_纯英文Anki与AI机制设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/03_%E7%BA%AF%E8%8B%B1%E6%96%87Anki%E4%B8%8EAI%E6%9C%BA%E5%88%B6%E8%AE%BE%E8%AE%A1.md) |
| **SQLite 存储** | Storage | [lesson_repository.dart](../../code/lib/storage/lesson_repository.dart) | [01_系统架构与运行时规范.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/01_%E7%B3%BB%E7%BB%9F%E6%9E%B6%E6%9E%84%E4%B8%8E%E8%BF%90%E8%A1%8C%E6%97%B6%E8%A7%84%E8%8C%83.md) |
| **纯英文 Anki** | `L2_ANKI` | `lib/screens/anki_review_session_screen.dart` | [03_纯英文Anki与AI机制设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/03_%E7%BA%AF%E8%8B%B1%E6%96%87Anki%E4%B8%8EAI%E6%9C%BA%E5%88%B6%E8%AE%BE%E8%AE%A1.md) |
| **AI 伴学在线通道** | Service | [ai_governor_service.dart](../../code/lib/data/ai_governor_service.dart) + [app_preferences.dart](../../code/lib/preferences/app_preferences.dart) | [04_AI伴学与Anki记忆卡优化设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/04_AI%E4%BC%B4%E5%AD%A6%E4%B8%8EAnki%E8%AE%B0%E5%BF%86%E5%8D%A1%E4%BC%98%E5%8C%96%E8%AE%BE%E8%AE%A1.md) |
| **长视频播放** | `L1_LISTEN` | [video_playback_facade.dart](../../code/lib/player/video_playback_facade.dart) | [04_AI伴学与Anki记忆卡优化设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/04_AI%E4%BC%B4%E5%AD%A6%E4%B8%8EAnki%E8%AE%B0%E5%BF%86%E5%8D%A1%E4%BC%98%E5%8C%96%E8%AE%BE%E8%AE%A1.md) |
| **尚雯婕四步法** | `L2_TRAIN` | — | [05_尚雯婕精听法产品化设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/05_%E5%B0%9A%E9%9B%AF%E5%A9%95%E7%B2%BE%E5%90%AC%E6%B3%95%E4%BA%A7%E5%93%81%E5%8C%96%E8%AE%BE%E8%AE%A1.md) |
| **听伴（AI 陪练）** | `L2_AI_TUTOR` | [ai_tutor_sheet.dart](../../code/lib/widgets/ai_tutor_sheet.dart) | [06_AI陪练与语音交互设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/06_AI%E9%99%AA%E7%BB%83%E4%B8%8E%E8%AF%AD%E9%9F%B3%E4%BA%A4%E4%BA%92%E8%AE%BE%E8%AE%A1.md) |
| **闪卡管理** | `L2_ANKI` | `lib/widgets/anki/anki_review_dialog.dart` | [07_Anki闪卡管理与复习策略设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/07_Anki%E9%97%AA%E5%8D%A1%E7%AE%A1%E7%90%86%E4%B8%8E%E5%A4%8D%E4%B9%A0%E7%AD%96%E7%95%A5%E8%AE%BE%E8%AE%A1.md) |
| **学习组件执行页** | `L2_DRILL` | [vocabulary_drill_screen.dart](../../code/lib/screens/vocabulary_drill_screen.dart) + [vocabulary_drill.dart](../../code/lib/training/vocabulary_drill.dart) | [10_生词本与Anki记忆卡设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/10_%E7%94%9F%E8%AF%8D%E6%9C%AC%E4%B8%8EAnki%E8%AE%B0%E5%BF%86%E5%8D%A1%E8%AE%BE%E8%AE%A1.md) |
| **闪卡复习（Item 级）** | `L2_REVIEW` | [vocabulary_review_screen.dart](../../code/lib/screens/vocabulary_review_screen.dart) + `VocabularySrs`（在 [vocabulary_model.dart](../../code/lib/models/vocabulary_model.dart)） | 同上 §十六 |
| **生词本（管理页，已落地）** | `L2_VOCAB` | [vocabulary_book_screen.dart](../../code/lib/screens/vocabulary_book_screen.dart) + [vocabulary_store.dart](../../code/lib/data/vocabulary_store.dart) + [vocabulary_model.dart](../../code/lib/models/vocabulary_model.dart) + [vocabulary_plan.dart](../../code/lib/training/vocabulary_plan.dart) + [subtitle_token.dart](../../code/lib/models/subtitle_token.dart) | [10_生词本与Anki记忆卡设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/10_%E7%94%9F%E8%AF%8D%E6%9C%AC%E4%B8%8EAnki%E8%AE%B0%E5%BF%86%E5%8D%A1%E8%AE%BE%E8%AE%A1.md) |
| **生词本 + Anki 设计** | `L2_VOCAB` | — （设计部分见 10 号文档） | [10_生词本与Anki记忆卡设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/10_%E7%94%9F%E8%AF%8D%E6%9C%AC%E4%B8%8EAnki%E8%AE%B0%E5%BF%86%E5%8D%A1%E8%AE%BE%E8%AE%A1.md) |
| **生词本 + Anki 设计** | `L2_VOCAB` | — （未落代码） | [10_生词本与Anki记忆卡设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/10_%E7%94%9F%E8%AF%8D%E6%9C%AC%E4%B8%8EAnki%E8%AE%B0%E5%BF%86%E5%8D%A1%E8%AE%BE%E8%AE%A1.md) |
| **听写引擎（核心 P1）** | `L2_DICTATION` | [dictation_engine.dart](../../code/lib/training/dictation_engine.dart) + [dictation_session.dart](../../code/lib/training/dictation_session.dart) + [dictation_screen.dart](../../code/lib/screens/dictation_screen.dart) | [09_听写引擎设计与实现.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/09_%E5%90%AC%E5%86%99%E5%BC%95%E6%93%8E%E8%AE%BE%E8%AE%A1%E4%B8%8E%E5%AE%9E%E7%8E%B0.md) |
| **⭐ 优先级基准** | — | — | [08_核心精听优先_产品优先级定调.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/08_%E6%A0%B8%E5%BF%83%E7%B2%BE%E5%90%AC%E4%BC%98%E5%85%88_%E4%BA%A7%E5%93%81%E4%BC%98%E5%85%88%E7%BA%A7%E5%AE%9A%E8%B0%83.md) |

---

## 三、 当前正在推进的工单 (Active Sprint Tasks)

- 📌 **当前史诗**：`EPIC-01: 核心播放与分句引擎`（＝「听」，产品的核心功能）
- 🔥 **2026-09-23 定调（郭老师）**：**"听"是核心功能；AI 陪练与 Anki 闪卡是附属功能（额外小创意）**。
  → 一切排期、交互层级与视觉权重服从此分层，基准文档 [08_核心精听优先_产品优先级定调.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/08_%E6%A0%B8%E5%BF%83%E7%B2%BE%E5%90%AC%E4%BC%98%E5%85%88_%E4%BA%A7%E5%93%81%E4%BC%98%E5%85%88%E7%BA%A7%E5%AE%9A%E8%B0%83.md)，**排期冲突时以 08 为准**。
- 🧭 **分层速记**：核心＝EPIC-01（听）＋ 训练方法学（05 尚雯婕四步法）；支撑＝EPIC-02（制课供给）；附属＝EPIC-03（听伴）／EPIC-04（Anki）；远期＝EPIC-05。
- 🆕 **2026-09-23 新增（含落地）**：08 优先级定调（基准）、05 四步法产品化、06 听伴与语音、07 闪卡管理与复习策略、09 听写引擎（已落地）、**10 生词本与 Anki 设计（含音频选型、边听边存交互、§十五 落地记录）**。
- ✅ **2026-09-23 P4 第二批已落地**：长按拖动圈短语（`SubtitleSelection`）、学习组件执行页（原声回听/单句听写/Cloze/形态纠错，逐步落盘）、闪卡复习接入 Item 级模型（`VocabularySrs`，一个词一张卡，配额 5/30）。（全量测试 468 项通过）\n- ✅ **2026-09-23 P4 第一批已落地**：两层模型 + 保位分词器 + 两级判重 + 持久化 + 计划规则引擎 + 生词本管理页（Library 二级）+ 回原声。（全量测试 398 项通过）
- 🚫 **交互红线**：核心操作不得深于 1 层；附属只能二级入口；附属失败不得阻塞核心；不得用 TTS 合成音替代原片句轴。

### 聚焦任务（按新优先级重排）

**P0–P3 核心层（不依赖 AI，优先做）**

1. `Task 1.4`: 核心听感硬化 —— 句轴精度、切句竞态、播放容错、复读与盲听可用性
2. `Task 1.5`: 音变标注本地规则（连读 / 弱读 / 失爆 / 闪音，可离线）
3. ✅ `Task 5.1`: **听写引擎**（**已完成** 2026-09-23）—— 句级录入 → 段级集中批改 → 词级 LCS diff → 错误分类两层。代码 `lib/training/dictation_engine.dart`、`dictation_session.dart`、`lib/screens/dictation_screen.dart`；入口在精听页顶栏 `Key('dictation-button')`；设计见 [09_听写引擎设计与实现.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/09_%E5%90%AC%E5%86%99%E5%BC%95%E6%93%8E%E8%AE%BE%E8%AE%A1%E4%B8%8E%E5%AE%9E%E7%8E%B0.md)；全量 `flutter test` **297 项通过**
4. `Task 5.2`: 同速背诵 —— 录音 + MiMo ASR + 归一化词级准确率 + 时长比判定
5. `Task 5.3`: 训练周期状态机与 10 篇训练营（播放进度与训练进度分离、跨天续训）

**P4–P6 附属层（核心稳定后再做）**

6. `Task 6.1`: 命名统一（AI 智能管家 → 听伴）+ 三主动作重构（拆音变 / 听写这句 / 跟读核对）
7. `Task 6.2`: 输入框麦克风（录音 → MiMo ASR → 发送）
8. `Task 6.3`: 回复朗读（分句 MiMo TTS + 播放队列；**默认不自动朗读**）
9. `Task 7.1`: 闪卡管理页（Library 二级入口 + "今日待复习 N" + 弱项统计 + 跳回原片）
10. `Task 4.5`: Anki 卡字段升级（targetWord / sentenceCloze / phoneticHintEn / phoneticAnalysis）
11. `Task 4.6`: 英文 Persona 分层 + 结果缓存
12. `Task 4.2`: 播放页打星与生词本沉淀（证据来源，为闪卡供料）
13. `Task 4.4`: 一键导出 `.apkg` 标准记忆卡包
14. `Task 6.4`: 快检重构或下线 —— Q2/Q3 选项未打乱、`correctIndex` 恒为 0 且正确项为通用模板，**当前属伪诊断**，必须先止损
