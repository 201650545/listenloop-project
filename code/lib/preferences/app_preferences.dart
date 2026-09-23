import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Personal reading preferences (spec V2 §六–§二十六 + follow-up):
///
/// * `themeMode` — whole-app brightness (system/light/dark, default dark).
/// * `learningFont` — applies ONLY to learning surfaces (sentence /
///   translation / transcript); the UI font is fixed for brand identity.
///   `Sans` is the bundled Roboto family so it stays visually distinct from
///   `System` even on ROMs whose custom font replaces the system sans slot.
/// * `textScale` — continuous multiplier on the learning type scale
///   (presets S/M/L/XL map to 0.90/1.00/1.15/1.30; a long-press slider can
///   set anything in between). English AND Chinese scale together so the
///   hierarchy survives (§十八).
///
/// These are whole-app preferences — deliberately NOT part of
/// LearningProgress (§二十三). Persisted via the simplest stable local
/// storage available (SharedPreferences, §二十五).
enum LearningFont {
  /// Modern, clean — the default, bundled Roboto (§十四 + follow-up).
  sans,

  /// Closer to reading English articles/books (platform serif).
  serif,

  /// Follow the phone's system font.
  system;

  /// Font family applied to ENGLISH learning text. Chinese glyphs fall back
  /// to the platform CJK font automatically (spec V2 §十五) — we never force
  /// an English serif onto Chinese and risk tofu.
  String? get family => switch (this) {
    LearningFont.sans => 'LL Sans',
    LearningFont.serif => 'serif',
    LearningFont.system => null,
  };

  String get label => switch (this) {
    LearningFont.sans => 'Sans',
    LearningFont.serif => 'Serif',
    LearningFont.system => 'System',
  };
}

/// Discrete presets shown in Settings (`A A A A` — S/M/L/XL). The stored
/// preference itself is the continuous [AppPreferences.textScale].
enum LearningTextSizePreset {
  small(0.50, 'S'),
  normal(0.75, 'M'),
  large(1.00, 'L'),
  extraLarge(1.30, 'XL');

  const LearningTextSizePreset(this.scale, this.label);

  final double scale;
  final String label;

  static LearningTextSizePreset? fromScale(double scale) {
    for (final preset in values) {
      if ((preset.scale - scale).abs() < 0.005) return preset;
    }
    return null;
  }
}

/// UI language (follow-up: 中/英界面切换). Default `en` — the brand voice
/// and the existing test surface; 中文 is one tap away in Settings.
enum AppLanguage {
  english('English'),
  chinese('中文');

  const AppLanguage(this.nativeLabel);

  /// Option labels are always rendered in their own language.
  final String nativeLabel;
}

/// Bounds of the long-press text-size slider (§ follow-up: 字号长按滑动).
/// The wide 0.30×–1.50× range is deliberate: below 1.0 it doubles as a
/// "shrink the English line" control for very long sentences, above it as a
/// magnifier. Stored values from the narrower 0.85–1.40 range stay valid.
const double kMinTextScale = 0.30;
const double kMaxTextScale = 1.50;

// ---------------------------------------------------------------- MiMo ----
/// 全 App 统一模型服务：小米 MiMo（`api.xiaomimimo.com`）。
///
/// 选型依据（2026-09-23 真机实测）：手机侧直连 **HTTP 200 / 0.28s** 拿到模型
/// 列表，不需要 PC、不需要 adb reverse、不需要代理、不需要同一局域网；而网关
/// 那批墙外免费线路（free-heavy 等路由到 nvidia/cloudflare）在手机侧全部
/// 不可达。故 2026-09-23 用户拍板：**伴学与翻译全部改用 MiMo flash**。
const String kDefaultMimoBaseUrl = 'https://api.xiaomimimo.com/v1';

/// MiMo 的 Bearer key，随 App 预填（本仓库无远端，不外泄）。
const String kDefaultMimoApiKey = 'YOUR_MIMO_API_KEY';

