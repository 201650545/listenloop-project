# 04 AI 伴学与 Anki 记忆卡优化设计 (English-First AI & Anki Overhaul)

> [!IMPORTANT]
> 本文是 2026-09-23 的**设计方案**（手机已拔线，先设计后实施）。重心明确转向 **纯英文精听**：AI 伴学与 Anki 记忆卡全部围绕英文场景重构，日语/中文课程降级为次要通道。

> [!NOTE]
> 配套已落地代码：`D:\listenloop`（在线通道已打通，见文末「已完成」一节）。本文描述的是**下一阶段**的设计。

---

## 一、 现状诊断（代码事实核查）

| 模块 | 现状 | 问题 |
| :--- | :--- | :--- |
| AI 伴学 | 2026-09-23 起直通本机网关 `:3100`，默认 `free-heavy`，带 5 条免费回退链 | ① Persona 仍为中文输出的「外语精听导师」，不区分语种；② 无结果缓存，同一句重复提问重复烧额度；③ 无流式，长回答需干等 |
| Anki 卡 | `AnkiCard` 字段：`clozeWord` / `phoneticClue` / `aiExplanation` | ① 三个字段全部由**本地中文模板**生成，AI 从未参与；② `clozeWord` 取「最后一个词」，毫无语义重点；③ 卡面是中文，与「纯英文 Anki」设计（`03_纯英文Anki与AI机制设计.md`）不符 |
| 学习中心 | `AGENT_MANIFEST.json` 中 `L1_LEARN` 状态 `NEXT_SPRINT` | 复习入口、今日到期卡、发音弱项雷达均未实现，SM-2 算法虽已就绪但无界面 |
| 发音标注 | 无 | 03 号文档定义的四大音变（连读/弱读/闪音/失爆）目前只存在于文档里 |

---

## 二、 目标：English-Only

1. **卡面纯英文**：正面只有音频 + 英文挖空句 + 英文发音提示；背面给英文拆解，中文仅作为释义对照位。
2. **AI 私教英语化**：英文课程使用英文 Persona（英文输出），把四大音变讲透；日语/中文课程各自保留独立 Persona。
3. **AI 真正参与制卡**：卡片内容由在线模型生成，本地模板只作失败兜底。

---

## 三、 AI 伴学优化方案

### 1. Persona 分层（按课程语种）

| 课程语言 | Persona | 输出语言 | 分析重点 |
| :--- | :--- | :--- | :--- |
| `en`（重点） | English Listening & Phonetics Coach | 英文 | Liaison / Incomplete plosion / Weak form / Flap T + 语调起伏 |
| `ja` | 日语精听私教 | 中文 | 音便、促音、长音、声调 |
| `zh` | 中文精听助手 | 中文 | 轻声、儿化、变调 |

英文 Persona 的系统提示要点（草案）：

```
You are ListenLoop's English listening & phonetics coach.
Answer in English. Keep each reply under 180 words.
For the current sentence, always cover, when relevant:
1. Liaison — where the final consonant glides into the next vowel
2. Weak form — function words reduced to /ə/ or /ɪ/
3. Flap T / soft D — /t/ between vowels
4. Incomplete plosion — a plosive followed by another consonant
Format: short bullets, one emoji marker per point, no filler.
```

> [!TIP]
> 现有中文版回答是 250~450 字；英文版建议压到 **120~180 词**，移动端一屏可读完，也省额度。

### 2. 结果缓存（省额度 + 秒回）

- Key：`hash(lessonId + sentenceIndex + promptType + personaVersion)`
- 存储：与 Anki 卡同层（SharedPreferences 现存量较小，建议迁到 SQLite 新表 `ai_cache`）
- 失效：切换模型族或 Persona 版本时整体作废；手动「重新解析」按钮强制刷新

### 3. 失败分层提示

| 错误 | 用户看到 | 动作 |
| :--- | :--- | :--- |
| 鉴权失败 | 网关密钥无效，请到设置页核对 | 不重试（换模型无用） |
| 全部免费线路限流 | 免费线路正忙，已切换离线解析 | 提供「稍后重试」 |
| 网络不可达 | 未连上网关（USB 调试需 adb reverse） | 提供「重试」+ 离线解析 |

