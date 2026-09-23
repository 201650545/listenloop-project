# 10 · 生词本 + Anki 记忆卡设计（含音频选型与边听边存交互）

> 归属：**附属层**（`EPIC-04`）｜优先级基准：[08_核心精听优先_产品优先级定调.md](08_%E6%A0%B8%E5%BF%83%E7%B2%BE%E5%90%AC%E4%BC%98%E5%85%88_%E4%BA%A7%E5%93%81%E4%BC%98%E5%85%88%E7%BA%A7%E5%AE%9A%E8%B0%83.md)
> 来源：2026-09-23 镜像站 GPT（Extended）第二轮评审 + 本地音频质检
> 状态：**设计定稿，未落代码**

---

## 一、先说结论（四条最高优先级）

| 问题 | 判断 |
|:--|:--|
| **A. 以什么为单位发现生词？** | **句子＝发现单位；整篇＝聚合单位；AI 对话＝诊断单位**。三者并存但**不同权**，不能把「AI 扫全文猜 50 个可能不会的词」当成发现机制 |
| **B. 点词后要不要立刻显示释义？** | **默认绝对不显示。点一下只「存」，不「查」。** 释义必须由用户的**第二个主动动作**打开 |
| **D. AI 怎么判断会不会？** | **一道翻译题不能判定**。每词先 2 题、冲突才第 3 题；**必须包含一次开放产出**；只靠选择题答对，最高只能判「半会」 |
| **E. AI 怎么选学习组件？** | **不让 AI 自由编 UI**。AI 只输出诊断标签与原因码，App 用确定规则从**固定白名单**里选，且**一次最多 2 个组件** |

> 这四条决定了生词系统不会退化成「边听边查词 + AI 到处弹窗 + 一键生卡」的第二条主线。

---

## 二、生词本的「单位」分层

```
一级：句子  = 生词发现单位
       只有句子能同时回答：这个词在哪段原声里？用户刚才听错了什么？
       该回去播哪一段？做 Cloze 时上下文是什么？
二级：整篇  = 候选汇总与计划单位
       课程结束只说「本课候选 8 个，其中 3 个有听写证据」，不让 AI 扫全文替用户猜
三级：AI 对话 = 掌握诊断单位
       回答「你是认识这个词，还是会在新语境里用」，不负责最初发现
```

**用户序列（关键差异）**

```
✅ 听 → 点词/听写犯错 → 候选池 → 课程结束统一整理 → 必要时 AI 诊断 → 确认进入 SRS
❌ 听 → 点词 → 立刻翻译 → 立刻制卡 → 立刻复习
```

**词条状态与诊断维度必须分开**：状态＝`候选 / 学习中 / 已掌握 / 忽略`；诊断维度＝`听辨弱 / 语义弱 / 使用弱 / 形态弱`。**不要把一切压成一个「不会」。**

---

## 三、数据模型：必须新增 VocabularyItem，不要复用 AnkiCard

**依据（已核实代码）**：`AnkiCard` 本质是**句子卡**（含 `lessonId / sentenceIndex / sentenceText / startMs / endMs` + 一个 `clozeWord`），而 `createAnkiCardFromSentence()` 的判重是：

```dart
final existingIndex = _ankiCards.indexWhere(
  (c) => c.lessonId == lesson.id && c.sentenceIndex == sentence.index,
);
```

→ **同一句目前只能存在一张卡；一句里若有第二个生词，会把第一张覆盖掉。** 且新建卡 `dueDate: DateTime.now()` —— 「随手收藏」立即变成「今天欠你一张复习卡」。

建议两层模型：

