/// 词形还原器（lemma normalizer）—— 13 号设计稿 §三 的落地。
///
/// 三层结构，**逐层兜底，不做猜测**（郭老师 2026-09-25 拍板）：
///   1. 不规则词表（~180 条高频变形 → 原形）；
///   2. 规则词尾剥离（-s/-es/-ed/-ing + 双写还原 + -ied→-y）；
///   3. 兜底 = 自身（小写化）—— 专有名词 / 未登录词 / 缩写不猜。
///
/// 纪律：
///   * lemma 只用于**判重与归并**；occurrence 永远同时保留原始 surfaceForm，
///     还原规则日后升级可全量重算（13 号 §三）；
///   * `kind == phrase` 不参与归并（"give up" 归到 "give" 是错误归并）——
///     由调用方保证，本文件不做 kind 判断；
///   * 纯函数、零依赖、离线。
library;

/// 不规则变形表：**变形（小写）→ 原形**。覆盖高频动词变形、名词复数、
/// 比较级最高级。规模按拍板取 ~180 条起步，后续可扩。
const Map<String, String> _irregular = {
  // ---- be / have / do 系
  'was': 'be', 'were': 'be', 'been': 'be', 'being': 'be', 'am': 'be',
  'is': 'be', 'are': 'be',
  'had': 'have', 'has': 'have',
  'did': 'do', 'done': 'do', 'does': 'do',
  // ---- 高频不规则动词（变形 → 原形）
  'went': 'go', 'gone': 'go', 'goes': 'go',
  'took': 'take', 'taken': 'take', 'takes': 'take',
  'came': 'come', 'comes': 'come',
  'got': 'get', 'gotten': 'get', 'gets': 'get',
  'made': 'make', 'makes': 'make',
  'said': 'say', 'says': 'say',
  'saw': 'see', 'seen': 'see', 'sees': 'see',
  'knew': 'know', 'known': 'know', 'knows': 'know',
  'thought': 'think', 'thinks': 'think',
  'found': 'find', 'finds': 'find',
  'gave': 'give', 'given': 'give', 'gives': 'give',
  'told': 'tell', 'tells': 'tell',
  'felt': 'feel', 'feels': 'feel',
  'brought': 'bring', 'brings': 'bring',
  'began': 'begin', 'begun': 'begin', 'begins': 'begin',
  'kept': 'keep', 'keeps': 'keep',
  'held': 'hold', 'holds': 'hold',
  'wrote': 'write', 'written': 'write', 'writes': 'write',
  'stood': 'stand', 'stands': 'stand',
  'heard': 'hear', 'hears': 'hear',
  'let': 'let',
  'meant': 'mean', 'means': 'mean',
  'met': 'meet', 'meets': 'meet',
  'ran': 'run', 'runs': 'run',
  'paid': 'pay', 'pays': 'pay',
  'sat': 'sit', 'sits': 'sit',
  'spoke': 'speak', 'spoken': 'speak', 'speaks': 'speak',
  'lay': 'lie', 'lain': 'lie', 'lies': 'lie',
  'lost': 'lose', 'loses': 'lose',
  'sold': 'sell', 'sells': 'sell',
  'sent': 'send', 'sends': 'send',
  'built': 'build', 'builds': 'build',
  'understood': 'understand', 'understands': 'understand',
  'grew': 'grow', 'grown': 'grow', 'grows': 'grow',
  'flew': 'fly', 'flown': 'fly', 'flies': 'fly',
  'fell': 'fall', 'fallen': 'fall', 'falls': 'fall',
  'broke': 'break', 'broken': 'break', 'breaks': 'break',
  'rose': 'rise', 'risen': 'rise', 'rises': 'rise',
  'drove': 'drive', 'driven': 'drive', 'drives': 'drive',
  'ate': 'eat', 'eaten': 'eat', 'eats': 'eat',
  'drank': 'drink', 'drunk': 'drink', 'drinks': 'drink',
  'slept': 'sleep', 'sleeps': 'sleep',
  'woke': 'wake', 'woken': 'wake', 'wakes': 'wake',
  'wore': 'wear', 'worn': 'wear', 'wears': 'wear',
  'won': 'win', 'wins': 'win',
  'swam': 'swim', 'swum': 'swim', 'swims': 'swim',
  'sang': 'sing', 'sung': 'sing', 'sings': 'sing',
  'rang': 'ring', 'rung': 'ring', 'rings': 'ring',
  'fought': 'fight', 'fights': 'fight',
  'caught': 'catch', 'catches': 'catch',
  'taught': 'teach', 'teaches': 'teach',
  'bought': 'buy', 'buys': 'buy',
  'chose': 'choose', 'chosen': 'choose', 'chooses': 'choose',
  'drew': 'draw', 'drawn': 'draw', 'draws': 'draw',
  'rode': 'ride', 'ridden': 'ride', 'rides': 'ride',
  'showed': 'show', 'shown': 'show', 'shows': 'show',
  'led': 'lead', 'leads': 'lead',
  'read': 'read', 'reads': 'read',
  'left': 'leave', 'leaves': 'leave',
  'swept': 'sweep', 'sweeps': 'sweep',
  'slew': 'slay', 'slays': 'slay',
  'stole': 'steal', 'stolen': 'steal', 'steals': 'steal',
  'hit': 'hit', 'hits': 'hit',
  'put': 'put', 'puts': 'put',
  'cut': 'cut', 'cuts': 'cut',
  'set': 'set', 'sets': 'set',
  'hurt': 'hurt', 'hurts': 'hurt',
  'spread': 'spread', 'spreads': 'spread',
  'cost': 'cost', 'costs': 'cost',
  // ---- 名词复数 / 单三 (不规则)
  'children': 'child', 'men': 'man', 'women': 'woman',
  'feet': 'foot', 'teeth': 'tooth', 'geese': 'goose',
  'mice': 'mouse', 'lice': 'louse', 'oxen': 'ox',
  'people': 'person',
  'knives': 'knife', 'wives': 'wife', 'lives': 'life',
  // 同形歧义弃用：'leaves'（leave 单三 vs leaf 复数）按动词高频保留 leave；
  // 'lives'（live 单三 vs life 复数）按名词高频保留 life。词形层面无法区分，
  // 保守策略 = 只保留更常见的一条（13 号 §三「宁缺勿错」）。
  'loaves': 'loaf', 'thieves': 'thief',
  'wolves': 'wolf', 'shelves': 'shelf', 'calves': 'calf',
  'halves': 'half', 'elves': 'elf',
  'potatoes': 'potato', 'tomatoes': 'tomato', 'heroes': 'hero',
  'echoes': 'echo', 'vetoes': 'veto',
  'phenomena': 'phenomenon', 'criteria': 'criterion',
  'data': 'datum', 'media': 'medium', 'bacteria': 'bacterium',
  'analyses': 'analysis', 'diagnoses': 'diagnosis',
  'crises': 'crisis', 'theses': 'thesis',
  'stimuli': 'stimulus', 'formulae': 'formula',
  // ---- 比较级 / 最高级
  'better': 'good', 'best': 'good',
  'worse': 'bad', 'worst': 'bad',
  'less': 'little', 'least': 'little',
  'more': 'many', 'most': 'many',
  'farther': 'far', 'furthest': 'far',
  // ---- 常见副词/代词形态
  'himself': 'him', 'herself': 'her', 'itself': 'it',
  'themselves': 'them', 'ourselves': 'us', 'yourselves': 'you',
};