/// 统一模型 `mimo-v2.6-flash`。手机侧直连实测：
/// * 字幕翻译 6.9s，严格返回 `{"translations": [...]}` 且条数与输入一致；
/// * 英语伴学 7.5s，输出规范的连读／弱读／闪音分析。
/// 它带少量 reasoning token，但 `content` 正常返回（不像 ling-3.0-flash
/// 那样只吐推理链）。
const String kDefaultMimoModel = 'mimo-v2.6-flash';

/// 翻译端点统一走 MiMo（base URL 含 `/v1`，App 自行拼 `/chat/completions`）。
const String kDefaultTranslationBaseUrl = kDefaultMimoBaseUrl;
const String kDefaultTranslationModel = kDefaultMimoModel;

/// AI 伴学（在线大模型）默认通道同样是 MiMo，手机可脱离 PC 独立使用。
const String kDefaultTutorBaseUrl = kDefaultMimoBaseUrl;
const String kDefaultTutorApiKey = kDefaultMimoApiKey;
const String kDefaultTutorModel = kDefaultMimoModel;

/// 回退链：同厂商同 key 只换档位，全部国内直连可达。
///
/// 原网关那组墙外免费线路已弃用（手机侧不可达）。flash 失败时依次退到
/// pro / v2.5，同端点同鉴权，不涉及任何墙外通道。
const List<String> kTutorFallbackModels = <String>[
  kDefaultMimoModel,
  'mimo-v2.6-pro',
  'mimo-v2.5',
];

/// 配置结构版本。装载到 `version < 当前值` 的存档（指向旧网关或 OpenRouter）
/// 时，一次性把伴学与翻译端点升级为上面的 MiMo 默认值，并把新值**写回存储**；
/// 升级后用户在设置页的改动不会再被覆盖。
///
/// 版本 2 是首版迁移，但它只改内存未落盘，导致第二次启动又读回旧端点。
/// 版本 3 修正该缺陷；实测被 v2 标记过的设备必须靠 v3 才能再次触发迁移。
const int kCurrentConfigVersion = 3;

/// ASR decode threads (Creation V2 §十五). Deliberately set to 6 on modern
/// high-end big.LITTLE (e.g. Snapdragon 8 Gen 3: 1 Prime + 5 Performance cores)
/// to max out the performance cluster without spilling onto slow efficiency cores.
const int kDefaultAsrThreads = 6;

/// Default PC-side YouTube relay URL (port 8793, adb reverse or LAN).
const String kDefaultYoutubeRelayBaseUrl = 'http://127.0.0.1:8793';

/// Hard bounds for [AppPreferences.asrThreads] — below 1 ONNX Runtime
/// misbehaves, above 8 there is nothing left to schedule on this device class.
const int kMinAsrThreads = 1;
const int kMaxAsrThreads = 8;

/// ASR quality tier (2026-09-18 用户拍板: Whisper 双档, 多语言模型).
/// Both tiers are self-exported whisper ONNX with cross-attention outputs —
/// the only form that yields word-level timestamps (M1 blocker).
enum AsrTier {
  /// whisper base — 快速档 (~160 MB int8, RTF≈0.13 on desktop).
  fast,

  /// whisper small — 精确档 (~374 MB int8, RTF≈0.35 on desktop).
  precise;

  /// Model directory name under `models/asr/` holding the tier's
  /// encoder/decoder/tokens files.
  String get modelDirName => switch (this) {
    AsrTier.fast => 'whisper-base',
    AsrTier.precise => 'whisper-small',
  };

  /// File names inside [modelDirName], as produced by
  /// `export-onnx-with-attention.py` (torch ≤2.8, see SherpaOnnxAsrEngine).
  String get modelPrefix => switch (this) {
    AsrTier.fast => 'base',
    AsrTier.precise => 'small',
  };
  String get encoderFile => '$modelPrefix-encoder.int8.onnx';
  String get decoderFile => '$modelPrefix-decoder.int8.onnx';
  String get tokensFile => '$modelPrefix-tokens.txt';

  String get label => switch (this) {
    AsrTier.fast => '快速档',
    AsrTier.precise => '精确档',
  };
}

