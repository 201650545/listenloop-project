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

### 7.2 质检发现与修正（**已应用，2026-09-23**）：该课程包转写有 6 处真错词

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

**修正结果**：已对句 4 / 12 / 15 / 27 / 35 应用 5 处修正（含 `a common medium → the common medium` 与去除句中多余逗号）；
参考稿与课程包词级相似度 **0.9785 → 0.9893**；剩余 8 处差异全部为英美拼写（`categorise/civilisation/civilised/theatre`）与数字写法（`three/3`），**非错误，保留**。
原包已备份为 `dist/teded-greek-music.lllesson.bak-20260923`。

> ⚠️ **一个重要教训**：参考稿只能当**证据**，不能当**圣旨**。本次差异中 `just as obsessed`（课程包）vs `just obsessed`（参考稿）—— **课程包才是对的**，参考稿漏了一个 `as`。修正前必须逐条人工确认，不可脚本盲改。
>
> 校验工具：官方逐字稿 `D:/Work/gh-sync/_teded_official_transcript.txt` + difflib 词级对齐脚本。同法可用于质检**任何**新导入课程 —— 建议把「导入后转写质检」做成制课管线的固定关卡。

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

---

## 十一、决策记录（2026-09-23 用户拍板）

| # | 问题 | 决定 |
|:--|:--|:--|
| 1 | 音频选型 | **用 TED-Ed《Music and creativity in Ancient Greece》做测试文档**（转写已修正并重新打包） |
| 2 | 生词积累 | **可以做** |
| 3 | 入口图标层级 | **作为三级图标** —— 必须先把一/二/三级页面与菜单的结构处理干净（见 §十二） |
| 4 | 单次诊断候选上限 | **5 个词** |
| 5 | 两层模型 | **采纳**（`VocabularyItem` + `VocabularyOccurrence`，详见 §十三） |
| 6 | 首版学习计划范围 | **先做小部分** —— 只做本地规则映射，不做 AI 出题（详见 §十四） |

---

## 十二、三级结构（页面与菜单同构）

**原则**：层级必须一致可推——一级页面配一级菜单，二级页面配二级菜单，三级只放**动作与开关**，不得再有第四级。

| 层级 | 页面 | 菜单 / 入口 | 内容 |
|:--|:--|:--|:--|
| **L1** | 底部主导航 4 页 | 一级菜单＝底部 tab | 课程 Library ／ 精听 Listen ／ 创建 Create ／ 设置 Settings |
| **L2** | 页面内主分区 | 二级菜单 | Library：课程列表 → **课程详情**；**今日计划 ／ 生词本 ／ 闪卡复习**（管理类都归 Library）<br>精听页：顶栏图标 + **「⋯」面板**<br>设置：七大分组页 |
| **L3** | — | 三级菜单 / 动作 | 「⋯」面板里的 **生词积累模式**（开关）<br>积累模式内：点词保存 ／ 再点取消 ／ 长按拖动选短语（动作）<br>听写页：提交本段 ／ 重写本段（动作） |

### 两个反复被讨论的落位，按此规则一次定死

* **听写（核心层）＝ L2 直达**：顶栏图标，符合 08「核心操作不得深于 1 层」。
* **生词积累（附属层）＝ L3**：进「⋯」二级面板，符合 08「附属只能二级入口」+ 本次「图标作为三级」的要求。

> 二者看似冲突，其实是**同一条规则的两面**：**核心允许 L2 直达，附属一律下沉到 L3。** 顶栏不会因此被附属功能塞满。

```
精听页（L1 页面）
 └─ 顶栏：听写图标（L2 直达）  ·  ⋯（L2 菜单）
                                   └─ 生词积累模式（L3 开关）
                                        └─ 点词保存 / 撤销（L3 动作）
```

---

## 十三、两层模型详解：`VocabularyItem` vs `VocabularyOccurrence`

### 13.1 一句话区别