| `VocabularyItem`（词本体） | `VocabularyOccurrence`（一次上下文证据） |
|:--|:--|
| id / surfaceForm / normalizedTerm | lessonId / lessonTitle |
| kind: word / phrase | sentenceId / sentenceIndex / sentenceText |
| status: candidate/learning/known/ignored | startMs / endMs / audioPath |
| englishDefinition? / chineseGloss? | tokenStart / tokenEnd（字符 span） |
| aiUsageNote? | source: tap / dictation / ai |
| createdAt / lastSeenAt / seenCount | dictationDiffType? / expected? / actual? |
| ankiCardIds | uncertain / causeHints |

* V1 **不要把 AI 生成的 lemma/sense 当主键** —— 否则离线判重不稳定。
* 音变只能存成 `causeHints` / `phoneticHints`，因为 09 已确认它们**只是文本规则推测，不是声学事实**。

### 必须有「候选池 → 正式复习队列」两层

进入正式 SRS 的三个条件（任一）：用户明确点「开始学习」／听写提供了可靠词级错误证据且用户确认／AI 诊断为「半会/不会」且用户接受计划。
**AI 不得因为「这个词看起来高级」自动塞进 SRS。**
这解决的是：**收藏成本接近零，但复习债务不能接近无限。**

---

## 四、边听边存的交互设计（定稿规格）

### 4.1 形态：**模式**，不是全局手势

| 项 | 规格 |
|:--|:--|
| 入口 | 精听页二级菜单 → **生词积累**（不占一级主操作位） |
| 进入后 | 顶部一条**轻状态条**：`生词积累中 · 点词保存 · ×`；**字幕不暂停、不换页** |
| 单击词 | 保存为候选；**再点同一词＝取消** |
| 长按 | **不做主入口**（手机播放中长按精度差，且与系统文本选择语义冲突）；保留给**多词短语**：长按后左右拖动选中连续 2–5 词 |
| 反馈 | 被点词获得**极轻标记**；底部 **1.5 秒 Toast**：`✓ 已存 take　撤销` |
| **释义** | **不显示。**没有弹窗、音频不停。要查只能在**词条里第二次主动点击「查看」** |
| 允许点词的时机 | ① 普通精听（字幕可见）② 听写 `reviewing` 批改后。**听写 `entering` 阶段禁止**（字幕被锁，点词＝泄露答案） |

### 4.2 为什么故意不照抄 LingQ / Readlang

LingQ、Readlang 的「点词 → 看释义 + 保存」是**阅读理解**场景的成熟做法；ListenLoop 的 08 把「听」放在所有附属能力之前，所以**只借「点词保存」，不借「点词立即解释」**。点词弹释义会让用户注意力从声音时间轴转到阅读义项选择——那等于把主任务切走。

### 4.3 点词命中精度：**不要复用 `DictationEngine.tokenize()`**

它是为**比对**设计的：小写化、`I'm → i am` 展开、去标点——**已经丢掉原始字符布局**，无法回答"用户点到了屏幕上哪一段字符"。需新增保留 offset 的 `SubtitleToken`：

| 字段 | 说明 |
|:--|:--|
| surface / normalized | 原样与归一化 |
| charStart / charEnd / tokenIndex | 命中映射 |

| 输入 | 点击单位 |
|:--|:--|
| `don't` / `I'm` | 整个缩写算**一个**可点击 surface token，内部 normalized 再展开 |
| `mother-in-law` | 默认整个连字符词为一个单元 |
| `teacher's` | 整体保存，后续 normalization 再分析 possessive |
| `, . ? !` | **不可点击** |

多词短语 V1 不做「AI 在热路径猜短语」——只靠「单击＝一词 / 长按拖动＝短语」两个机制，完全离线。以后可加本地 phrase lexicon，但只能给**建议**（`可能是短语：take off`），**不得偷偷把用户点的 `off` 改成整个短语**。

---

## 五、AI 判定「用户不会这个词」

**先改一个基本假设：听写错词 ≠ 不认识这个词。** 漏 `the` 可能是弱读没听清；`walked → walk` 可能是词尾没听见；拼错可能只是不熟拼写。09 已把错误分成 `missing / replaced / spelling / morphology / merged / split`，正说明不能把 `errorCount > 0` 全部翻译成「不会」。