/// 规则词尾剥离（层 2）。返回 null 表示**不适用**（保持原形，宁缺勿错）。
String? _stripRegular(String lower) {
  // -ies → -y（studied 走 -ed 双分支；carries→carry）
  if (lower.endsWith('ies') && lower.length >= 4) {
    return '${lower.substring(0, lower.length - 3)}y';
  }

  // -ing：stem ≥ 3 且双写还原；stem 不以 w/x/y 结尾（rowing→row 不还原）
  if (lower.endsWith('ing') && lower.length >= 5) {
    final stem = lower.substring(0, lower.length - 3);
    final fixed = _undoGemination(stem);
    if (fixed != null) return fixed;
    return stem;
  }

  // -ed：stem ≥ 2 且双写还原；否则直接去 ed
  if (lower.endsWith('ied') && lower.length >= 4) {
    return '${lower.substring(0, lower.length - 3)}y';
  }
  if (lower.endsWith('ed') && lower.length >= 4) {
    final stem = lower.substring(0, lower.length - 2);
    final fixed = _undoGemination(stem);
    if (fixed != null) return fixed;
    return stem;
  }

  // -es：仅当 stem 以 s/x/z/ch/sh 结尾（watches→watch、boxes→box、buses→bus）
  if (lower.endsWith('es') && lower.length >= 4) {
    final stem = lower.substring(0, lower.length - 2);
    if (_hisses(stem)) return stem;
  }

  // -s：长度 ≥ 3 且不以 ss 结尾（class 不剥）；不以 us 结尾（bus 不剥）
  if (lower.endsWith('s') &&
      !lower.endsWith('ss') &&
      !lower.endsWith('us') &&
      !lower.endsWith('is') &&
      lower.length >= 3) {
    return lower.substring(0, lower.length - 1);
  }

  return null;
}

/// 尾部双写辅音还原（running→runn→run、stopped→stopp→stop）。
///
/// 条件：stem 以「同一辅音连续两个」结尾，且该辅音不是 w/x/y。
/// 返回 null 表示不适用。
String? _undoGemination(String stem) {
  if (stem.length < 3) return null;
  final last = stem[stem.length - 1];
  final prev = stem[stem.length - 2];
  if (last != prev) return null;
  if (_isVowel(last)) return null;
  if (last == 'w' || last == 'x' || last == 'y') return null;
  return stem.substring(0, stem.length - 1);
}

/// 咝音词尾：-s / -x / -z / -ch / -sh（这些词的复数/单三加 -es）。
bool _hisses(String stem) {
  if (stem.isEmpty) return false;
  return stem.endsWith('s') ||
      stem.endsWith('x') ||
      stem.endsWith('z') ||
      stem.endsWith('ch') ||
      stem.endsWith('sh');
}

bool _isVowel(String ch) =>
    ch == 'a' || ch == 'e' || ch == 'i' || ch == 'o' || ch == 'u';

/// 还原 lemma（主入口）。
///
/// 顺序：小写化 → 不规则表 → 规则剥离 → 兜底自身。
/// 空串返回空串（调用方自行判空）。
String lemmaOf(String surfaceForm) {
  final lower = surfaceForm.trim().toLowerCase();
  if (lower.isEmpty) return '';
  return _irregular[lower] ?? _stripRegular(lower) ?? lower;
}

/// 归并键：lemma 的小写形式。判重与归并统一用它。
String lemmaKey(String surfaceForm) => lemmaOf(surfaceForm);
