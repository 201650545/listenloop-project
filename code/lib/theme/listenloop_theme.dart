import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../preferences/app_preferences.dart';
import 'll_style.dart';

/// ListenLoop design tokens — Visual Polish V1 §三–§七, V2 §九–十一,
/// and the four-style extension (doc 21, 2026-10-07).
///
/// A *style* (LLStyle) owns ink hue, material, shape and texture; *brightness*
/// picks which side of that style is lit. Each style therefore ships a light
/// and a dark palette, so `themeMode` / follow-system keeps working untouched.
abstract final class LLColors {
  /// Brand-dark constants — used ONLY by always-black brand surfaces
  /// (splash / intro, spec V2 §三十八) and as the nightfall palette values.
  static const Color bg = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF111111);
  static const Color surfaceHigh = Color(0xFF181818);
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFA3A3A3);
  static const Color textTertiary = Color(0xFF666666);
  static const Color divider = Color(0xFF242424);
  static const Color disabled = Color(0xFF4A4A4A);
  static const Color onPrimary = Color(0xFF0A0A0A);
}

/// Spacing, corner and shadow language per style. 都市 更方、学堂 无影、
/// 古典 双线，所以形状不能是全站常量。
class LLShape extends ThemeExtension<LLShape> {
  const LLShape({
    required this.style,
    required this.card,
    required this.chip,
    required this.pill,
    required this.hairline,
    required this.rule,
    required this.gutter,
    required this.shadowOn,
    required this.shadowAlpha,
    required this.texture,
  });

  /// Which style owns this shape language — the only reliable way for a widget
  /// to ask "which style am I in" without reading preferences.
  final LLStyle style;

  /// Card / sheet corner radius.
  final double card;
  final double chip;
  final double pill;

  /// Ordinary border width (学堂/古典 用发丝线，都市 用实线).
  final double hairline;

  /// Emphasis border width (当前句选中框).
  final double rule;

  /// Inner padding of [LLCard] and friends. 儒雅那一套"卡片不浮，靠留白撑"，
  /// 留白就是它的层次来源，所以这一枚必须跟着风格走，不能全站写死 10。
  final double gutter;

  /// Whether this style uses drop shadows at all.
  final bool shadowOn;
  final double shadowAlpha;
  final LLTexture texture;

  /// 白昼：纸面极淡投影，圆角中等。
  static const LLShape baseLight = LLShape(
    style: LLStyle.base,
    card: 12,
    chip: 6,
    pill: 999,
    hairline: 1,
    rule: 1.6,
    gutter: 10,
    shadowOn: true,
    shadowAlpha: 0.18,
    texture: LLTexture.none,
  );

  /// 黑夜：同一套形状，投影稍重以撑出层级。
  static const LLShape baseDark = LLShape(
    style: LLStyle.base,
    card: 12,
    chip: 6,
    pill: 999,
    hairline: 1,
    rule: 1.6,
    gutter: 10,
    shadowOn: true,
    shadowAlpha: 0.28,
    texture: LLTexture.none,
  );

  /// 学堂：纸面无投影，靠墨线分栏；卡片不浮，层次由留白撑（doc 21 队列 10）。
  static const LLShape paper = LLShape(
    style: LLStyle.academy,
    card: 4,
    chip: 4,
    pill: 999,
    hairline: 0.8,
    rule: 1.4,
    gutter: 14,
    shadowOn: false,
    shadowAlpha: 0,
    texture: LLTexture.ricePaper,
  );

  /// 书院：大圆角不成立，用直角 + 双线。阴影一并去掉——石头的层次靠线，
  /// 不靠投影（doc 21 队列 10「发线不阴影」）。
  static const LLShape stone = LLShape(
    style: LLStyle.oxbridge,
    card: 6,
    chip: 4,
    pill: 6,
    hairline: 1,
    rule: 2,
    gutter: 13,
    shadowOn: false,
    shadowAlpha: 0,
    texture: LLTexture.inkRules,
  );

  /// 都市：利落、几乎直角。
  static const LLShape steel = LLShape(
    style: LLStyle.metropolis,
    card: 4,
    chip: 2,
    pill: 4,
    hairline: 1,
    rule: 1.6,
    gutter: 10,
    shadowOn: true,
    shadowAlpha: 0.32,
    texture: LLTexture.glaze,
  );

  @override
  LLShape copyWith({
    LLStyle? style,
    double? card,
    double? chip,
    double? pill,
    double? hairline,
    double? rule,
    double? gutter,
    bool? shadowOn,
    double? shadowAlpha,
    LLTexture? texture,
  }) => LLShape(
    style: style ?? this.style,
    card: card ?? this.card,
    chip: chip ?? this.chip,
    pill: pill ?? this.pill,
    hairline: hairline ?? this.hairline,
    rule: rule ?? this.rule,
    gutter: gutter ?? this.gutter,
    shadowOn: shadowOn ?? this.shadowOn,
    shadowAlpha: shadowAlpha ?? this.shadowAlpha,
    texture: texture ?? this.texture,
  );

