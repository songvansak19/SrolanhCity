import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../../data/repositories/report_repository.dart';
import '../../../../data/services/audio_recorder_service.dart';
import '../../../../data/services/civic_ai_service.dart';
import '../../../../data/services/location_service.dart';
import '../../../../data/services/reverse_geocoding_service.dart';
import '../../../../data/services/voice_input_service.dart';
import '../../../../domain/models/cambodia_locations.dart';
import '../../../../domain/models/report_models.dart';
import '../../../../domain/models/routing_result.dart';
import '../../../../domain/services/ai_classifier_service.dart';
import '../../../../domain/services/gis_routing_service.dart';
import '../../../../domain/services/priority_calculator.dart';

/// Manages state and business interactions for the 3-step Report Wizard.
class ReportWizardViewModel extends ChangeNotifier {
  ReportWizardViewModel({
    required this.repository,
    IssueCategory initialCategory = IssueCategory.pothole,
    LatLng? initialCoordinates,
    ReportDraft? initialDraft,
    VoiceInputService? voiceInputService,
    AudioRecorderService? audioRecorderService,
    CivicAiService? civicAiService,
  }) : _voiceService = voiceInputService ?? SpeechToTextVoiceInputService(),
       _audioRecorder = audioRecorderService ?? RecordAudioRecorderService(),
       _civicAiService = civicAiService ?? BackendCivicAiService(),
       _step = initialDraft != null ? 1 : 0,
       _category = initialDraft?.category ?? initialCategory,
       _severity = initialDraft?.severity ?? 3,
       _isAnonymous =
           initialDraft?.isAnonymous ?? repository.settings.anonymousByDefault,
       _description = initialDraft?.description ?? '',
       _descriptionEditedByUser =
           initialDraft != null && initialDraft.description.trim().isNotEmpty,
       _localPhotoPaths = List<String>.of(
         initialDraft?.localPhotoPaths ?? const <String>[],
       ),
       _voiceTranscript = initialDraft?.voiceTranscript,
       _voicePreferEnglish = repository.settings.englishFirst,
       _pinLocation =
           initialCoordinates ??
           (repository.profile.hasHomeArea
               ? CambodiaLocationCatalog.matchFromProfileArea(
                   khmerArea: repository.profile.khmerHomeArea,
                   englishArea: repository.profile.englishHomeArea,
                   provinceCode: repository.profile.homeProvinceCode,
                 ).province.center
               : LocationService.phnomPenhCenter),
       _locationVerified = initialCoordinates != null;

  static const int maxPhotos = 3;
  static const int maxVoiceSeconds = 30;
  static const double _silencePeakThreshold = 0.04;

  final ReportRepository repository;
  final VoiceInputService _voiceService;
  final AudioRecorderService _audioRecorder;
  final CivicAiService _civicAiService;

  int _step;
  IssueCategory _category;
  bool _categoryLockedByUser = false;
  int _severity; // 2=Minor, 3=Moderate, 5=Dangerous (1–5 scale)
  bool _isAnonymous;
  String _description;
  bool _descriptionEditedByUser;
  final List<String> _localPhotoPaths;
  PhotoAiAnalysis _photoAi = PhotoAiAnalysis.noPhoto;
  int _photoAnalysisGeneration = 0;

  LatLng _pinLocation;
  GeocodedPlace? _geocodedPlace;
  double? _gpsAccuracyMeters;
  bool _locationVerified;
  bool _usedLiveGps = false;
  bool _isOutsideCambodia = false;
  LatLng? _rawOutsideGps;
  bool _isLocating = false;

