import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../../data/repositories/report_repository.dart';
import '../../../../data/services/audio_recorder_service.dart';
import '../../../../data/services/civic_ai_service.dart';
import '../../../../data/services/exif_stripper.dart';
import '../../../../data/services/ip_geolocation_service.dart';
import '../../../../data/services/location_service.dart';
import '../../../../data/services/reverse_geocoding_service.dart';
import '../../../../data/services/voice_input_service.dart';
import '../../../../domain/models/cambodia_locations.dart';
import '../../../../domain/models/report_models.dart';
import '../../../../domain/models/routing_result.dart';
import '../../../../domain/services/ai_classifier_service.dart';
import '../../../../domain/services/anti_spoof_service.dart';
import '../../../../domain/services/gis_routing_service.dart';
import '../../../../domain/services/priority_calculator.dart';
import '../../../../domain/services/report_location_eligibility_service.dart';
import '../../../../domain/services/spatial_clustering_service.dart';

/// Manages state and business interactions for the 3-step Report Wizard:
/// 1. Mandatory `>= 1` real photo + auto-saved photo GPS anchor draft.
/// 2. Details, severity, quick tags, and transcript-only Khmer/EN voice input.
/// 3. Strict universal 150 m zone + multi-incident picker + return navigation.
class ReportWizardViewModel extends ChangeNotifier {
  ReportWizardViewModel({
    required this.repository,
    IssueCategory initialCategory = IssueCategory.pothole,
    LatLng? initialCoordinates,
    ReportDraft? initialDraft,
    List<String> initialPhotoPaths = const [],
    VoiceInputService? voiceInputService,
    AudioRecorderService? audioRecorderService,
    CivicAiService? civicAiService,
    IpGeolocationService? ipGeolocationService,
  }) : _voiceService = voiceInputService ?? SpeechToTextVoiceInputService(),
       _audioRecorder = audioRecorderService ?? RecordAudioRecorderService(),
       _civicAiService = civicAiService ?? BackendCivicAiService(),
       _ipGeoService =
           ipGeolocationService ?? HttpIpGeolocationService.instance,
       _step = (initialDraft != null && initialDraft.localPhotoPaths.isNotEmpty)
           ? 1
           : 0,
       _category = initialDraft?.category ?? initialCategory,
       _severity = initialDraft?.severity ?? 3,
       _isAnonymous =
           initialDraft?.isAnonymous ?? repository.settings.anonymousByDefault,
       _description = initialDraft?.description ?? '',
       _descriptionEditedByUser =
           initialDraft != null && initialDraft.description.trim().isNotEmpty,
       _localPhotoPaths = List<String>.of(
         initialDraft != null
             ? initialDraft.localPhotoPaths
             : initialPhotoPaths.where((p) => p.isNotEmpty).take(maxPhotos),
       ),
       _photoExifEntries = List<PhotoExifMetadata?>.filled(
         initialDraft != null
             ? initialDraft.localPhotoPaths.length
             : initialPhotoPaths
                   .where((p) => p.isNotEmpty)
                   .take(maxPhotos)
                   .length,
         null,
         growable: true,
       ),
       _photoAnchors = List<PhotoLocationAnchor?>.filled(
         initialDraft != null
             ? initialDraft.localPhotoPaths.length
             : initialPhotoPaths
                   .where((p) => p.isNotEmpty)
                   .take(maxPhotos)
                   .length,
         null,
         growable: true,
       ),
       _hasExplicitInitialCoordinates = initialCoordinates != null,
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
       _locationVerified = initialCoordinates != null {
    if (initialDraft != null && initialDraft.hasPhotoAnchor) {
      final point = LatLng(
        initialDraft.photoAnchorLat!,
        initialDraft.photoAnchorLng!,
      );
      if (LocationService.isInsideCambodia(point)) {
        final source =
            initialDraft.photoAnchorSource ==
                PhotoAnchorSource.liveCameraCapture.name
            ? PhotoAnchorSource.liveCameraCapture
            : PhotoAnchorSource.photoExif;
        final restoredAnchor = PhotoLocationAnchor(
          point: point,
          source: source,
          capturedAt: initialDraft.photoAnchorCapturedAt,
        );
        if (_photoAnchors.isNotEmpty) {
          _photoAnchors[0] = restoredAnchor;
        } else {
          _explicitPhotoAnchor = restoredAnchor;
        }
        if (!_hasExplicitInitialCoordinates) {
          _pinLocation = point;
          _locationVerified = true;
        }
      }
    }
  }