  @override
  LLShape lerp(ThemeExtension<LLShape>? other, double t) {
    if (other is! LLShape) return this;
    return LLShape(
      style: t < 0.5 ? style : other.style,
      card: _d(card, other.card, t),
      chip: _d(chip, other.chip, t),
      pill: _d(pill, other.pill, t),
      hairline: _d(hairline, other.hairline, t),
      rule: _d(rule, other.rule, t),
      gutter: _d(gutter, other.gutter, t),
      shadowOn: t < 0.5 ? shadowOn : other.shadowOn,
      shadowAlpha: _d(shadowAlpha, other.shadowAlpha, t),
      texture: t < 0.5 ? texture : other.texture,
    );
  }
}


/// Brightness- and style-aware palette. Access via `context.ll`.
///
/// Every color a page needs is a field here: the old practice of writing
/// `Colors.white` / `Colors.blueAccent` / `textPrimary.withValues(0.06)`
/// inline is what forced four styles back into two (doc 21 §四).
class LLPalette extends ThemeExtension<LLPalette> {
  const LLPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.disabled,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.annotation,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.scrim,
    required this.onScrim,
    required this.shadow,
    required this.emphasis,
    required this.emphasisStrong,
    required this.tabTrack,
    required this.tabActive,
    required this.tabOnActive,
    required this.controlTrack,
    required this.controlThumb,
    required this.controlThumbBorder,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color disabled;
  final Color onPrimary;

  /// 控件主色：按钮、选中态、进度。儒雅那一套把它从朱砂收回成墨，朱砂降级到
  /// [annotation]——满屏红按钮不是民国课本，黑字米纸加一道朱砂批才是。
  final Color accent;
  final Color onAccent;

  /// Judgement colors: 对 / 近音 / 错 / 提示. These must change with the paper
  /// hue or 听写批改 becomes unreadable (doc 21 §四 last row).
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// 批注色 — 这套风格的"朱砂位"。它**只**出现在眉批（`LLMarginalNote`）、
  /// 旁注、以及需要"有人在书边提一句"的地方，绝不进按钮、Tab、开关：
  /// 儒雅那一套的要求就是「朱砂只作批注与错处」（doc 21 队列 10）。
  /// 错处走 [danger]，两套色在同一种纸上只差一档深浅。
  final Color annotation;

  /// Inverted chips (跳句气泡等) — replaces `textPrimary`-as-background hacks.
  final Color inverseSurface;
  final Color onInverseSurface;

  /// Badges and progress tracks that sit ON artwork, which may be any hue.
  final Color scrim;
  final Color onScrim;

  /// The single shadow color for this style. 黑夜 uses it faintly, paper
  /// styles avoid black washes.
  final Color shadow;

  /// Selected / current-sentence row wash and its stroke.
  final Color emphasis;
  final Color emphasisStrong;

  /// Segmented control (语种 Tab、档位等).
  final Color tabTrack;
  final Color tabActive;
  final Color tabOnActive;

  /// The raised pill selector (设置页的 跟随系统/白昼/黑夜、English/中文、字号档).
  ///
  /// Its thumb carries primary ink and has to read as *raised above* its track
  /// in both brightnesses, which no existing step does: in the light ladder the
  /// step away from the card goes down, in the dark ladder it goes up. So the
  /// pair is authored per style rather than derived — and being tokens, not
  /// `isDark ?` literals, is what lets it glide with the canvas instead of
  /// snapping at the halfway point of a theme change.
  final Color controlTrack;
  final Color controlThumb;
  final Color controlThumbBorder;

