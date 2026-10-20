import 'dart:convert';
import 'dart:io';

import '../preferences/app_preferences.dart';

/// Translation boundary (spec V1 §二十四): English sentences in, Chinese
/// sentences out — one per input, always (count mismatch = failure).
///
/// v1 talks to an OpenAI-compatible endpoint (§二十五). The endpoint is
/// configured ON THE DEVICE — base URL, API key and model all live in
/// [AppPreferences] and are edited in Settings, so an expired key or a
/// renamed model never needs the PC again. Offline translation stays a
/// deliberate M4 topic (§二十六).
abstract class TranslationEngine {
  Future<List<String>> translate(
    List<String> sentences, {
    String? sourceLanguage,
  });
}

/// Dynamic system prompt: tailors instructions based on sourceLanguage.
String buildTranslationSystemPrompt(String? sourceLanguage) {
  final lang = (sourceLanguage ?? '').toLowerCase().trim();
  if (lang == 'ja') {
    return '你是专业日文字幕翻译。把用户给出的编号日文字幕句子逐条翻译成流畅自然的简体中文，'
        '只输出 JSON：{"translations": ["...", ...]}，条数必须与输入一致，'
        '不要输出任何其他内容。';
  } else if (lang == 'zh') {
    return '你是专业中文字幕助手。保持原意，将用户给出的编号字幕句子输出为规范自然的简体中文，'
        '只输出 JSON：{"translations": ["...", ...]}，条数必须与输入一致，'
        '不要输出任何其他内容。';
  }
  return '你是专业字幕翻译。把用户给出的编号字幕句子（包含英文、日文等多语种）逐条翻译成自然的简体中文，'
      '只输出 JSON：{"translations": ["...", ...]}，条数必须与输入一致，'
      '不要输出任何其他内容。';
}

const String kTranslationSystemPrompt =
    '你是专业字幕翻译。把用户给出的编号字幕句子（包含英文、日文等多语种）逐条翻译成自然的简体中文，'
    '只输出 JSON：{"translations": ["...", ...]}，条数必须与输入一致，'
    '不要输出任何其他内容。';

/// Joins a configured base URL with an OpenAI-style path. The base URL
/// carries the `/v1` segment (e.g. `https://openrouter.ai/api/v1`), but a
/// trailing slash or a base that already ends in `/v1/` must not double up.
Uri translationEndpoint(String baseUrl, String path) {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  return Uri.parse('$base/$path');
}

