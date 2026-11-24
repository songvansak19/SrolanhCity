import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/report_models.dart';
import 'file_helper.dart';

/// Lifecycle state of backend-powered AI classification on a citizen photo.
enum PhotoAiStatus {
  noPhoto,
  awaitingBackend,
  analyzing,
  analyzed,
  notCivicIssue,
  offline,
  rateLimited,
  failed,
}

/// Structured result returned from SrolanhCity's backend AI classifier
/// (`POST /api/v1/ai/classify-issue`, `hackathonshow.md §4 Step 1`).
class PhotoAiAnalysis {
  const PhotoAiAnalysis({
    required this.status,
    this.detectedCategory,
    this.confidencePercent,
    this.suggestedSeverity,
    this.khmerSummary,
    this.englishSummary,
    this.khmerReason,
    this.englishReason,
    this.errorMessage,
  });

  static const PhotoAiAnalysis noPhoto = PhotoAiAnalysis(
    status: PhotoAiStatus.noPhoto,
  );

  static const PhotoAiAnalysis awaitingBackend = PhotoAiAnalysis(
    status: PhotoAiStatus.awaitingBackend,
  );

  static const PhotoAiAnalysis analyzing = PhotoAiAnalysis(
    status: PhotoAiStatus.analyzing,
  );

  static const PhotoAiAnalysis offline = PhotoAiAnalysis(
    status: PhotoAiStatus.offline,
  );

  final PhotoAiStatus status;
  final IssueCategory? detectedCategory;
  final int? confidencePercent;
  final int? suggestedSeverity;
  final String? khmerSummary;
  final String? englishSummary;
  final String? khmerReason;
  final String? englishReason;
  final String? errorMessage;

  bool get hasDetectedIssue =>
      status == PhotoAiStatus.analyzed && detectedCategory != null;
}

/// Structured result returned from SrolanhCity's backend voice transcription
/// endpoint (`POST /api/v1/ai/transcribe-voice`, `hackathonshow.md §5`).
class AudioTranscriptionResult {
  const AudioTranscriptionResult({
    required this.success,
    this.transcript,
    this.detectedCategory,
    this.isRateLimited = false,
    this.errorMessage,
  });

  final bool success;
  final String? transcript;
  final IssueCategory? detectedCategory;
  final bool isRateLimited;
  final String? errorMessage;
}

/// One message turn sent as conversational history to `/api/v1/ai/help-chat`.
class HelpChatTurn {
  const HelpChatTurn({required this.role, required this.text});

  final String role; // 'user' | 'assistant'
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'role': role,
    'text': text,
  };
}

/// Optional contextual action chip attached to a Help Center AI reply.
enum HelpSuggestedAction {
  openReportWizard,
  openMyReports,
  openTicket,
  callRoadHotline1190,
  callPowerHotline1298,
  openEditProfile,
}

/// Structured reply from SrolanhCity's Help Center AI endpoint or on-device
/// civic assistant fallback.
class HelpChatReply {
  const HelpChatReply({
    required this.success,
    required this.text,
    this.fromBackendAi = false,
    this.suggestedAction,
    this.referencedReportId,
    this.isRateLimited = false,
    this.errorMessage,
  });

  final bool success;
  final String text;
  final bool fromBackendAi;
  final HelpSuggestedAction? suggestedAction;
  final String? referencedReportId;
  final bool isRateLimited;
  final String? errorMessage;
}

/// Clean client-to-backend AI contract.
///
/// The mobile app never holds third-party AI API keys or calls external AI
/// providers directly—SrolanhCity's backend owns the AI model credentials,
/// free-tier rate limits, and ODC GIS pipeline.
abstract class CivicAiService {
  /// Whether a SrolanhCity backend base URL (`--dart-define=API_BASE_URL=...`)
  /// is configured for this build.
  bool get isBackendConfigured;

  Future<PhotoAiAnalysis> analyzeIssuePhoto({
    required String imagePath,
    required bool englishFirst,
    String? descriptionHint,
    bool forceRefresh = false,
  });