  static const int maxPhotos = 3;
  static const int maxVoiceSeconds = 30;
  static const double _silencePeakThreshold = 0.04;

  final ReportRepository repository;
  final VoiceInputService _voiceService;
  final AudioRecorderService _audioRecorder;
  final CivicAiService _civicAiService;
  final IpGeolocationService _ipGeoService;

  int _step;
  IssueCategory _category;
  bool _categoryLockedByUser = false;
  int _severity; // 2=Minor, 3=Moderate, 5=Dangerous (1–5 scale)
  bool _isAnonymous;
  String _description;
  bool _descriptionEditedByUser;
  final List<String> _localPhotoPaths;
  final List<PhotoExifMetadata?> _photoExifEntries;
  final List<PhotoLocationAnchor?> _photoAnchors;
  final bool _hasExplicitInitialCoordinates;
  PhotoExifMetadata? _explicitPhotoExif;
  PhotoLocationAnchor? _explicitPhotoAnchor;
  bool _isCapturingCameraAnchor = false;
  bool _autoSavedPhotoAnchorDraft = false;
  PhotoAiAnalysis _photoAi = PhotoAiAnalysis.noPhoto;
  int _photoAnalysisGeneration = 0;

  LatLng _pinLocation;
  GeocodedPlace? _geocodedPlace;
  double? _gpsAccuracyMeters;
  bool _locationVerified;
  bool _usedLiveGps = false;
  LocationFetchResult? _liveGpsResult;
  bool _userManuallyMovedPin = false;
  bool _isOutsideCambodia = false;
  LatLng? _rawOutsideGps;
  bool _isLocating = false;
  String? _ipCountryCode;
  bool _checkedIpGeo = false;

  String? _selectedMasterReportId;
  bool _preferCreateNewReport = false;

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

  /// Every new report requires at least 1 real photo (Camera or Gallery).
  bool get hasRequiredPhoto => _localPhotoPaths.isNotEmpty;
  bool get isCapturingCameraAnchor => _isCapturingCameraAnchor;
  bool get autoSavedPhotoAnchorDraft => _autoSavedPhotoAnchorDraft;

  /// Best available pre-strip EXIF metadata across attached photos (or an
  /// explicitly supplied initial EXIF payload).
  PhotoExifMetadata? get photoExifMetadata {
    for (final entry in _photoExifEntries) {
      if (entry != null && entry.coordinates != null) return entry;
    }
    for (final entry in _photoExifEntries) {
      if (entry != null && !entry.isEmpty) return entry;
    }
    return _explicitPhotoExif;
  }

  /// Authoritative photo capture anchor (in-Cambodia EXIF GPS or live in-app
  /// camera shutter GPS). Prefers fresh in-Cambodia EXIF, then live camera GPS,
  /// then any remaining in-Cambodia EXIF (for stale-EXIF diagnostics).
  PhotoLocationAnchor? get activePhotoAnchor {
    for (final anchor in _photoAnchors) {
      if (anchor != null &&
          anchor.source == PhotoAnchorSource.photoExif &&
          anchor.isFresh() &&
          LocationService.isInsideCambodia(anchor.point)) {
        return anchor;
      }
    }
    for (final anchor in _photoAnchors) {
      if (anchor != null &&
          anchor.source == PhotoAnchorSource.liveCameraCapture &&
          LocationService.isInsideCambodia(anchor.point)) {
        return anchor;
      }
    }
    if (_explicitPhotoAnchor != null &&
        LocationService.isInsideCambodia(_explicitPhotoAnchor!.point)) {
      return _explicitPhotoAnchor;
    }
    for (final anchor in _photoAnchors) {
      if (anchor != null && LocationService.isInsideCambodia(anchor.point)) {
        return anchor;
      }
    }
    final exif = photoExifMetadata;
    if (exif?.coordinates != null &&
        LocationService.isInsideCambodia(exif!.coordinates!)) {
      return PhotoLocationAnchor(
        point: exif.coordinates!,
        source: PhotoAnchorSource.photoExif,
        capturedAt: exif.capturedAt,
      );
    }
    return null;
  }