/// Immutable snapshot of the user's reading preferences.
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.dark,
    this.learningFont = LearningFont.sans,
    this.textScale = 0.75,
    this.uiLanguage = AppLanguage.english,
    this.translationBaseUrl = kDefaultTranslationBaseUrl,
    this.translationApiKey = kDefaultMimoApiKey,
    this.translationModel = kDefaultTranslationModel,
    this.asrThreads = kDefaultAsrThreads,
    this.asrTier = AsrTier.fast,
    this.youtubeRelayBaseUrl = kDefaultYoutubeRelayBaseUrl,
    this.tutorBaseUrl = kDefaultTutorBaseUrl,
    this.tutorApiKey = kDefaultTutorApiKey,
    this.tutorModel = kDefaultTutorModel,
    this.libraryGridView = true,
    this.scrubberHaptics = true,
    this.configVersion = kCurrentConfigVersion,
  });

  /// §八: Dark is the default and stays ListenLoop's visual identity.
  final ThemeMode themeMode;
  final LearningFont learningFont;
  final double textScale;
  final AppLanguage uiLanguage;

  /// OpenAI-compatible base URL, `/v1` included.
  final String translationBaseUrl;

  /// Bearer key for [translationBaseUrl]. Empty means "unauthenticated
  /// endpoint" — kept on the device only, never in the repository.
  final String translationApiKey;

  /// Model id sent with every translation request.
  final String translationModel;

  /// ASR decode threads (Creation V2 §十五). On device only — the 2/4/6/8
  /// sweep is run by writing this value, so no rebuild is needed per data
  /// point, and no UI is exposed until the measurement says what to expose.
  final int asrThreads;

  /// ASR quality tier — selects which on-device whisper model a new lesson
  /// is transcribed with (快速档 base / 精确档 small).
  final AsrTier asrTier;

  /// PC-side YouTube relay service URL (default 127.0.0.1:8793 via adb reverse,
  /// or a LAN IP when Wi-Fi debugging).
  final String youtubeRelayBaseUrl;

  /// AI 伴学所用的 OpenAI 兼容接口地址（含 `/v1`）。默认本机网关 :3100，
  /// 手机上经 adb reverse 直达 PC，也可手工改填任意 OpenAI 兼容中继。
  final String tutorBaseUrl;

  /// [tutorBaseUrl] 的 Bearer key。网关 key 已预填；改指第三方时自行覆盖。
  final String tutorApiKey;

  /// AI 伴学默认模型（MiMo flash，与翻译共用）。
  final String tutorModel;

  /// Whether the library uses 2-column poster grid view (default true) or
  /// classic single-column editorial list view.
  final bool libraryGridView;

  /// Whether the long-press sentence scrubber gives per-tick haptic feedback
  /// while dragging (2026-09-22 user request; toggle lives in Settings).
  final bool scrubberHaptics;

  /// Schema version of the persisted configuration — see [kCurrentConfigVersion].
  final int configVersion;

  /// True once the translation endpoint is usable (§二十四): a base URL is
  /// always set, so only the model and — for hosted providers — the key gate.
  bool get hasTranslationEndpoint =>
      translationBaseUrl.trim().isNotEmpty && translationModel.trim().isNotEmpty;

  /// AI 伴学在线链路是否可发起请求：地址与模型都非空即可（网关不需要
  /// key 也能匿名访问，但带了会过鉴权，所以不强制）。
  bool get hasTutorEndpoint =>
      tutorBaseUrl.trim().isNotEmpty && tutorModel.trim().isNotEmpty;

  static const AppPreferences defaults = AppPreferences();

  AppPreferences copyWith({
    ThemeMode? themeMode,
    LearningFont? learningFont,
    double? textScale,
    AppLanguage? uiLanguage,
    String? translationBaseUrl,
    String? translationApiKey,
    String? translationModel,
    int? asrThreads,
    AsrTier? asrTier,
    String? youtubeRelayBaseUrl,
    String? tutorBaseUrl,
    String? tutorApiKey,
    String? tutorModel,
    bool? libraryGridView,
    bool? scrubberHaptics,
    int? configVersion,
  }) => AppPreferences(
    themeMode: themeMode ?? this.themeMode,
    learningFont: learningFont ?? this.learningFont,
    textScale: textScale ?? this.textScale,
    uiLanguage: uiLanguage ?? this.uiLanguage,
    translationBaseUrl: translationBaseUrl ?? this.translationBaseUrl,
    translationApiKey: translationApiKey ?? this.translationApiKey,
    translationModel: translationModel ?? this.translationModel,
    asrThreads: asrThreads ?? this.asrThreads,
    asrTier: asrTier ?? this.asrTier,
    youtubeRelayBaseUrl: youtubeRelayBaseUrl ?? this.youtubeRelayBaseUrl,
    tutorBaseUrl: tutorBaseUrl ?? this.tutorBaseUrl,
    tutorApiKey: tutorApiKey ?? this.tutorApiKey,
    tutorModel: tutorModel ?? this.tutorModel,
    libraryGridView: libraryGridView ?? this.libraryGridView,
    scrubberHaptics: scrubberHaptics ?? this.scrubberHaptics,
    configVersion: configVersion ?? this.configVersion,
  );
}