  Future<AudioTranscriptionResult> transcribeVoiceAudio({
    required String audioPath,
    required bool englishFirst,
  });

  Future<HelpChatReply> askHelpAssistant({
    required String message,
    required List<HelpChatTurn> history,
    required bool englishFirst,
    Map<String, dynamic>? citizenContext,
  });
}

/// Backend-first HTTP client targeting SrolanhCity's own API endpoints:
/// - `POST {API_BASE_URL}/api/v1/ai/classify-issue`
/// - `POST {API_BASE_URL}/api/v1/ai/transcribe-voice`
///
/// While `API_BASE_URL` is unset (client-only phase), stays cleanly in draft
/// state ([PhotoAiStatus.awaitingBackend]) with zero network calls.
class BackendCivicAiService implements CivicAiService {
  BackendCivicAiService({this.httpClient, String? baseUrl})
    : _rawBaseUrl = (baseUrl ?? _envBaseUrl).trim();

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String classifyPath = '/api/v1/ai/classify-issue';
  static const String transcribePath = '/api/v1/ai/transcribe-voice';
  static const String helpChatPath = '/api/v1/ai/help-chat';
  static const Duration requestTimeout = Duration(seconds: 18);

  final http.Client? httpClient;
  final String _rawBaseUrl;
  final Map<String, PhotoAiAnalysis> _photoCache = <String, PhotoAiAnalysis>{};

  String get normalizedBaseUrl => _rawBaseUrl.endsWith('/')
      ? _rawBaseUrl.substring(0, _rawBaseUrl.length - 1)
      : _rawBaseUrl;

  @override
  bool get isBackendConfigured => normalizedBaseUrl.isNotEmpty;

  Uri? endpointUri(String path) {
    if (!isBackendConfigured) return null;
    return Uri.tryParse('$normalizedBaseUrl$path');
  }

  /// Builds the JSON request body for `POST /api/v1/ai/classify-issue`.
  Map<String, dynamic> buildPhotoRequestBody({
    required String base64Image,
    required String mimeType,
    required bool englishFirst,
    String? descriptionHint,
  }) {
    final hint = descriptionHint?.trim() ?? '';
    return <String, dynamic>{
      'image_base64': base64Image,
      'mime_type': mimeType,
      'language': englishFirst ? 'en' : 'km',
      if (hint.isNotEmpty) 'description_hint': hint,
    };
  }

  /// Builds the JSON request body for `POST /api/v1/ai/transcribe-voice`.
  Map<String, dynamic> buildAudioRequestBody({
    required String base64Audio,
    required String mimeType,
    required bool englishFirst,
  }) {
    return <String, dynamic>{
      'audio_base64': base64Audio,
      'mime_type': mimeType,
      'language': englishFirst ? 'en' : 'km',
    };
  }

  @override
  Future<PhotoAiAnalysis> analyzeIssuePhoto({
    required String imagePath,
    required bool englishFirst,
    String? descriptionHint,
    bool forceRefresh = false,
  }) async {
    if (!isBackendConfigured) {
      return PhotoAiAnalysis.awaitingBackend;
    }

    final cacheKey = '$imagePath|${descriptionHint?.trim() ?? ''}';
    if (!forceRefresh && _photoCache.containsKey(cacheKey)) {
      return _photoCache[cacheKey]!;
    }

    final bytes = await readLocalFileBytes(imagePath);
    if (bytes == null) {
      return const PhotoAiAnalysis(
        status: PhotoAiStatus.failed,
        errorMessage: 'Image file not found.',
      );
    }
    final mimeType = imagePath.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';

    final payload = buildPhotoRequestBody(
      base64Image: base64Encode(bytes),
      mimeType: mimeType,
      englishFirst: englishFirst,
      descriptionHint: descriptionHint,
    );

    final response = await _postJson(path: classifyPath, payload: payload);
    if (!response.ok) {
      return PhotoAiAnalysis(
        status: response.isRateLimited
            ? PhotoAiStatus.rateLimited
            : PhotoAiStatus.failed,
        errorMessage: response.errorMessage,
      );
    }

    final parsed = parsePhotoResponseJson(response.body!);
    if (parsed.status == PhotoAiStatus.analyzed ||
        parsed.status == PhotoAiStatus.notCivicIssue) {
      _photoCache[cacheKey] = parsed;
    }
    return parsed;
  }