| | `VocabularyItem` | `VocabularyOccurrence` |
|:--|:--|:--|
| 回答的问题 | **「这个词是什么」** | **「这个词在哪儿被遇到过、当时发生了什么」** |
| 粒度 | 一个**词 / 短语** | 一次**上下文证据** |
| 数量 | 1 份 | **N 份**（一对多） |
| 判重键 | `normalizedTerm`（跨课程、跨句子合并） | `(itemId, lessonId, sentenceId, 字符 span)` |
| 生命周期 | 长期存在，跨课程累积 | 随课程/句子产生，只增不改 |
| 谁读它 | 复习调度（SM-2）、生词本列表、今日计划 | 组件选择规则、证据展示、"回原声"跳转 |

**关系**：`1 个 Item ↔ N 个 Occurrence`。

### 13.2 为什么必须分开（三个都来自真实缺陷，不是理论洁癖）

**① 同一个词在多处出现会"碎成多条"**
只做一层（每个「词+句」一条记录）时，`barbaric` 在课程 A 第 10 句、课程 B 第 88 句会被记成**两条互不相关的记录**。后果：闪卡里出现两张 `barbaric`，复习时间各自独立，**掌握度永远无法累积**——第 3 次遇到它时，系统还以为这是新词。

**② 一句里有多个生词会互相覆盖（现有代码的真实缺陷）**
`AnkiCard` 挂在句子上，判重是 `lessonId + sentenceIndex`：

```dart
final existingIndex = _ankiCards.indexWhere(
  (c) => c.lessonId == lesson.id && c.sentenceIndex == sentence.index,
);
```

→ 同一句里点存第二个词，会**覆盖**第一个。两层模型下，同一句可以生成 2 个 Occurrence，分别指向 2 个不同 Item，**互不覆盖**。

**③ 证据来源不同、结论也不同**
「用户点选的」「听写漏掉的」「AI 判不会的」可能是**同一个词**，但发生的时间、句子、错误类型完全不同。混在一层，就永远说不清**这个词到底哪儿不行**——而 09 已经证明「听写错 ≠ 不认识这个词」（漏 `the` 可能是弱读没听清；`walked→walk` 是词尾；拼错可能只是不熟拼写）。

### 13.3 字段分工

| `VocabularyItem`（1 份） | `VocabularyOccurrence`（N 份） |
|:--|:--|
| `id` / `surfaceForm` / `normalizedTerm` | `lessonId` / `lessonTitle` |
| `kind`: word / phrase | `sentenceId` / `sentenceIndex` / `sentenceText` |
| **`status`**: candidate/learning/known/ignored | `startMs` / `endMs` / `audioPath`（**回原声用**） |
| `englishDefinition?` / `chineseGloss?` | `charStart` / `charEnd`（**点词命中用**） |
| `aiUsageNote?` | **`source`**: tap / dictation / ai |
| `createdAt` / `lastSeenAt` / **`seenCount`** | `dictationDiffType?` / `expected?` / `actual?` |
| `ankiCardIds`（调度挂在这里） | `uncertain` / `causeHints`（音变提示） |

**三条派生规则**（决定实现顺序）：

1. `Item.status` **由 Occurrence 汇总推导**，不是手填（候选→学习中→已掌握/忽略）。
2. `Item.seenCount` = 它的 Occurrence 数量（**重复点同一个词不再产生新 Item，只是 seenCount+1**）。
3. **SM-2 调度挂在 Item 级** —— 即**一个词一张卡**，而不是一句一张卡。这是与现状最大的结构差异。

### 13.4 用 TED-Ed 这一课走一遍（具体例子）