  /// Washes are derived, so a style cannot forget to set them.
  Color get accentWash => accent.withValues(
    alpha: brightness == Brightness.dark ? 0.22 : 0.12,
  );
  Color get successWash => success.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.14);
  Color get warningWash => warning.withValues(alpha: brightness == Brightness.dark ? 0.24 : 0.16);
  Color get dangerWash => danger.withValues(alpha: brightness == Brightness.dark ? 0.24 : 0.14);
  Color get infoWash => info.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.12);

  /// The established ListenLoop identity, kept as an alias so existing call
  /// sites and tests (`LLPalette.dark`) keep compiling.
  static const LLPalette dark = nightfallDark;
  static const LLPalette light = daylightLight;

  static const LLPalette daylightLight = LLPalette(
    brightness: Brightness.light,
    bg: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1F1EE),
    textPrimary: Color(0xFF14161A),
    textSecondary: Color(0xFF5C6169),
    textTertiary: Color(0xFF868D95),
    divider: Color(0xFFE4E4E0),
    disabled: Color(0xFFB9BFC6),
    onPrimary: Color(0xFFFAFAF8),
    accent: Color(0xFF2F5DA8),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF2F7D4F),
    warning: Color(0xFFA0670E),
    danger: Color(0xFFB02A21),
    info: Color(0xFF2C6E9B),
    annotation: Color(0xFF2F5DA8),
    inverseSurface: Color(0xFF14161A),
    onInverseSurface: Color(0xFFFAFAF8),
    scrim: Color(0xB3000000),
    onScrim: Color(0xFFFFFFFF),
    shadow: Color(0x14000000),
    emphasis: Color(0x0F14161A),
    emphasisStrong: Color(0x1F14161A),
    tabTrack: Color(0xFFEFEFEA),
    tabActive: Color(0xFF14161A),
    tabOnActive: Color(0xFFFFFFFF),
    controlTrack: Color(0xFFEDEDE9),
    controlThumb: Color(0xFFFFFFFF),
    controlThumbBorder: Color(0xFFDBDBD6),
  );



  static const LLPalette nightfallDark = LLPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0C1014),
    surface: Color(0xFF131920),
    surfaceHigh: Color(0xFF1A222B),
    textPrimary: Color(0xFFE6E9EE),
    textSecondary: Color(0xFF9AA4B2),
    textTertiary: Color(0xFF5F6875),
    divider: Color(0xFF202833),
    disabled: Color(0xFF414A57),
    onPrimary: Color(0xFF0C1014),
    accent: Color(0xFFC9A227),
    onAccent: Color(0xFF0C1014),
    success: Color(0xFF63B583),
    warning: Color(0xFFD8A94F),
    danger: Color(0xFFE06B60),
    info: Color(0xFF79B0D8),
    annotation: Color(0xFFC9A227),
    inverseSurface: Color(0xFFE6E9EE),
    onInverseSurface: Color(0xFF0C1014),
    scrim: Color(0xB3000000),
    onScrim: Color(0xFFEDEFF3),
    shadow: Color(0x40000000),
    emphasis: Color(0x14E6E9EE),
    emphasisStrong: Color(0x2AE6E9EE),
    tabTrack: Color(0xFF1A222B),
    tabActive: Color(0xFFC9A227),
    tabOnActive: Color(0xFF0C1014),
    controlTrack: Color(0xFF0C1014),
    controlThumb: Color(0xFF1E262F),
    controlThumbBorder: Color(0xFF2C3642),
  );

  static const LLPalette academyLight = LLPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF2EAD8),
    surface: Color(0xFFF8F2E4),
    surfaceHigh: Color(0xFFEADFC8),
    textPrimary: Color(0xFF241F19),
    textSecondary: Color(0xFF6B5C46),
    textTertiary: Color(0xFF88775E),
    divider: Color(0xFFDDD0B6),
    disabled: Color(0xFFAFA188),
    onPrimary: Color(0xFFF2EAD8),
    accent: Color(0xFF241F19),
    onAccent: Color(0xFFF8F2E4),
    success: Color(0xFF45704F),
    warning: Color(0xFF8C6216),
    danger: Color(0xFF8E2A22),
    info: Color(0xFF3F6B8A),
    annotation: Color(0xFFB3352B),
    inverseSurface: Color(0xFF241F19),
    onInverseSurface: Color(0xFFF8F2E4),
    scrim: Color(0x99241F19),
    onScrim: Color(0xFFF8F2E4),
    shadow: Color(0x0F241F19),
    emphasis: Color(0x14241F19),
    emphasisStrong: Color(0x1F241F19),
    tabTrack: Color(0xFFE7DCC4),
    tabActive: Color(0xFF241F19),
    tabOnActive: Color(0xFFF8F2E4),
    controlTrack: Color(0xFFE7DCC4),
    controlThumb: Color(0xFFF8F2E4),
    controlThumbBorder: Color(0xFFD8C9A8),
  );

  static const LLPalette academyDark = LLPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF1E1A15),
    surface: Color(0xFF26211A),
    surfaceHigh: Color(0xFF302A21),
    textPrimary: Color(0xFFEFE6D2),
    textSecondary: Color(0xFFB5A489),
    textTertiary: Color(0xFF7A6C56),
    divider: Color(0xFF3A3228),
    disabled: Color(0xFF5C5142),
    onPrimary: Color(0xFF1E1A15),
    accent: Color(0xFFB5A489),
    onAccent: Color(0xFF1E1A15),
    success: Color(0xFF7FAE8B),
    warning: Color(0xFFD8A94F),
    danger: Color(0xFFD96A4A),
    info: Color(0xFF8AB0C8),
    annotation: Color(0xFFE07A50),
    inverseSurface: Color(0xFFEFE6D2),
    onInverseSurface: Color(0xFF1E1A15),
    scrim: Color(0xB3100C08),
    onScrim: Color(0xFFEFE6D2),
    shadow: Color(0x00000000),
    emphasis: Color(0x14EFE6D2),
    emphasisStrong: Color(0x1FEFE6D2),
    tabTrack: Color(0xFF302A21),
    tabActive: Color(0xFFB5A489),
    tabOnActive: Color(0xFF1E1A15),
    controlTrack: Color(0xFF1E1A15),
    controlThumb: Color(0xFF332C22),
    controlThumbBorder: Color(0xFF443B2C),
  );

  static const LLPalette oxbridgeLight = LLPalette(
    brightness: Brightness.light,
    bg: Color(0xFFE9E3D7),
    surface: Color(0xFFF4EFE6),
    surfaceHigh: Color(0xFFDED6C6),
    textPrimary: Color(0xFF1F1B16),
    textSecondary: Color(0xFF5F5741),
    textTertiary: Color(0xFF847A62),
    divider: Color(0xFFD3CAB8),
    disabled: Color(0xFFA8A08C),
    onPrimary: Color(0xFFE9E3D7),
    accent: Color(0xFF1F3A2C),
    onAccent: Color(0xFFF4EFE6),
    success: Color(0xFF3E6B4C),
    warning: Color(0xFF816020),
    danger: Color(0xFF6E2634),
    info: Color(0xFF43617E),
    annotation: Color(0xFF6E2634),
    inverseSurface: Color(0xFF1F3A2C),
    onInverseSurface: Color(0xFFF4EFE6),
    scrim: Color(0xA61F1B16),
    onScrim: Color(0xFFF4EFE6),
    shadow: Color(0x141F1B16),
    emphasis: Color(0x141F3A2C),
    emphasisStrong: Color(0x331F3A2C),
    tabTrack: Color(0xFFDED6C6),
    tabActive: Color(0xFF1F3A2C),
    tabOnActive: Color(0xFFF4EFE6),
    controlTrack: Color(0xFFDED6C6),
    controlThumb: Color(0xFFF4EFE6),
    controlThumbBorder: Color(0xFFC9BFAB),
  );

  static const LLPalette oxbridgeDark = LLPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF171310),
    surface: Color(0xFF211B16),
    surfaceHigh: Color(0xFF2A2219),
    textPrimary: Color(0xFFE8DFCB),
    textSecondary: Color(0xFFA99B7F),
    // WP-G 终审实测：原 #6F6350 压在 surface(#211B16) 上只有 2.90、
    // 压 surfaceHigh(#2A2219) 只有 2.67，全站所有弱化字（含设置页摘要行、
    // LLNavRow、个人中心卡副标题）在「书院·暗」这一套下都低于 3.0。
    // #7E7059 = 同色相上抬一档：最差底 3.24 / 卡面 3.53，与 textSecondary
    // 仍保持 1.77× 的层级差（不塌层），只此一格。
    textTertiary: Color(0xFF7E7059),
    divider: Color(0xFF33291F),
    disabled: Color(0xFF544838),
    onPrimary: Color(0xFF171310),
    accent: Color(0xFFB98F3E),
    onAccent: Color(0xFF171310),
    success: Color(0xFF74A182),
    warning: Color(0xFFC8A05A),
    danger: Color(0xFFC57578),
    info: Color(0xFF88A6C0),
    annotation: Color(0xFFC8A05A),
    inverseSurface: Color(0xFFB98F3E),
    onInverseSurface: Color(0xFF171310),
    scrim: Color(0xB30D0A07),
    onScrim: Color(0xFFE8DFCB),
    shadow: Color(0x4D000000),
    emphasis: Color(0x14B98F3E),
    emphasisStrong: Color(0x33B98F3E),
    tabTrack: Color(0xFF2A2219),
    tabActive: Color(0xFFB98F3E),
    tabOnActive: Color(0xFF171310),
    controlTrack: Color(0xFF171310),
    controlThumb: Color(0xFF2E261C),
    controlThumbBorder: Color(0xFF3E3527),
  );

  static const LLPalette metroLight = LLPalette(
    brightness: Brightness.light,
    bg: Color(0xFFEDF1F5),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFE1E8EF),
    textPrimary: Color(0xFF16283C),
    textSecondary: Color(0xFF54687E),
    textTertiary: Color(0xFF72849A),
    divider: Color(0xFFD8E0E8),
    disabled: Color(0xFFA2B2C2),
    onPrimary: Color(0xFFEDF1F5),
    accent: Color(0xFF1B5FAA),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF2C7559),
    warning: Color(0xFF8C6715),
    danger: Color(0xFFBC3B2E),
    info: Color(0xFF2C6E96),
    annotation: Color(0xFF1B5FAA),
    inverseSurface: Color(0xFF16283C),
    onInverseSurface: Color(0xFFEDF1F5),
    scrim: Color(0xB30A121C),
    onScrim: Color(0xFFFFFFFF),
    shadow: Color(0x1A0A121C),
    emphasis: Color(0x141B5FAA),
    emphasisStrong: Color(0x281B5FAA),
    tabTrack: Color(0xFFE1E8EF),
    tabActive: Color(0xFF16283C),
    tabOnActive: Color(0xFFFFFFFF),
    controlTrack: Color(0xFFE1E8EF),
    controlThumb: Color(0xFFFFFFFF),
    controlThumbBorder: Color(0xFFCBD7E2),
  );

  static const LLPalette metroDark = LLPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0A0E13),
    surface: Color(0xFF111820),
    surfaceHigh: Color(0xFF18212B),
    textPrimary: Color(0xFFE4EBF2),
    textSecondary: Color(0xFF94A5B8),
    textTertiary: Color(0xFF5C6B7C),
    divider: Color(0xFF1E2833),
    disabled: Color(0xFF3D4A58),
    onPrimary: Color(0xFF0A0E13),
    accent: Color(0xFF79C7DE),
    onAccent: Color(0xFF06202A),
    success: Color(0xFF5CB98F),
    warning: Color(0xFFE0A72E),
    danger: Color(0xFFE2685E),
    info: Color(0xFF6FB6D8),
    annotation: Color(0xFF79C7DE),
    inverseSurface: Color(0xFFE4EBF2),
    onInverseSurface: Color(0xFF0A0E13),
    scrim: Color(0xB3000000),
    onScrim: Color(0xFFE4EBF2),
    shadow: Color(0x59000000),
    emphasis: Color(0x1479C7DE),
    emphasisStrong: Color(0x2E79C7DE),
    tabTrack: Color(0xFF18212B),
    tabActive: Color(0xFF79C7DE),
    tabOnActive: Color(0xFF06202A),
    controlTrack: Color(0xFF0A0E13),
    controlThumb: Color(0xFF1D2733),
    controlThumbBorder: Color(0xFF2A3644),
  );

  @override
  LLPalette copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? disabled,
    Color? onPrimary,
    Color? accent,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? annotation,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? scrim,
    Color? onScrim,
    Color? shadow,
    Color? emphasis,
    Color? emphasisStrong,
    Color? tabTrack,
    Color? tabActive,
    Color? tabOnActive,
    Color? controlTrack,
    Color? controlThumb,
    Color? controlThumbBorder,
  }) => LLPalette(
    brightness: brightness ?? this.brightness,
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    divider: divider ?? this.divider,
    disabled: disabled ?? this.disabled,
    onPrimary: onPrimary ?? this.onPrimary,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    info: info ?? this.info,
    annotation: annotation ?? this.annotation,
    inverseSurface: inverseSurface ?? this.inverseSurface,
    onInverseSurface: onInverseSurface ?? this.onInverseSurface,
    scrim: scrim ?? this.scrim,
    onScrim: onScrim ?? this.onScrim,
    shadow: shadow ?? this.shadow,
    emphasis: emphasis ?? this.emphasis,
    emphasisStrong: emphasisStrong ?? this.emphasisStrong,
    tabTrack: tabTrack ?? this.tabTrack,
    tabActive: tabActive ?? this.tabActive,
    tabOnActive: tabOnActive ?? this.tabOnActive,
    controlTrack: controlTrack ?? this.controlTrack,
    controlThumb: controlThumb ?? this.controlThumb,
    controlThumbBorder: controlThumbBorder ?? this.controlThumbBorder,
  );

  @override
  LLPalette lerp(LLPalette? other, double t) {
    if (other == null) return this;
    return LLPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      annotation: Color.lerp(annotation, other.annotation, t)!,
      inverseSurface: Color.lerp(inverseSurface, other.inverseSurface, t)!,
      onInverseSurface: Color.lerp(onInverseSurface, other.onInverseSurface, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      onScrim: Color.lerp(onScrim, other.onScrim, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      emphasis: Color.lerp(emphasis, other.emphasis, t)!,
      emphasisStrong: Color.lerp(emphasisStrong, other.emphasisStrong, t)!,
      tabTrack: Color.lerp(tabTrack, other.tabTrack, t)!,
      tabActive: Color.lerp(tabActive, other.tabActive, t)!,
      tabOnActive: Color.lerp(tabOnActive, other.tabOnActive, t)!,
      controlTrack: Color.lerp(controlTrack, other.controlTrack, t)!,
      controlThumb: Color.lerp(controlThumb, other.controlThumb, t)!,
      controlThumbBorder: Color.lerp(
        controlThumbBorder,
        other.controlThumbBorder,
        t,
      )!,
    );
  }

  /// Fraction of [t] spent inside one layer's window, eased.
  static double _window(
    double t,
    double start,
    double end,
    Curve curve,
  ) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return curve.transform((t - start) / (end - start));
  }

  /// Three-beat blend for the day/night transition (doc 21 §十二, §十四, §十六;
  /// WP-G §二.1 for the 空间 → 表面 → 墨迹 reading of the beats).
  ///
  /// The split into beats is decided by *legibility*, not by how far back an
  /// element sits. Beat 1 (空间) is the luminance axis: canvas, card faces, all
  /// three ink levels, and every role primary ink is drawn on — they must move
  /// as one synchronized breath. Beat 2 (表面) is surface furniture: roles that
  /// are figure-ground against *each other* (hairlines, the control track and
  /// its border) and may therefore lag. Beat 3 (墨迹) is the accent ink settling.
  ///
  /// 空间 and 表面 deliberately **overlap** — 表面 opens at [depthShapeStart]
  /// (0.20), before 空间 lands at [depthInkEnd] (0.26) — so the three layers read
  /// as one continuous 开灯 rather than a staircase (WP-G §二.1). 墨迹 keeps a
  /// short hold after 表面 because it is itself an inverted pair
  /// (`onAccent` ↔ `accent`) and the only knob on that crossing is how *briefly*
  /// it is spent there (§十四).
  ///
  /// Layering by depth order was tried first (底 0–0.62, 卡面 0.22–0.85) and it
  /// is what he was complaining about: light ink crossed a card that had not
  /// moved yet (389 ms of 正文/卡面 under 3:1), and the selected pill stayed
  /// ink-dark on an already-dark canvas, so the 白昼/黑夜 control lost its thumb
  /// for half a second and popped back (2026-10-07 用户：「图标、English/中文、
  /// 白昼黑夜这些按钮背景的过渡不是很好」). See §十四 for why a contrast pair can
  /// never be split: day and night invert luminance, so every pair must cross
  /// the equal-luminance instant together, and the only tunable is how
  /// *briefly* it is spent there.
  ///
  /// Unlike [lerp] this is not a uniform tween, so `t` here is the raw
  /// transition progress, not a blend factor.
  LLPalette staggerTo(LLPalette b, double t) {
    final inkW = _window(
      t,
      LLMotion.depthInkStart,
      LLMotion.depthInkEnd,
      Curves.easeInOut,
    );
    final shapeW = _window(
      t,
      LLMotion.depthShapeStart,
      LLMotion.depthShapeEnd,
      Curves.easeInOut,
    );
    final hueW = _window(
      t,
      LLMotion.depthHueStart,
      LLMotion.depthHueEnd,
      Curves.easeInOut,
    );
    Color mix(Color from, Color to, double k) => Color.lerp(from, to, k)!;
    return LLPalette(
      // The bool every remaining `isDark ? …` site reads flips inside the
      // first beat, so the one hard cut lands while colour is already moving
      // instead of in a quiet moment.
      brightness: t < LLMotion.depthBoolFlip ? brightness : b.brightness,
      // 第一拍 · 空间（墙、纸、墨同一口气）：画布、卡面、三级墨色，以及所有
      // 承载主墨或必须相对画布保持可见的东西。同窗是硬约束（§十四）。
      bg: mix(bg, b.bg, inkW),
      surface: mix(surface, b.surface, inkW),
      surfaceHigh: mix(surfaceHigh, b.surfaceHigh, inkW),
      textPrimary: mix(textPrimary, b.textPrimary, inkW),
      textSecondary: mix(textSecondary, b.textSecondary, inkW),
      textTertiary: mix(textTertiary, b.textTertiary, inkW),
      disabled: mix(disabled, b.disabled, inkW),
      emphasis: mix(emphasis, b.emphasis, inkW),
      emphasisStrong: mix(emphasisStrong, b.emphasisStrong, inkW),
      controlThumb: mix(controlThumb, b.controlThumb, inkW),
      tabTrack: mix(tabTrack, b.tabTrack, inkW),
      tabActive: mix(tabActive, b.tabActive, inkW),
      tabOnActive: mix(tabOnActive, b.tabOnActive, inkW),
      inverseSurface: mix(inverseSurface, b.inverseSurface, inkW),
      onInverseSurface: mix(onInverseSurface, b.onInverseSurface, inkW),
      scrim: mix(scrim, b.scrim, inkW),
      onScrim: mix(onScrim, b.onScrim, inkW),
      shadow: mix(shadow, b.shadow, inkW),
      // 第二拍 · 表面：发线与控件的轨道/描边。只有"旧值贴在新画布上仍然看得见"
      // 的角色才配晚一拍——胶囊不行（深色胶囊贴在深色画布上会消失 791ms，
      // 实测），所以胶囊三件套留在第一拍。这一拍提前到 0.20 开动、压着空间拍的
      // 尾巴（WP-G §二.1「与前拍重叠一点」），三层之间就没有阶梯感了。
      divider: mix(divider, b.divider, shapeW),
      controlTrack: mix(controlTrack, b.controlTrack, shapeW),
      controlThumbBorder: mix(controlThumbBorder, b.controlThumbBorder, shapeW),
      // 第三拍 · 墨迹（强调色）：灯先亮起来，颜色最后开花。
      accent: mix(accent, b.accent, hueW),
      onAccent: mix(onAccent, b.onAccent, hueW),
      onPrimary: mix(onPrimary, b.onPrimary, hueW),
      success: mix(success, b.success, hueW),
      warning: mix(warning, b.warning, hueW),
      danger: mix(danger, b.danger, hueW),
      info: mix(info, b.info, hueW),
      // 批注是**字**，不是灯：它跟墨一起走第一拍。留在第三拍的话，朱砂会在画布
      // 已经入夜之后还停在纸上那一档，糊一整段（doc 21 §十四 的介值论证）。
      annotation: mix(annotation, b.annotation, inkW),
    );
  }
}