  bool _isInitializingVoice = false;
  bool _isRecordingVoice = false;
  bool _isTranscribingVoice = false;
  bool _isHoldRecording = false;
  bool _voicePreferEnglish;
  VoiceCaptureMode _voiceMode = VoiceCaptureMode.deviceSpeech;
  double _voiceSoundLevel = 0.0;
  double _peakMicLevel = 0.0;
  int _recordingSeconds = 0;
  String? _voiceTranscript;
  String? _voiceFeedbackKhmer;
  String? _voiceFeedbackEnglish;
  bool _showVoiceDemoFallbackAction = false;
  bool _receivedSpeechInSession = false;
  Timer? _voiceTimer;
  Timer? _amplitudeTimer;
  Timer? _lateFinalTimer;
  bool _disposed = false;

  int get step => _step;
  IssueCategory get category => _category;
  int get severity => _severity;
  bool get isAnonymous => _isAnonymous;
  String get description => _description;
  List<String> get localPhotoPaths => List.unmodifiable(_localPhotoPaths);
  String? get localPhotoPath =>
      _localPhotoPaths.isEmpty ? null : _localPhotoPaths.first;
  String? get latestLocalPhotoPath =>
      _localPhotoPaths.isEmpty ? null : _localPhotoPaths.last;
  List<String> get additionalLocalPhotoPaths => _localPhotoPaths.length > 1
      ? List.unmodifiable(_localPhotoPaths.sublist(1))
      : const [];
  int get remainingPhotoSlots =>
      (maxPhotos - _localPhotoPaths.length).clamp(0, maxPhotos);
  bool get canAddMorePhotos => _localPhotoPaths.length < maxPhotos;
  PhotoAiAnalysis get photoAi => _photoAi;
  bool get isBackendAiAvailable => _civicAiService.isBackendConfigured;

  LatLng get pinLocation => _pinLocation;
  GeocodedPlace? get geocodedPlace => _geocodedPlace;
  double? get gpsAccuracyMeters => _gpsAccuracyMeters;
  bool get locationVerified => _locationVerified;
  bool get usedLiveGps => _usedLiveGps;
  bool get isOutsideCambodia => _isOutsideCambodia;
  LatLng? get rawOutsideGps => _rawOutsideGps;
  bool get isLocating => _isLocating;

  bool get isInitializingVoice => _isInitializingVoice;
  bool get isRecordingVoice => _isRecordingVoice;
  bool get isTranscribingVoice => _isTranscribingVoice;
  bool get isHoldRecording => _isHoldRecording;
  bool get voicePreferEnglish => _voicePreferEnglish;
  VoiceCaptureMode get voiceMode => _voiceMode;
  double get voiceSoundLevel => _voiceSoundLevel;
  int get recordingSeconds => _recordingSeconds;
  String? get voiceTranscript => _voiceTranscript;
  String? get voiceFeedbackKhmer => _voiceFeedbackKhmer;
  String? get voiceFeedbackEnglish => _voiceFeedbackEnglish;
  bool get showVoiceDemoFallbackAction => _showVoiceDemoFallbackAction;

  bool get hasUnsavedChanges =>
      _descriptionEditedByUser ||
      _localPhotoPaths.isNotEmpty ||
      _voiceTranscript != null ||
      _severity != 3;

  /// Honest text-keyword classification strictly over citizen-entered text.
  AiClassificationResult get classification => AiClassifierService.classify(
    description: _description,
    selectedCategory: _category,
    hasCustomPhoto: _localPhotoPaths.isNotEmpty,
  );

  GisRoutingResult get gisRouting => GisRoutingService.resolve(
    coordinates: _pinLocation,
    category: _category,
    geocodedPlace: _geocodedPlace,
  );

  DuplicateMatch? get nearbyDuplicate => repository.findDuplicateNearby(
    point: _pinLocation,
    category: _category,
    roadName: _geocodedPlace?.roadName ?? gisRouting.englishRoadName,
  );