---

## 四、 Anki 记忆卡优化方案

### 1. 数据模型升级（`AnkiCard`）

| 字段 | 变更 | 说明 |
| :--- | :--- | :--- |
| `targetWord`（原 `clozeWord`） | 重命名 + AI 选词 | 由模型挑选**承载语义或发音难点的词/语块**，而非「最后一个词」 |
| `sentenceCloze` | **新增** | 正面显示的挖空句，形如 `... pick [ ______ ] up` |
| `phoneticHintEn` | **新增** | 正面英文发音提示（≤ 12 词） |
| `phoneticAnalysis` | **新增** | 背面英文音变拆解（四大音变逐条） |
| `phoneticClue` | 保留旧字段 | 兼容旧卡，读取时若 `phoneticHintEn` 为空则回退 |
| `aiExplanation` | 改为中文释义位 | 对应模板里的 `Sentence_ZH` |

迁移策略：`fromJson` 容忍新字段缺失，旧卡自动回退到中文模板文案；新卡一律写全新字段。

### 2. 卡片模板对齐 03 号文档

**正面（Front）**

```
🎧 {{Audio}}
{{Sentence_Cloze}}          # 英文挖空句
{{Phonetic_Hint}}           # 英文提示，例："listen for the flap T in 'better'"
```

**背面（Back）**

```
{{Target_Word}}             # 目标词 + 音标
{{Full_Sentence_EN}}        # 完整英文原句
{{Sentence_ZH}}             # 中文释义（唯一中文位）
—————————————
🗣️ {{Phonetic_Analysis}}   # 英文音变拆解
[🤖 让 AI 考我造句]  [🎬 还原原片现场]
```

### 3. AI 制卡流程

```
用户打星句子 → 入队（单条串行）→ 调在线模型（free-heavy + 回退链）
      → 严格 JSON 输出 → 校验（cloze 必须能在原句中找到）→ 落库
      → 失败（限流/超时/JSON 不合法）→ 回退本地英文模板 → 标记 offline_generated
```

- **串行 + 800ms 间隔**：免费线路对并发敏感，参考既有翻译层的退避策略
- **JSON 校验**：`sentenceText.contains(targetWord)`，否则判为无效并要求模型重答一次（最多 1 次）
- **离线兜底模板**（英文版，不再用中文）：
  - `phoneticHintEn`: `Listen for the linking between these words.`
  - `phoneticAnalysis`: 规则库匹配（见下）

### 4. 四大音变自动标注（规则表，AI 不可用时兜底）

| 现象 | 正则/词表触发 | 示例输出 |
| :--- | :--- | :--- |
| 辅元连读 | 词尾辅音 + 下一词元音开头 | `pick it up → /pɪkɪtʌp/` |
| 功能词弱读 | `to / for / of / and / can` 等 | `trying to → /ˈtraɪɪŋtə/` |
| 闪音 Flap T | 两元音之间的 `t` | `better → /ˈbedər/` |
| 失去爆破 | 爆破音 + 辅音 | `bad guy → /bæ(d) ɡaɪ/` |

---

## 五、 免费线路策略（沿用已验证结果）

| 用途 | 模型 | 备注 |
| :--- | :--- | :--- |
| 伴学对话 | `free-heavy` → 回退链 | 已实测 2s 级、cost=0 |
| 卡片生成 | 同上 | 串行限速，避免触发限流 |
| 翻译（制课） | 现有 OpenRouter 配置 | 不在本次调整范围 |

> [!WARNING]
> `free-fast` / `free-balanced` 路由到 ling-3.0-flash **推理版**，token 全耗在 `reasoning` 上、`content` 恒为 null，**不要**用作默认。

---

## 六、 落地顺序

| 阶段 | 内容 | 依赖 |
| :--- | :--- | :--- |
| **P0（已完成）** | 在线通道打通：网关配置、设置页卡片、多模型回退、reasoning 兜底 | — |
| **P1** | `AnkiCard` 字段升级 + 迁移 + 单测 | — |
| **P2** | 英文 Persona 分层 + 结果缓存 | P0 |
| **P3** | AI 制卡（串行队列 + JSON 校验 + 离线英文模板） | P1, P2 |
| **P4** | 学习中心 `L1_LEARN`：今日到期卡 / 复习会话 / 弱项雷达 | P3 |