  @override
  Future<AudioTranscriptionResult> transcribeVoiceAudio({
    required String audioPath,
    required bool englishFirst,
  }) async {
    if (!isBackendConfigured) {
      return const AudioTranscriptionResult(
        success: false,
        errorMessage: 'Backend AI service is not connected yet.',
      );
    }

    final bytes = await readLocalFileBytes(audioPath);
    if (bytes == null) {
      return const AudioTranscriptionResult(
        success: false,
        errorMessage: 'Recorded audio file not found.',
      );
    }
    if (bytes.length < 1024) {
      return const AudioTranscriptionResult(
        success: false,
        errorMessage: 'Recording too short.',
      );
    }

    final lower = audioPath.toLowerCase();
    final mimeType = lower.endsWith('.wav')
        ? 'audio/wav'
        : (lower.endsWith('.mp3') ? 'audio/mp3' : 'audio/aac');

    final payload = buildAudioRequestBody(
      base64Audio: base64Encode(bytes),
      mimeType: mimeType,
      englishFirst: englishFirst,
    );

    final response = await _postJson(path: transcribePath, payload: payload);
    if (!response.ok) {
      return AudioTranscriptionResult(
        success: false,
        isRateLimited: response.isRateLimited,
        errorMessage: response.errorMessage,
      );
    }

    return parseAudioResponseJson(response.body!);
  }

  /// Builds the JSON request body for `POST /api/v1/ai/help-chat`.
  Map<String, dynamic> buildHelpChatRequestBody({
    required String message,
    required List<HelpChatTurn> history,
    required bool englishFirst,
    Map<String, dynamic>? citizenContext,
  }) => <String, dynamic>{
    'message': message.trim(),
    'language': englishFirst ? 'en' : 'km',
    'history': history.take(8).map((t) => t.toJson()).toList(),
    if (citizenContext != null && citizenContext.isNotEmpty)
      'citizen_context': citizenContext,
  };

  @override
  Future<HelpChatReply> askHelpAssistant({
    required String message,
    required List<HelpChatTurn> history,
    required bool englishFirst,
    Map<String, dynamic>? citizenContext,
  }) async {
    if (!isBackendConfigured) {
      return const HelpChatReply(
        success: false,
        text: '',
        errorMessage: 'Backend AI service is not connected yet.',
      );
    }

    final payload = buildHelpChatRequestBody(
      message: message,
      history: history,
      englishFirst: englishFirst,
      citizenContext: citizenContext,
    );
    final response = await _postJson(path: helpChatPath, payload: payload);
    if (!response.ok) {
      return HelpChatReply(
        success: false,
        text: '',
        isRateLimited: response.isRateLimited,
        errorMessage: response.errorMessage,
      );
    }
    return parseHelpChatResponseJson(response.body!);
  }