  PriorityBreakdown get estimatedPriority {
    final duplicate = nearbyDuplicate;
    if (duplicate != null) {
      final existing = duplicate.masterReport;
      return PriorityCalculator.calculate(
        trafficScore: existing.roadClass.trafficScore,
        severityScore: _severity > existing.severity
            ? _severity
            : existing.severity,
        reportCount: existing.affectedCitizens + 1,
      );
    }
    return PriorityCalculator.calculate(
      trafficScore: gisRouting.roadClass.trafficScore,
      severityScore: _severity,
      reportCount: 1,
    );
  }

  ReportDraft toDraft() => ReportDraft(
    category: _category,
    severity: _severity,
    description: _description,
    isAnonymous: _isAnonymous,
    localPhotoPaths: List<String>.of(_localPhotoPaths),
    voiceTranscript: _voiceTranscript,
  );

  void saveDraft() => repository.saveDraft(toDraft());

  void nextStep() {
    if (_step < 2) {
      _step++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_step > 0) {
      _step--;
      notifyListeners();
    }
  }

  void selectCategory(IssueCategory next) {
    if (_category == next) return;
    _category = next;
    _categoryLockedByUser = true;
    notifyListeners();
  }

  void applyAiSuggestedCategory() {
    final suggested = _photoAi.hasDetectedIssue
        ? _photoAi.detectedCategory!
        : classification.category;
    if (suggested == _category) return;
    _category = suggested;
    notifyListeners();
  }

  void updateDescription(String value) {
    _description = value;
    _descriptionEditedByUser = value.trim().isNotEmpty;
    notifyListeners();
  }

  bool hasTag(String tag) => _description.contains(tag);

  void togglePresetTag(String tag) {
    if (_description.contains(tag)) {
      _description = _description
          .replaceAll(' · $tag', '')
          .replaceAll('$tag · ', '')
          .replaceAll(tag, '')
          .trim();
      _descriptionEditedByUser = _description.isNotEmpty;
    } else {
      _description = _description.trim().isEmpty
          ? tag
          : '${_description.trim()} · $tag';
      _descriptionEditedByUser = true;
    }
    notifyListeners();
  }

  void setSeverity(int value) {
    final clamped = value.clamp(1, 5);
    if (_severity == clamped) return;
    _severity = clamped;
    notifyListeners();
  }

  void setAnonymous(bool value) {
    if (_isAnonymous == value) return;
    _isAnonymous = value;
    notifyListeners();
  }

  void toggleVoiceLanguage() {
    if (_isRecordingVoice || _isTranscribingVoice) return;
    _voicePreferEnglish = !_voicePreferEnglish;
    _clearVoiceFeedback();
    notifyListeners();
  }

  bool addLocalPhotoPath(String path) {
    if (path.isEmpty) return false;
    if (_localPhotoPaths.length >= maxPhotos) return false;
    _localPhotoPaths.add(path);
    notifyListeners();
    unawaited(analyzeLatestPhoto());
    return true;
  }

  int addLocalPhotoPaths(Iterable<String> paths) {
    var added = 0;
    for (final path in paths) {
      if (path.isEmpty) continue;
      if (_localPhotoPaths.length >= maxPhotos) break;
      _localPhotoPaths.add(path);
      added++;
    }
    if (added > 0) {
      notifyListeners();
      unawaited(analyzeLatestPhoto());
    }
    return added;
  }

  void removeLocalPhotoAt(int index) {
    if (index < 0 || index >= _localPhotoPaths.length) return;
    _localPhotoPaths.removeAt(index);
    if (_localPhotoPaths.isEmpty) {
      _photoAnalysisGeneration++;
      _photoAi = PhotoAiAnalysis.noPhoto;
    } else {
      unawaited(analyzeLatestPhoto());
    }
    notifyListeners();
  }

