import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phrasing/preferences/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppPreferences defaults (spec V2 §八/§十四/§十七 + follow-up)', () {
    test('dark, sans, default scale — the ListenLoop identity', () {
      final prefs = AppPreferences.defaults;
      expect(prefs.themeMode, ThemeMode.dark);
      expect(prefs.learningFont, LearningFont.sans);
      expect(prefs.textScale, 0.75);
    });

    test('preset scales keep the english/chinese hierarchy', () {
      // 2026-10-20 郭老师：字号从 4 档收到 3 档「小/中/大」直选，0.50 那档
      // 太小已撤掉。
      expect(LearningTextSizePreset.small.scale, 0.75);
      expect(LearningTextSizePreset.normal.scale, 1.00);
      expect(LearningTextSizePreset.large.scale, 1.30);
    });

    test('preset lookup matches the current scale exactly', () {
      expect(
        LearningTextSizePreset.fromScale(1.30),
        LearningTextSizePreset.large,
      );
      // A custom value from the long-press slider matches no preset.
      expect(LearningTextSizePreset.fromScale(1.07), isNull);
    });

    test('learning font families: english choice, system-safe fallback', () {
      // Sans ships as bundled Roboto so it stays distinct from System even
      // on ROMs whose custom font replaces the system sans slot.
      expect(LearningFont.sans.family, 'LL Sans');
      expect(LearningFont.serif.family, 'serif');
      // System = no override, letting the platform (and its CJK fallbacks)
      // decide — spec V2 §十五.
      expect(LearningFont.system.family, isNull);
    });
  });

  group('PreferencesController', () {
    test('updates notify listeners and persist through the store', () async {
      final store = InMemoryAppPreferencesStore();
      final controller = PreferencesController(store: store);
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.update(themeMode: ThemeMode.light);
      await controller.update(learningFont: LearningFont.serif);
      await controller.update(textScale: 1.30);

      expect(notifications, 3);
      expect(controller.prefs.themeMode, ThemeMode.light);
      expect(controller.prefs.learningFont, LearningFont.serif);
      expect(controller.prefs.textScale, 1.30);
      expect(store.saveCount, 3, reason: 'every change is checkpointed');
    });

    test('load restores whatever the store holds', () async {
      final store = InMemoryAppPreferencesStore();
      await store.save(
        const AppPreferences(
          themeMode: ThemeMode.light,
          learningFont: LearningFont.system,
          textScale: 1.15,
        ),
      );
      final controller = PreferencesController(store: store);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.prefs.themeMode, ThemeMode.light);
      expect(controller.prefs.learningFont, LearningFont.system);
      expect(controller.prefs.textScale, 1.15);
    });
  });

  group('SharedPrefsAppPreferencesStore', () {
    test('round-trips preferences across "restarts"', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPrefsAppPreferencesStore();
      await store.save(
        const AppPreferences(
          themeMode: ThemeMode.light,
          learningFont: LearningFont.serif,
          textScale: 1.30,
        ),
      );

      // Simulate a fresh read (a new instance reads the same mock store).
      final store2 = SharedPrefsAppPreferencesStore();
      final prefs = await store2.load();

      expect(prefs.themeMode, ThemeMode.light);
      expect(prefs.learningFont, LearningFont.serif);
      expect(prefs.textScale, 1.30);
    });

    test('missing keys fall back to defaults (dark/sans/1.0)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPrefsAppPreferencesStore();

      final prefs = await store.load();

      expect(prefs.themeMode, ThemeMode.dark);
      expect(prefs.learningFont, LearningFont.sans);
      expect(prefs.textScale, 0.75);
    });

    test('legacy preset-name storage maps to a scale once', () async {
      // Pre-follow-up builds stored the size as a preset name.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'listenloop:pref.textSize': 'large',
      });
      final store = SharedPrefsAppPreferencesStore();

      final prefs = await store.load();

      expect(prefs.textScale, 1.00);
    });

    test('legacy preset names keep their OLD 4-tier scale', () async {
      // 2026-10-20 预设从 4 档收到 3 档后，枚举名含义整体挪了一位。
      // 老存档必须按**旧表**还原，升级才不改字号。
      for (final entry in <String, double>{
        'small': 0.50,
        'normal': 0.75,
        'large': 1.00,
        'extraLarge': 1.30,
      }.entries) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'listenloop:pref.textSize': entry.key,
        });
        final prefs = await SharedPrefsAppPreferencesStore().load();
        expect(prefs.textScale, entry.value, reason: 'legacy ${entry.key}');
      }
    });
  });

  group('ASR decode threads (Creation V2 §十五)', () {
    test('defaults to 6 (8 Gen 3 performance cluster)', () {
      expect(AppPreferences.defaults.asrThreads, kDefaultAsrThreads);
      expect(kDefaultAsrThreads, 6);
    });

    test('copyWith swaps only the thread count', () {
      final prefs = AppPreferences.defaults.copyWith(asrThreads: 6);
      expect(prefs.asrThreads, 6);
      expect(prefs.translationModel, kDefaultTranslationModel);
    });

    test('round-trips through the store', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPrefsAppPreferencesStore();

      await store.save(AppPreferences.defaults.copyWith(asrThreads: 8));

      expect((await store.load()).asrThreads, 8);
    });

    test('an out-of-range stored value is clamped, not trusted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'listenloop:pref.asrThreads': 99,
      });
      expect(
        (await SharedPrefsAppPreferencesStore().load()).asrThreads,
        kMaxAsrThreads,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'listenloop:pref.asrThreads': 0,
      });
      expect(
        (await SharedPrefsAppPreferencesStore().load()).asrThreads,
        kMinAsrThreads,
      );
    });
  });

  group('YouTube relay base URL', () {
    test('defaults to 127.0.0.1:8793', () {
      expect(
        AppPreferences.defaults.youtubeRelayBaseUrl,
        kDefaultYoutubeRelayBaseUrl,
      );
      expect(kDefaultYoutubeRelayBaseUrl, 'http://127.0.0.1:8793');
    });

    test('copyWith updates relay URL', () {
      final prefs = AppPreferences.defaults.copyWith(
        youtubeRelayBaseUrl: 'http://192.168.1.100:8793',
      );
      expect(prefs.youtubeRelayBaseUrl, 'http://192.168.1.100:8793');
    });

    test('round-trips through SharedPrefsAppPreferencesStore', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPrefsAppPreferencesStore();

      await store.save(
        AppPreferences.defaults.copyWith(
          youtubeRelayBaseUrl: 'http://192.168.31.50:8793',
        ),
      );

      final loaded = await store.load();
      expect(loaded.youtubeRelayBaseUrl, 'http://192.168.31.50:8793');
    });
  });

  group('config schema upgrade to MiMo (version < current)', () {
    test('a stale archive is upgraded AND persisted across launches', () async {
      // 模拟旧装机数据：伴学指向本机 :3100 网关，翻译指向 OpenRouter。
      SharedPreferences.setMockInitialValues(<String, Object>{
        'listenloop:pref.tutorBaseUrl': 'http://127.0.0.1:3100/v1',
        'listenloop:pref.tutorApiKey': 'gyt2005228',
        'listenloop:pref.tutorModel': 'free-heavy',
        'listenloop:pref.translationBaseUrl': 'https://openrouter.ai/api/v1',
        'listenloop:pref.translationApiKey': '',
        'listenloop:pref.translationModel': 'nex-agi/nex-n2.5-pro:free',
      });
      final store = SharedPrefsAppPreferencesStore();

      final first = await store.load();
      expect(first.translationBaseUrl, kDefaultMimoBaseUrl);
      expect(first.translationModel, kDefaultMimoModel);
      expect(first.tutorBaseUrl, kDefaultMimoBaseUrl);
      expect(first.tutorModel, kDefaultMimoModel);
      // 空串 = 从未配置过，应回退到随包预填的 key。
      expect(first.translationApiKey, isNotEmpty);

      // 第二次装载必须仍是 MiMo。首版迁移只改内存不落盘，第二次启动就会
      // 读回旧端点 —— 这个缺陷在真机上复现过，故此断言是回归锁。
      final second = await store.load();
      expect(second.translationBaseUrl, kDefaultMimoBaseUrl);
      expect(second.tutorBaseUrl, kDefaultMimoBaseUrl);
      expect(second.tutorModel, kDefaultMimoModel);
      expect(second.configVersion, kCurrentConfigVersion);
    });

    test('an already-upgraded archive keeps the user edits', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'listenloop:pref.configVersion': kCurrentConfigVersion,
        'listenloop:pref.tutorBaseUrl': 'https://custom.example/v1',
        'listenloop:pref.tutorModel': 'custom-model',
        'listenloop:pref.translationBaseUrl': 'https://custom.example/v1',
        'listenloop:pref.translationModel': 'custom-model',
      });
      final store = SharedPrefsAppPreferencesStore();
      final loaded = await store.load();
      expect(loaded.tutorBaseUrl, 'https://custom.example/v1');
      expect(loaded.tutorModel, 'custom-model');
      expect(loaded.translationModel, 'custom-model');
    });
  });
}