  static HelpChatReply parseHelpChatResponseJson(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        final reply = ((decoded['reply'] as String?) ?? '').trim();
        if (reply.isNotEmpty) {
          return HelpChatReply(
            success: true,
            text: reply,
            fromBackendAi: true,
            referencedReportId: (decoded['report_id'] as String?)?.trim(),
          );
        }
      }
    } catch (_) {}
    return const HelpChatReply(
      success: false,
      text: '',
      errorMessage: 'Could not parse backend Help AI JSON.',
    );
  }

  static PhotoAiAnalysis parsePhotoResponseJson(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) {
        return const PhotoAiAnalysis(
          status: PhotoAiStatus.failed,
          errorMessage: 'Unexpected backend AI response format.',
        );
      }

      final isCivic = decoded['is_civic_issue'] == true;
      final category = _parseCategory(decoded['category'] as String?);
      final confidenceRaw = decoded['confidence_percent'];
      final confidence = confidenceRaw is num
          ? confidenceRaw.round().clamp(1, 99)
          : 85;
      final severityRaw = decoded['severity'];
      final severity = switch (severityRaw is num ? severityRaw.round() : 3) {
        <= 2 => 2,
        >= 4 => 5,
        _ => 3,
      };
      final khSummary = (decoded['khmer_summary'] as String?)?.trim();
      final enSummary = (decoded['english_summary'] as String?)?.trim();
      final khReason = (decoded['khmer_reason'] as String?)?.trim();
      final enReason = (decoded['english_reason'] as String?)?.trim();

      if (!isCivic || category == null) {
        return PhotoAiAnalysis(
          status: PhotoAiStatus.notCivicIssue,
          confidencePercent: confidence,
          khmerSummary: khSummary,
          englishSummary: enSummary,
          khmerReason: khReason,
          englishReason: enReason,
        );
      }

      return PhotoAiAnalysis(
        status: PhotoAiStatus.analyzed,
        detectedCategory: category,
        confidencePercent: confidence,
        suggestedSeverity: severity,
        khmerSummary: khSummary?.isNotEmpty == true ? khSummary : null,
        englishSummary: enSummary?.isNotEmpty == true ? enSummary : null,
        khmerReason: khReason?.isNotEmpty == true ? khReason : null,
        englishReason: enReason?.isNotEmpty == true ? enReason : null,
      );
    } catch (_) {
      return const PhotoAiAnalysis(
        status: PhotoAiStatus.failed,
        errorMessage: 'Could not parse backend AI JSON.',
      );
    }
  }

  static AudioTranscriptionResult parseAudioResponseJson(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        final transcript = ((decoded['transcript'] as String?) ?? '').trim();
        final category = _parseCategory(decoded['category'] as String?);
        if (transcript.isEmpty) {
          return const AudioTranscriptionResult(
            success: false,
            errorMessage: 'No speech detected in audio.',
          );
        }
        return AudioTranscriptionResult(
          success: true,
          transcript: transcript,
          detectedCategory: category,
        );
      }
    } catch (_) {}
    return const AudioTranscriptionResult(
      success: false,
      errorMessage: 'Could not parse backend transcription response.',
    );
  }

  static IssueCategory? _parseCategory(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'pothole' => IssueCategory.pothole,
      'streetlight' => IssueCategory.streetlight,
      'drain' => IssueCategory.drain,
      'trash' => IssueCategory.trash,
      'other' => IssueCategory.other,
      _ => null,
    };
  }

  Future<_BackendHttpResult> _postJson({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    final uri = endpointUri(path);
    if (uri == null || !uri.hasScheme) {
      return const _BackendHttpResult(
        ok: false,
        errorMessage: 'Invalid backend API URL.',
      );
    }

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;

    try {
      final response = await client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(requestTimeout);
      final body = response.body;

      if (response.statusCode == 429) {
        return const _BackendHttpResult(
          ok: false,
          isRateLimited: true,
          errorMessage: 'AI service is busy. Please wait a moment.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _BackendHttpResult(
          ok: false,
          errorMessage: 'Backend AI returned HTTP ${response.statusCode}.',
        );
      }
      return _BackendHttpResult(ok: true, body: body);
    } on TimeoutException {
      return const _BackendHttpResult(
        ok: false,
        errorMessage: 'Backend AI request timed out.',
      );
    } catch (_) {
      return const _BackendHttpResult(
        ok: false,
        errorMessage: 'Could not reach SrolanhCity backend AI service.',
      );
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }
}

class _BackendHttpResult {
  const _BackendHttpResult({
    required this.ok,
    this.body,
    this.isRateLimited = false,
    this.errorMessage,
  });

  final bool ok;
  final String? body;
  final bool isRateLimited;
  final String? errorMessage;
}