/// Persistence seam so tests can run without the platform plugin.
abstract class AppPreferencesStore {
  Future<AppPreferences> load();
  Future<void> save(AppPreferences prefs);
}

class InMemoryAppPreferencesStore implements AppPreferencesStore {
  AppPreferences _value = AppPreferences.defaults;
  int saveCount = 0;

  @override
  Future<AppPreferences> load() async => _value;

  @override
  Future<void> save(AppPreferences prefs) async {
    _value = prefs;
    saveCount++;
  }
}

class SharedPrefsAppPreferencesStore implements AppPreferencesStore {
  static const _keyThemeMode = 'listenloop:pref.themeMode';
  static const _keyFont = 'listenloop:pref.learningFont';
  static const _keyTextScale = 'listenloop:pref.textScale';
  static const _keyLanguage = 'listenloop:pref.uiLanguage';
  static const _keyTranslationBaseUrl = 'listenloop:pref.translationBaseUrl';
  static const _keyTranslationApiKey = 'listenloop:pref.translationApiKey';
  static const _keyTranslationModel = 'listenloop:pref.translationModel';
  static const _keyAsrThreads = 'listenloop:pref.asrThreads';
  static const _keyAsrTier = 'listenloop:pref.asrTier';
  static const _keyYoutubeRelayBaseUrl = 'listenloop:pref.youtubeRelayBaseUrl';
  static const _keyTutorBaseUrl = 'listenloop:pref.tutorBaseUrl';
  static const _keyTutorApiKey = 'listenloop:pref.tutorApiKey';
  static const _keyTutorModel = 'listenloop:pref.tutorModel';
  static const _keyLibraryGridView = 'listenloop:pref.libraryGridView';
  static const _keyScrubberHaptics = 'listenloop:pref.scrubberHaptics';
  static const _keyConfigVersion = 'listenloop:pref.configVersion';

  /// Pre-follow-up builds stored the size as a preset name; honour it once.
  static const _legacyKeyTextSize = 'listenloop:pref.textSize';