extension LLPaletteContext on BuildContext {
  /// The active palette for the current style and brightness.
  LLPalette get ll =>
      Theme.of(this).extension<LLPalette>() ?? LLPalette.nightfallDark;

  /// The active shape language (corners, hairlines, shadows, texture).
  LLShape get llShape =>
      Theme.of(this).extension<LLShape>() ?? LLShape.baseDark;

  /// Which style is active, for the few places that must branch on identity
  /// rather than on a color token.
  LLStyle get llStyle => llShape.style;
}

double _d(double a, double b, double t) => a + (b - a) * t;

/// Spacing scale (spec V1 §六). Page horizontal margin is `xl` (24) — one
/// gutter per screen, so switching modes never shifts content sideways.
abstract final class LLSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

/// Corner radii (spec V1 §七 + doc 21 §四). Shapes are per style through
/// [LLShape]; these are the shared reference steps pages may quote.
abstract final class LLRadius {
  static const double xsmall = 4;
  static const double small = 8;
  static const double chip = 6;
  static const double medium = 12;
  static const double large = 16;
  static const double pill = 999;
}

/// Motion tokens (spec V1 §四十二): three durations, one curve.
abstract final class LLMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 280);
  static const Curve curve = Curves.easeOut;

  /// Day/night and style changes run as a three-beat colour transition
  /// (`LLPalette.staggerTo`) over this duration. 2000 ms because a fast rise
  /// from night to day is what dazzles (2026-10-08 用户：「突然从黑夜过渡到白昼，
  /// 感觉还是有点晃眼睛」); the beats and the silence between them are what make
  /// it read as layers instead of one wash (同次：「没有分层级做动画」).
  static const Duration themeDepth = Duration(milliseconds: 2000);

  /// Beat windows as fractions of [themeDepth], read as the three layers of
  /// 「开灯」: **空间 → 表面 → 墨迹** (WP-G §二.1).
  ///
  /// * 空间 (beat 1, [depthInkStart]–[depthInkEnd]) — 房间的墙、纸与墨：画布、
  ///   卡面、三级墨色，以及所有互为对比对子的角色，都在**同一拍**里一起走。
  /// * 表面 (beat 2, [depthShapeStart]–[depthShapeEnd]) — 表面的细部：发丝线、
  ///   控件轨道与描边。它们只跟彼此做图底关系，所以允许晚一拍。
  /// * 墨迹 (beat 3, [depthHueStart]–[depthHueEnd]) — 强调色最后落定。
  ///
  /// 与上一版（0/0.26 → 0.42/0.62 → 0.76/1.0，拍与拍之间留白）的差别只有一处：
  /// **表面拍提前到 0.20 开动**，压着空间拍的尾巴，于是三层之间不再有阶梯感
  /// （WP-G §二.1「与前拍重叠一点，避免阶梯感」）。
  ///
  /// 为什么能动的地方只有这一处：昼夜是亮度反相，一对「文字↔它的底」中途必然
  /// 穿过等亮度点。把 `bg` 挪进更早的一拍、把文字留到更晚的一拍，文字就会有几百
  /// 毫秒落在一个已经变暗（或变亮）的底上——这正是 WP-G §二.1 那句 caveat 防的事。
  /// 实测：`bg` 单独提前到 0–0.30 时，「正文/画布」糊掉 1000 ms 以上，远超
  /// `ll_palette_stagger_test` 的预算（正文低于 3:1 ≤130 ms，任何一对低于自身
  /// 一半 ≤260 ms）。所以空间拍**必须是**画布＋卡面＋墨色同窗的一口气；真正能
  /// 错开的只有不参与任何对比对子的「表面细部」与「强调色」。
  ///
  /// 每一拍自己仍然很短，因为一个反相对子穿过等亮度点的时长就等于这个窗口的
  /// 长度。整屏快照擦除试过、当场被否（§十六「一块黑布」）——擦除表达不了分层。
  static const double depthInkStart = 0.0;
  static const double depthInkEnd = 0.26;
  static const double depthShapeStart = 0.20;
  static const double depthShapeEnd = 0.62;
  static const double depthHueStart = 0.76;
  static const double depthHueEnd = 1.0;

  /// Where `ThemeData.brightness` — the bool every remaining `isDark ? …`
  /// site reads — is allowed to flip. Inside the first beat, so the one hard
  /// cut left in the transition happens while colour is already moving rather
  /// than in a quiet moment.
  static const double depthBoolFlip = 0.13;
}