  /// Runs backend AI classification (`hackathonshow.md §4 Step 1`) on the
  /// latest user-attached photo combined with any Khmer/English description.
  /// While no backend server is connected yet, stays cleanly in draft state
  /// ([PhotoAiStatus.awaitingBackend]) without faking detections.
  Future<void> analyzeLatestPhoto({bool forceRefresh = false}) async {
    final photoPath = latestLocalPhotoPath;
    if (photoPath == null) {
      _photoAi = PhotoAiAnalysis.noPhoto;
      notifyListeners();
      return;
    }

    if (!repository.isOnline) {
      _photoAi = PhotoAiAnalysis.offline;
      notifyListeners();
      return;
    }

    if (!_civicAiService.isBackendConfigured) {
      _photoAi = PhotoAiAnalysis.awaitingBackend;
      notifyListeners();
      return;
    }

    final gen = ++_photoAnalysisGeneration;
    _photoAi = PhotoAiAnalysis.analyzing;
    notifyListeners();

    final result = await _civicAiService.analyzeIssuePhoto(
      imagePath: photoPath,
      englishFirst: repository.settings.englishFirst,
      descriptionHint: _description.trim().isNotEmpty ? _description : null,
      forceRefresh: forceRefresh,
    );

    if (_disposed || gen != _photoAnalysisGeneration) return;
    _photoAi = result;

    if (result.hasDetectedIssue) {
      final detected = result.detectedCategory!;
      if (!_categoryLockedByUser || forceRefresh) {
        _category = detected;
      }
      if (result.suggestedSeverity != null) {
        _severity = result.suggestedSeverity!.clamp(1, 5);
      }
      if (!_descriptionEditedByUser) {
        final summary = repository.settings.englishFirst
            ? (result.englishSummary ?? result.khmerSummary)
            : (result.khmerSummary ?? result.englishSummary);
        if (summary != null && summary.trim().isNotEmpty) {
          _description = summary.trim();
        }
      }
    }

    notifyListeners();
  }

  /// Updates pin coordinates immediately while panning so duplicate detection
  /// reacts in real time without waiting for reverse-geocoding debounce.
  void updatePinCoordinatesLive(LatLng point) {
    _pinLocation = point;
    _locationVerified = true;
    _usedLiveGps = false;
    _isOutsideCambodia = false;
    _rawOutsideGps = null;
    notifyListeners();
  }

  void setLocating(bool value) {
    if (_isLocating == value) return;
    _isLocating = value;
    notifyListeners();
  }

  void setPinLocation(
    LatLng point, {
    bool verified = true,
    bool fromLiveGps = false,
    double? accuracyMeters,
  }) {
    _pinLocation = point;
    _locationVerified = verified;
    _usedLiveGps = fromLiveGps;
    _gpsAccuracyMeters = accuracyMeters ?? _gpsAccuracyMeters;
    _isOutsideCambodia = false;
    _rawOutsideGps = null;
    _geocodedPlace = null;
    notifyListeners();
  }

  void setOutsideCambodiaDetected(LatLng rawPoint, {double? accuracyMeters}) {
    _isOutsideCambodia = true;
    _rawOutsideGps = rawPoint;
    _gpsAccuracyMeters = accuracyMeters;
    notifyListeners();
  }

  void usePhnomPenhCenter() {
    setPinLocation(
      LocationService.phnomPenhCenter,
      verified: true,
      fromLiveGps: false,
    );
  }

  void setGeocodedPlace(LatLng forPoint, GeocodedPlace? place) {
    if (_pinLocation != forPoint) return;
    _geocodedPlace = place;
    notifyListeners();
  }

  void confirmCurrentPin() {
    _locationVerified = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Telegram-style Hold-to-Speak & Tap-to-Toggle Hybrid Khmer/EN Voice Note
  // (`hackathonshow.md §5`)
  // ---------------------------------------------------------------------------

  Future<void> startHoldVoiceRecording() async {
    if (_isInitializingVoice || _isRecordingVoice || _isTranscribingVoice) {
      return;
    }
    _isHoldRecording = true;
    await _startVoiceSession();
  }

  Future<void> finishHoldVoiceRecording() async {
    if (!_isHoldRecording) return;
    _isHoldRecording = false;
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
    }
  }