  @override
  Future<AppPreferences> load() async {
    final sp = await SharedPreferences.getInstance();

    // One-shot schema upgrade: archives written before kCurrentConfigVersion
    // still point at the PC gateway (:3100) or OpenRouter, both of which the
    // phone cannot reach on its own. Force the unified MiMo endpoint once;
    // after this bump the user's own edits in Settings are never overwritten.
    //
    // The new values must be WRITTEN BACK, not merely returned: load() does not
    // persist otherwise, so a second launch (which already sees version 2)
    // would happily read the stale endpoints straight back off disk.
    final storedVersion = sp.getInt(_keyConfigVersion) ?? 1;
    final upgradeEndpoints = storedVersion < kCurrentConfigVersion;
    if (upgradeEndpoints) {
      final defaults = AppPreferences.defaults;
      await sp.setString(_keyTranslationBaseUrl, defaults.translationBaseUrl);
      await sp.setString(_keyTranslationApiKey, defaults.translationApiKey);
      await sp.setString(_keyTranslationModel, defaults.translationModel);
      await sp.setString(_keyTutorBaseUrl, defaults.tutorBaseUrl);
      await sp.setString(_keyTutorApiKey, defaults.tutorApiKey);
      await sp.setString(_keyTutorModel, defaults.tutorModel);
      await sp.setInt(_keyConfigVersion, kCurrentConfigVersion);
    }

    final legacy = sp.getString(_legacyKeyTextSize);
    final scale =
        sp.getDouble(_keyTextScale) ??
        (legacy == null
            ? null
            : LearningTextSizePreset.values
                  .firstWhere(
                    (preset) => preset.name == legacy,
                    orElse: () => LearningTextSizePreset.normal,
                  )
                  .scale);
    return AppPreferences(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == sp.getString(_keyThemeMode),
        orElse: () => AppPreferences.defaults.themeMode,
      ),
      learningFont: LearningFont.values.firstWhere(
        (f) => f.name == sp.getString(_keyFont),
        orElse: () => AppPreferences.defaults.learningFont,
      ),
      textScale:
          scale?.clamp(kMinTextScale, kMaxTextScale) ??
          AppPreferences.defaults.textScale,
      uiLanguage: AppLanguage.values.firstWhere(
        (l) => l.name == sp.getString(_keyLanguage),
        orElse: () => AppPreferences.defaults.uiLanguage,
      ),
      translationBaseUrl: upgradeEndpoints
          ? AppPreferences.defaults.translationBaseUrl
          : (sp.getString(_keyTranslationBaseUrl) ??
                AppPreferences.defaults.translationBaseUrl),
      // An empty stored key means "never configured" rather than "deliberately
      // keyless" — fall back to the shipped default so translation works.
      translationApiKey: () {
        if (upgradeEndpoints) return AppPreferences.defaults.translationApiKey;
        final stored = sp.getString(_keyTranslationApiKey);
        return (stored == null || stored.isEmpty)
            ? AppPreferences.defaults.translationApiKey
            : stored;
      }(),
      translationModel: upgradeEndpoints
          ? AppPreferences.defaults.translationModel
          : (sp.getString(_keyTranslationModel) ??
                AppPreferences.defaults.translationModel),
      asrThreads: () {
        final stored = sp.getInt(_keyAsrThreads);
        if (stored == null || stored == 4) return kDefaultAsrThreads;
        return stored.clamp(kMinAsrThreads, kMaxAsrThreads);
      }(),
      asrTier: AsrTier.values.firstWhere(
        (t) => t.name == sp.getString(_keyAsrTier),
        orElse: () => AppPreferences.defaults.asrTier,
      ),
      youtubeRelayBaseUrl:
          sp.getString(_keyYoutubeRelayBaseUrl) ??
          AppPreferences.defaults.youtubeRelayBaseUrl,
      tutorBaseUrl: upgradeEndpoints
          ? AppPreferences.defaults.tutorBaseUrl
          : (sp.getString(_keyTutorBaseUrl) ??
                AppPreferences.defaults.tutorBaseUrl),
      tutorApiKey: () {
        if (upgradeEndpoints) return AppPreferences.defaults.tutorApiKey;
        final stored = sp.getString(_keyTutorApiKey);
        return (stored == null || stored.isEmpty)
            ? AppPreferences.defaults.tutorApiKey
            : stored;
      }(),
      tutorModel: upgradeEndpoints
          ? AppPreferences.defaults.tutorModel
          : (sp.getString(_keyTutorModel) ??
                AppPreferences.defaults.tutorModel),
      libraryGridView: sp.getBool(_keyLibraryGridView) ?? true,
      scrubberHaptics: sp.getBool(_keyScrubberHaptics) ?? true,
      configVersion: kCurrentConfigVersion,
    );
  }

  @override
  Future<void> save(AppPreferences prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyThemeMode, prefs.themeMode.name);
    await sp.setString(_keyFont, prefs.learningFont.name);
    await sp.setDouble(_keyTextScale, prefs.textScale);
    await sp.setString(_keyLanguage, prefs.uiLanguage.name);
    await sp.setString(_keyTranslationBaseUrl, prefs.translationBaseUrl);
    await sp.setString(_keyTranslationApiKey, prefs.translationApiKey);
    await sp.setString(_keyTranslationModel, prefs.translationModel);
    await sp.setInt(_keyAsrThreads, prefs.asrThreads);
    await sp.setString(_keyAsrTier, prefs.asrTier.name);
    await sp.setString(_keyYoutubeRelayBaseUrl, prefs.youtubeRelayBaseUrl);
    await sp.setString(_keyTutorBaseUrl, prefs.tutorBaseUrl);
    await sp.setString(_keyTutorApiKey, prefs.tutorApiKey);
    await sp.setString(_keyTutorModel, prefs.tutorModel);
    await sp.setBool(_keyLibraryGridView, prefs.libraryGridView);
    await sp.setBool(_keyScrubberHaptics, prefs.scrubberHaptics);
    await sp.setInt(_keyConfigVersion, prefs.configVersion);
  }
}