/// Letter-spacing steps (doc 21 §四): the app used six loose values.
abstract final class LLTracking {
  static const double tight = 0.3;
  static const double normal = 0;
  static const double wide = 1.1;
  static const double label = 2;
}

/// Type scale (spec V1 §五). The English sentence is the loudest voice in
/// the app; everything else steps down in size AND brightness.
/// `micro` / `meta` / `cardTitle` close the gaps that pages were filling with
/// hand-written 8.5 / 9 / 10.5 / 11.5 / 13.5 values.
abstract final class LLText {
  static const TextStyle appTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Quiet uppercase section labels: CONTINUE / APPEARANCE / PREVIEW.
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 2,
    height: 1.2,
  );

  /// 分组眉题（设置页「外观」「连接」）。比 `sectionLabel` 小一档、字距收着，
  /// 因为中文也要用：CJK 上 2.0 字距会散。字距由 `LLSectionLabel` 按文种给。
  static const TextStyle groupLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// 行左边的名字（设置页每一行的标题）。
  static const TextStyle rowLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// 行右边当前值。`bodySm` 是正文小字（行距 1.5），单行值用它会把行撑高。
  static const TextStyle rowValue = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  /// 带图标行的主标题。`rowTitle`(17) 是卡片标题，这里是一行里的标题。
  static const TextStyle itemTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.2,
  );

  /// 带图标行主标题下面那行实时摘要。
  static const TextStyle itemSummary = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  /// 密集分段控件里未选中的档名（选中档加到 w600）。
  static const TextStyle chipLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  /// 竖排眉批 `LLMarginalNote`。行高 1.45 是字与字之间的呼吸——竖着排时，
  /// 水平行距完全由这个值决定，所以它必须 own 在这里，不能让组件写死。
  static const TextStyle marginalNote = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle rowTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodySm = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle controlLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Small metadata (`36 句 · 04:12`). Floor for anything that carries meaning.
  static const TextStyle meta = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Badges only (语种 / 已入 / 视频角标). Never body text.
  static const TextStyle badge = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// `06 / 36` style counters — tabular figures keep digits from jumping.
  static const TextStyle counter = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.2,
  );
}