  Future<void> cancelHoldVoiceRecording() async {
    if (!_isHoldRecording && !_isRecordingVoice) return;
    _isHoldRecording = false;
    _stopAllVoiceTimers();
    if (_voiceMode == VoiceCaptureMode.backendAudio) {
      await _audioRecorder.cancelAndDelete();
    } else if (_voiceMode == VoiceCaptureMode.deviceSpeech) {
      await _voiceService.cancel();
    }
    if (_disposed) return;
    _isRecordingVoice = false;
    _isInitializingVoice = false;
    _voiceSoundLevel = 0.0;
    notifyListeners();
  }

  Future<void> toggleVoiceRecording() async {
    if (_isInitializingVoice || _isTranscribingVoice) return;
    if (_isRecordingVoice) {
      _isHoldRecording = false;
      await _stopVoiceRecording();
      return;
    }
    _isHoldRecording = false;
    await _startVoiceSession();
  }

  Future<void> _startVoiceSession() async {
    _clearVoiceFeedback();
    _receivedSpeechInSession = false;
    _recordingSeconds = 0;
    _voiceSoundLevel = 0.0;
    _peakMicLevel = 0.0;

    // Tier 1: SrolanhCity backend AI transcription when server is connected.
    if (repository.isOnline && _civicAiService.isBackendConfigured) {
      _isInitializingVoice = true;
      notifyListeners();

      final started = await _audioRecorder.startRecording();
      if (_disposed) return;
      _isInitializingVoice = false;

      if (started) {
        _voiceMode = VoiceCaptureMode.backendAudio;
        _isRecordingVoice = true;
        _startDurationTimer(autoStopAtMax: true);
        _amplitudeTimer?.cancel();
        _amplitudeTimer = Timer.periodic(
          const Duration(milliseconds: 120),
          (_) => unawaited(_pollRecorderAmplitude()),
        );
        notifyListeners();
        return;
      }

      // If hardware recorder couldn't start, fall through to on-device STT.
    }

    // Tier 2: On-device speech_to_text while backend is offline / not deployed.
    await _startDeviceSpeechSession();
  }

  Future<void> _pollRecorderAmplitude() async {
    if (_disposed ||
        !_isRecordingVoice ||
        _voiceMode != VoiceCaptureMode.backendAudio) {
      return;
    }
    final level = await _audioRecorder.getNormalizedAmplitude();
    if (_disposed || !_isRecordingVoice) return;
    if (level > _peakMicLevel) {
      _peakMicLevel = level;
    }
    _voiceSoundLevel = level;
    notifyListeners();
  }