---

## 七、 验收标准（可测）

1. 英文课程的伴学回复**全英文**，且命中四大音变中至少一项（人工抽检 10 条）
2. 同一句二次提问命中缓存，无新请求发出（抓包或日志验证）
3. 新生成的卡片：`sentenceCloze` 非空且 `targetWord` 能在原句中定位；`phoneticHintEn` 为英文
4. 模型全部不可用时，卡片仍能生成（离线英文模板），并在卡上标记来源
5. 全量 `flutter test` 保持全绿

---

## 八、 待郭老师拍板

1. 卡面是否**完全不放中文**（背面 `Sentence_ZH` 保留与否）？
2. 卡片生成是否允许**走付费线路**换质量（当前坚持全免费）？
3. 学习中心是否本轮就开工，还是等 P1~P3 稳定后再做？
4. 英文回答长度上限：120~180 词（建议）还是保持现在的 250~450 字？

---

## 九、 接入模式与上游可达性（2026-09-23 实测，决定「能否脱离 PC」）

### 1. 核心结论：瓶颈是上游可达性，不是网关位置

网关（:3100）本身不产生智能，只是把请求转发给上游厂商 API。**把网关搬到手机上并不能让手机连通那些上游** —— 需先看上游在手机侧是否可达。

### 2. 实测数据（手机 Wi-Fi `ChinaNet-2322` / 192.168.2.12）

| 上游 | PC 侧 | 手机侧 | 结论 |
| :--- | :--- | :--- | :--- |
| openrouter.ai | 200 | **000** | 需墙外代理 |
| api.cloudflare.com | 404（服务在） | **000** | 需墙外代理 |
| api.nvidia.com | — | **000** | 需墙外代理 |
| api-inference.modelscope.cn | 200 | **200** | ✅ 手机直连可用 |
| api.siliconflow.cn | — | 401（缺 key） | ✅ 手机直连可用 |
| open.bigmodel.cn（智谱） | — | 401 | ✅ 手机直连可用 |
| token.sensenova.cn（商汤） | — | 401 | ✅ 手机直连可用 |
| ark.cn-beijing.volces.com（火山） | — | 401 | ✅ 手机直连可用 |

> [!IMPORTANT]
> 手机上 `000` 是"完全不可达"，`401` 是"服务可达、仅缺鉴权" —— 后者才是真的能用。

### 3. 端到端验证：手机直连国内免费渠道（已通过）

在**手机侧**直接调用 ModelScope（该渠道在网关里标注 `billing_type: free_quota` / `free: True`）：

```
POST https://api-inference.modelscope.cn/v1/chat/completions
model: deepseek-ai/DeepSeek-V4-Flash-0731
→ HTTP 200 / 1.93s / content: "ready" / usage: 101 tokens
```

**全程不需要 PC、不需要数据线、不需要代理、不需要同一局域网。**

这意味着「手机独立可用」的最小改动是：**设置页把网关地址改成国内 OpenAI 兼容端点 + 填对应 key**，App 现有能力即可支持，无需装网关。

### 4. 三种接入模式对比（更新版）

| 模式 | 要求 | 可用上游 | 适用 |
| :--- | :--- | :--- | :--- |
| **A. USB + adb reverse**（当前） | 插数据线 | 网关全部渠道（PC 有 TUN 代理，含墙外） | 在家精听，免费线路最多 |
| **B. 局域网** | 手机与 PC 同网段 | 同上 | ⚠️ 当前不可用：PC 在 `192.168.152.x`、手机在 `192.168.2.x`，**不同网段** |
| **C. 手机直连国内端点**（推荐补充） | 无 | ModelScope / 硅基流动 / 智谱 / 商汤 / 火山 | 随时随地，完全脱离 PC |
| **D. 网关搬手机（Termux）** | 手机装 Termux 保活 | ⚠️ 仍需手机可达的上游 → 墙外渠道依旧不可用，收益有限 | 不建议 |
| **E. 网关部署到墙外云服务器** | 服务器成本 | 全部渠道 | 最省心，手机随时可用 |

