# 03 纯英文 Anki 与 AI 机制设计 (English Anki & AI Spec)

> [!NOTE]
> 本文规范专为**纯英文（English-Only）**精听特训打造的 AI + Anki 记忆卡系统设计。

---

## 一、 英语发音规则与自动标注体系 (Phonetics)

AI 在对打星句子进行分析时，自动提取以下四大英语发音特征，并嵌入卡片背面：

| 现象 (Phonetic Phenomenon) | 规则描述 | 原声音频示例 |
| :--- | :--- | :--- |
| **辅元连读 (Consonant + Vowel)** | 前词辅音结尾，后词元音开头，自然拼合 | `pick it up` ➔ `/pɪkɪtʌp/` |
| **功能词弱读 (Weak Forms)** | 介词/助词等功能词元音弱化为 `/ə/` 或 `/ɪ/` | `trying to` ➔ `/ˈtraɪɪŋtə/` |
| **闪音 (Flap T / Soft D)** | 处于两元音之间的 /t/ 软化为轻弹音 | `better` ➔ `/ˈbedər/` |
| **失去爆破 (Incomplete Plosion)** | 爆破音遇辅音只做发音动作而不爆破 | `bad guy` ➔ `/bæ(d) ɡaɪ/` |

---

## 二、 纯英文 Anki 卡片模板标准 (Card Template)

### 1. 卡片正面 (Front)
```html
<div class="card-front">
  <div class="audio-player">{{Audio}}</div>
  <div class="cloze-sentence">{{Sentence_Cloze}}</div>
  <div class="phonetic-hint">🎧 连读提示：{{Phonetic_Hint}}</div>
</div>
```

### 2. 卡片背面 (Back)
```html
<div class="card-back">
  <div class="target-word">{{Target_Word}}</div>
  <div class="full-sentence">{{Full_Sentence_EN}}</div>
  <div class="translation">{{Sentence_ZH}}</div>
  <hr/>
  <div class="phonetic-breakdown">
    <b>🗣️ 连读与音变拆解：</b><br/>
    {{Phonetic_Analysis}}
  </div>
  <div class="ai-actions">
    <button onclick="askAiToTest()">🤖 让 AI 考我造句</button>
    <button onclick="jumpToScene()">🎬 还原原片现场</button>
  </div>
</div>
```

---

## 三、 Anki `.apkg` 导出契约与工程落地

1. **导出文件格式**：标准的 ZIP 压缩包，后缀为 `.apkg`；
2. **包内文件结构**：
   - `collection.anki2`：SQLite 数据库，包含 decks、models、notes、cards 表；
   - `media`：JSON 映射文件，将媒体数字文件名（如 `0`、`1`）映射至原声剪切音频文件名（如 `ted_ed_s14.mp3`）；
   - 各音频切片二进制文件；
3. **兼容性**：100% 无缝兼容 Windows/Mac 桌面端 Anki、iOS AnkiMobile、Android AnkiDroid。

---

## 四、 Groq 超高速 AI 伴学引擎接入规范 (Groq Qwen 3.8 27B)

为实现移动端毫秒级响应的母语级伴学体验，系统已正式接入 Groq 平台的 Qwen 模型：

1. **模型配置**：
   - **Model ID**：`qwen/qwen3.8-27b`
   - **API Endpoint**：`https://api.groq.com/openai/v1/chat/completions`
   - **协议标准**：OpenAI 兼容 RESTful 规范（Bearer Token 授权）
2. **伴学 Prompt 工程标准**：
   - **角色设定**：世界顶级专业外语精听与语音学私教导师（ListenLoop AI Tutor）；
   - **上下文注入**：学员当前正在循环精听的原声音频区间、外语原句、中文释义；
   - **分析核心**：直击四大音变（连读滑音、辅音失爆、功能词弱读、闪音）与语调高低起伏；
   - **字数与排版**：单次回复控制在 250~450 字，以 Emoji 与 Markdown 清晰分点，直击听力突破口。
3. **安全与容错机制**：
   - **安全存储**：API Key 仅通过 `SharedPreferences` 加密保存在手机本地设备，不上传云端；
   - **离线降级 (Offline Fallback)**：未配置 Key 或网络受阻时，一键自动降级为内置离线智能模版，确保用户零阻塞沉浸式学习。