  /// Returns the photo anchor ONLY when fresh (`<= 30 days` EXIF or live
  /// in-app camera capture), ready to lock the 150 m zone from anywhere.
  PhotoLocationAnchor? get activeFreshPhotoAnchor {
    final anchor = activePhotoAnchor;
    if (anchor == null || !anchor.isFresh()) return null;
    return anchor;
  }

  /// True when attached photo(s) carry in-Cambodia EXIF GPS older than 30 days
  /// (and no live camera anchor overrides it), requiring live GPS on Step 3.
  bool get hasStalePhotoExif {
    final anchor = activePhotoAnchor;
    return anchor != null &&
        anchor.source == PhotoAnchorSource.photoExif &&
        !anchor.isFresh();
  }

  PhotoAiAnalysis get photoAi => _photoAi;
  bool get isBackendAiAvailable => _civicAiService.isBackendConfigured;

  LatLng get pinLocation => _pinLocation;
  GeocodedPlace? get geocodedPlace => _geocodedPlace;
  double? get gpsAccuracyMeters => _gpsAccuracyMeters;
  bool get locationVerified => _locationVerified;
  bool get usedLiveGps => _usedLiveGps;
  LocationFetchResult? get liveGpsResult => _liveGpsResult;
  bool get userManuallyMovedPin => _userManuallyMovedPin;
  bool get isOutsideCambodia => _isOutsideCambodia;
  LatLng? get rawOutsideGps => _rawOutsideGps;
  bool get isLocating => _isLocating;
  String? get ipCountryCode => _ipCountryCode;

  /// Verified live Cambodia GPS fix (if acquired in this session or fresh
  /// repository checkpoint <= 15 minutes old).
  LatLng? get liveGpsPoint {
    final live = _liveGpsResult;
    if (live is LocationSuccess && !live.isOutsideCambodia) {
      return live.point;
    }
    final cp = repository.lastVerifiedGpsCheckpoint;
    if (live == null && cp != null) {
      final age = DateTime.now().difference(cp.timestamp);
      if (!age.isNegative &&
          age <= ReportLocationEligibilityService.freshCheckpointWindow &&
          LocationService.isInsideCambodia(cp.point)) {
        return cp.point;
      }
    }
    return null;
  }

  /// Pure strict universal 150 m zone eligibility evaluation (zero 15 km
  /// commuter or Home District bypasses).
  ReportLocationEligibilityResult get locationEligibility =>
      ReportLocationEligibilityService.evaluate(
        pinnedLocation: _pinLocation,
        liveGpsResult: _liveGpsResult,
        photoExif: photoExifMetadata,
        photoAnchor: activePhotoAnchor,
        lastVerifiedCheckpoint: repository.lastVerifiedGpsCheckpoint,
      );

  /// Active center & source of the universal 150 m reporting zone (Fresh Photo
  /// EXIF -> Live Camera GPS -> Live Device GPS), or null until verified.
  ({LatLng point, ZoneAnchorSource source})? get activeZoneAnchor {
    return switch (locationEligibility) {
      ReportLocationEligible(:final anchorPoint, :final anchorSource) => (
        point: anchorPoint,
        source: anchorSource,
      ),
      ReportLocationDeniedOutOfZone(:final anchorPoint, :final anchorSource) =>
        (point: anchorPoint, source: anchorSource),
      _ => null,
    };
  }

  /// True when the citizen dragged the Step 3 pin beyond 150 m from the zone center.
  bool get isOutside150mZone =>
      locationEligibility is ReportLocationDeniedOutOfZone;

  /// Distance in meters from the 150 m zone center when dragged out of range.
  double? get distanceOutsideZoneMeters => switch (locationEligibility) {
    ReportLocationDeniedOutOfZone(:final distanceMeters) => distanceMeters,
    _ => null,
  };

  /// Whether the citizen is currently permitted to submit at [pinLocation].
  bool get canSubmitAtCurrentPin =>
      hasRequiredPhoto && locationEligibility.isAllowed;