  Future<void> _startDeviceSpeechSession() async {
    _isInitializingVoice = true;
    notifyListeners();

    final available = await _voiceService.initialize(
      onStatus: (status) {
        if (_disposed) return;
        if ((status == 'done' || status == 'notListening') &&
            _isRecordingVoice &&
            _voiceMode == VoiceCaptureMode.deviceSpeech) {
          _scheduleDeviceSpeechFinalize();
        }
      },
      onError: (errorMsg) {
        if (_disposed) return;
        if (_voiceMode != VoiceCaptureMode.deviceSpeech) return;
        if (!_isRecordingVoice && _lateFinalTimer == null) return;
        _stopAllVoiceTimers();
        _isRecordingVoice = false;
        _isHoldRecording = false;
        _voiceSoundLevel = 0.0;
        _setVoiceFeedbackForError(errorMsg);
        notifyListeners();
      },
    );

    if (_disposed) return;
    _isInitializingVoice = false;

    if (!available) {
      _setVoiceFeedback(
        khmer: 'ឧបករណ៍នេះមិនមានសេវាស្តាប់សំឡេងទេ — អ្នកអាចវាយអក្សរ ឬចុច "សាកល្បងសំឡេង"',
        english: 'Device speech recognition is unavailable — type your note or tap "Try Sample".',
        offerDemoFallback: true,
      );
      notifyListeners();
      return;
    }

    try {
      final resolution = await _voiceService.resolveLocale(
        preferEnglish: _voicePreferEnglish,
      );
      if (_disposed) return;

      if (!resolution.exactLanguageAvailable && !_voicePreferEnglish) {
        _setVoiceFeedback(
          khmer: 'ឧបករណ៍នេះមិនមានកញ្ចប់សំឡេងខ្មែរទេ — សូមប្តូរទៅ EN ឬចុច "សាកល្បងសំឡេង"',
          english: 'Khmer speech pack is not installed on this device — switch to EN or tap "Try Sample".',
          offerDemoFallback: true,
        );
      }

      _voiceMode = VoiceCaptureMode.deviceSpeech;
      _isRecordingVoice = true;
      _startDurationTimer(autoStopAtMax: false);
      notifyListeners();

      await _voiceService.startListening(
        localeId: resolution.localeId,
        onResult: (words, isFinal) {
          if (_disposed) return;
          final trimmed = words.trim();
          if (trimmed.isNotEmpty) {
            _receivedSpeechInSession = true;
            _clearVoiceFeedback();
            _voiceTranscript = trimmed;
            _description = trimmed;
            _descriptionEditedByUser = true;
          }
          if (isFinal) {
            _stopAllVoiceTimers();
            _isRecordingVoice = false;
            _isHoldRecording = false;
            _voiceSoundLevel = 0.0;
            if (!_receivedSpeechInSession) {
              _setNoSpeechFeedback();
            }
          }
          notifyListeners();
        },
        onSoundLevel: (level) {
          if (_disposed || !_isRecordingVoice) return;
          if (level > _peakMicLevel) {
            _peakMicLevel = level;
          }
          _voiceSoundLevel = level;
          notifyListeners();
        },
      );
    } catch (_) {
      if (_disposed) return;
      _stopAllVoiceTimers();
      _isRecordingVoice = false;
      _isHoldRecording = false;
      _setVoiceFeedback(
        khmer: 'មិនអាចបើកមីក្រូហ្វូនបានទេ — សូមពិនិត្យសិទ្ធិមីក្រូហ្វូន ឬប្រើសំឡេងសាកល្បង',
        english: 'Could not start microphone — check mic permission or try Sample voice.',
        offerDemoFallback: true,
      );
      notifyListeners();
    }
  }