### 5.1 触发时机
**不在听的过程中。** 课程结束或用户主动打开：`本课生词 → 检查我是不是真的会`，**每次最多 5 个候选**。
优先级：**听写可靠错误 > 手动点存 > AI 认为值得检查**（AI 只能决定第三类问不问，不能凭感觉宣判）。

### 5.2 每词 2 题起步，冲突才第 3 题

| 题 | 内容 | 测什么 |
|:--|:--|:--|
| **第 1 题 · 原语境理解** | 来自原句，可先播原片 snippet。**不问**「take off 中文是什么」，而问 `In this sentence, what does "take off" mean or do?`（允许中英自由答） | 当前义项识别 |
| **第 2 题 · 新语境产出** | AI 按同一义项换场景，要求**开放输入**，如 `Say in English that the plane leaves the ground at 7:30, using "take off".` | 能否真正取回 + 用法/形态/搭配 |
| **第 3 题 · 仅冲突时** | 如第 1 题对、造句错 → 出对比/纠错任务 | 消解冲突 |

### 5.3 「会 / 半会 / 不会」的本地映射（不让 LLM 输出「我认为掌握了」）

三个维度：`listening`（09 的可靠听写证据）、`recognition`（原语境理解）、`production`（新语境开放产出）。

| 判定 | 条件 |
|:--|:--|
| **会** | recognition=pass **AND** production=pass **AND** 至少经过 2 个不同语境 |
| **半会** | recognition pass + production fail／反向／**只通过选择题**／听写持续失败但语义掌握／两题证据冲突 |
| **不会** | **至少两个独立证据失败**，或用户主动点「我不知道」 |
| 附加 | 若 `listening` 仍失败，整体显示 **`半会 · 认识，但原声里还听不稳`** |

**一题翻译错，不能直接判不会。**

### 5.4 怎么避免「猜对＝掌握」
1. **选择题永远不能单独把状态升到「会」**；
2. 「会」必须包含一次开放产出；
3. 至少两个不同语境；
4. 同一原句重复答对**不增加掌握维度**，只算重复曝光。
5. AI 对开放答案只返回结构化结果：`pass / partial / fail + reasonCode`（如 `WRONG_SENSE`、`BAD_COLLOCATION`、`WRONG_FORM`、`GRAMMAR_ERROR`），**不输出神秘的「掌握度 83%」**。

### 5.5 离线要求
句级发现、候选聚合、听写证据、升入 SRS **全部离线可用**；文章级 AI 总结与诊断可消失，且**不得阻塞任何听力行为**。

---

## 六、AI 制定学习计划

### 6.1 「学习」的本质（先定义，否则计划必然做歪）

一个词真正学会＝**听到能识别 → 语境中能取回意义 → 延迟后还能取回 → 换语境还能正确使用**。
即**成功的提取（retrieval）+ 迁移（transfer）**，不是「看过信息」。

**明确的伪学习**：只看中文释义／连续读 AI 长解释／只做选择题／在同一句里连答十次／AI 一次性批量生 100 张卡／看到提示说「我懂了」／**把 09 的文本音变提示当成真实声学诊断**。

### 6.2 组件白名单（只给 7 个，AI 不得自创）

`original_relisten`（原声回听）／`dictation_retry`（听写这一句）／`cloze_recall`（英文 Cloze 回忆）／`context_transfer`（新语境辨义）／`sentence_production`（造句/交流）／`grammar_repair`（形态搭配语法纠错）／`srs_review`（纯 SRS）。

AI 返回的是 `skill state + reasonCodes + recommendedComponentIds`，**不是 Flutter widget**；App 再校验。
→ 防止 AI 今天显示一个轮盘、明天生成一个「词汇冒险游戏」。

### 6.3 组件选择规则（可直接写成规则引擎）