### 5. 若要做 C 模式的落地优化（待拍板）

1. 设置页增加**「服务预设」**快捷项：ModelScope / 硅基流动 / 智谱 / USB 中继，一键填 baseUrl + model；
2. 现有 `kTutorFreeFallbackModels` 全是**墙外**线路（free-heavy 等路由到 nvidia/cloudflare），**在 C 模式下全部不可用** → 需要按上游可达性分组，新增一组**国内免费回退链**；
3. 失败提示要区分「无网络」与「上游被墙」，后者直接引导用户切换预设。

---

## 十、 统一模型服务：小米 MiMo（2026-09-23 落地，已取代网关与 OpenRouter）

### 1. 决策与依据

郭老师拍板：**App 内所有用到模型的地方（AI 伴学 + 字幕翻译）统一用小米 MiMo 的 flash 模型**，不再依赖 PC 网关与 OpenRouter。

| 项 | 值 |
| :--- | :--- |
| Base URL | `https://api.xiaomimimo.com/v1` |
| 模型 | `mimo-v2.6-flash` |
| 鉴权 | Bearer key，随包预填 |

选它的理由（全部手机侧实测，不是推测）：

1. **手机直连可用**：`/v1/models` **HTTP 200 / 0.28s** —— 不需要 PC、不需要 adb reverse、不需要代理、不需要同一局域网；而网关那批墙外线路（free-heavy 等）在手机侧实测全部不可达。
2. **字幕翻译胜任**：6.9s，严格返回 `{"translations": [...]}`，条数与输入一致。
3. **英语伴学胜任**：7.5s，输出规范的连读／弱读／闪音分析（实测 `Can I pick it up for you?` 逐点拆解正确）。
4. 该模型带少量 reasoning token，但 `content` 正常返回，不存在 ling-3.0-flash 那种"只吐推理链"的问题。

### 2. 代码落地

| 位置 | 变更 |
| :--- | :--- |
| `app_preferences.dart` | 新增 `kDefaultMimoBaseUrl / kDefaultMimoApiKey / kDefaultMimoModel`；`kDefaultTranslation*` 与 `kDefaultTutor*` 全部改指 MiMo；回退链 `kTutorFallbackModels` = flash → pro → v2.5（同厂同 key，只换档位） |
| 配置迁移 | 新增 `configVersion`（当前 **3**）。装载 `version < 3` 的存档时，把伴学与翻译端点一次性改写为 MiMo 并把新值**写回存储** |
| `translation_service.dart` | 翻译请求补 `max_tokens: 2048` —— 批量 12 句加 reasoning token 有被截断的风险，截断后 JSON 条数不符会让整批翻译失败 |
| 设置页 | 状态条由「FREE」徽标改为「MiMo」标识；模型列表徽标由「FREE」改为「回退」，标注哪些档位在自动回退链内 |

> [!WARNING]
> **迁移必须落盘**。首版迁移（version 2）只改了内存返回值、没写回 SharedPreferences，导致第二次启动 `version` 已是 2 → 又读回旧端点。真机上复现后修正为 version 3，并补了两条回归测试锁住这个行为。

### 3. 仍保留的能力

- **USB 中继模式仍可用**：设置页把地址改回 `http://127.0.0.1:3100/v1` 即可，用于需要网关聚合渠道（含墙外线路）的场景。
- **失败自动回退**：flash 不可用时依次退到 pro / v2.5，全部同端点同鉴权。
- **离线兜底不变**：所有在线请求失败时，伴学仍可退到内置离线模板。

---

## 附：本轮已完成（2026-09-23，代码已落地）

- `AiGovernorService` 改为通用 OpenAI 兼容客户端，新增 `sendOnlineChat` 与多模型自动回退
- reasoning-only 模型兜底（content 为空时返回推理内容）
- 设置页新增「AI 伴学 (在线大模型)」卡片并置顶，含在线模型列表（FREE 徽标）、一键填充、真实连通自检
- 默认：网关 `http://127.0.0.1:3100/v1` + `free-heavy` + 5 条免费回退
- 全量测试 253 项通过
