import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../preferences/app_preferences.dart';

/// ListenLoop Visual Polish design tokens (spec V1 §三–§七; V2 §九–十一).
///
/// Black · White · Type · Motion. Spacing / radius / motion / type scale are
/// brightness-independent; colors live in [LLPalette] (dark + light) so the
/// theme switch only changes 明暗, never the layout (spec V2 §十一).
abstract final class LLColors {
  /// Brand-dark constants — used ONLY by always-black brand surfaces
  /// (splash / intro, spec V2 §三十八) and as the dark palette values.
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

/// Brightness-aware palette. Access via `context.ll`.
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

  /// §九: the established ListenLoop identity.
  static const LLPalette dark = LLPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0A0A0A),
    surface: Color(0xFF111111),
    surfaceHigh: Color(0xFF181818),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFA3A3A3),
    textTertiary: Color(0xFF666666),
    divider: Color(0xFF242424),
    disabled: Color(0xFF4A4A4A),
    onPrimary: Color(0xFF0A0A0A),
  );

  /// §十: warm-white paper, near-black ink — still black/white minimal.
  static const LLPalette light = LLPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF7F7F5),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEFEFEC),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF6A6A6A),
    textTertiary: Color(0xFF999999),
    divider: Color(0xFFE5E5E2),
    disabled: Color(0xFFB8B8B8),
    onPrimary: Color(0xFFF7F7F5),
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
    );
  }
}

extension LLPaletteContext on BuildContext {
  /// The active black/white palette for the current theme.
  LLPalette get ll => Theme.of(this).extension<LLPalette>() ?? LLPalette.dark;
}

/// Spacing scale (spec V1 §六). Page horizontal margin is `xl` (24).
abstract final class LLSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

/// Corner radii (spec V1 §七).
abstract final class LLRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
}

/// Motion tokens (spec V1 §四十二): three durations, one curve.
abstract final class LLMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 280);
  static const Duration themeSwitch = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOut;
}

/// Type scale (spec V1 §五). The English sentence is the loudest voice in
/// the app; everything else steps down in size AND brightness.
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

  static const TextStyle rowTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
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
/// / transcript); the UI font is fixed for brand consistency. Base sizes:
/// English 28 / Chinese 18 (spec V1 §五), scaled together by the user's
/// text-size choice (§十八).
abstract final class LLLearning {
  static const double _englishBase = 28;
  static const double _chineseBase = 18;
  static const double _transcriptEnglishBase = 17;
  static const double _transcriptChineseBase = 14;

  /// 当字号为 0.5 倍时，中文基准额外放大 50% 防止过小看不清。
  static double _effectiveChineseScale(double scale) {
    if (scale <= 0.505) {
      return scale * 1.5;
    }
    return scale;
  }

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
        color: palette.textSecondary,
        height: 1.5,
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
SystemUiOverlayStyle llSystemOverlay(Brightness brightness) {
  final palette = brightness == Brightness.dark
      ? LLPalette.dark
      : LLPalette.light;
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

/// Global theme (spec V1 §一; V2 §九–十一): one quiet canvas, two
/// brightnesses. Switching theme must not feel like entering another app.
ThemeData buildListenLoopTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark
      ? LLPalette.dark
      : LLPalette.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: palette.textPrimary,
    onPrimary: palette.onPrimary,
    secondary: palette.textPrimary,
    onSecondary: palette.onPrimary,
    error: brightness == Brightness.dark
        ? const Color(0xFFCF6679)
        : const Color(0xFFB3261E),
    onError: brightness == Brightness.dark
        ? const Color(0xFF0A0A0A)
        : Colors.white,
    surface: palette.bg,
    onSurface: palette.textPrimary,
  );
  return base.copyWith(
    scaffoldBackgroundColor: palette.bg,
    colorScheme: colorScheme,
    extensions: [palette],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.bg,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: llSystemOverlay(brightness),
    ),
    dividerTheme: DividerThemeData(
      color: palette.divider,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceHigh,
      contentTextStyle: TextStyle(color: palette.textPrimary, fontSize: 14),
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
