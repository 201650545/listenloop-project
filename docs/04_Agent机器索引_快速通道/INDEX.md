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

---

## 三、 当前正在推进的工单 (Active Sprint Tasks)
- 📌 **当前史诗**：`EPIC-04: 纯英文 Anki 记忆卡体系`
- 🔥 **2026-09-23 定调**：重心全面转向**纯英文**（AI 伴学 + Anki 卡面），详见 [04_AI伴学与Anki记忆卡优化设计.md](../02_%E5%B7%A5%E7%A8%8B%E6%9E%B6%E6%9E%84%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%AE%BE%E8%AE%A1/04_AI%E4%BC%B4%E5%AD%A6%E4%B8%8EAnki%E8%AE%B0%E5%BF%86%E5%8D%A1%E4%BC%98%E5%8C%96%E8%AE%BE%E8%AE%A1.md)
- 🆕 **2026-09-23 新增三份设计**：尚雯婕四步法产品化（05）、听伴与语音交互（06）、闪卡管理与复习策略（07）
- 🎯 **聚焦任务**：
  1. `Task 4.2`: 播放页纯英文原声对白打星与生词本沉淀
  2. `Task 4.3`: 连读（Linking）、弱读（Reduction）规则自动标注
  3. `Task 4.4`: 一键导出 `.apkg` 标准记忆卡包
  4. `Task 4.5`: Anki 卡字段升级（targetWord / sentenceCloze / phoneticHintEn / phoneticAnalysis）
  5. `Task 4.6`: 英文 Persona 分层 + 结果缓存
  6. `Task 5.1`: 听写引擎（逐句盲听 + LCS 词级 diff + 三色标注）
  7. `Task 5.2`: 同速背诵（录音 + MiMo ASR + 时长比判定）
  8. `Task 5.3`: 训练周期状态机与 10 篇训练营
  9. `Task 6.1`: 命名统一（AI 智能管家 → 听伴）+ 六动作重构
  10. `Task 6.2`: 输入框麦克风（录音 → MiMo ASR → 发送）
  11. `Task 6.3`: 回复朗读（分句 MiMo TTS + 播放队列）
  12. `Task 7.1`: 闪卡管理页（列表 / 筛选 / 弱项雷达 / 跳回原片）