/// Learning typography (spec V2 §十三–§十九): the USER-controlled side of
/// the type system. Applies only to learning surfaces (sentence / translation
/// / transcript); the UI font is fixed for brand consistency.
abstract final class LLLearning {
  static const double _englishBase = 28;
  static const double _chineseBase = 18;
  static const double _transcriptEnglishBase = 17;
  static const double _transcriptChineseBase = 14;

  /// 中文字号严格遵循用户设置的比例，不进行人工拉伸，保证 0.3 倍为真实 0.3 倍。
  static double _effectiveChineseScale(double scale) => scale;


  /// Listening: the English sentence — always the strongest element.
  static TextStyle englishSentence(LLPalette palette, AppPreferences prefs) =>
      TextStyle(
        fontSize: _englishBase * prefs.textScale,
        fontWeight: FontWeight.w500,
        fontFamily: prefs.learningFont.family,
        color: palette.textPrimary,
        height: 1.45,
      );

  /// Listening: the Chinese translation — clearly secondary.
  static TextStyle chineseSentence(LLPalette palette, AppPreferences prefs) =>
      TextStyle(
        fontSize: _chineseBase * _effectiveChineseScale(prefs.textScale),
        fontWeight: FontWeight.w400,
        fontFamily: prefs.learningChineseFont.family,
        color: palette.textSecondary,
        height: 1.5,
      );