  void _startDurationTimer({required bool autoStopAtMax}) {
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !_isRecordingVoice) return;
      _recordingSeconds++;
      notifyListeners();
      if (autoStopAtMax && _recordingSeconds >= maxVoiceSeconds) {
        unawaited(_stopVoiceRecording());
      }
    });
  }

  void _scheduleDeviceSpeechFinalize() {
    _lateFinalTimer?.cancel();
    _lateFinalTimer = Timer(const Duration(milliseconds: 550), () {
      if (_disposed) return;
      _stopAllVoiceTimers();
      _isRecordingVoice = false;
      _isHoldRecording = false;
      _voiceSoundLevel = 0.0;
      if (!_receivedSpeechInSession && _voiceFeedbackKhmer == null) {
        _setNoSpeechFeedback();
      }
      notifyListeners();
    });
  }

  Future<void> _stopVoiceRecording() async {
    _voiceTimer?.cancel();
    _voiceTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    if (_voiceMode == VoiceCaptureMode.backendAudio) {
      await _finishBackendAudioRecording();
      return;
    }

    if (_voiceMode == VoiceCaptureMode.deviceSpeech) {
      await _voiceService.stopListening();
      if (_disposed) return;
      // Allow up to 550 ms for Android/iOS SpeechRecognizer's late final result.
      _scheduleDeviceSpeechFinalize();
      notifyListeners();
      return;
    }

    _finishDemoRecording();
  }

  Future<void> _finishBackendAudioRecording() async {
    _isRecordingVoice = false;
    _isHoldRecording = false;
    _voiceSoundLevel = 0.0;

    final audioPath = await _audioRecorder.stopRecording();
    if (_disposed) {
      await _audioRecorder.deleteFile(audioPath);
      return;
    }

    if (audioPath == null) {
      _setNoSpeechFeedback();
      notifyListeners();
      return;
    }

    // Detect silent emulator / muted mic before sending audio to backend.
    if (_peakMicLevel < _silencePeakThreshold) {
      await _audioRecorder.deleteFile(audioPath);
      _setNoSpeechFeedback();
      notifyListeners();
      return;
    }

    _isTranscribingVoice = true;
    notifyListeners();

    try {
      final result = await _civicAiService.transcribeVoiceAudio(
        audioPath: audioPath,
        englishFirst: _voicePreferEnglish,
      );
      if (_disposed) return;

      if (result.success &&
          result.transcript != null &&
          result.transcript!.trim().isNotEmpty) {
        final spoken = result.transcript!.trim();
        _voiceTranscript = spoken;
        _description = spoken;
        _descriptionEditedByUser = true;
        _clearVoiceFeedback();

        if (result.detectedCategory != null &&
            !_categoryLockedByUser &&
            !_photoAi.hasDetectedIssue) {
          _category = result.detectedCategory!;
        }
      } else if (result.isRateLimited) {
        _setVoiceFeedback(
          khmer: 'សេវា AI កំពុងមមាញឹក — សូមរង់ចាំបន្តិច ឬវាយអក្សរផ្ទាល់',
          english: 'AI service is busy — wait a moment or type manually.',
          offerDemoFallback: true,
        );
      } else {
        _setNoSpeechFeedback();
      }
    } finally {
      await _audioRecorder.deleteFile(audioPath);
      if (!_disposed) {
        _isTranscribingVoice = false;
        notifyListeners();
      }
    }
  }

  /// Explicit 1-tap sample voice transcription helper for emulator demos or
  /// when microphone hardware is silent/unavailable.
  void runSampleVoiceDemo() {
    if (_isTranscribingVoice) return;
    _stopAllVoiceTimers();
    _clearVoiceFeedback();
    _voiceMode = VoiceCaptureMode.demoFallback;
    _isRecordingVoice = true;
    _recordingSeconds = 0;
    _voiceSoundLevel = 0.65;
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      _recordingSeconds++;
      notifyListeners();
      if (_recordingSeconds >= 2) {
        _finishDemoRecording();
      }
    });
    notifyListeners();
  }

  void _finishDemoRecording() {
    _stopAllVoiceTimers();
    _isRecordingVoice = false;
    _isHoldRecording = false;
    _voiceSoundLevel = 0.0;

    final transcript = switch ((_category, _voicePreferEnglish)) {
      (IssueCategory.pothole, false) =>
        'មានរណ្តៅផ្លូវជ្រៅ និងដក់ទឹកខ្លាំង សូមជួយជួសជុលបន្ទាន់ផង',
      (IssueCategory.pothole, true) => 'Deep water-filled pothole in the middle of the lane, dangerous for motorbikes.',
      (IssueCategory.streetlight, false) =>
        'ភ្លើងផ្លូវរលត់ងងឹតខ្លាំងពេលយប់ ពិបាកធ្វើដំណើរណាស់',
      (IssueCategory.streetlight, true) =>
        'Streetlights are completely out along this road, very dark at night.',
      (IssueCategory.drain, false) =>
        'លូស្ទះលិចទឹកពេញផ្លូវពេលភ្លៀងធ្លាក់ មានក្លិនស្អុយទៀតផង',
      (IssueCategory.drain, true) =>
        'Clogged drain flooding the road during rain with a strong odor.',
      (IssueCategory.trash, false) =>
        'មានសំរាមចោលគរច្រើនតាមដងផ្លូវ សូមអាជ្ញាធរជួយប្រមូលផង',
      (IssueCategory.trash, true) => 'Large illegal garbage pile dumped beside the sidewalk blocking pedestrians.',
      (IssueCategory.other, false) => 'មានបញ្ហាហេដ្ឋារចនាសម្ព័ន្ធសាធារណៈខូចខាតនៅតាមដងផ្លូវ សូមជួយពិនិត្យ និងជួសជុលផង',
      (IssueCategory.other, true) => 'Damaged street infrastructure along the roadside creating a hazard for passersby.',
    };

    _voiceTranscript = transcript;
    _descriptionEditedByUser = true;
    _description = transcript;
    _clearVoiceFeedback();
    notifyListeners();
  }

  void _setNoSpeechFeedback() {
    _setVoiceFeedback(
      khmer: 'មិនឮសំឡេងក្នុងការថតទេ (មីក្រូហ្វូនស្ងាត់ ឬ Emulator) — និយាយជិតមីក្រូហ្វូន ឬចុច "សាកល្បង"',
      english: 'No speech heard (quiet mic or emulator) — speak closer or tap "Try Sample".',
      offerDemoFallback: true,
    );
  }

  void _setVoiceFeedbackForError(String errorMsg) {
    final lower = errorMsg.toLowerCase();
    if (lower.contains('permission')) {
      _setVoiceFeedback(
        khmer: 'ត្រូវការសិទ្ធិមីក្រូហ្វូនដើម្បីរាយការណ៍ជាសំឡេង',
        english: 'Microphone permission is required for voice notes.',
        offerDemoFallback: true,
      );
    } else if (lower.contains('network')) {
      _setVoiceFeedback(
        khmer: 'សេវាស្តាប់សំឡេងត្រូវការអ៊ីនធឺណិត — អ្នកអាចវាយអក្សរ ឬសាកល្បងបាន',
        english:
            'Speech recognition needs internet — type your note or try Sample.',
        offerDemoFallback: true,
      );
    } else if (lower.contains('language')) {
      _setVoiceFeedback(
        khmer: 'ឧបករណ៍នេះមិនគាំទ្រភាសាខ្មែរសម្រាប់សំឡេងទេ — សូមប្តូរទៅ EN ឬចុច "សាកល្បងសំឡេង"',
        english: 'Selected speech language is unavailable on this device — switch to EN or tap "Try Sample".',
        offerDemoFallback: true,
      );
    } else {
      _setNoSpeechFeedback();
    }
  }

  void _setVoiceFeedback({
    required String khmer,
    required String english,
    bool offerDemoFallback = false,
  }) {
    _voiceFeedbackKhmer = khmer;
    _voiceFeedbackEnglish = english;
    _showVoiceDemoFallbackAction = offerDemoFallback;
  }

  void _clearVoiceFeedback() {
    _voiceFeedbackKhmer = null;
    _voiceFeedbackEnglish = null;
    _showVoiceDemoFallbackAction = false;
  }

  void _stopAllVoiceTimers() {
    _voiceTimer?.cancel();
    _voiceTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _lateFinalTimer?.cancel();
    _lateFinalTimer = null;
  }

  void clearVoiceTranscript() {
    _voiceTranscript = null;
    _clearVoiceFeedback();
    notifyListeners();
  }

  ReportSubmissionResult submit({
    bool forceCreateNew = false,
    String? customTitle,
  }) {
    return repository.submitReport(
      category: _category,
      description: _description.trim(),
      severity: _severity,
      coordinates: _pinLocation,
      isAnonymous: _isAnonymous,
      customTitle: customTitle,
      localPhotoPath: localPhotoPath,
      additionalLocalPhotoPaths: additionalLocalPhotoPaths,
      voiceTranscript: _voiceTranscript,
      geocodedPlace: _geocodedPlace,
      forceCreateNew: forceCreateNew,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _stopAllVoiceTimers();
    unawaited(_voiceService.cancel());
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }
}