| 条件 | App 出什么 |
|:--|:--|
| 听写 `missing`/`replaced` 且 `uncertain=false` | `original_relisten` + `dictation_retry` |
| `spelling` | `cloze_recall`（**不自动判听力差**） |
| `morphology` | `grammar_repair` + `cloze_recall` |
| `merged`/`split` | `original_relisten` + `dictation_retry`，目标优先按 **phrase/chunk** 处理 |
| 听写 `uncertain=true` | **只出** `original_relisten`；**禁止**自动生成精确词计划 |
| 原语境语义诊断失败 | `cloze_recall` + `context_transfer` |
| 原语境会、新语境不会用 | `sentence_production` |
| 造句目标词对但形态/搭配错 | `grammar_repair` |
| 选择题答对、无开放产出 | `sentence_production`，状态**保持半会** |
| 已判「会」，SRS 到期 | 只出 `srs_review` |
| 已判「会」，SRS 未到期 | **什么都不出** |
| 仅手动点存、无其它证据 | 留候选池，**什么都不出** |
| AI 不可用但有听写证据 | 本地 `original_relisten`/`dictation_retry`/`cloze_recall` |
| AI 不可用且只有裸候选 | 什么都不出，等用户主动学或联网诊断 |

**硬约束：一个词一次 session 最多显示 2 种组件。** 否则「多样化学习」会变成「每个词做七个小游戏」。

### 6.4 SRS 与多样化训练的分工

**SRS 决定「什么时候回来」；诊断状态决定「回来后练什么」。** AI 不发明复习日期。

示例节奏：首次确诊不会 → 原声回听 + Cloze；第二次到期若 Cloze 已过但 production 未验证 → SRS + 新语境造句；连续成功且无新错误 → 只做纯 SRS；日后新听写又漏 → 重新触发原声回听 + 听写。

---

## 七、音频选型（本轮结论 + 质检证据）

### 7.1 结论：**TED-Ed《Music and creativity in Ancient Greece》**（`dist/teded-greek-music.lllesson`）

| 项 | 实测 |
|:--|:--|
| 语言 / 体裁 | 英语 · 讲解（符合四步法「演讲/讲解」选材标准，**不是影视剧**） |
| 规模 | **36 句 / 271 秒（4.5 分钟）** —— 恰好是「一篇」的量级，一次能听完 |
| 音画 | 内含 `audio.m4a`；已挂 B 站视频 `BV1Gf4y1y7wc`（**该类视频此前已验证可正常播放**） |
| 词汇画像 | 324 个词形 / 552 词次；**90 个只出现一次的长词**（`arguably`、`barbarian`、`civilisation`、`accompany`、`degenerate`、`gibbering`…）→ 生词密度足够做演示 |
| 复现词 | `ethos`、`civilization`、`music` 等多次出现，适合观察「同词多语境」 |

备选：`dist/gettysburg.lllesson`（10 句 / 100 秒；转写与权威原文**逐字一致**，但词汇偏古雅）。

### 7.2 质检发现：该课程包转写有 **6 处必须修的真错词**

用官方逐字稿（TED-Ed 课程页 / 公开 ESL 站点）做全量比对，**700 词 vs 698 词，相似度 0.9785，差异 14 处**：

| # | 类型 | 课程包 ❌ | 官方 ✅ |
|:--|:--|:--|:--|
| 1 | **错词** | `liars` | `lyres` |
| 2 | **错词** | `genes` | `jeans` |
| 3 | **错词** | `dragon's laying` | `dragon slaying` |
| 4 | **错词（改义）** | `a moral barbarian` | `amoral barbarian` |
| 5 | 介词错 | `one at the most famous` | `one of the most famous` |
| 6 | 冠词错 | `through a common medium` | `through the common medium` |
| 7 | 多词 | `just obsessed with music as we are` | `just as obsessed…` |
| 8–10 | 英美拼写 | `categorise / civilisation / civilised` | `categorize / civilization / civilized` |
| 11 | 英美拼写 | `theatre` | `theater` |
| 12–14 | 数字写法 | `three / thirteen / nine` | `3 / 13 / 9` |