```
用户在第 10 句听到 barbaric → 点词保存
   Item      : { term: "barbaric", status: candidate }
   Occurrence: { itemId, lesson: teded-greek-music, sentence: 10,
                 span: [charStart, charEnd], source: tap }

后来听写第 35 句，把 amoral 写成了 a moral → 判定为错误
   Item      : { term: "amoral", status: candidate }
   Occurrence: { itemId, sentence: 35, source: dictation,
                 diffType: replaced/spelling, expected: "amoral", actual: "a moral" }

同一课又出现 barbarian（不同词形）
   → V1 **不合并**（lemma 归并留到以后，因为 GPT 明确建议
     「不要把 AI 生成的 lemma/sense 当主键，否则离线判重不稳定」）

用户在另一课又点存 barbaric
   → **不新建 Item**，只加 Occurrence#3
   → Item.seenCount 变 2，status 可由 candidate → learning
```

**一句话对照**：`Item` 是"词典里那一行"，`Occurrence` 是"你在哪些句子、哪一秒、因为什么原因碰到过它"。

---

## 十四、首版学习计划（v1）—— 只做本地规则映射

### 14.1 范围（做）

**输入信号只取两类**（都不依赖 AI）：
1. **听写证据**（来自 09，本地已有）：`dictationDiffType`
2. **手动点存**（候选池）

**组件只用 4 个**（纯本地可判定）：
`original_relisten`（原声回听）／`dictation_retry`（听写这一句）／`cloze_recall`（英文 Cloze 回忆）／`srs_review`（纯 SRS）
＋ `morphology` 时的**本地纠错展示**（`grammar_repair` 的简化版，只展示正确形态，不判开放答案）。

**输出**：Library 二级页「**今日计划**」—— 一个列表，每项 ＝ `词 + 1~2 个组件按钮`，点进去执行。

**规则表（v1 全部规则，可直接实现）**

| 条件 | 出什么 |
|:--|:--|
| 听写 `missing`/`replaced` 且 `uncertain=false` | `original_relisten` + `dictation_retry` |
| `spelling` | `cloze_recall`（**不判听力差**） |
| `morphology` | 本地纠错展示 + `cloze_recall` |
| `merged`/`split` | `original_relisten` + `dictation_retry`（按 chunk 处理） |
| `uncertain=true` | **只**出 `original_relisten` |
| 仅手动点存、无其它证据 | **什么都不出**，留候选池 |
| 已判「会」且 SRS 到期 | 只出 `srs_review` |
| 已判「会」且未到期 | **什么都不出** |

**三条硬约束**：① 一个词一次最多 2 个组件；② 受 SRS 配额约束（新卡 5 / 复习 30）；③ 执行组件后**回写成功/失败证据**，供下次规则判定。

### 14.2 范围外（留给 v1.5+）

* AI 出题与**开放答案评判**（`context_transfer` / `sentence_production` / `grammar_repair` 的判定）
* 多次到期的**节奏编排**（SRS 决定何时回来，诊断状态决定练什么 —— 编排属增强）
* lemma 归并、短语词典（本地 phrase lexicon 只能给建议，不得偷改用户的点选）
* 文章级 AI 汇总

### 14.3 v1 验收标准（可测）

1. **断网可用**：飞行模式下能生成今日计划并完成全部组件；
2. **可解释**：每个组件都能回答"因为哪条证据"；
3. **不制造复习债**：仅点存、无证据的词**不出组件**；
4. **一次最多 2 组件**；
5. 不做任何 AI 出题也能跑通完整闭环（点存 → 候选池 → 今日计划 → 执行 → 回写证据）。

---

## 十五、落地记录（2026-09-23 · 第一批）

### 15.1 已交付