  /// Primary Chinese Curriculum: the main text and character reading.
  static TextStyle chineseMainSentence(LLPalette palette, AppPreferences prefs) =>
      TextStyle(
        fontSize: 28 * prefs.textScale,
        fontWeight: FontWeight.w600,
        fontFamily: prefs.learningChineseFont.family,
        color: palette.textPrimary,
        height: 1.25,
      );

  /// Transcript: current sentence English.
  static TextStyle transcriptEnglish(
    LLPalette palette,
    AppPreferences prefs, {
    required bool current,
  }) => TextStyle(
    fontSize: _transcriptEnglishBase * prefs.textScale,
    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
    fontFamily: prefs.learningFont.family,
    color: current ? palette.textPrimary : palette.textSecondary,
    height: 1.45,
  );

  /// Transcript: sentence Chinese.
  static TextStyle transcriptChinese(
    LLPalette palette,
    AppPreferences prefs, {
    required bool current,
  }) => TextStyle(
    fontSize: _transcriptChineseBase * _effectiveChineseScale(prefs.textScale),
    color: current ? palette.textSecondary : palette.textTertiary,
    height: 1.5,
  );
}

/// Status/navigation bar styling that follows the palette (spec V2 §三十七).
SystemUiOverlayStyle llSystemOverlay(
  Brightness brightness, {
  LLStyle style = LLStyle.base,
}) {
  final palette = style.paletteFor(brightness);
  final icons = brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: brightness, // iOS
    systemNavigationBarColor: palette.bg,
    systemNavigationBarIconBrightness: icons,
  );
}