/// Lists the model ids an endpoint advertises (`GET {base}/models`).
///
/// Throws with a readable reason on any failure — Settings shows it verbatim,
/// because a silent translation failure is exactly what made the first M1
/// lesson come out with empty Chinese.
Future<List<String>> fetchTranslationModels({
  required String baseUrl,
  required String apiKey,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final body = await _requestJson(
    method: 'GET',
    url: translationEndpoint(baseUrl, 'models'),
    apiKey: apiKey,
    timeout: timeout,
  );
  final data = body['data'];
  if (data is! List) {
    throw const FormatException('endpoint returned no model list');
  }
  final ids = <String>[
    for (final entry in data)
      if (entry is Map && entry['id'] is String) entry['id'] as String,
  ]..sort();
  if (ids.isEmpty) {
    throw const FormatException('endpoint advertised no models');
  }
  return ids;
}

/// Sentences per translation request.
///
/// Kept at 12 sentences per batch so even low-limit free tier models
/// (e.g. Groq OTPM limit of 1000 tokens) stay well within quota per request.
const int kTranslationBatchSize = 12;

/// Attempts per batch before giving up on that batch alone.
///
/// Deliberately NOT a whole-lesson retry: by the time translation runs, the
/// expensive ASR work is already done and must not be repeated (§二十六).
const int kTranslationBatchAttempts = 4;

/// Wait before attempt N+1 of a batch, multiplied by the attempt number.
///
/// Measured reason: on a 95-sentence lesson, rapid successive requests came
/// back as `SSL: UNEXPECTED_EOF_WHILE_READING` / `RemoteDisconnected` while a
/// single large request succeeded — the endpoint drops connections under a
/// burst, so the retry has to back off rather than hammer.
const Duration kTranslationRetryBackoff = Duration(milliseconds: 800);

/// One-shot translation against an explicit configuration.
///
/// Settings calls this to TEST unsaved form values; [GatewayTranslationEngine]
/// calls it with the live preferences.
///
/// Splits the work into batches, retries a failing batch on its own, and only
/// throws when EVERY batch failed — a total outage must stay visible instead
/// of degrading into an all-empty lesson with a cheerful "Translation: OK".
Future<List<String>> translateSentences({
  required String baseUrl,
  required String apiKey,
  required String model,
  required List<String> english,
  String? sourceLanguage,
  Duration timeout = const Duration(minutes: 5),
}) async {
  if (english.isEmpty) return const [];
  final translations = List<String>.filled(english.length, '');
  Object? lastError;
  var succeeded = 0;

  for (var start = 0; start < english.length; start += kTranslationBatchSize) {
    final end = (start + kTranslationBatchSize).clamp(0, english.length);
    final batch = english.sublist(start, end);
    final result = await _translateBatch(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      english: batch,
      sourceLanguage: sourceLanguage,
      timeout: timeout,
      onError: (error) => lastError = error,
    );
    if (result != null) {
      succeeded++;
      for (var i = 0; i < batch.length && i < result.length; i++) {
        translations[start + i] = result[i];
      }
    }
  }

  if (succeeded == 0 && lastError != null) throw lastError!;
  return translations;
}

/// Translates one batch, retrying on a short or failed response.
///
/// Returns null when the batch never came back complete — the caller keeps
/// whatever other batches produced instead of losing the whole lesson.
Future<List<String>?> _translateBatch({
  required String baseUrl,
  required String apiKey,
  required String model,
  required List<String> english,
  String? sourceLanguage,
  required Duration timeout,
  required void Function(Object) onError,
}) async {
  for (var attempt = 1; attempt <= kTranslationBatchAttempts; attempt++) {
    Object? currentError;
    try {
      final got = await _requestTranslations(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        english: english,
        sourceLanguage: sourceLanguage,
        timeout: timeout,
      );
      if (got.length >= english.length) return got;
      currentError = StateError('batch returned ${got.length}/${english.length}');
      onError(currentError);
    } catch (error) {
      currentError = error;
      onError(error);
    }
    if (attempt < kTranslationBatchAttempts) {
      final is429 = currentError.toString().contains('429');
      final backoff = is429
          ? Duration(seconds: 3 * attempt)
          : kTranslationRetryBackoff * attempt;
      await Future<void>.delayed(backoff);
    }
  }

  // Fallback: If full batch fails, try translating sentence by sentence
  if (english.length > 1) {
    final fallbackList = <String>[];
    for (final sent in english) {
      try {
        final single = await _requestTranslations(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          english: [sent],
          sourceLanguage: sourceLanguage,
          timeout: timeout,
        );
        fallbackList.add(single.isNotEmpty ? single.first : '');
      } catch (_) {
        fallbackList.add('');
      }
    }
    if (fallbackList.any((s) => s.isNotEmpty)) {
      return fallbackList;
    }
  }

  return null;
}

/// One request: numbered sentences in, N translations out.
Future<List<String>> _requestTranslations({
  required String baseUrl,
  required String apiKey,
  required String model,
  required List<String> english,
  String? sourceLanguage,
  required Duration timeout,
}) async {
  final numbered = [
    for (var i = 0; i < english.length; i++) '${i + 1}. ${english[i]}',
  ].join('\n');

  final body = await _requestJson(
    method: 'POST',
    url: translationEndpoint(baseUrl, 'chat/completions'),
    apiKey: apiKey,
    timeout: timeout,
    payload: {
      'model': model,
      'messages': [
        {'role': 'system', 'content': buildTranslationSystemPrompt(sourceLanguage)},
        {'role': 'user', 'content': numbered},
      ],
      'temperature': 0.2,
      // 12 sentences ≈ 400 output tokens, but reasoning-style models (MiMo
      // flash / DeepSeek) bill thinking tokens too. An explicit cap keeps a
      // batch from being cut mid-JSON, which the parser would read as a count
      // mismatch and fail the whole batch.
      'max_tokens': 2048,
    },
  );

  final choices = body['choices'];
  if (choices is! List || choices.isEmpty) {
    throw const FormatException('endpoint returned no choices');
  }
  final content = '${(choices.first as Map)['message']?['content'] ?? ''}';
  return _parseTranslations(content, english.length);
}

String _extractJsonBlock(String text) {
  final codeBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
  final match = codeBlock.firstMatch(text);
  if (match != null) return match.group(1)!.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start != -1 && end != -1 && end > start) {
    return text.substring(start, end + 1).trim();
  }
  return text.trim();
}