| 文件 | 职责 |
|:--|:--|
| `lib/models/vocabulary_model.dart` | 两层模型：`VocabularyItem`（词本体）+ `VocabularyOccurrence`（上下文证据）、三个枚举、`normalizeTerm()`、JSON 往返 |
| `lib/models/subtitle_token.dart` | **保留字符位**的分词器：`surface / normalized / charStart / charEnd / tokenIndex`，含 `tokenAt()` 命中测试与 `phraseFor()` 短语圈选（2–5 词） |
| `lib/data/vocabulary_store.dart` | 两级判重 + toggle + 状态转移 + **持久化**（`SharedPreferences` 键 `listenloop:vocab_items`），写盘串行化 |
| `lib/training/vocabulary_plan.dart` | **v1 学习计划规则引擎**：纯本地、可解释、组件上限 2、SRS 配额 |
| `lib/screens/vocabulary_book_screen.dart` | 生词本管理页（Library 二级）：汇总 / 今日计划 / 筛选 / 行内管理 / 证据面板 |
| `lib/widgets/sentence_display.dart` | 字幕逐词可点（`accumulationMode` 默认关闭，用 `WidgetSpan`） |
| `lib/screens/listening_screen.dart` | 顶栏「⋯」→ 生词积累模式（三级开关）；`jumpToSentence()` 供回原声 |
| `lib/screens/library_screen.dart` | 生词本入口（带计数）+ 回原声导航 |
| `lib/screens/root_shell.dart` | **全应用共享**一个 `VocabularyStore`；`ActiveLessonSession` 增加 `startSentenceIndex` + 请求序号 |

### 15.2 这一批做出的三处设计裁决

**① 今日计划与词条列表放在同一页。** 两者是同一件事的两个视角（"我今天练什么" / "我总共存了什么"），拆成两个二级入口只会让用户来回横跳。等闪卡复习上线、入口变多时再拆。

**② Library 入口只在生词本非空时出现。** 空生词本不该在课程列表上占一行；新用户的第一条引导放在积累模式的提示文案里。入口行直接给出「候选 N · 今日计划 M」，不点进去也能看出有没有事要做。

**③ 回原声 = 退出二级页 + 落到证据句 + 开播。** 实现上给 Shell 增加了 `onOpenLessonAtSentence` 回调，并在 `_ListenTab.didUpdateWidget` 里做**同课显式跳转**——因为课程没变时 `GlobalKey` 不重建，`initialSentenceIndex` 只在 `initState` 读一次，只传参数会静默停在原句。

> **★ 测试抓到的一个真实交互断层**：第一版实现里，用户在生词本页点「回原声」后，音频确实跳转开播，但**眼前的页面没变**（二级页仍压在 Shell 之上）——声音在后台响而画面毫无反应。修法是在回调前 `Navigator.of(context).maybePop()` 退出二级页。这类"功能对、观感断"的缺陷只有把 Shell 与页面一起 pump 起来才测得出来。

### 15.3 v1 规则表的一处**超出原设计**的补充

`DictationDiffType.extra`（多写）在原规则表里没有对应行。裁决：多写意味着用户**听到了原文里没有的东西**，属听辨问题而非拼写问题，因此按听辨处理但**只给原声回听、不给重听写**——「重写一遍」对「多写」没有针对性（他不知道该少写哪个）。`matched`（命中）则什么都不出。二者均已在代码注释与测试中显式标注。

### 15.4 验收对照（§14.3 五条）

| 验收标准 | 状态 |
|:--|:--|
| ① 断网可用 | ✅ 全部逻辑本地：判重、状态机、计划规则均无网络调用 |
| ② 可解释 | ✅ `PlanReason` 唯一出口，UI 不得自行拼条件；页面直接显示「依据: …」 |
| ③ 不制造复习债 | ✅ 仅点存无证据 → 不出组件（有专门测试） |
| ④ 一次最多 2 组件 | ✅ 引擎内强制截断（`maxComponentsPerItem`） |
| ⑤ 不做 AI 出题也能闭环 | ✅ 点存 → 候选池 → 计划 → 证据面板 → 回原声 |

### 15.5 未做（下一棒）

- 长按拖动圈短语（`phraseFor` / `phraseSpan` 已就绪，UI 未接）
- 组件的**执行页**（回原声/重听写/Cloze 目前只有建议标签，点了还没有落地页）
- 闪卡复习入口（`EPIC-04` 既有的 `AnkiReviewDialog` 仍是按句判重的老模型）
- lemma 归并与 phrase lexicon
- AI 出题与开放答案评判（v1.5）