  /// Layer 4 pre-strip photo EXIF assessment against the current pin.
  SpoofAssessment get photoExifAssessment => AntiSpoofService.evaluatePhotoExif(
    exif: photoExifMetadata,
    pinnedLocation: _pinLocation,
  );

  /// Layer 5 non-blocking IP country check against Cambodia.
  SpoofAssessment get ipIntegrityAssessment =>
      AntiSpoofService.evaluateIpGeo(ipCountryCode: _ipCountryCode);

  /// Combined Step 3 integrity assessment (EXIF + IP).
  SpoofAssessment get combinedIntegrityAssessment => AntiSpoofService.combine(
    <SpoofAssessment>[photoExifAssessment, ipIntegrityAssessment],
  );

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
  );

  GisRoutingResult get gisRouting => GisRoutingService.resolve(
    coordinates: _pinLocation,
    category: _category,
    geocodedPlace: _geocodedPlace,
  );

  /// ALL open same-category Master Incidents within 150 m of the current pin
  /// or verified photo anchor, sorted nearest-first.
  List<DuplicateMatch> get nearbySimilarReports =>
      repository.findSimilarReportsNearby(
        point: _pinLocation,
        category: _category,
        photoAnchorPoint: activeFreshPhotoAnchor?.point,
      );

  /// Nearest open same-category Master Incident within 150 m (if any).
  DuplicateMatch? get nearbyDuplicate {
    final matches = nearbySimilarReports;
    return matches.isEmpty ? null : matches.first;
  }

  /// Nearest open same-category report already created/joined by the citizen
  /// within `<= 50 m` of the current dragged pin, or `null` if clear.
  DuplicateMatch? get hardSelfBlockedMatch {
    for (final m in nearbySimilarReports) {
      if (m.masterReport.isContributedByCurrentUser &&
          m.distanceMeters <=
              SpatialClusteringService.hardSelfBlockRadiusMeters) {
        return m;
      }
    }
    return null;
  }

  /// True when the citizen already created/joined an open same-category report
  /// within `<= 50 m` of the current pin (blocks self-duplicate new reports).
  bool get isHardSelfBlockedAtPin => hardSelfBlockedMatch != null;

  /// Currently selected Master Incident in Step 3's 150 m picker, or `null`
  /// when no matches exist or the citizen is filing a new separate report.
  DuplicateMatch? get selectedMasterMatch {
    final matches = nearbySimilarReports;
    if (matches.isEmpty) return null;

    final selfBlock = hardSelfBlockedMatch;
    if (selfBlock != null) {
      if (_selectedMasterReportId != null) {
        for (final match in matches) {
          if (match.masterReport.id == _selectedMasterReportId &&
              !match.masterReport.isContributedByCurrentUser) {
            return match;
          }
        }
      }
      return selfBlock;
    }

    if (_preferCreateNewReport) return null;

    if (_selectedMasterReportId != null) {
      for (final match in matches) {
        if (match.masterReport.id == _selectedMasterReportId) {
          return match;
        }
      }
    }

    // Default to the nearest joinable neighbor incident.
    for (final match in matches) {
      if (!match.masterReport.isContributedByCurrentUser) {
        return match;
      }
    }

    // All nearby matches within 150 m are already owned/joined by the citizen
    // and > 50 m away from the dragged pin -> default to creating a new
    // separate report here while keeping existing tickets selectable.
    return null;
  }

  /// True when similar reports exist within 150 m and the citizen is filing a
  /// new separate report (explicitly chosen, or defaulted when all nearby
  /// reports are already theirs and > 50 m from the dragged pin).
  bool get isCreatingNewDespiteMatches =>
      nearbySimilarReports.isNotEmpty &&
      !isHardSelfBlockedAtPin &&
      selectedMasterMatch == null;

  void selectMasterReport(String reportId) {
    if (_selectedMasterReportId == reportId && !_preferCreateNewReport) return;
    _selectedMasterReportId = reportId;
    _preferCreateNewReport = false;
    notifyListeners();
  }

  void selectCreateNewReport() {
    if (isHardSelfBlockedAtPin) return;
    if (_preferCreateNewReport && _selectedMasterReportId == null) return;
    _preferCreateNewReport = true;
    _selectedMasterReportId = null;
    notifyListeners();
  }

  PriorityBreakdown get estimatedPriority {
    final selected = selectedMasterMatch;
    if (selected != null) {
      final existing = selected.masterReport;
      return PriorityCalculator.calculate(
        trafficScore: existing.roadClass.trafficScore,
        severityScore: _severity > existing.severity
            ? _severity
            : existing.severity,
        reportCount: existing.isContributedByCurrentUser
            ? existing.affectedCitizens
            : existing.affectedCitizens + 1,
      );
    }
    return PriorityCalculator.calculate(
      trafficScore: gisRouting.roadClass.trafficScore,
      severityScore: _severity,
      reportCount: 1,
    );
  }

  ReportDraft toDraft() {
    final anchor = activePhotoAnchor;
    return ReportDraft(
      category: _category,
      severity: _severity,
      description: _description,
      isAnonymous: _isAnonymous,
      localPhotoPaths: List<String>.of(_localPhotoPaths),
      voiceTranscript: _voiceTranscript,
      photoAnchorLat: anchor?.point.latitude,
      photoAnchorLng: anchor?.point.longitude,
      photoAnchorSource: anchor?.source.name,
      photoAnchorCapturedAt: anchor?.capturedAt,
    );
  }

  void saveDraft() => repository.saveDraft(toDraft());

  void _maybeAutoSavePhotoAnchorDraft() {
    if (_localPhotoPaths.isEmpty || activeFreshPhotoAnchor == null) return;
    repository.saveDraft(toDraft());
    _autoSavedPhotoAnchorDraft = true;
  }

  void setCapturingCameraAnchor(bool value) {
    if (_isCapturingCameraAnchor == value) return;
    _isCapturingCameraAnchor = value;
    notifyListeners();
  }

  void nextStep() {
    if (!hasRequiredPhoto) return;
    if (_step < 2) {
      _step++;
      notifyListeners();
      if (_step == 2) {
        unawaited(refreshIpIntegrityCheck());
      }
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
    _selectedMasterReportId = null;
    _preferCreateNewReport = false;
    notifyListeners();
  }

  void applyAiSuggestedCategory() {
    final suggested = _photoAi.hasDetectedIssue
        ? _photoAi.detectedCategory!
        : classification.category;
    if (suggested == _category) return;
    _category = suggested;
    _selectedMasterReportId = null;
    _preferCreateNewReport = false;
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

  void setVoicePreferEnglish(bool preferEnglish) {
    if (_isRecordingVoice || _isTranscribingVoice) return;
    if (_voicePreferEnglish == preferEnglish) return;
    _voicePreferEnglish = preferEnglish;
    _clearVoiceFeedback();
    notifyListeners();
  }

  void toggleVoiceLanguage() => setVoicePreferEnglish(!_voicePreferEnglish);

  /// Auto-snaps Step 3's initial pin straight onto a newly attached photo's
  /// anchor when the wizard was opened via `+` (not a specific map tap) and
  /// the user hasn't manually dragged the pin yet.
  void _maybeAutoSnapToAnchor(PhotoLocationAnchor? anchor) {
    if (anchor == null ||
        !anchor.isFresh() ||
        !LocationService.isInsideCambodia(anchor.point)) {
      return;
    }
    if (_hasExplicitInitialCoordinates || _userManuallyMovedPin || _step >= 2) {
      return;
    }
    _pinLocation = anchor.point;
    _locationVerified = true;
    _geocodedPlace = null;
  }

  static PhotoLocationAnchor? _anchorFromExif(PhotoExifMetadata? exif) {
    final coords = exif?.coordinates;
    if (coords == null || !LocationService.isInsideCambodia(coords)) {
      return null;
    }
    return PhotoLocationAnchor(
      point: coords,
      source: PhotoAnchorSource.photoExif,
      capturedAt: exif!.capturedAt,
    );
  }

  /// Records pre-strip EXIF metadata extracted in memory from a citizen photo.
  void setPhotoExifMetadata(PhotoExifMetadata? exif) {
    if (exif == null || exif.isEmpty) return;
    _explicitPhotoExif = exif;
    _maybeAutoSnapToAnchor(_anchorFromExif(exif));
    notifyListeners();
  }

  /// Records an explicit photo capture anchor (e.g. live camera capture GPS).
  void setPhotoLocationAnchor(PhotoLocationAnchor? anchor) {
    if (anchor == null || !LocationService.isInsideCambodia(anchor.point)) {
      return;
    }
    _explicitPhotoAnchor = anchor;
    _maybeAutoSnapToAnchor(anchor);
    notifyListeners();
  }

  /// Attaches an asynchronously acquired live camera GPS anchor to the photo
  /// added at [index] (when the browser/camera stripped EXIF metadata) and
  /// auto-saves the draft so the citizen can finish Steps 2–3 later from home.
  void attachLiveCameraAnchorToPhotoAt(int index, PhotoLocationAnchor anchor) {
    if (index < 0 || index >= _photoAnchors.length) return;
    if (!LocationService.isInsideCambodia(anchor.point)) return;
    // Never overwrite a valid fresh photo EXIF anchor with a looser live GPS fix.
    final existing = _photoAnchors[index];
    if (existing?.source == PhotoAnchorSource.photoExif &&
        existing!.isFresh()) {
      return;
    }
    _photoAnchors[index] = anchor;
    _maybeAutoSnapToAnchor(anchor);
    _maybeAutoSavePhotoAnchorDraft();
    notifyListeners();
  }

  /// Snaps the Step 3 map pin straight back to the center of the active 150 m
  /// zone (Photo EXIF GPS, Live Camera GPS, or Live Device GPS).
  LatLng? returnTo150mZone() {
    final zone = activeZoneAnchor;
    if (zone == null) return null;
    _pinLocation = zone.point;
    _locationVerified = true;
    _usedLiveGps = zone.source == ZoneAnchorSource.liveDeviceGps;
    _userManuallyMovedPin = false;
    _geocodedPlace = null;
    notifyListeners();
    return zone.point;
  }

  /// Backward-compatible alias for snapping to the active photo/zone anchor.
  LatLng? snapToPhotoAnchor() => returnTo150mZone();

  /// Runs non-blocking Layer 5 IP-country check when online (fails open).
  Future<void> refreshIpIntegrityCheck({bool force = false}) async {
    if (!repository.isOnline) return;
    if (_checkedIpGeo && !force) return;
    _checkedIpGeo = true;
    final info = await _ipGeoService.lookupCurrentIp();
    if (_disposed) return;
    if (info != null && info.countryCode.isNotEmpty) {
      _ipCountryCode = info.countryCode;
      notifyListeners();
    }
  }

  bool addLocalPhotoPath(
    String path, {
    PhotoExifMetadata? exifMetadata,
    PhotoLocationAnchor? photoAnchor,
  }) {
    if (path.isEmpty) return false;
    if (_localPhotoPaths.length >= maxPhotos) return false;
    final cleanExif = (exifMetadata != null && !exifMetadata.isEmpty)
        ? exifMetadata
        : null;
    final resolvedAnchor = photoAnchor ?? _anchorFromExif(cleanExif);
    _localPhotoPaths.add(path);
    _photoExifEntries.add(cleanExif);
    _photoAnchors.add(resolvedAnchor);
    _maybeAutoSnapToAnchor(resolvedAnchor);
    _maybeAutoSavePhotoAnchorDraft();
    notifyListeners();
    unawaited(analyzeLatestPhoto());
    return true;
  }

  int addLocalPhotoPaths(
    Iterable<String> paths, {
    PhotoExifMetadata? exifMetadata,
    List<PhotoExifMetadata?>? perPhotoExif,
  }) {
    var added = 0;
    var idx = 0;
    PhotoLocationAnchor? firstFreshAnchor;
    for (final path in paths) {
      final rawExif = (perPhotoExif != null && idx < perPhotoExif.length)
          ? perPhotoExif[idx]
          : (added == 0 ? exifMetadata : null);
      idx++;
      if (path.isEmpty) continue;
      if (_localPhotoPaths.length >= maxPhotos) break;
      final cleanExif = (rawExif != null && !rawExif.isEmpty) ? rawExif : null;
      final anchor = _anchorFromExif(cleanExif);
      if (anchor != null && anchor.isFresh()) {
        firstFreshAnchor ??= anchor;
      }
      _localPhotoPaths.add(path);
      _photoExifEntries.add(cleanExif);
      _photoAnchors.add(anchor);
      added++;
    }
    if (added > 0) {
      _maybeAutoSnapToAnchor(firstFreshAnchor);
      _maybeAutoSavePhotoAnchorDraft();
      notifyListeners();
      unawaited(analyzeLatestPhoto());
    }
    return added;
  }

  void removeLocalPhotoAt(int index) {
    if (index < 0 || index >= _localPhotoPaths.length) return;
    _localPhotoPaths.removeAt(index);
    if (index < _photoExifEntries.length) {
      _photoExifEntries.removeAt(index);
    }
    if (index < _photoAnchors.length) {
      _photoAnchors.removeAt(index);
    }
    if (_localPhotoPaths.isEmpty) {
      _explicitPhotoExif = null;
      _explicitPhotoAnchor = null;
      _autoSavedPhotoAnchorDraft = false;
      _photoAnalysisGeneration++;
      _photoAi = PhotoAiAnalysis.noPhoto;
    } else {
      unawaited(analyzeLatestPhoto());
    }
    notifyListeners();
  }

  /// Runs backend AI classification (`hackathonshow.md §4 Step 1`) on the
  /// latest user-attached photo combined with any Khmer/English description.
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

  /// Updates pin coordinates immediately while panning so 150 m zone &
  /// candidate detection react live without erasing live GPS.
  void updatePinCoordinatesLive(LatLng point) {
    _pinLocation = point;
    _locationVerified = true;
    _usedLiveGps = false;
    _userManuallyMovedPin = true;
    notifyListeners();
  }

  void setLocating(bool value) {
    if (_isLocating == value) return;
    _isLocating = value;
    notifyListeners();
  }

  /// Records the device's actual GPS result separately from the draggable pin
  /// so the strict 150 m zone remains accurate even while panning.
  void recordLiveGpsResult(
    LocationFetchResult result, {
    bool movePinToGps = false,
  }) {
    _liveGpsResult = result;
    if (result is LocationSuccess) {
      _gpsAccuracyMeters = result.accuracyMeters;
      if (result.isOutsideCambodia) {
        _isOutsideCambodia = true;
        _rawOutsideGps = result.point;
      } else {
        _isOutsideCambodia = false;
        _rawOutsideGps = null;
        if (movePinToGps) {
          _pinLocation = result.point;
          _locationVerified = true;
          _usedLiveGps = true;
          _geocodedPlace = null;
        }
      }
    } else {
      _isOutsideCambodia = false;
      _rawOutsideGps = null;
    }
    notifyListeners();
  }

  /// Snaps the draggable pin back onto the device's verified live GPS fix.
  LatLng? jumpToLiveGps() {
    final target = liveGpsPoint;
    if (target == null) return null;
    _pinLocation = target;
    _locationVerified = true;
    _usedLiveGps = true;
    _userManuallyMovedPin = false;
    _geocodedPlace = null;
    notifyListeners();
    return target;
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
    if (!fromLiveGps) {
      _userManuallyMovedPin = true;
    }
    _gpsAccuracyMeters = accuracyMeters ?? _gpsAccuracyMeters;
    if (fromLiveGps) {
      _isOutsideCambodia = false;
      _rawOutsideGps = null;
    }
    _geocodedPlace = null;
    notifyListeners();
  }

  void setOutsideCambodiaDetected(LatLng rawPoint, {double? accuracyMeters}) {
    _liveGpsResult = LocationSuccess(
      point: rawPoint,
      accuracyMeters: accuracyMeters ?? 0,
      isOutsideCambodia: true,
    );
    _isOutsideCambodia = true;
    _rawOutsideGps = rawPoint;
    _gpsAccuracyMeters = accuracyMeters;
    notifyListeners();
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
  // Transcript-Only Khmer / English Voice Input (`hackathonshow.md §5`)
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

  /// Finalizes any active speech session before leaving Step 2.
  Future<void> stopVoiceRecordingIfActive() async {
    if (!_isRecordingVoice) return;
    _isHoldRecording = false;
    await _stopVoiceRecording();
  }

  Future<void> _startVoiceSession() async {
    _clearVoiceFeedback();
    _receivedSpeechInSession = false;
    _recordingSeconds = 0;
    _voiceSoundLevel = 0.0;
    _peakMicLevel = 0.0;

    // Offline: voice-to-text requires internet — show honest guidance instead
    // of saving audio files.
    if (!repository.isOnline) {
      _setVoiceFeedback(
        khmer: 'គ្មានអ៊ីនធឺណិត — ការបំប្លែងសំឡេងជាអក្សរត្រូវការអ៊ីនធឺណិត · សូមវាយអក្សរ ឬជ្រើសស្លាករហ័ស',
        english: 'Offline — voice-to-text requires internet. Type your note or tap quick tags.',
        offerDemoFallback: true,
      );
      notifyListeners();
      return;
    }

    // Tier 1: SrolanhCity backend AI transcription when server is connected
    // (ephemeral audio clip is deleted immediately after transcribing).
    if (_civicAiService.isBackendConfigured) {
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
    }

    // Tier 2: On-device / Web Speech API live transcription.
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
        khmer: 'ឧបករណ៍នេះមិនមានសេវាបំប្លែងសំឡេងជាអក្សរទេ — សូមវាយអក្សរ ជ្រើសស្លាករហ័ស ឬចុច "សាកល្បងសំឡេង"',
        english: 'Live speech-to-text is unavailable here — type your note, tap quick tags, or tap "Try Sample".',
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
          khmer: 'ឧបករណ៍នេះមិនមានកញ្ចប់សំឡេងខ្មែរទេ — សូមប្តូរទៅ EN វាយអក្សរ ឬចុច "សាកល្បងសំឡេង"',
          english: 'Khmer speech pack is not installed on this device — switch to EN, type manually, or tap "Try Sample".',
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
    if (!repository.isOnline) {
      _setVoiceFeedback(
        khmer: 'គ្មានអ៊ីនធឺណិត — ការបំប្លែងសំឡេងជាអក្សរត្រូវការអ៊ីនធឺណិត · សូមវាយអក្សរ ឬជ្រើសស្លាករហ័ស',
        english: 'Offline — voice-to-text requires internet. Type your note or tap quick tags.',
        offerDemoFallback: true,
      );
      return;
    }
    if (lower.contains('permission') || lower.contains('not-allowed')) {
      _setVoiceFeedback(
        khmer: 'ត្រូវការសិទ្ធិមីក្រូហ្វូនដើម្បីរាយការណ៍ជាសំឡេង',
        english: 'Microphone permission is required for voice notes.',
        offerDemoFallback: true,
      );
    } else if (lower.contains('service-not-allowed') ||
        lower.contains('network')) {
      _setVoiceFeedback(
        khmer: 'កម្មវិធីរុករក (ដូចជា Brave) ឬបណ្តាញបានបិទសេវាបំប្លែងសំឡេង — សូមវាយអក្សរ ឬជ្រើសស្លាករហ័ស',
        english: 'Browser/network blocked speech-to-text (e.g., Brave Shields) — type your note or tap quick tags.',
        offerDemoFallback: true,
      );
    } else if (lower.contains('language')) {
      _setVoiceFeedback(
        khmer: 'ឧបករណ៍នេះមិនគាំទ្រភាសាខ្មែរសម្រាប់សំឡេងទេ — សូមប្តូរទៅ EN ឬវាយអក្សរផ្ទាល់',
        english: 'Selected speech language is unavailable on this device — switch to EN or type manually.',
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
    final eligibility = locationEligibility;
    final verificationTier = eligibility is ReportLocationEligible
        ? eligibility.tier
        : null;
    final createNew = forceCreateNew || isCreatingNewDespiteMatches;
    final targetMasterId = createNew
        ? null
        : selectedMasterMatch?.masterReport.id;

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
      photoAnchorCoordinates: activeFreshPhotoAnchor?.point,
      locationVerificationTier: verificationTier,
      targetMasterReportId: targetMasterId,
      forceCreateNew: createNew,
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