/// Theme for one (style, brightness) pair.
///
/// `style` is an optional named argument with a default so the 15 existing
/// `buildListenLoopTheme(Brightness.x)` call sites in tests keep compiling
/// untouched (doc 21 §一).
///
/// [paletteOverride] replaces the style's own palette while the shape and the
/// reported brightness stay as given — that is how the depth transition feeds
/// in a mid-blend [LLPalette.staggerTo] result frame by frame.
ThemeData buildListenLoopTheme(
  Brightness brightness, {
  LLStyle style = LLStyle.base,
  LLPalette? paletteOverride,
}) {
  final palette = paletteOverride ?? style.paletteFor(brightness);
  final shape = style.shapeFor(brightness);
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: palette.accent,
    onPrimary: palette.onAccent,
    secondary: palette.textPrimary,
    onSecondary: palette.onPrimary,
    error: palette.danger,
    onError: palette.onPrimary,
    surface: palette.bg,
    onSurface: palette.textPrimary,
  );
  return base.copyWith(
    scaffoldBackgroundColor: palette.bg,
    colorScheme: colorScheme,
    extensions: [palette, shape],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.bg,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: llSystemOverlay(brightness, style: style),
    ),
    dividerTheme: DividerThemeData(
      color: palette.divider,
      thickness: shape.hairline,
      space: shape.hairline,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceHigh,
      contentTextStyle: LLText.bodySm.copyWith(color: palette.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: palette.bg,
      selectedItemColor: palette.textPrimary,
      unselectedItemColor: palette.textTertiary,
      elevation: 0,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
    ),
  );
}

/// Palette and shape mapping for each style. Lives here (not in ll_style.dart)
/// because it depends on [LLPalette] and [LLShape].
///
/// Contrast for every palette was measured against its own bg
/// (doc 21 §二 · 正文 ≥4.5，三级字 ≥3.0，反相/蒙版配对 ≥4.5/3.0);
/// changing any hex here must re-run that check.
extension LLStyleTheme on LLStyle {
  LLPalette paletteFor(Brightness b) => b == Brightness.light ? light : dark;

  LLPalette get light => switch (this) {
    LLStyle.base => LLPalette.daylightLight,
    LLStyle.academy => LLPalette.academyLight,
    LLStyle.oxbridge => LLPalette.oxbridgeLight,
    LLStyle.metropolis => LLPalette.metroLight,
  };

  LLPalette get dark => switch (this) {
    LLStyle.base => LLPalette.nightfallDark,
    LLStyle.academy => LLPalette.academyDark,
    LLStyle.oxbridge => LLPalette.oxbridgeDark,
    LLStyle.metropolis => LLPalette.metroDark,
  };

  /// 只有基础风格的两面各自有形状（白昼轻投影、黑夜重一点）；
  /// 其余三套的纸/石/钢质感与明暗无关。
  LLShape shapeFor(Brightness b) => switch (this) {
    LLStyle.base => b == Brightness.light ? LLShape.baseLight : LLShape.baseDark,
    LLStyle.academy => LLShape.paper,
    LLStyle.oxbridge => LLShape.stone,
    LLStyle.metropolis => LLShape.steel,
  };
}