/// Reads translations from JSON object, array, or numbered lines.
List<String> _parseTranslations(String content, int expectedCount) {
  final extracted = _extractJsonBlock(content);
  try {
    final decoded = jsonDecode(extracted);
    final raw = decoded is Map
        ? decoded['translations']
        : (decoded is List ? decoded : null);
    if (raw is List) {
      final out = <String>[];
      for (final entry in raw) {
        if (entry is String) {
          out.add(entry.trim());
        } else if (entry is Map) {
          final value = entry['zh'] ?? entry['text'] ?? entry['translation'] ?? entry['zh-CN'];
          out.add(value is String ? value.trim() : '');
        } else {
          out.add('');
        }
      }
      if (out.isNotEmpty) return out;
    }
  } catch (_) {
    // Fall back to line-by-line parsing
  }

  // Regex line-by-line fallback: "1. xxx" or "1: xxx" or plain lines
  final lines = content
      .split('\n')
      .map((l) => l.trim())
      .where((l) =>
          l.isNotEmpty &&
          !l.startsWith('```') &&
          !l.startsWith('{') &&
          !l.startsWith('}'))
      .toList();
  final numbered = <String>[];
  final numPattern = RegExp(r'^\d+[\.、:：\s]+(.*)$');
  for (final line in lines) {
    final m = numPattern.firstMatch(line);
    if (m != null) {
      numbered.add(m.group(1)!.trim());
    }
  }
  if (numbered.length == expectedCount) return numbered;
  if (lines.length == expectedCount) return lines;
  return numbered.isNotEmpty ? numbered : const [];
}

/// Shared OpenAI-compatible JSON call: Bearer auth, JSON in/out, and a status
/// check that keeps the server's own message in the error.
Future<Map<String, dynamic>> _requestJson({
  required String method,
  required Uri url,
  required String apiKey,
  required Duration timeout,
  Map<String, Object?>? payload,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.openUrl(method, url);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final key = apiKey.trim();
    if (key.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
    }
    if (payload != null) request.write(jsonEncode(payload));

    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode}'
        '${_serverMessage(text) == null ? '' : ': ${_serverMessage(text)}'}',
        uri: url,
      );
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('endpoint returned a non-object body');
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

/// OpenAI-compatible servers report failures as
/// `{"error": {"message": "..."}}` — surface that instead of a bare status.
String? _serverMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (error is String) return error;
    }
  } catch (_) {
    // Not JSON — nothing useful to add.
  }
  return null;
}

/// Translates through the endpoint the user configured in Settings.
class GatewayTranslationEngine implements TranslationEngine {
  GatewayTranslationEngine({
    required this.settings,
    this.timeout = const Duration(minutes: 5),
  });

  /// Live view of the translation settings — read on EVERY call, so a change
  /// in Settings applies to the next job without rebuilding the app.
  final AppPreferences Function() settings;

  final Duration timeout;

  @override
  Future<List<String>> translate(
    List<String> english, {
    String? sourceLanguage,
  }) {
    final prefs = settings();
    return translateSentences(
      baseUrl: prefs.translationBaseUrl,
      apiKey: prefs.translationApiKey,
      model: prefs.translationModel,
      english: english,
      sourceLanguage: sourceLanguage,
      timeout: timeout,
    );
  }
}

/// Emits empty translations (mirrors `--no-translate` on the PC pipeline) —
/// used when the endpoint is unreachable and the user still wants the lesson.
class NullTranslationEngine implements TranslationEngine {
  const NullTranslationEngine();

  @override
  Future<List<String>> translate(
    List<String> english, {
    String? sourceLanguage,
  }) async =>
      List.filled(english.length, '');
}