**为什么这条必须先修**：生词本会把用户点选的词原样存下来。若用户在 `genes` 上点「存」、或听写时把 `jeans` 写成 `genes` 被判错，**系统就在教错词**。8–14 属可接受差异（英美变体/数字写法），1–7 必须修。

> 校验工具已就绪：官方逐字稿 `D:/Work/gh-sync/_teded_official_transcript.txt` + 比对脚本（difflib 词级对齐）。同法可用于质检**任何**新导入课程 —— 建议把「导入后转写质检」做成制课管线的固定关卡。

---

## 八、附属层不得挤占核心：红线清单

| ✅ 允许 | ❌ 不允许 |
|:--|:--|
| 精听字幕在**用户主动开启**积累模式后可点词 | 顶部永久新增一个巨大的「生词」主按钮 |
| 点词后**音频继续** | 点词**自动暂停** |
| 点词后**轻提示「已存」** | 点词**弹半屏词典** |
| **二级菜单**进入积累模式 | 新增底部「生词」L1 tab |
| 听写 `reviewing` 后从错误词加入候选 | 听写 `entering` 时出现可点击字幕 |
| **原片 snippet** 作为词卡声音 | TTS 替代原片 |
| Library 二级页统一管理生词 + 闪卡 | 精听页直接展示每日 SRS 任务 |
| AI 离线消失 | AI 故障导致无法保存 / 回听 |

**最尖锐那个问题的答案**：**保存行为允许发生在精听页；但「生词本功能入口」不允许成为精听页一级主操作。** 这是同时满足 08 红线与「边听边存必须够快」的唯一合理切法。

---

## 九、要纠正的既有文档（GPT 指出 + 已核实）

**03 文档**
1. **所谓 English-Only 并不真的 English-Only**：正面模板写了中文「连读提示」，背面直接展示 `Sentence_ZH`。若目标真是「正面零中文」，模板至少要重新命名，不要继续叫 English-Only。
2. **把四类音变写成 AI 可从打星句「自动提取」的特征，语气是确定性的** —— 与 09 已收缩的口径冲突，**以 09 为准**（只能说「可能」）。
3. **仍把 Groq 公网当正式架构并宣称「毫秒级」** —— 与当前手机网络现实、以及已落地的 MiMo 直连方向脱节。**03 应标记为旧架构**，不再作为 AI 诊断新功能的基础契约。

**07 文档**
4. 把 `<10min → 1d → 3d` 写成现有 learning steps，**不准确**：当前实现是 **rating 行为**（Again 10 分钟；Good 第一次 1d、第二次 3d），不存在独立 learning-step 状态机。
5. `10 新卡 / 100 复习` 已被 08 新定调覆盖为 **5 / 30**，不能再当基线。
6. 数据模型仍默认「一句一张卡」，**没有考虑一句多词**；而 service 恰好按句覆盖 → **直接阻塞生词本**。**必须先修模型，再做 UI。**

---

## 十、待拍板

1. **音频就用 TED-Ed 这一课？** 若是，我下一步把 1–7 处转写修正落进课程包（保持句轴时间戳不变）并重新打包。
2. **生词积累模式的入口放二级菜单**（GPT 建议）还是做成顶栏第三个小图标（更快但要占位）？
3. **每段/每篇的候选上限**定多少？（GPT 建议诊断一次最多 5 个词）
4. **VocabularyItem 与 AnkiCard 的关系**：确认走「生词本体 + 上下文证据」两层、Anki 作为下游？（这会改动现有 `createAnkiCardFromSentence` 的按句判重逻辑）
5. 「学习计划」首版做到哪一步：只做**组件选择规则表**（E2），还是一并做**节奏编排**（E3 的多次到期编排）？
