import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'civic_backend_api_service.dart';

/// Injectable Khmer ↔ English comment translation contract.
abstract class CommentTranslationService {
  /// Translates [text] into [targetLang] (`'km'` or `'en'`).
  /// Returns `null` when offline or translation fails.
  Future<String?> translate({required String text, required String targetLang});

  /// Detects whether [text] should be translated into Khmer (`'km'`) or
  /// English (`'en'`) based on Khmer Unicode vs. Latin character count.
  static String detectTargetLanguage(
    String text, {
    bool appEnglishFirst = false,
  }) {
    var khmerChars = 0;
    var latinChars = 0;
    for (final rune in text.runes) {
      if ((rune >= 0x1780 && rune <= 0x17FF) ||
          (rune >= 0x19E0 && rune <= 0x19FF)) {
        khmerChars++;
      } else if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A)) {
        latinChars++;
      }
    }

    if (khmerChars > 0 && latinChars == 0) return 'en';
    if (latinChars > 0 && khmerChars == 0) return 'km';
    if (khmerChars > latinChars) return 'en';
    if (latinChars > khmerChars) return 'km';
    return appEnglishFirst ? 'en' : 'km';
  }
}

/// CORS-friendly dual-provider Khmer ↔ English translation client with
/// in-memory LRU caching and zero API keys required.
class HttpCommentTranslationService implements CommentTranslationService {
  HttpCommentTranslationService({this.httpClient, String? baseUrl})
    : _baseUrl = resolveBackendBaseUrl(baseUrl ?? _envBaseUrl);

  static final HttpCommentTranslationService instance =
      HttpCommentTranslationService();
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String translatePath = '/api/v1/ai/translate';
  static const Duration requestTimeout = Duration(seconds: 5);
  static const int _maxCacheEntries = 120;

  final http.Client? httpClient;
  final String _baseUrl;
  final Map<String, String> _cache = <String, String>{};

  String get normalizedBaseUrl => _baseUrl;

  @override
  Future<String?> translate({
    required String text,
    required String targetLang,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final normalizedTarget = targetLang.trim().toLowerCase() == 'km'
        ? 'km'
        : 'en';
    final cacheKey = '$normalizedTarget::$trimmed';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    try {
      if (normalizedBaseUrl.isNotEmpty) {
        final backend = await _translateWithBackend(
          client: client,
          text: trimmed,
          targetLang: normalizedTarget,
        );
        if (backend != null && backend.isNotEmpty) {
          _storeCache(cacheKey, backend);
          return backend;
        }
      }

      final primary = await _translateWithGoogle(
        client: client,
        text: trimmed,
        targetLang: normalizedTarget,
      );
      if (primary != null && primary.isNotEmpty) {
        _storeCache(cacheKey, primary);
        return primary;
      }

      final fallback = await _translateWithMyMemory(
        client: client,
        text: trimmed,
        targetLang: normalizedTarget,
      );
      if (fallback != null && fallback.isNotEmpty) {
        _storeCache(cacheKey, fallback);
        return fallback;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (shouldClose) client.close();
    }
  }

  void _storeCache(String key, String value) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  Future<String?> _translateWithBackend({
    required http.Client client,
    required String text,
    required String targetLang,
  }) async {
    try {
      final uri = Uri.parse('$normalizedBaseUrl$translatePath');
      final response = await client
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'text': text,
              'target_lang': targetLang,
            }),
          )
          .timeout(requestTimeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final translated = (decoded['translated_text'] as String?)?.trim();
      return (translated == null || translated.isEmpty) ? null : translated;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _translateWithGoogle({
    required http.Client client,
    required String text,
    required String targetLang,
  }) async {
    try {
      final uri = Uri.https(
        'translate.googleapis.com',
        '/translate_a/single',
        <String, String>{
          'client': 'gtx',
          'sl': 'auto',
          'tl': targetLang,
          'dt': 't',
          'q': text,
        },
      );
      final response = await client.get(uri).timeout(requestTimeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final segments = decoded.first;
      if (segments is! List) return null;

      final buffer = StringBuffer();
      for (final seg in segments) {
        if (seg is List && seg.isNotEmpty && seg.first is String) {
          buffer.write(seg.first as String);
        }
      }
      final result = buffer.toString().trim();
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _translateWithMyMemory({
    required http.Client client,
    required String text,
    required String targetLang,
  }) async {
    try {
      final sourceLang = targetLang == 'km' ? 'en' : 'km';
      final uri = Uri.https(
        'api.mymemory.translated.net',
        '/get',
        <String, String>{'q': text, 'langpair': '$sourceLang|$targetLang'},
      );
      final response = await client.get(uri).timeout(requestTimeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final responseData = decoded['responseData'];
      if (responseData is! Map<String, dynamic>) return null;
      final translated = (responseData['translatedText'] as String?)?.trim();
      if (translated == null || translated.isEmpty) return null;
      return translated;
    } catch (_) {
      return null;
    }
  }
}