/// Owns the current [AppPreferences] and notifies listeners (theme, settings
/// page and learning typography all react). Saving is fire-and-forget: a
/// failed write must never block a settings tap.
class PreferencesController extends ChangeNotifier {
  PreferencesController({AppPreferencesStore? store})
    : store = store ?? SharedPrefsAppPreferencesStore();

  final AppPreferencesStore store;

  AppPreferences _prefs = AppPreferences.defaults;

  AppPreferences get prefs => _prefs;

  Future<void> load() async {
    _prefs = await store.load();
    notifyListeners();
  }

  Future<void> update({
    ThemeMode? themeMode,
    LearningFont? learningFont,
    double? textScale,
    AppLanguage? uiLanguage,
    String? translationBaseUrl,
    String? translationApiKey,
    String? translationModel,
    int? asrThreads,
    AsrTier? asrTier,
    String? youtubeRelayBaseUrl,
    String? tutorBaseUrl,
    String? tutorApiKey,
    String? tutorModel,
    bool? libraryGridView,
    bool? scrubberHaptics,
  }) async {
    _prefs = _prefs.copyWith(
      themeMode: themeMode,
      learningFont: learningFont,
      textScale: textScale,
      uiLanguage: uiLanguage,
      translationBaseUrl: translationBaseUrl,
      translationApiKey: translationApiKey,
      translationModel: translationModel,
      asrThreads: asrThreads,
      asrTier: asrTier,
      youtubeRelayBaseUrl: youtubeRelayBaseUrl,
      tutorBaseUrl: tutorBaseUrl,
      tutorApiKey: tutorApiKey,
      tutorModel: tutorModel,
      libraryGridView: libraryGridView,
      scrubberHaptics: scrubberHaptics,
    );
    notifyListeners();
    try {
      await store.save(_prefs);
    } catch (error) {
      debugPrint('[ListenLoop] saving preferences failed: $error');
    }
  }
}

/// Provides [PreferencesController] to the whole tree; widgets that depend on
/// it rebuild whenever a preference changes (live preview for free).
class PreferencesScope extends InheritedNotifier<PreferencesController> {
  const PreferencesScope({
    super.key,
    required PreferencesController controller,
    required super.child,
  }) : super(notifier: controller);

  static PreferencesController of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PreferencesScope>()
          ?.notifier ??
      (throw FlutterError('PreferencesScope missing above ${context.widget}'));

  /// Tolerant lookup for widgets that must also work without a scope
  /// (widget tests pump listening screens directly): falls back to defaults.
  static AppPreferences maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PreferencesScope>()
          ?.notifier
          ?.prefs ??
      AppPreferences.defaults;
}
