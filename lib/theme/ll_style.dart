/// The four visual styles and their background materials.
///
/// Kept free of `LLPalette` / `LLShape` so the preferences layer can persist a
/// style without importing the theme layer (which imports preferences).
/// Palette and shape mapping live in `listenloop_theme.dart` as an extension.
/// 四套风格。白昼与黑夜**不在这里**——它们就是浅色/深色模式本身（郭老师
/// 2026-10-07 定名），由 `themeMode` 管，`base` 是它们共用的那套黑白极简。
enum LLStyle {
  /// 基础：纸白墨黑（白昼）与墨蓝夜色（黑夜）两面，随明暗切换。
  base,

  /// 学堂: rice-paper cream, pine ink, cinnabar marginal notes, bamboo-green
  /// rules. No drop shadows — depth comes from ink lines.
  academy,

  /// 书院: limestone and oak, ivy green, brass hairlines, double rules.
  oxbridge,

  /// 都市: steel and glass, harbour blue, subway yellow, cold cyan glow.
  metropolis;

  String label(bool zh) => switch (this) {
    LLStyle.base => zh ? '基础' : 'Base',
    LLStyle.academy => zh ? '学堂' : 'Academy',
    LLStyle.oxbridge => zh ? '书院' : 'College',
    LLStyle.metropolis => zh ? '都市' : 'Metropolis',
  };

  /// One-line description shown in the style picker.
  String blurb(bool zh) => switch (this) {
    LLStyle.base => zh ? '黑白极简，随明暗切换' : 'Black & white, follows brightness',
    LLStyle.academy => zh ? '宣纸松墨，朱砂批点' : 'Rice paper, pine ink, cinnabar',
    LLStyle.oxbridge => zh ? '石灰橡木，常春藤黄铜' : 'Limestone, oak, ivy, brass',
    LLStyle.metropolis => zh ? '钢青玻璃，地铁黄线' : 'Steel, glass, subway yellow',
  };

  /// Latin face used for Pinyin annotation, kept separate from the Chinese face
  /// so swapping the style cannot drop Pinyin onto a missing font (doc 21 §三).
  /// The 拼音行/汉字行 mixed-alignment rule itself is untouched.
  String? get pinyinFont => switch (this) {
    LLStyle.base || LLStyle.academy => 'SongTi',
    LLStyle.oxbridge => 'serif',
    LLStyle.metropolis => 'LL Sans',
  };

  /// Latin face for headings / brand type.
  String? get headingFont => switch (this) {
    LLStyle.base || LLStyle.metropolis => 'LL Sans',
    LLStyle.academy || LLStyle.oxbridge => 'serif',
  };

  /// Face for the vertical marginal note (`LLMarginalNote`). 儒雅那一套的眉批
  /// 必须是手写体的仿宋，不能跟着正文吃 `headingFont` 的衬线（doc 21 §二十一 队列 10）。
  /// A full 楷体 would be +10~12 MB (doc 21 §三, 未拍板), so 学堂/书院 ship on the
  /// bundled FangSong and swap to 楷体 only if that ever gets priced in.
  String? get noteFont => switch (this) {
    LLStyle.base => null,
    LLStyle.academy || LLStyle.oxbridge => 'FangSong',
    LLStyle.metropolis => 'LL Sans',
  };

  LLTexture get texture => switch (this) {
    LLStyle.base => LLTexture.none,
    LLStyle.academy => LLTexture.ricePaper,
    LLStyle.oxbridge => LLTexture.inkRules,
    // 都市：镜面/幕墙。WP-G 之后这里一直是 none，四套里唯一没有材质的
    // 风格——它因此只剩配色差异，与另外三套不同级。glaze 画竖向幕墙分格
    // 加一道斜向高光，不铺满、不抢字。
    LLStyle.metropolis => LLTexture.glaze,
  };
}

/// Background material painted behind each screen. Vector only — no raster
/// assets, so textures follow the palette and never blur at large text sizes.
enum LLTexture {
  none,

  /// 宣纸：竹帘留下的竖向细纹（学堂）。
  ricePaper,

  /// 稿纸：横向细行 + 左侧栏线（书院）。
  inkRules,

  /// 幕墙：竖向分格 + 一道斜向高光（都市）。
  glaze,
}
