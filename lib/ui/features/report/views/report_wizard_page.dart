import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/services/audio_recorder_service.dart';
import '../../../../data/services/civic_ai_service.dart';
import '../../../../data/services/exif_stripper.dart';
import '../../../../data/services/ip_geolocation_service.dart';
import '../../../../data/services/location_service.dart';
import '../../../../data/services/photo_picker_service.dart';
import '../../../../data/services/reverse_geocoding_service.dart';
import '../../../../data/services/voice_input_service.dart';
import '../../../../domain/models/report_models.dart';
import '../../../../domain/models/routing_result.dart';
import '../../../../domain/services/anti_spoof_service.dart';
import '../../../../domain/services/report_location_eligibility_service.dart';
import '../../../../domain/services/support_eligibility_service.dart';
import '../../../core/assistant/assistant_bubble_suppressor.dart';
import '../../../core/l10n.dart';
import '../../../core/map_tile_config.dart';
import '../../../core/report_scope.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/bilingual_text.dart';
import '../../../core/widgets/photo_lightbox_page.dart';
import '../../../core/widgets/priority_badge.dart';
import '../../../core/widgets/report_photo.dart';
import '../../../core/widgets/voice_waveform.dart';
import '../../tracking/tracking_page.dart';
import '../view_models/report_wizard_view_model.dart';
import 'fake_gps_page.dart';
import 'report_submitted_page.dart';

class ReportWizardPage extends StatefulWidget {
  const ReportWizardPage({
    super.key,
    this.initialCategory = IssueCategory.pothole,
    this.initialCoordinates,
    this.initialDraft,
    this.initialPhotoPaths = const [],
    this.initialPhotoExif,
    this.initialPhotoAnchor,
    this.locationService = const LocationService(),
    this.geocodingService,
    this.voiceInputService,
    this.audioRecorderService,
    this.civicAiService,
    this.ipGeolocationService,
  });

  final IssueCategory initialCategory;
  final LatLng? initialCoordinates;
  final ReportDraft? initialDraft;
  final List<String> initialPhotoPaths;
  final PhotoExifMetadata? initialPhotoExif;
  final PhotoLocationAnchor? initialPhotoAnchor;
  final LocationService locationService;
  final ReverseGeocodingService? geocodingService;
  final VoiceInputService? voiceInputService;
  final AudioRecorderService? audioRecorderService;
  final CivicAiService? civicAiService;
  final IpGeolocationService? ipGeolocationService;

  @override
  State<ReportWizardPage> createState() => _ReportWizardPageState();
}

class _ReportWizardPageState extends State<ReportWizardPage>
    with SingleTickerProviderStateMixin {
  ReportWizardViewModel? _viewModel;
  late final TextEditingController _descriptionController;
  late final ReverseGeocodingService _geocodingService;
  late final AnimationController _step3SheetController;
  late final Animation<double> _step3SheetCurve;
  final MapController _mapController = MapController();
  Timer? _dragDebounce;
  bool _mapReady = false;
  bool _isDraggingMap = false;
  bool _autoGpsRequested = false;
  int _previousStep = 0;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController();
    _geocodingService = widget.geocodingService ?? ReverseGeocodingService();
    _step3SheetController = AnimationController(
      vsync: this,
      value: 1.0,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _step3SheetCurve = CurvedAnimation(
      parent: _step3SheetController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  void _setStep3SheetExpanded(bool expanded) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      _step3SheetController.value = expanded ? 1.0 : 0.0;
    } else if (expanded) {
      _step3SheetController.forward();
    } else {
      _step3SheetController.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      final repo = ReportScope.read(context);
      _viewModel = ReportWizardViewModel(
        repository: repo,
        initialCategory: widget.initialCategory,
        initialCoordinates: widget.initialCoordinates,
        initialDraft: widget.initialDraft,
        initialPhotoPaths: widget.initialPhotoPaths,
        voiceInputService: widget.voiceInputService,
        audioRecorderService: widget.audioRecorderService,
        civicAiService: widget.civicAiService,
        ipGeolocationService: widget.ipGeolocationService,
      );
      if (widget.initialPhotoExif != null) {
        _viewModel!.setPhotoExifMetadata(widget.initialPhotoExif);
      }
      if (widget.initialPhotoAnchor != null) {
        _viewModel!.setPhotoLocationAnchor(widget.initialPhotoAnchor);
      }
      _previousStep = _viewModel!.step;
      _descriptionController.text = _viewModel!.description;
    }
  }

  @override
  void dispose() {
    _dragDebounce?.cancel();
    _step3SheetController.dispose();
    _viewModel?.dispose();
    _descriptionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _syncDescriptionController(String text) {
    if (_descriptionController.text == text) return;
    _descriptionController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _reverseGeocodeCurrentPin(LatLng point) async {
    final place = await _geocodingService.reverseGeocode(point);
    if (!mounted) return;
    _viewModel?.setGeocodedPlace(point, place);
  }

  Future<void> _handleExitRequest(
    ReportWizardViewModel vm,
    Bilingual tr,
  ) async {
    if (!vm.hasUnsavedChanges) {
      Navigator.pop(context);
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(tr.primary('រក្សាទុកសេចក្តីព្រាង?', 'Save report draft?')),
        content: Text(
          tr.primary(
            'អ្នកអាចបន្តបំពេញរបាយការណ៍នេះនៅពេលក្រោយពីទំព័រដើមបាន។',
            'You can resume this report anytime from the Home screen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'discard'),
            child: Text(
              tr.primary('បោះបង់', 'Discard'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, 'save'),
            child: Text(tr.primary('រក្សាទុក', 'Save draft')),
          ),
        ],
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'save') {
      vm.saveDraft();
    } else if (action == 'discard') {
      vm.repository.deleteDraft(vm.draftId);
    }
    Navigator.pop(context);
  }

  bool _hasVerifiedCambodiaCameraExif(PhotoExifMetadata exif) {
    final coords = exif.coordinates;
    if (coords == null || !LocationService.isInsideCambodia(coords)) {
      return false;
    }
    final capturedAt = exif.capturedAt;
    if (capturedAt != null &&
        DateTime.now().difference(capturedAt).abs() >
            const Duration(days: 30)) {
      return false;
    }
    return true;
  }

  void _showMissingCameraExifSnackBar(Bilingual tr) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr.primary(
            'រូបភាពពីវិចិត្រសាលមិនមានទិន្នន័យ GPS កាមេរ៉ានៅកម្ពុជាទេ — សូមប្រើកាមេរ៉ាថតផ្ទាល់',
            'Gallery photo lacks Cambodia camera EXIF GPS — please take a live photo with your phone camera.',
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source, Bilingual tr) async {
    final vm = _viewModel;
    if (vm == null || !vm.canAddMorePhotos) return;

    try {
      if (source == ImageSource.gallery && vm.remainingPhotoSlots > 1) {
        final results = await pickMultipleSanitizedPhotos(
          limit: vm.remainingPhotoSlots,
          maxDimension: 1024,
          jpegQuality: 78,
        );
        if (!mounted || results.isEmpty) return;
        final validPaths = <String>[];
        final perPhotoExif = <PhotoExifMetadata?>[];
        var hadUnsupported = false;
        var hadMissingCameraExif = false;
        for (final item in results) {
          if (item.isValid) {
            if (!_hasVerifiedCambodiaCameraExif(item.exifMetadata)) {
              hadMissingCameraExif = true;
              continue;
            }
            validPaths.add(item.path);
            perPhotoExif.add(item.exifMetadata);
          } else if (item.unsupportedFormat) {
            hadUnsupported = true;
          }
        }
        if (validPaths.isNotEmpty) {
          HapticFeedback.selectionClick();
          _viewModel?.addLocalPhotoPaths(
            validPaths,
            perPhotoExif: perPhotoExif,
          );
        }
        if (hadMissingCameraExif) {
          _showMissingCameraExifSnackBar(tr);
        } else if (hadUnsupported && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr.primary(
                  'រូបភាពខ្លះមានទម្រង់មិនគាំទ្រ (ឧ. HEIC) — សូមជ្រើសរូប JPG ឬ PNG',
                  'Some photos use an unsupported format (e.g. HEIC) — please choose JPG or PNG.',
                ),
              ),
            ),
          );
        }
        return;
      }

      final result = await pickSanitizedPhoto(
        source: source,
        maxDimension: 1024,
        jpegQuality: 78,
      );
      if (!mounted || result == null) return;
      if (result.unsupportedFormat || !result.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr.primary(
                'ទម្រង់រូបភាពនេះ (ឧ. HEIC) មិនគាំទ្រទេ — សូមជ្រើសរូប JPG ឬ PNG',
                'This photo format (e.g. HEIC) is not supported — please choose JPG or PNG.',
              ),
            ),
          ),
        );
        return;
      }
      if (source == ImageSource.gallery &&
          !_hasVerifiedCambodiaCameraExif(result.exifMetadata)) {
        _showMissingCameraExifSnackBar(tr);
        return;
      }
      HapticFeedback.selectionClick();
      final added = vm.addLocalPhotoPath(
        result.path,
        exifMetadata: result.exifMetadata,
      );
      final hasInCambodiaExif =
          result.exifMetadata.coordinates != null &&
          LocationService.isInsideCambodia(result.exifMetadata.coordinates!);
      if (added && source == ImageSource.camera && !hasInCambodiaExif) {
        final photoIndex = vm.localPhotoPaths.length - 1;
        unawaited(_captureLiveCameraAnchor(vm, photoIndex, tr));
      }
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? tr.primary(
                    'ឧបករណ៍នេះមិនអាចបើកកាមេរ៉ាបានទេ សូមជ្រើសរូបពីវិចិត្រសាល',
                    'Camera unavailable on this device. Please choose from Gallery.',
                  )
                : tr.primary(
                    'មិនអាចបើកវិចិត្រសាលរូបភាពបានទេ',
                    'Unable to open photo gallery.',
                  ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary(
              'មិនអាចជ្រើសរូបភាពបានទេ សូមព្យាយាមម្តងទៀត',
              'Could not load photo. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  void _showPhotoSourceSheet(Bilingual tr) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.tealSoft,
                  child: Icon(
                    Icons.photo_camera_outlined,
                    color: AppColors.teal,
                  ),
                ),
                title: Text(tr.paired('ថតរូបថ្មី', 'Take Photo')),
                onTap: () {
                  unawaited(_pickPhoto(ImageSource.camera, tr));
                  Navigator.pop(sheetCtx);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.tealSoft,
                  child: Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.teal,
                  ),
                ),
                title: Text(
                  tr.paired('ជ្រើសពីវិចិត្រសាល', 'Choose from Gallery'),
                ),
                onTap: () {
                  unawaited(_pickPhoto(ImageSource.gallery, tr));
                  Navigator.pop(sheetCtx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryPickerSheet(ReportWizardViewModel vm, Bilingual tr) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BilingualText(
                bilingual: tr,
                khmer: 'ជ្រើសប្រភេទបញ្ហា',
                english: 'Select issue category',
                fontSize: 16,
              ),
              const SizedBox(height: 10),
              for (final cat in IssueCategory.values)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: vm.category == cat
                        ? AppColors.teal
                        : AppColors.tealSoft,
                    child: Icon(
                      Bilingual.categoryIcon(cat),
                      color: vm.category == cat ? Colors.white : AppColors.teal,
                    ),
                  ),
                  title: Text(tr.paired(cat.khmerName, cat.englishName)),
                  trailing: vm.category == cat
                      ? const Icon(Icons.check_circle, color: AppColors.teal)
                      : null,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    vm.selectCategory(cat);
                    Navigator.pop(sheetCtx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Captures a fast, anti-spoof-verified live GPS anchor when the citizen
  /// shoots a photo directly with the in-app camera and the OS/browser strips
  /// EXIF GPS metadata.
  Future<void> _captureLiveCameraAnchor(
    ReportWizardViewModel vm,
    int photoIndex,
    Bilingual tr,
  ) async {
    vm.setCapturingCameraAnchor(true);
    try {
      final result = await widget.locationService.getCurrentLocation(
        fastFix: true,
      );
      if (!mounted) return;
      switch (result) {
        case LocationSuccess(:final point, :final isOutsideCambodia):
          if (isOutsideCambodia) return;
          final spoofCheck = AntiSpoofService.evaluateGpsFix(
            current: result.toReadingSample(),
            lastCheckpoint: vm.repository.lastVerifiedGpsCheckpoint,
          );
          if (spoofCheck.isBlocked) {
            vm.recordLiveGpsResult(
              LocationMockDetected(
                point: point,
                detectedLabel:
                    spoofCheck.detectedLabel ?? 'Mock GPS / Spoofing Provider',
                reasonKhmer: spoofCheck.khmerSummary,
                reasonEnglish: spoofCheck.englishSummary,
              ),
            );
            await Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => FakeGpsPage(
                  detectedAppLabel:
                      spoofCheck.detectedLabel ??
                      'Mock GPS / Spoofing Provider',
                  detailKhmer: spoofCheck.khmerSummary,
                  detailEnglish: spoofCheck.englishSummary,
                  onOpenSettings: widget.locationService.openLocationSettings,
                  onTryAgain: () {
                    Navigator.pop(context);
                    _verifyGpsLocation(tr);
                  },
                ),
              ),
            );
            return;
          }
          vm.repository.recordVerifiedGpsCheckpoint(
            point,
            timestamp: result.timestamp,
          );
          vm.recordLiveGpsResult(result, movePinToGps: false);
          vm.attachLiveCameraAnchorToPhotoAt(
            photoIndex,
            PhotoLocationAnchor(
              point: point,
              source: PhotoAnchorSource.liveCameraCapture,
              capturedAt: result.timestamp,
            ),
          );
        case LocationMockDetected(
          :final detectedLabel,
          :final reasonKhmer,
          :final reasonEnglish,
        ):
          vm.recordLiveGpsResult(result);
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => FakeGpsPage(
                detectedAppLabel: detectedLabel,
                detailKhmer: reasonKhmer,
                detailEnglish: reasonEnglish,
                onOpenSettings: widget.locationService.openLocationSettings,
                onTryAgain: () {
                  Navigator.pop(context);
                  _verifyGpsLocation(tr);
                },
              ),
            ),
          );
        default:
          break;
      }
    } finally {
      if (mounted) {
        vm.setCapturingCameraAnchor(false);
      }
    }
  }

  void _maybeTriggerAutoGps(Bilingual tr) {
    if (_autoGpsRequested) return;
    _autoGpsRequested = true;
    unawaited(_verifyGpsLocation(tr, autoRequest: true));
  }

  Future<void> _verifyGpsLocation(
    Bilingual tr, {
    bool autoRequest = false,
  }) async {
    final vm = _viewModel;
    if (vm == null || vm.isLocating) return;

    if (!autoRequest) {
      HapticFeedback.selectionClick();
    }
    vm.setLocating(true);
    try {
      final result = await widget.locationService.getCurrentLocation(
        fastFix: autoRequest,
      );
      if (!mounted) return;

      switch (result) {
        case LocationSuccess(
          :final point,
          :final accuracyMeters,
          :final isOutsideCambodia,
        ):
          if (isOutsideCambodia) {
            vm.setOutsideCambodiaDetected(
              point,
              accuracyMeters: accuracyMeters,
            );
          } else {
            final spoofCheck = AntiSpoofService.evaluateGpsFix(
              current: result.toReadingSample(),
              lastCheckpoint: vm.repository.lastVerifiedGpsCheckpoint,
            );
            if (spoofCheck.isBlocked) {
              vm.recordLiveGpsResult(
                LocationMockDetected(
                  point: point,
                  detectedLabel:
                      spoofCheck.detectedLabel ??
                      'Mock GPS / Spoofing Provider',
                  reasonKhmer: spoofCheck.khmerSummary,
                  reasonEnglish: spoofCheck.englishSummary,
                ),
              );
              await Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FakeGpsPage(
                    detectedAppLabel:
                        spoofCheck.detectedLabel ??
                        'Mock GPS / Spoofing Provider',
                    detailKhmer: spoofCheck.khmerSummary,
                    detailEnglish: spoofCheck.englishSummary,
                    onOpenSettings: widget.locationService.openLocationSettings,
                    onTryAgain: () {
                      Navigator.pop(context);
                      _verifyGpsLocation(tr);
                    },
                  ),
                ),
              );
              return;
            }
            vm.repository.recordVerifiedGpsCheckpoint(
              point,
              timestamp: result.timestamp,
            );
            final shouldMovePin =
                vm.activeFreshPhotoAnchor == null &&
                (!autoRequest ||
                    (widget.initialCoordinates == null &&
                        !vm.userManuallyMovedPin));
            vm.recordLiveGpsResult(result, movePinToGps: shouldMovePin);
            if (shouldMovePin) {
              if (_mapReady) {
                _mapController.move(point, MapTileConfig.streetFocusZoom);
              }
              await _reverseGeocodeCurrentPin(point);
            }
          }
        case LocationMockDetected(
          :final detectedLabel,
          :final reasonKhmer,
          :final reasonEnglish,
        ):
          vm.recordLiveGpsResult(result);
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => FakeGpsPage(
                detectedAppLabel: detectedLabel,
                detailKhmer: reasonKhmer,
                detailEnglish: reasonEnglish,
                onOpenSettings: widget.locationService.openLocationSettings,
                onTryAgain: () {
                  Navigator.pop(context);
                  _verifyGpsLocation(tr);
                },
              ),
            ),
          );
        case LocationServiceDisabled():
          vm.recordLiveGpsResult(result);
          if (!autoRequest) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr.primary(
                    'សូមបើកសេវាកម្ម GPS ដើម្បីផ្ទៀងផ្ទាត់ទីតាំង',
                    'Please enable GPS services to verify your reporting area.',
                  ),
                ),
              ),
            );
          }
        case LocationPermissionDenied():
          vm.recordLiveGpsResult(result);
          if (!autoRequest) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr.primary(
                    'ត្រូវការសិទ្ធិ GPS ដើម្បីផ្ទៀងផ្ទាត់ទីតាំង',
                    'Location permission is required to verify your reporting area.',
                  ),
                ),
              ),
            );
          }
        case LocationFailure():
          vm.recordLiveGpsResult(result);
          if (!autoRequest) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr.primary(
                    'មិនអាចចាប់ GPS បានទេ — សូមព្យាយាមម្តងទៀត ឬកំណត់តំបន់រស់នៅ',
                    'Could not acquire GPS fix — try again or set your Home District.',
                  ),
                ),
              ),
            );
          }
      }
    } finally {
      if (mounted) vm.setLocating(false);
    }
  }

  void _onMapDragged(LatLng center) {
    if (!_isDraggingMap) {
      setState(() => _isDraggingMap = true);
    }
    // Update coordinates immediately so duplicate geofencing reacts live!
    _viewModel?.updatePinCoordinatesLive(center);
    _dragDebounce?.cancel();
    _dragDebounce = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() => _isDraggingMap = false);
      _viewModel?.setPinLocation(center, verified: true, fromLiveGps: false);
      _reverseGeocodeCurrentPin(center);
    });
  }

  void _completeSubmission(
    ReportWizardViewModel vm,
    Bilingual tr, {
    bool forceCreateNew = false,
    String? customTitle,
  }) {
    HapticFeedback.mediumImpact();
    if (_dragDebounce?.isActive ?? false) {
      _dragDebounce?.cancel();
      if (_mapReady) {
        vm.updatePinCoordinatesLive(_mapController.camera.center);
      }
    }
    // Enforce Rule #1 (Smart Distance Gate) and AI / online guard defensively.
    if (vm.isPhotoAiBlockedForNextStep || vm.requiresOfflineDraftOnly) {
      return;
    }
    if (!vm.canSubmitAtCurrentPin) {
      final eligibility = vm.locationEligibility;
      if (eligibility is ReportLocationDeniedLocationRequired &&
          eligibility.pendingGpsCheck &&
          !vm.isLocating) {
        unawaited(_verifyGpsLocation(tr));
      }
      return;
    }
    if (!vm.locationVerified) {
      vm.confirmCurrentPin();
    }
    final result = vm.submit(
      forceCreateNew: forceCreateNew,
      customTitle: customTitle,
    );
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReportSubmittedPage(result: result),
      ),
    );
  }

  void _returnTo150mZone(ReportWizardViewModel vm) {
    HapticFeedback.selectionClick();
    final coords = vm.returnTo150mZone();
    if (coords != null) {
      if (_mapReady) {
        _mapController.move(coords, MapTileConfig.streetFocusZoom);
      }
      unawaited(_reverseGeocodeCurrentPin(coords));
    }
  }

  Future<void> _openSimilarReportPreview(
    ReportWizardViewModel vm,
    DuplicateMatch match,
    Bilingual tr,
  ) async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (_) => _SimilarReportPreviewSheet(match: match, tr: tr),
    );
    if (picked == true && mounted) {
      vm.selectMasterReport(match.masterReport.id);
    }
  }

  Future<void> _openDifferentProblemSheet(
    ReportWizardViewModel vm,
    CivicReport masterReport,
    Bilingual tr,
  ) async {
    if (!vm.canSubmitAtCurrentPin) return;
    HapticFeedback.selectionClick();
    final submitted =
        await showModalBottomSheet<
          ({IssueCategory category, String title, String description})
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: AppColors.paper,
          builder: (_) => _DifferentProblemSheet(
            masterReport: masterReport,
            initialDescription: vm.description,
            tr: tr,
          ),
        );

    if (submitted == null || !mounted) return;
    vm.selectCategory(submitted.category);
    vm.updateDescription(submitted.description);
    _completeSubmission(
      vm,
      tr,
      forceCreateNew: true,
      customTitle: submitted.title.isNotEmpty ? submitted.title : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel!;
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);

    return AssistantBubbleSuppressor(
      child: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          _syncDescriptionController(vm.description);

          return PopScope(
            canPop: vm.step == 0 && !vm.hasUnsavedChanges,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (vm.step > 0) {
                vm.previousStep();
              } else {
                _handleExitRequest(vm, tr);
              }
            },
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: vm.step == 0
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: Builder(
                builder: (context) {
                  final step = vm.step;
                  final goingForward = step >= _previousStep;
                  _previousStep = step;
                  final reduceMotion = MediaQuery.disableAnimationsOf(context);
                  return AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      final offset = Tween<Offset>(
                        begin: Offset(goingForward ? 0.06 : -0.06, 0.0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: offset, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey('wizard-step-$step'),
                      child: switch (step) {
                        0 => _buildCameraStep(vm, tr),
                        1 => _buildDetailsStep(vm, tr),
                        _ => _buildFullBleedLocationStep(vm, repo.reports, tr),
                      },
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// Screen 2.1: Honest Camera Viewfinder — only scans & runs real Gemini
  /// Vision AI after the citizen captures or picks an actual photo.
  Widget _buildCameraStep(ReportWizardViewModel vm, Bilingual tr) {
    final hasRealPhoto = vm.latestLocalPhotoPath != null;
    final photoAi = vm.photoAi;
    final isScanning = photoAi.status == PhotoAiStatus.analyzing;

    Widget buildStatusPill() {
      if (!hasRealPhoto) {
        return Container(
          key: const Key('step1-capture-prompt-pill'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.device.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_camera_outlined,
                size: 15,
                color: AppColors.saffron,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  tr.primary(
                    'ថត ឬជ្រើសរូបភាពបញ្ហាពិត',
                    'Take or pick a real issue photo',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      if (isScanning) {
        return Container(
          key: const Key('step1-ai-scanning-pill'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  tr.primary(
                    'AI កំពុងវិភាគរូបភាពរបស់អ្នក...',
                    'AI analyzing your photo...',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      if (photoAi.hasDetectedIssue) {
        final detected = photoAi.detectedCategory!;
        return Container(
          key: const Key('step1-ai-detected-pill'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 15, color: AppColors.teal),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'AI: ${tr.paired(detected.khmerName, detected.englishName)} ${photoAi.confidencePercent ?? 90}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      if (photoAi.status == PhotoAiStatus.notCivicIssue) {
        return Container(
          key: const Key('step1-ai-not-issue-pill'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.saffronSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.saffron),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: AppColors.saffronInk,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tr.primary(
                    'រូបភាពនេះមិនមែនជាបញ្ហាផ្លូវទេ · សូមថតថ្មី ឬជ្រើសដោយដៃ',
                    'Not recognized as a street issue — retake or select below',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.saffronInk,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        key: const Key('step1-ai-status-pill'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.device.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              photoAi.status == PhotoAiStatus.offline
                  ? Icons.wifi_off_rounded
                  : Icons.check_circle_outline_rounded,
              size: 15,
              color: AppColors.saffron,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                switch (photoAi.status) {
                  PhotoAiStatus.offline => tr.primary(
                    'គ្មានអ៊ីនធឺណិត · ជ្រើសប្រភេទខាងក្រោម',
                    'Offline — select category below',
                  ),
                  PhotoAiStatus.rateLimited => tr.primary(
                    'សេវា AI កំពុងមមាញឹក · ជ្រើសប្រភេទខាងក្រោម',
                    'AI busy — select category below',
                  ),
                  _ => tr.primary(
                    'បានភ្ជាប់រូបភាព (${vm.localPhotoPaths.length}/3) · ជ្រើសប្រភេទខាងក្រោម',
                    'Photo attached (${vm.localPhotoPaths.length}/3) — pick category below',
                  ),
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.device,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (hasRealPhoto)
            ReportPhoto(
              category: vm.category,
              localPhotoPath: vm.latestLocalPhotoPath,
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0E2120), Color(0xFF0A1414)],
                ),
              ),
            ),
          Container(
            color: AppColors.device.withValues(
              alpha: hasRealPhoto ? 0.30 : 0.15,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _FrostedCircleButton(
                        icon: Icons.close_rounded,
                        tooltip: tr.primary('បិទ', 'Close'),
                        onTap: () => _handleExitRequest(vm, tr),
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.device.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: BilingualText(
                              bilingual: tr,
                              khmer: 'ជំហាន ១/៣ · ថតរូប',
                              english: 'Step 1 of 3 · Photo',
                              fontSize: 12,
                              color: Colors.white,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              maxLines: 1,
                              isHeader: true,
                            ),
                          ),
                        ),
                      ),
                      _FrostedCircleButton(
                        icon: Icons.tune_rounded,
                        tooltip: tr.primary('ប្តូរប្រភេទ', 'Change category'),
                        onTap: () => _showCategoryPickerSheet(vm, tr),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 252,
                              height: 184,
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(26),
                                      border: Border.all(
                                        color: isScanning
                                            ? AppColors.saffron
                                            : Colors.white.withValues(
                                                alpha: 0.45,
                                              ),
                                        width: isScanning ? 2.5 : 1.8,
                                      ),
                                    ),
                                  ),
                                  if (!hasRealPhoto)
                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.add_a_photo_outlined,
                                            size: 40,
                                            color: Colors.white.withValues(
                                              alpha: 0.72,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                            ),
                                            child: Text(
                                              tr.primary(
                                                'ចុចប៊ូតុងកាមេរ៉ា ឬវិចិត្រសាលខាងក្រោម',
                                                'Tap Camera or Gallery below',
                                              ),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.78,
                                                ),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (isScanning &&
                                      !MediaQuery.disableAnimationsOf(context))
                                    const _AiScanLine(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Semantics(
                              container: true,
                              liveRegion: true,
                              child: buildStatusPill(),
                            ),
                            if (hasRealPhoto) ...[
                              const SizedBox(height: 8),
                              _buildStep1PhotoGpsPill(vm, tr),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              hasRealPhoto
                                  ? tr.paired(
                                      'បានលុប EXIF ដោយស្វ័យប្រវត្តិ · រូបភាព ${vm.localPhotoPaths.length}/${ReportWizardViewModel.maxPhotos}',
                                      'EXIF stripped · ${vm.localPhotoPaths.length}/${ReportWizardViewModel.maxPhotos} photo(s) attached',
                                    )
                                  : tr.paired(
                                      'សូមថត ឬជ្រើសរូបភាពបញ្ហាយ៉ាងតិច ១ សន្លឹកដើម្បីបន្ត',
                                      'Take or pick at least 1 issue photo to continue',
                                    ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      for (final cat in IssueCategory.values) ...[
                        ChoiceChip(
                          label: Text(
                            tr.categoryPrimary(cat),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: vm.category == cat
                                  ? AppColors.saffronInk
                                  : Colors.white,
                            ),
                          ),
                          selected: vm.category == cat,
                          selectedColor: AppColors.saffron,
                          backgroundColor: AppColors.device.withValues(
                            alpha: 0.65,
                          ),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            vm.selectCategory(cat);
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 0, 26, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _FrostedCircleButton(
                        icon: Icons.photo_library_outlined,
                        tooltip: tr.primary('វិចិត្រសាល', 'Gallery'),
                        size: 50,
                        onTap: () => _pickPhoto(ImageSource.gallery, tr),
                      ),
                      Semantics(
                        button: true,
                        excludeSemantics: true,
                        label: tr.primary('ថតរូបបញ្ហា', 'Take issue photo'),
                        child: Tooltip(
                          message: tr.primary('ថតរូបបញ្ហា', 'Take issue photo'),
                          child: Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: () => _pickPhoto(ImageSource.camera, tr),
                              customBorder: const CircleBorder(),
                              child: Container(
                                width: 72,
                                height: 72,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3.5,
                                  ),
                                ),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: AppColors.ink,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: vm.hasRequiredPhoto
                            ? tr.primary(
                                'ទៅជំហានបន្ទាប់',
                                'Continue to details',
                              )
                            : tr.primary(
                                'ត្រូវការរូបភាពបញ្ហាយ៉ាងតិច ១ សន្លឹក',
                                'At least 1 issue photo is required',
                              ),
                        child: FilledButton.icon(
                          key: const Key('step1-next-btn'),
                          onPressed: vm.hasRequiredPhoto
                              ? () {
                                  HapticFeedback.selectionClick();
                                  vm.nextStep();
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.teal,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white.withValues(
                              alpha: 0.16,
                            ),
                            disabledForegroundColor: Colors.white.withValues(
                              alpha: 0.50,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          icon: Text(tr.primary('បន្ទាប់', 'Next')),
                          label: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1PhotoGpsPill(ReportWizardViewModel vm, Bilingual tr) {
    final isLocking = vm.isCapturingCameraAnchor;
    final hasLockedAnchor = vm.activeFreshPhotoAnchor != null;
    final isStaleExif = vm.hasStalePhotoExif;

    final Color bgColor;
    final Color borderColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    if (isLocking) {
      bgColor = AppColors.device.withValues(alpha: 0.85);
      borderColor = AppColors.teal.withValues(alpha: 0.65);
      fgColor = Colors.white;
      icon = Icons.my_location_rounded;
      label = tr.primary('កំពុងភ្ជាប់ GPS រូបថត...', 'Locking photo GPS...');
    } else if (hasLockedAnchor) {
      bgColor = AppColors.successSoft;
      borderColor = AppColors.success.withValues(alpha: 0.55);
      fgColor = AppColors.tealDark;
      icon = Icons.verified_rounded;
      label = vm.autoSavedPhotoAnchorDraft
          ? tr.primary(
              '✓ ភ្ជាប់ GPS រូបថត · រង្វង់ 150m & សេចក្តីព្រាងរួចរាល់',
              '✓ Photo GPS locked · 150 m zone & draft saved',
            )
          : tr.primary(
              '✓ ភ្ជាប់ GPS រូបថត (រង្វង់ 150m រួចរាល់)',
              '✓ Photo GPS locked (150 m zone ready)',
            );
    } else if (isStaleExif) {
      bgColor = AppColors.saffronSoft;
      borderColor = AppColors.saffron.withValues(alpha: 0.75);
      fgColor = AppColors.saffronInk;
      icon = Icons.schedule_rounded;
      label = tr.primary(
        'GPS រូបថតចាស់ជាង 30 ថ្ងៃ — ជំហាន ៣ នឹងប្រើ GPS ផ្ទាល់ (150m)',
        'Photo GPS >30 days old — Step 3 will use live GPS (150 m)',
      );
    } else {
      bgColor = AppColors.saffronSoft;
      borderColor = AppColors.saffron.withValues(alpha: 0.75);
      fgColor = AppColors.saffronInk;
      icon = Icons.gps_not_fixed_rounded;
      label = tr.primary(
        'រូបថតគ្មាន GPS — ជំហាន ៣ នឹងប្រើ GPS ផ្ទាល់ (150m)',
        'No GPS tag in photo — Step 3 will lock 150 m to live GPS',
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('step1-photo-gps-pill'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLocking)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.saffron,
                ),
              )
            else
              Icon(icon, size: 14, color: fgColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Screen 2.2: Report Details with multi-photo support (up to 3),
  /// animated VoiceWaveform, 3 severity cards, quick-tap tags, & keyboard dismiss.
  Widget _buildDetailsStep(ReportWizardViewModel vm, Bilingual tr) {
    final ai = vm.classification;
    final severityCards = [
      (2, 'តិច', 'Minor', Icons.info_outline_rounded),
      (3, 'មធ្យម', 'Moderate', Icons.warning_amber_rounded),
      (5, 'គ្រោះថ្នាក់', 'Dangerous', Icons.report_gmailerrorred_rounded),
    ];

    return GestureDetector(
      excludeFromSemantics: true,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: AppColors.cardShadow,
                          ),
                          child: IconButton(
                            tooltip: tr.primary('ថយក្រោយ', 'Back'),
                            icon: const Icon(Icons.arrow_back),
                            onPressed: vm.previousStep,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: BilingualText(
                            bilingual: tr,
                            khmer: 'ព័ត៌មានលម្អិត',
                            english: 'Report details',
                            fontSize: 17,
                            isHeader: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Semantics(
                      label: tr.primary('ជំហាន ២ នៃ ៣', 'Step 2 of 3'),
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.teal,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.teal,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Multi-Photo Row (up to 3 real photos; no fake sample thumbnail)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (
                                  var i = 0;
                                  i < vm.localPhotoPaths.length;
                                  i++
                                ) ...[
                                  KeyedSubtree(
                                    key: ValueKey(
                                      '${vm.localPhotoPaths[i]}-$i',
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Semantics(
                                          button: true,
                                          excludeSemantics: true,
                                          label: tr.primary(
                                            'មើលរូបភាព ${i + 1} ពេញអេក្រង់',
                                            'View photo ${i + 1} full screen',
                                          ),
                                          child: InkWell(
                                            onTap: () => PhotoLightboxPage.open(
                                              context,
                                              category: vm.category,
                                              bilingual: tr,
                                              localPhotoPath:
                                                  vm.localPhotoPaths[i],
                                              title:
                                                  '${tr.categoryPrimary(vm.category)} (${i + 1})',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            child: ReportPhoto(
                                              category: vm.category,
                                              localPhotoPath:
                                                  vm.localPhotoPaths[i],
                                              width: 84,
                                              height: 84,
                                              borderRadius: 18,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 6,
                                          bottom: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.teal,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              '${i + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: -12,
                                          top: -12,
                                          child: Semantics(
                                            button: true,
                                            excludeSemantics: true,
                                            label: tr.primary(
                                              'លុបរូបភាព ${i + 1}',
                                              'Remove photo ${i + 1}',
                                            ),
                                            child: Tooltip(
                                              message: tr.primary(
                                                'លុបរូបភាព',
                                                'Remove photo',
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                shape: const CircleBorder(),
                                                child: InkWell(
                                                  customBorder:
                                                      const CircleBorder(),
                                                  onTap: () {
                                                    HapticFeedback.selectionClick();
                                                    vm.removeLocalPhotoAt(i);
                                                  },
                                                  child: SizedBox(
                                                    width: 48,
                                                    height: 48,
                                                    child: Center(
                                                      child: Container(
                                                        width: 24,
                                                        height: 24,
                                                        decoration:
                                                            BoxDecoration(
                                                              color:
                                                                  AppColors.ink,
                                                              shape: BoxShape
                                                                  .circle,
                                                              border: Border.all(
                                                                color: Colors
                                                                    .white,
                                                                width: 2,
                                                              ),
                                                            ),
                                                        child: const Icon(
                                                          Icons.close,
                                                          size: 13,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                if (vm.canAddMorePhotos)
                                  InkWell(
                                    key: const Key('step2-add-photo-btn'),
                                    onTap: () => _showPhotoSourceSheet(tr),
                                    borderRadius: BorderRadius.circular(18),
                                    child: Container(
                                      constraints: BoxConstraints(
                                        minWidth: vm.localPhotoPaths.isEmpty
                                            ? 156
                                            : 84,
                                        maxWidth: 180,
                                        minHeight: 84,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: vm.localPhotoPaths.isEmpty
                                            ? AppColors.dangerSoft
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: vm.localPhotoPaths.isEmpty
                                              ? AppColors.danger.withValues(
                                                  alpha: 0.65,
                                                )
                                              : AppColors.border,
                                          width: 1.6,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_a_photo_outlined,
                                            size: 21,
                                            color: vm.localPhotoPaths.isEmpty
                                                ? AppColors.danger
                                                : AppColors.muted,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            vm.localPhotoPaths.isEmpty
                                                ? tr.primary(
                                                    'បន្ថែមរូបភាព (ចាំបាច់)',
                                                    'Add photo (Required)',
                                                  )
                                                : '${tr.primary('បន្ថែម', 'Add')} (${vm.localPhotoPaths.length}/${ReportWizardViewModel.maxPhotos})',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: vm.localPhotoPaths.isEmpty
                                                  ? AppColors.ink
                                                  : AppColors.muted,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!vm.hasRequiredPhoto) ...[
                            const SizedBox(height: 10),
                            Semantics(
                              container: true,
                              liveRegion: true,
                              child: Container(
                                key: const Key('step2-photo-required-banner'),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerSoft,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.danger.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.photo_camera_outlined,
                                      size: 16,
                                      color: AppColors.danger,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        tr.primary(
                                          'ត្រូវការរូបភាពបញ្ហាយ៉ាងតិច ១ សន្លឹក ដើម្បីបន្តទៅជំហានបន្ទាប់',
                                          'At least 1 issue photo is required to continue',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.verified_user_outlined,
                                size: 15,
                                color: AppColors.teal,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  tr.primary(
                                    'ទិន្នន័យ EXIF រូបភាពត្រូវបានលុបចេញដោយស្វ័យប្រវត្តិ (អាចភ្ជាប់បានដល់ ៣ រូប)',
                                    'Photo EXIF metadata is stripped automatically (up to 3 angles)',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Honest Photo + Text AI Category Card (`hackathonshow.md §4 Step 1`)
                          _buildStep2AiCard(vm, ai, tr),
                          const SizedBox(height: 16),

                          // 3-Card Severity Selector
                          BilingualText(
                            bilingual: tr,
                            khmer: 'កម្រិតធ្ងន់ធ្ងរ',
                            english: 'How serious is it?',
                            fontSize: 14,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (
                                var i = 0;
                                i < severityCards.length;
                                i++
                              ) ...[
                                Expanded(
                                  child: _SeverityCard(
                                    score: severityCards[i].$1,
                                    khmer: severityCards[i].$2,
                                    english: severityCards[i].$3,
                                    icon: severityCards[i].$4,
                                    selected:
                                        vm.severity == severityCards[i].$1,
                                    tr: tr,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      vm.setSeverity(severityCards[i].$1);
                                    },
                                  ),
                                ),
                                if (i < severityCards.length - 1)
                                  const SizedBox(width: 8),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Quick-Tap Preset Tags
                          Text(
                            tr.paired('ពាក្យរហ័ស', 'Quick hazard tags'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (khTag, enTag)
                                  in vm.category.presetTags)
                                FilterChip(
                                  label: Text(tr.primary(khTag, enTag)),
                                  selected: vm.hasTag(tr.primary(khTag, enTag)),
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    vm.togglePresetTag(
                                      tr.primary(khTag, enTag),
                                    );
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Telegram-Style Hold-or-Tap Khmer Voice Note (`hackathonshow.md §5`)
                          _buildVoiceNoteCard(vm, tr),
                          const SizedBox(height: 14),

                          // Description Box (starts empty with clear bilingual hint)
                          TextField(
                            key: const Key('report-description-field'),
                            controller: _descriptionController,
                            maxLines: 3,
                            onChanged: vm.updateDescription,
                            decoration: InputDecoration(
                              labelText: tr.paired(
                                'ពិពណ៌នាបញ្ហា',
                                'Describe the problem',
                              ),
                              hintText: tr.primary(
                                'ឧ. មានរណ្តៅផ្លូវជ្រៅ លូស្ទះលិចទឹក ឬគំនរសំរាមតាមផ្លូវ...',
                                'e.g. Deep pothole, flooded drain, or roadside garbage...',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Anonymous Toggle
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: SwitchListTile(
                              secondary: const Icon(
                                Icons.visibility_off_outlined,
                                color: AppColors.teal,
                              ),
                              title: Text(
                                tr.primary('របាយការណ៍អនាមិក', 'Anonymous Mode'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: Text(
                                tr.primary(
                                  'លាក់ឈ្មោះ និងលេខទូរស័ព្ទលើរបាយការណ៍សាធារណៈ',
                                  'Hide your profile from public incident records',
                                ),
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              value: vm.isAnonymous,
                              onChanged: vm.setAnonymous,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                    decoration: const BoxDecoration(
                      color: AppColors.paper,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Builder(
                      builder: (context) {
                        final isNonCivicBlocked =
                            vm.photoAi.status == PhotoAiStatus.notCivicIssue;
                        final isAnalyzingPhoto =
                            vm.photoAi.status == PhotoAiStatus.analyzing;
                        final isTransientAiFailure =
                            vm.isBackendAiAvailable &&
                            vm.repository.isOnline &&
                            (vm.photoAi.status == PhotoAiStatus.failed ||
                                vm.photoAi.status == PhotoAiStatus.rateLimited);
                        final canProceedToStep3 =
                            vm.hasRequiredPhoto &&
                            !vm.isPhotoAiBlockedForNextStep;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isAnalyzingPhoto) ...[
                              Semantics(
                                container: true,
                                liveRegion: true,
                                child: Text(
                                  tr.primary(
                                    'កំពុងពិនិត្យរូបភាពដោយ AI...',
                                    'Verifying photo with AI...',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ] else if (isNonCivicBlocked) ...[
                              Semantics(
                                container: true,
                                liveRegion: true,
                                child: Text(
                                  tr.primary(
                                    'សូមថត ឬជ្រើសរូបបញ្ហាផ្លូវពិតប្រាកដមុនបន្តទៅជំហានទី ៣',
                                    'Please retake or choose a real street-issue photo before continuing to Step 3.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.saffronInk,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ] else if (isTransientAiFailure) ...[
                              Semantics(
                                container: true,
                                liveRegion: true,
                                child: Text(
                                  vm.photoAi.status == PhotoAiStatus.rateLimited
                                      ? tr.primary(
                                          'AI កំពុងពេញកូតាបណ្តោះអាសន្ន — សូមសាកល្បងម្តងទៀត ឬរក្សាទុកសេចក្តីព្រាង',
                                          'AI quota is temporarily full — retry or save as a draft for later.',
                                        )
                                      : tr.primary(
                                          'មិនទាន់អាចពិនិត្យរូបភាពដោយ AI បានទេ — សូមសាកល្បងម្តងទៀត ឬរក្សាទុកសេចក្តីព្រាង',
                                          'Could not verify photo with AI — retry or save as a draft.',
                                        ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.saffronInk,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton.icon(
                                    key: const Key('step2-footer-retry-ai-btn'),
                                    onPressed: () => unawaited(
                                      vm.analyzeLatestPhoto(forceRefresh: true),
                                    ),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      tapTargetSize:
                                          MaterialTapTargetSize.padded,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      tr.primary('ពិនិត្យម្តងទៀត', 'Retry'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    key: const Key(
                                      'step2-footer-save-draft-btn',
                                    ),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      vm.saveDraft();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                tr.primary(
                                                  'បានរក្សាទុកសេចក្តីព្រាង! សូមបន្តផ្ញើពីទំព័រដើមពេលក្រោយ។',
                                                  'Draft saved! Resume from Home when AI is available.',
                                                ),
                                              ),
                                            ),
                                          );
                                      Navigator.pop(context);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      tapTargetSize:
                                          MaterialTapTargetSize.padded,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      foregroundColor: AppColors.saffronInk,
                                      side: BorderSide(
                                        color: AppColors.saffronInk.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.save_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      tr.primary(
                                        'រក្សាទុកសេចក្តីព្រាង',
                                        'Save draft',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                key: const Key('step2-confirm-location-btn'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: canProceedToStep3
                                    ? () async {
                                        HapticFeedback.selectionClick();
                                        await vm.stopVoiceRecordingIfActive();
                                        if (!mounted ||
                                            !vm.hasRequiredPhoto ||
                                            vm.isPhotoAiBlockedForNextStep) {
                                          return;
                                        }
                                        vm.nextStep();
                                        _reverseGeocodeCurrentPin(
                                          vm.pinLocation,
                                        );
                                        _maybeTriggerAutoGps(tr);
                                      }
                                    : null,
                                child: Text(
                                  tr.paired(
                                    'បន្ទាប់ · បញ្ជាក់ទីតាំង',
                                    'Next · Confirm location',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep2AiCard(
    ReportWizardViewModel vm,
    AiClassificationResult textAi,
    Bilingual tr,
  ) {
    final photoAi = vm.photoAi;
    final hasPhoto = vm.localPhotoPaths.isNotEmpty;
    final isWarning =
        photoAi.status == PhotoAiStatus.notCivicIssue ||
        photoAi.status == PhotoAiStatus.rateLimited;

    final cardColor = isWarning ? AppColors.saffronSoft : AppColors.tealSoft;
    final borderColor = isWarning
        ? AppColors.saffronInk.withValues(alpha: 0.55)
        : AppColors.teal.withValues(alpha: 0.25);

    Widget buildEyebrow() {
      if (photoAi.status == PhotoAiStatus.analyzing) {
        return Row(
          children: [
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tr.primary(
                  'AI កំពុងវិភាគរូបភាព និងការពិពណ៌នា...',
                  'AI analyzing photo & description...',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.teal,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      }

      if (photoAi.hasDetectedIssue) {
        return Row(
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: AppColors.teal),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${tr.primary('AI បានរកឃើញ', 'AI detected')} · ${photoAi.confidencePercent ?? 90}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.teal,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      }

      if (photoAi.status == PhotoAiStatus.notCivicIssue) {
        return Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: AppColors.saffronInk,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                tr.primary(
                  'រូបភាពប្រហែលមិនមែនជាបញ្ហាផ្លូវទេ',
                  'Photo may not show a street/civic issue',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.saffronInk,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      }

      if (photoAi.status == PhotoAiStatus.rateLimited) {
        return Row(
          children: [
            const Icon(
              Icons.hourglass_top_rounded,
              size: 14,
              color: AppColors.saffronInk,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                tr.primary(
                  'សេវា AI កំពុងមមាញឹកបណ្តោះអាសន្ន',
                  'AI service is busy — try again shortly',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.saffronInk,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      }

      if (textAi.matchedFromText) {
        return Row(
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: AppColors.teal),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${tr.primary('ណែនាំតាមការពិពណ៌នា', 'Matched from description')} · ${textAi.confidencePercent}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.teal,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      }

      return Row(
        children: [
          const Icon(Icons.category_outlined, size: 14, color: AppColors.teal),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              tr.paired('ប្រភេទបញ្ហាដែលបានជ្រើស', 'Selected issue category'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.teal,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    }

    final detailLine = switch (photoAi.status) {
      PhotoAiStatus.analyzed => tr.primary(
        photoAi.khmerReason ?? 'វិភាគពីរូបភាពពិតដោយប្រព័ន្ធ AI',
        photoAi.englishReason ?? 'Classified automatically from your photo',
      ),
      PhotoAiStatus.notCivicIssue => tr.primary(
        photoAi.khmerReason ?? 'សូមថតរូបបញ្ហាផ្លូវឱ្យច្បាស់ ឬជ្រើសប្រភេទដោយដៃ',
        photoAi.englishReason ??
            'Please retake a clear street photo or pick a category manually.',
      ),
      PhotoAiStatus.offline => tr.primary(
        'គ្មានអ៊ីនធឺណិត — សូមជ្រើសប្រភេទបញ្ហាដោយដៃ',
        'Offline — pick an issue category manually.',
      ),
      PhotoAiStatus.awaitingBackend => tr.primary(
        'AI វិភាគរូបភាពស្វ័យប្រវត្តិត្រៀមដំណើរការជាមួយប្រព័ន្ធ Backend',
        'Automatic photo AI classification activates once backend connects.',
      ),
      PhotoAiStatus.failed => tr.primary(
        'មិនអាចវិភាគរូបភាពបានទេ — សូមជ្រើសប្រភេទដោយដៃ ឬសាកម្តងទៀត',
        photoAi.errorMessage ??
            'Could not analyze photo — retry or pick manually.',
      ),
      _ => null,
    };

    return Container(
      key: const Key('step2-ai-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildEyebrow(),
                    const SizedBox(height: 6),
                    BilingualText(
                      bilingual: tr,
                      khmer: vm.category.defaultKhmerTitle,
                      english: vm.category.defaultEnglishTitle,
                      fontSize: 15,
                    ),
                  ],
                ),
              ),
              if (textAi.matchedFromText &&
                  textAi.category != vm.category &&
                  !photoAi.hasDetectedIssue)
                TextButton(
                  onPressed: vm.applyAiSuggestedCategory,
                  child: Text(
                    tr.primary(
                      'ប្រើ ${textAi.category.khmerName}',
                      'Use ${textAi.category.englishName}',
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: () => _showCategoryPickerSheet(vm, tr),
                  child: Text(
                    tr.paired('កែ', 'Change'),
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (detailLine != null) ...[
            const SizedBox(height: 6),
            Text(
              detailLine,
              style: TextStyle(
                fontSize: 11.5,
                color: isWarning ? AppColors.saffronInk : AppColors.muted,
              ),
            ),
          ],
          if (hasPhoto &&
              vm.isBackendAiAvailable &&
              (photoAi.status == PhotoAiStatus.analyzed ||
                  photoAi.status == PhotoAiStatus.notCivicIssue ||
                  photoAi.status == PhotoAiStatus.rateLimited ||
                  photoAi.status == PhotoAiStatus.failed)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (photoAi.status == PhotoAiStatus.notCivicIssue)
                  ActionChip(
                    key: const Key('step2-retake-photo-chip'),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    avatar: const Icon(
                      Icons.add_a_photo_outlined,
                      size: 14,
                      color: AppColors.saffronInk,
                    ),
                    label: Text(
                      tr.primary('ថត ឬជ្រើសរូបថ្មី', 'Retake / change photo'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.saffronInk,
                      ),
                    ),
                    onPressed: () {
                      vm.removeLocalPhotoAt(0);
                      vm.previousStep();
                    },
                  ),
                ActionChip(
                  key: const Key('step2-rescan-ai-chip'),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  avatar: const Icon(
                    Icons.refresh_rounded,
                    size: 14,
                    color: AppColors.teal,
                  ),
                  label: Text(
                    tr.primary(
                      'វិភាគរូបភាព និងអក្សរម្តងទៀត',
                      'Re-scan photo & note',
                    ),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () =>
                      unawaited(vm.analyzeLatestPhoto(forceRefresh: true)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceNoteCard(ReportWizardViewModel vm, Bilingual tr) {
    final isActive = vm.isRecordingVoice || vm.isTranscribingVoice;
    final hasFeedback =
        vm.voiceFeedbackKhmer != null || vm.voiceFeedbackEnglish != null;
    final isOffline = !vm.repository.isOnline;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    String modePillLabel() => switch (vm.voiceMode) {
      VoiceCaptureMode.backendAudio => 'AI Voice',
      VoiceCaptureMode.deviceSpeech => tr.primary('ផ្ទាល់', 'Live'),
      VoiceCaptureMode.demoFallback => tr.primary('សាកល្បង', 'Demo'),
    };

    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      key: const Key('voice-note-card'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: vm.isRecordingVoice ? AppColors.dangerSoft : AppColors.tealSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: vm.isRecordingVoice
              ? AppColors.danger.withValues(alpha: 0.4)
              : AppColors.teal.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Telegram-style Hold-to-Speak OR Tap-to-Toggle mic button
              Semantics(
                button: true,
                excludeSemantics: true,
                label: vm.isRecordingVoice
                    ? tr.primary('បញ្ឈប់ការថតសំឡេង', 'Stop voice recording')
                    : tr.primary('ចាប់ផ្តើមថតសំឡេង', 'Start voice recording'),
                hint: tr.primary(
                  'ចុច ឬសង្កត់ដើម្បីនិយាយ',
                  'Tap or press and hold to speak',
                ),
                child: Tooltip(
                  message: vm.isRecordingVoice
                      ? tr.primary('បញ្ឈប់ការថតសំឡេង', 'Stop recording')
                      : tr.primary('ថតសំឡេង', 'Record voice note'),
                  child: GestureDetector(
                    key: const Key('voice-record-btn'),
                    onTap: (vm.isInitializingVoice || vm.isTranscribingVoice)
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            unawaited(vm.toggleVoiceRecording());
                          },
                    onLongPressStart:
                        (vm.isInitializingVoice ||
                            vm.isRecordingVoice ||
                            vm.isTranscribingVoice)
                        ? null
                        : (_) {
                            HapticFeedback.heavyImpact();
                            unawaited(vm.startHoldVoiceRecording());
                          },
                    onLongPressEnd: (_) {
                      if (vm.isHoldRecording) {
                        HapticFeedback.selectionClick();
                        unawaited(vm.finishHoldVoiceRecording());
                      }
                    },
                    onLongPressCancel: () {
                      if (vm.isHoldRecording) {
                        unawaited(vm.cancelHoldVoiceRecording());
                      }
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: vm.isRecordingVoice
                          ? AppColors.danger
                          : AppColors.teal,
                      child: (vm.isInitializingVoice || vm.isTranscribingVoice)
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              vm.isRecordingVoice
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vm.isTranscribingVoice
                                ? tr.primary(
                                    'AI កំពុងបំប្លែងសំឡេង...',
                                    'AI transcribing audio...',
                                  )
                                : vm.isRecordingVoice
                                ? tr.primary(
                                    vm.voicePreferEnglish
                                        ? 'កំពុងស្តាប់ភាសាអង់គ្លេស... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}'
                                        : 'កំពុងស្តាប់ភាសាខ្មែរ... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}',
                                    vm.voicePreferEnglish
                                        ? 'Listening in English... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}'
                                        : 'Listening in Khmer... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}',
                                  )
                                : tr.primary(
                                    'រាយការណ៍ជាសំឡេង (សង្កត់ ឬចុច)',
                                    'Voice-to-Text (Hold or Tap)',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: vm.isRecordingVoice
                                  ? AppColors.danger
                                  : AppColors.tealDark,
                            ),
                          ),
                        ),
                        if (!isActive && isOffline) ...[
                          const SizedBox(width: 6),
                          Container(
                            key: const Key('voice-offline-badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.ink,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tr.primary('ក្រៅបណ្តាញ', 'Offline'),
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.saffron,
                              ),
                            ),
                          ),
                        ],
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            key: const Key('voice-mode-pill'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  vm.voiceMode == VoiceCaptureMode.demoFallback
                                  ? AppColors.saffronSoft
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${modePillLabel()} · ${vm.voicePreferEnglish ? 'EN' : 'ខ្មែរ'}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color:
                                    vm.voiceMode ==
                                        VoiceCaptureMode.demoFallback
                                    ? AppColors.saffronInk
                                    : AppColors.tealDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Clear 2-option voice recognition language selector (Khmer | EN)
                    Row(
                      children: [
                        Container(
                          key: const Key('voice-lang-toggle'),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.teal.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _VoiceLangOption(
                                key: const Key('voice-lang-km'),
                                label: 'ខ្មែរ',
                                selected: !vm.voicePreferEnglish,
                                enabled: !isActive,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  vm.setVoicePreferEnglish(false);
                                },
                              ),
                              _VoiceLangOption(
                                key: const Key('voice-lang-en'),
                                label: 'EN',
                                selected: vm.voicePreferEnglish,
                                enabled: !isActive,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  vm.setVoicePreferEnglish(true);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            vm.voicePreferEnglish
                                ? tr.primary(
                                    'ភាសាសំឡេង៖ អង់គ្លេស (EN)',
                                    'Voice: English (EN)',
                                  )
                                : tr.primary(
                                    'ភាសាសំឡេង៖ ខ្មែរ (km-KH)',
                                    'Voice: Khmer (ខ្មែរ)',
                                  ),
                            key: const Key('voice-active-lang-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.tealDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (vm.voiceTranscript != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        vm.voiceTranscript!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (vm.isRecordingVoice)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: VoiceWaveform(soundLevel: vm.voiceSoundLevel),
                )
              else if (vm.voiceTranscript != null)
                IconButton(
                  tooltip: tr.primary('លុបអត្ថបទសំឡេង', 'Clear voice note'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: vm.clearVoiceTranscript,
                ),
            ],
          ),
          if (hasFeedback) ...[
            const SizedBox(height: 10),
            Semantics(
              container: true,
              liveRegion: true,
              child: Container(
                key: const Key('voice-feedback-box'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.saffronSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.saffron.withValues(alpha: 0.55),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: AppColors.saffronInk,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tr.primary(
                              vm.voiceFeedbackKhmer ?? '',
                              vm.voiceFeedbackEnglish ?? '',
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.saffronInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (vm.showVoiceDemoFallbackAction) ...[
                      const SizedBox(height: 6),
                      ActionChip(
                        key: const Key('voice-try-sample-btn'),
                        avatar: const Icon(
                          Icons.graphic_eq_rounded,
                          size: 14,
                          color: AppColors.teal,
                        ),
                        label: Text(
                          tr.primary('សាកល្បងសំឡេង', 'Try Sample'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          vm.runSampleVoiceDemo();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Screen 2.3: Grab-Style Full-Bleed Cambodia-Bounded Map with Centered
  /// Draggable Crosshair Pin, Unified Strict 150 m Detection & Adjustment Zone,
  /// Multi-Incident Picker, and Out-of-Range Return Navigation.
  Widget _buildFullBleedLocationStep(
    ReportWizardViewModel vm,
    List<CivicReport> allReports,
    Bilingual tr,
  ) {
    final similarMatches = vm.nearbySimilarReports;
    final selectedMatch = vm.selectedMasterMatch;
    final routing = vm.gisRouting;
    final priority = vm.estimatedPriority;
    final activeZone = vm.activeZoneAnchor;
    final isOutOfZone = vm.isOutside150mZone;
    final matchingIds = {for (final m in similarMatches) m.masterReport.id};
    final categoryLabel = tr.primary(
      vm.category.khmerName,
      vm.category.englishName,
    );
    final outOfZoneDistLabel = vm.distanceOutsideZoneMeters != null
        ? SupportEligibilityService.formatDistance(
            vm.distanceOutsideZoneMeters!,
            englishFirst: tr.englishFirst,
          )
        : null;

    final Color zoneColor = isOutOfZone
        ? AppColors.danger
        : similarMatches.isNotEmpty
        ? AppColors.priorityColor(4)
        : AppColors.teal;

    const sheetCornerRadius = 24.0;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final hasSimilar = similarMatches.isNotEmpty;
    final hasSecondarySelfBtn =
        hasSimilar &&
        !vm.isCreatingNewDespiteMatches &&
        selectedMatch != null &&
        selectedMatch.masterReport.isContributedByCurrentUser &&
        vm.isHardSelfBlockedAtPin;
    final textScale = MediaQuery.textScalerOf(context)
        .scale(1.0)
        .clamp(1.0, 2.0);
    final extraOfflineCaption = vm.requiresOfflineDraftOnly
        ? 36.0 * textScale
        : 0.0;
    final maxCollapsed = math.max(122.0, screenHeight * 0.42);
    final collapsedHeight =
        (122.0 * (1.0 + (textScale - 1.0) * 0.45) + extraOfflineCaption).clamp(
          122.0,
          maxCollapsed,
        ) +
        bottomInset;
    final double baseExpandedHeight = hasSimilar
        ? (screenHeight * (hasSecondarySelfBtn ? 0.48 : 0.44)).clamp(
            hasSecondarySelfBtn ? 310.0 : 275.0,
            hasSecondarySelfBtn ? 426.0 : 388.0,
          )
        : (vm.locationEligibility is! ReportLocationEligible
              ? (screenHeight * 0.38).clamp(254.0, 326.0)
              : (screenHeight * 0.30).clamp(218.0, 266.0));
    final maxExpanded = math.max(collapsedHeight + 48.0, screenHeight * 0.68);
    final expandedHeight =
        (baseExpandedHeight * (1.0 + (textScale - 1.0) * 0.25) +
                extraOfflineCaption)
            .clamp(collapsedHeight + 48.0, maxExpanded) +
        bottomInset;

    // Built once and passed via AnimatedBuilder.child so map tiles never
    // rebuild while the collapsible bottom sheet glides smoothly at 60 FPS.
    final Widget mapViewport = Stack(
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: tr.primary(
            'ផែនទីកំណត់ទីតាំងបញ្ហា · អូសដើម្បីផ្លាស់ទីម្ជុលក្នុងរង្វង់ 150m',
            'Issue location map, drag to position pin within 150 m zone',
          ),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: vm.pinLocation,
              initialZoom: MapTileConfig.streetFocusZoom,
              minZoom: LocationService.minMapZoom,
              maxZoom: LocationService.maxMapZoom,
              backgroundColor: MapTileConfig.mapBackgroundColor,
              cameraConstraint: CameraConstraint.contain(
                bounds: LocationService.cambodiaMapBounds,
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () => _mapReady = true,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  _onMapDragged(camera.center);
                }
              },
              onTap: (_, point) {
                HapticFeedback.selectionClick();
                if (_mapReady) {
                  _mapController.move(point, _mapController.camera.zoom);
                }
                vm.setPinLocation(point, verified: true, fromLiveGps: false);
                _reverseGeocodeCurrentPin(point);
              },
            ),
            children: [
              ExcludeSemantics(child: MapTileConfig.buildTileLayer()),
              ExcludeSemantics(
                child: CircleLayer(
                  circles: [
                    if (activeZone != null)
                      CircleMarker(
                        point: activeZone.point,
                        radius: ReportLocationEligibilityService
                            .maxZoneRadiusMeters,
                        useRadiusInMeter: true,
                        color: zoneColor.withValues(
                          alpha: isOutOfZone ? 0.14 : 0.12,
                        ),
                        borderColor: zoneColor.withValues(
                          alpha: isOutOfZone ? 0.92 : 0.80,
                        ),
                        borderStrokeWidth: isOutOfZone ? 2.4 : 2.0,
                      ),
                  ],
                ),
              ),
              MarkerLayer(
                markers: allReports
                    .where(
                      (r) =>
                          r.status != ReportStatus.resolved &&
                          r.syncStatus != SyncStatus.rejectedByAi &&
                          (vm.showAllCategoriesOnStep3 ||
                              r.category == vm.category),
                    )
                    .map((existing) {
                      final isCandidate = matchingIds.contains(existing.id);
                      final isSelectedCandidate =
                          selectedMatch?.masterReport.id == existing.id;
                      final markerDiameter = isSelectedCandidate
                          ? 38.0
                          : isCandidate
                          ? 34.0
                          : 24.0;
                      final markerWidget = Container(
                        key: Key('step3-report-pin-${existing.id}'),
                        width: markerDiameter,
                        height: markerDiameter,
                        padding: const EdgeInsets.all(2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.priorityColor(
                            existing.priority.level,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelectedCandidate
                                ? AppColors.tealDark
                                : Colors.white,
                            width: isSelectedCandidate
                                ? 3
                                : isCandidate
                                ? 2
                                : 1.5,
                          ),
                          boxShadow: isCandidate ? AppColors.cardShadow : null,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${existing.affectedCitizens}',
                            style: AppFonts.displayStyle(
                              color: AppColors.priorityForeground(
                                existing.priority.level,
                              ),
                              fontSize: isSelectedCandidate
                                  ? 11
                                  : isCandidate
                                  ? 10
                                  : 9,
                            ),
                          ),
                        ),
                      );

                      return Marker(
                        point: existing.coordinates,
                        width: isCandidate ? 48 : 28,
                        height: isCandidate ? 48 : 28,
                        child: isCandidate
                            ? Semantics(
                                button: true,
                                selected: isSelectedCandidate,
                                excludeSemantics: true,
                                label: tr.primary(
                                  'ជ្រើសរបាយការណ៍ ${existing.id} · ${existing.category.khmerName} · P${existing.priority.level} · ${existing.affectedCitizens} នាក់',
                                  'Select similar report ${existing.id}, ${existing.category.englishName}, P${existing.priority.level}, ${existing.affectedCitizens} citizens',
                                ),
                                hint: tr.primary(
                                  'ចុចដើម្បីជ្រើសរើស',
                                  'Tap to select',
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    vm.selectMasterReport(existing.id);
                                    if (_step3SheetController.value < 0.5) {
                                      _setStep3SheetExpanded(true);
                                    }
                                  },
                                  child: Center(child: markerWidget),
                                ),
                              )
                            : ExcludeSemantics(
                                child: Center(
                                  child: Opacity(
                                    opacity: 0.55,
                                    child: markerWidget,
                                  ),
                                ),
                              ),
                      );
                    })
                    .toList(growable: false),
              ),
              if (vm.otherSavedDraftsWithPin.isNotEmpty)
                MarkerLayer(
                  markers: vm.otherSavedDraftsWithPin
                      .map((savedDraft) {
                        final point = savedDraft.effectivePinLocation!;
                        final isSameCategory =
                            savedDraft.category == vm.category;
                        final note = savedDraft.description.trim();
                        final noteSuffix = note.isNotEmpty ? ' · $note' : '';
                        final pinBadge = Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: isSameCategory
                                ? AppColors.saffron
                                : AppColors.saffronSoft,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSameCategory
                                  ? Colors.white
                                  : AppColors.saffronInk,
                              width: isSameCategory ? 2.5 : 1.8,
                            ),
                            boxShadow: AppColors.cardShadow,
                          ),
                          child: const Icon(
                            Icons.edit_note_rounded,
                            size: 18,
                            color: AppColors.saffronInk,
                          ),
                        );
                        return Marker(
                          point: point,
                          width: 48,
                          height: 48,
                          child: Semantics(
                            button: true,
                            excludeSemantics: true,
                            label: tr.primary(
                              'សេចក្តីព្រាងបានរក្សាទុក · ${savedDraft.category.khmerName}$noteSuffix',
                              'Saved draft · ${savedDraft.category.englishName}$noteSuffix',
                            ),
                            hint: tr.primary(
                              'ចុចដើម្បីមើលព័ត៌មានសេចក្តីព្រាង',
                              'Tap to preview saved draft',
                            ),
                            child: GestureDetector(
                              key: Key('step3-draft-pin-${savedDraft.id}'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      tr.primary(
                                        'សេចក្តីព្រាងបានរក្សាទុក · ${savedDraft.category.khmerName}$noteSuffix',
                                        'Saved draft · ${savedDraft.category.englishName}$noteSuffix',
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Center(child: pinBadge),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              MapTileConfig.buildAttributionBadge(
                bottomPadding: sheetCornerRadius + 6,
              ),
            ],
          ),
        ),

        // Centered Grab-Style Crosshair Pin (always inside unobstructed map)
        IgnorePointer(
          child: Center(
            child: Builder(
              builder: (context) {
                final pinDuration = MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 140);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: pinDuration,
                      transform: Matrix4.translationValues(
                        0,
                        _isDraggingMap ? -28 : -20,
                        0,
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: isOutOfZone ? AppColors.danger : AppColors.teal,
                        size: 46,
                      ),
                    ),
                    AnimatedContainer(
                      duration: pinDuration,
                      width: _isDraggingMap ? 12 : 8,
                      height: _isDraggingMap ? 6 : 4,
                      decoration: BoxDecoration(
                        color: AppColors.ink.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // Floating Top Header Pill
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: IconButton(
                        tooltip: tr.primary('ថយក្រោយ', 'Back'),
                        icon: const Icon(Icons.arrow_back),
                        onPressed: vm.previousStep,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isDraggingMap
                                  ? tr.primary(
                                      'កំពុងជ្រើសទីតាំង...',
                                      'Moving pin...',
                                    )
                                  : tr.primary(
                                      routing.khmerRoadName,
                                      routing.englishRoadName,
                                    ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: AppColors.ink,
                              ),
                            ),
                            Semantics(
                              container: true,
                              liveRegion: true,
                              child: Row(
                                children: [
                                  Icon(
                                    isOutOfZone
                                        ? Icons.wrong_location_outlined
                                        : activeZone != null
                                        ? Icons.verified_rounded
                                        : Icons.gps_not_fixed_rounded,
                                    size: 13,
                                    color: isOutOfZone
                                        ? AppColors.danger
                                        : AppColors.teal,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      isOutOfZone
                                          ? tr.primary(
                                              'នៅក្រៅរង្វង់ 150m (${outOfZoneDistLabel ?? ''})',
                                              'Outside 150 m zone (${outOfZoneDistLabel ?? ''})',
                                            )
                                          : activeZone != null
                                          ? (hasSimilar
                                                ? tr.primary(
                                                    'រង្វង់ 150m · រកឃើញ ${similarMatches.length} របាយការណ៍ $categoryLabel',
                                                    '150 m zone · ${similarMatches.length} $categoryLabel report(s) nearby',
                                                  )
                                                : tr.primary(
                                                    'រង្វង់ 150m · មិនមានរបាយការណ៍ $categoryLabel នៅក្បែរទេ',
                                                    '150 m zone · No $categoryLabel reports nearby',
                                                  ))
                                          : tr.primary(
                                              'ត្រូវការ GPS ដើម្បីបើករង្វង់ 150m',
                                              'GPS required to unlock 150 m zone',
                                            ),
                                      maxLines: 2,
                                      softWrap: true,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: isOutOfZone
                                            ? AppColors.danger
                                            : AppColors.teal,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      heroTag: 'wizard-locate',
                      tooltip: vm.activeFreshPhotoAnchor != null
                          ? tr.primary(
                              'ត្រឡប់ទៅរង្វង់ 150m',
                              'Return to 150 m zone',
                            )
                          : tr.primary(
                              'ផ្ទៀងផ្ទាត់ទីតាំង GPS',
                              'Verify GPS location',
                            ),
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.white,
                      onPressed: vm.isLocating
                          ? null
                          : () {
                              if (vm.activeFreshPhotoAnchor != null) {
                                _returnTo150mZone(vm);
                              } else {
                                unawaited(_verifyGpsLocation(tr));
                              }
                            },
                      child: vm.isLocating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.my_location),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          button: true,
                          toggled: vm.showAllCategoriesOnStep3,
                          excludeSemantics: true,
                          label: vm.showAllCategoriesOnStep3
                              ? tr.primary(
                                  'កំពុងបង្ហាញគ្រប់ប្រភេទ · ចុចដើម្បីបង្ហាញតែ $categoryLabel',
                                  'Showing all types, tap to show $categoryLabel only',
                                )
                              : tr.primary(
                                  'កំពុងបង្ហាញតែ $categoryLabel · ចុចដើម្បីបង្ហាញគ្រប់ប្រភេទ',
                                  'Showing $categoryLabel only, tap to show all types',
                                ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const Key('step3-category-filter-pill'),
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                vm.toggleShowAllCategoriesOnStep3();
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                  minWidth: 48,
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: vm.showAllCategoriesOnStep3
                                          ? AppColors.tealDark
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: vm.showAllCategoriesOnStep3
                                            ? AppColors.tealDark
                                            : AppColors.teal,
                                      ),
                                      boxShadow: AppColors.cardShadow,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          vm.showAllCategoriesOnStep3
                                              ? Icons.layers_rounded
                                              : Bilingual.categoryIcon(
                                                  vm.category,
                                                ),
                                          size: 14,
                                          color: vm.showAllCategoriesOnStep3
                                              ? Colors.white
                                              : AppColors.tealDark,
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            vm.showAllCategoriesOnStep3
                                                ? tr.primary(
                                                    'គ្រប់ប្រភេទ',
                                                    'All types',
                                                  )
                                                : tr.primary(
                                                    'បង្ហាញតែ៖ $categoryLabel',
                                                    '$categoryLabel only',
                                                  ),
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: vm.showAllCategoriesOnStep3
                                                  ? Colors.white
                                                  : AppColors.tealDark,
                                            ),
                                          ),
                                        ),
                                        if (!vm.showAllCategoriesOnStep3) ...[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.layers_outlined,
                                            size: 13,
                                            color: AppColors.tealDark,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (vm.otherSavedDraftsWithPin.isNotEmpty)
                          Container(
                            key: const Key('step3-draft-pins-legend'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.saffronSoft,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.saffronInk.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                              boxShadow: AppColors.cardShadow,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.edit_note_rounded,
                                  size: 14,
                                  color: AppColors.saffronInk,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    tr.primary(
                                      '${vm.otherSavedDraftsWithPin.length} សេចក្តីព្រាងបានរក្សាទុក',
                                      '${vm.otherSavedDraftsWithPin.length} saved draft pin(s)',
                                    ),
                                    softWrap: true,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.saffronInk,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!vm.repository.isOnline)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: AppColors.saffron,
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr.primary(
                              'គ្មានអ៊ីនធឺណិត — GPS និងរបាយការណ៍នឹងរក្សាទុកក្នុងឧបករណ៍ និងផ្ញើស្វ័យប្រវត្តិពេលមានសេវា',
                              'Offline — GPS pin & report save locally and auto-sync when online',
                            ),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.paper,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (vm.isOutsideCambodia &&
                    vm.rawOutsideGps != null &&
                    vm.locationEligibility is! ReportLocationEligible)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.saffronSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.saffron.withValues(alpha: 0.6),
                      ),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.public_off_outlined,
                          color: AppColors.saffronInk,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr.primary(
                              'GPS ឧបករណ៍នៅក្រៅកម្ពុជា (${vm.rawOutsideGps!.latitude.toStringAsFixed(2)}, ${vm.rawOutsideGps!.longitude.toStringAsFixed(2)}) — ត្រូវការ GPS ក្នុងកម្ពុជា ឬរូបថតមាន EXIF នៅកម្ពុជា',
                              'Device GPS outside Cambodia (${vm.rawOutsideGps!.latitude.toStringAsFixed(2)}, ${vm.rawOutsideGps!.longitude.toStringAsFixed(2)}) — Cambodia GPS or geotagged photo required',
                            ),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.saffronInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Floating Out-of-Range Return Pill anchored cleanly above the sheet's
        // rounded top edge and clear of the © OpenStreetMap badge.
        if (isOutOfZone)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: sheetCornerRadius + 30),
              child: FilledButton.icon(
                key: const Key('step3-floating-return-zone-btn'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: const StadiumBorder(),
                  elevation: 4,
                ),
                onPressed: () => _returnTo150mZone(vm),
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(
                  tr.primary(
                    outOfZoneDistLabel != null
                        ? 'ត្រឡប់ទៅរង្វង់ 150m ($outOfZoneDistLabel)'
                        : 'ត្រឡប់ទៅរង្វង់ 150m',
                    outOfZoneDistLabel != null
                        ? 'Return to 150 m zone ($outOfZoneDistLabel)'
                        : 'Return to 150 m zone',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: MapTileConfig.mapBackgroundColor,
      body: AnimatedBuilder(
        animation: _step3SheetController,
        child: mapViewport,
        builder: (context, mapChild) {
          final t = _step3SheetCurve.value;
          final currentSheetHeight =
              collapsedHeight + (expandedHeight - collapsedHeight) * t;
          final isExpanded = _step3SheetController.value >= 0.5;
          final contentOpacity = ((t - 0.15) / 0.85).clamp(0.0, 1.0);

          return Stack(
            children: [
              // 1. Live Map extending 24 dp behind the rounded top corners of
              //    the bottom sheet -> ZERO gray/beige corner gaps while keeping
              //    the crosshair pin & 150 m zone dead-center in the visible map.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: (currentSheetHeight - sheetCornerRadius).clamp(
                  0.0,
                  double.infinity,
                ),
                child: mapChild!,
              ),

              // 2. Interactive 1:1 Draggable & Smoothly Animated Bottom Sheet
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: currentSheetHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(sheetCornerRadius),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.12),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Column(
                          children: [
                            // Drag handle + 1-tap smooth Collapse/Expand toggle
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragUpdate: (details) {
                                final dragSpan =
                                    (expandedHeight - collapsedHeight).clamp(
                                      1.0,
                                      double.infinity,
                                    );
                                _step3SheetController.value =
                                    (_step3SheetController.value -
                                            (details.primaryDelta ?? 0) /
                                                dragSpan)
                                        .clamp(0.0, 1.0);
                              },
                              onVerticalDragEnd: (details) {
                                final velocity = details.primaryVelocity ?? 0;
                                if (velocity > 180) {
                                  HapticFeedback.selectionClick();
                                  _setStep3SheetExpanded(false);
                                } else if (velocity < -180) {
                                  HapticFeedback.selectionClick();
                                  _setStep3SheetExpanded(true);
                                } else {
                                  _setStep3SheetExpanded(
                                    _step3SheetController.value >= 0.5,
                                  );
                                }
                              },
                              child: Semantics(
                                button: true,
                                expanded: isExpanded,
                                excludeSemantics: true,
                                label:
                                    '${hasSimilar ? tr.primary('របាយការណ៍ $categoryLabel ក្នុង 150m (${similarMatches.length})', 'Nearby $categoryLabel reports (${similarMatches.length})') : tr.primary(routing.khmerAgency, routing.englishAgency)} · ${isExpanded ? tr.primary('បង្រួមផ្ទាំងដើម្បីមើលផែនទីពេញ', 'Collapse panel to view more map') : tr.primary('បង្ហាញព័ត៌មានទីតាំង និងជម្រើសបញ្ជូន', 'Expand location panel')}',
                                child: InkWell(
                                  key: const Key('step3-sheet-toggle'),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(sheetCornerRadius),
                                  ),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    _setStep3SheetExpanded(!isExpanded);
                                  },
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: AppColors.inputBorder,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            if (hasSimilar) ...[
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.saffronSoft,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.radar_rounded,
                                                  color: AppColors.saffronInk,
                                                  size: 15,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  tr.primary(
                                                    'របាយការណ៍ $categoryLabel ក្នុង 150m (${similarMatches.length})',
                                                    'Nearby $categoryLabel reports (${similarMatches.length})',
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.ink,
                                                  ),
                                                ),
                                              ),
                                            ] else ...[
                                              const Icon(
                                                Icons.account_balance_outlined,
                                                size: 16,
                                                color: AppColors.teal,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  tr.primary(
                                                    routing.khmerAgency,
                                                    routing.englishAgency,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                    color: AppColors.ink,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              PriorityBadge(
                                                breakdown: priority,
                                                bilingual: tr,
                                                compact: true,
                                              ),
                                            ],
                                            const SizedBox(width: 6),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  isExpanded
                                                      ? tr.primary(
                                                          'ផែនទី',
                                                          'Map',
                                                        )
                                                      : tr.primary(
                                                          'បង្ហាញ',
                                                          'Show',
                                                        ),
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.tealDark,
                                                  ),
                                                ),
                                                Transform.rotate(
                                                  angle: (1.0 - t) * math.pi,
                                                  child: const Icon(
                                                    Icons
                                                        .keyboard_arrow_down_rounded,
                                                    size: 20,
                                                    color: AppColors.tealDark,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Smoothly fading & resizing scrollable body
                            Expanded(
                              child: ClipRect(
                                child: ExcludeSemantics(
                                  excluding: t < 0.5,
                                  child: ExcludeFocus(
                                    excluding: t < 0.5,
                                    child: IgnorePointer(
                                      ignoring: t < 0.35,
                                      child: Opacity(
                                        opacity: contentOpacity,
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            2,
                                            16,
                                            8,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (vm.nearbySimilarSavedDraft !=
                                                  null) ...[
                                                Semantics(
                                                  container: true,
                                                  liveRegion: true,
                                                  child: Container(
                                                    key: const Key(
                                                      'step3-nearby-draft-warning',
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 8,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppColors.saffronSoft,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      border: Border.all(
                                                        color: AppColors
                                                            .saffronInk
                                                            .withValues(
                                                              alpha: 0.55,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .edit_note_rounded,
                                                          size: 16,
                                                          color: AppColors
                                                              .saffronInk,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            tr.primary(
                                                              'អ្នកមានសេចក្តីព្រាង ${vm.nearbySimilarSavedDraft!.draft.category.khmerName} នៅក្បែរនេះ (${vm.nearbySimilarSavedDraft!.distanceMeters.round()} ម៉ែត្រ)',
                                                              'You already saved a ${vm.nearbySimilarSavedDraft!.draft.category.englishName} draft nearby (${vm.nearbySimilarSavedDraft!.distanceMeters.round()} m away)',
                                                            ),
                                                            style: const TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: AppColors
                                                                  .saffronInk,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                              ],
                                              if (hasSimilar)
                                                _buildStep3SimilarReportsList(
                                                  vm: vm,
                                                  matches: similarMatches,
                                                  selectedMatch: selectedMatch,
                                                  tr: tr,
                                                )
                                              else
                                                Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '${tr.primary(routing.fullKhmerLocation, routing.fullEnglishLocation)} · ${tr.roadClassLabel(routing.roadClass)} · ODC GIS',
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: AppColors.muted,
                                                        fontSize: 11.5,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    _buildLocationEligibilitySection(
                                                      vm,
                                                      tr,
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Pinned Primary CTA Footer
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: _buildStep3PrimaryActionFooter(
                                vm: vm,
                                hasSimilar: hasSimilar,
                                selectedMatch: selectedMatch,
                                priority: priority,
                                expandFactor: t,
                                tr: tr,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Renders the scrollable list of similar open Master Incidents within 150 m
  /// plus the "+ Submit as a new separate report here" option and zone status.
  Widget _buildStep3SimilarReportsList({
    required ReportWizardViewModel vm,
    required List<DuplicateMatch> matches,
    required DuplicateMatch? selectedMatch,
    required Bilingual tr,
  }) {
    final isCreatingNew = vm.isCreatingNewDespiteMatches;
    final hardSelfBlocked = vm.isHardSelfBlockedAtPin;

    return Column(
      key: const Key('step3-similar-picker'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr.primary(
            'ពិនិត្យ និងជ្រើសរបាយការណ៍ដែលត្រូវគ្នា ដើម្បីបង្កើនអាទិភាព ឬបង្កើតរបាយការណ៍ថ្មីដាច់ដោយឡែក។',
            'Inspect and join a matching incident to boost priority, or file a new separate report below.',
          ),
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 8),

        // Selectable candidate list
        for (final match in matches) ...[
          Builder(
            builder: (context) {
              final report = match.masterReport;
              final isSelected =
                  !isCreatingNew && selectedMatch?.masterReport.id == report.id;
              final isMine = report.isContributedByCurrentUser;
              final titleText = tr.primary(
                report.khmerTitle,
                report.englishTitle,
              );
              final semanticSummary = tr.primary(
                'ជ្រើសរបាយការណ៍ $titleText ${report.id}${isMine ? ' របស់អ្នក' : ''} · ${report.affectedCitizens} នាក់ · P${report.priority.level}',
                'Select report $titleText ${report.id}${isMine ? ', Yours' : ''} · ${report.affectedCitizens} affected · P${report.priority.level}',
              );

              return Container(
                constraints: const BoxConstraints(minHeight: 56),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.tealSoft : AppColors.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppColors.teal : AppColors.inputBorder,
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        inMutuallyExclusiveGroup: true,
                        selected: isSelected,
                        excludeSemantics: true,
                        label: semanticSummary,
                        child: InkWell(
                          key: Key('similar-match-${report.id}'),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            vm.selectMasterReport(report.id);
                          },
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  size: 19,
                                  color: isSelected
                                      ? AppColors.teal
                                      : AppColors.muted,
                                ),
                                const SizedBox(width: 8),
                                ReportPhoto(
                                  category: report.category,
                                  localPhotoPath: report.localPhotoPath,
                                  assetPath: report.photoAssetPath,
                                  width: 40,
                                  height: 40,
                                  borderRadius: 9,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              titleText,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12.5,
                                                color: AppColors.ink,
                                              ),
                                            ),
                                          ),
                                          if (isMine) ...[
                                            const SizedBox(width: 5),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1.5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? AppColors.paper
                                                    : AppColors.tealSoft,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: isSelected
                                                    ? Border.all(
                                                        color: AppColors.teal
                                                            .withValues(
                                                              alpha: 0.45,
                                                            ),
                                                      )
                                                    : null,
                                              ),
                                              child: Text(
                                                tr.primary('របស់អ្នក', 'Yours'),
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.tealDark,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        '${report.id} · ×${report.affectedCitizens}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                PriorityBadge(
                                  breakdown: report.priority,
                                  bilingual: tr,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: Key('preview-match-${report.id}'),
                      tooltip: tr.primary(
                        'ពិនិត្យមើលព័ត៌មានលម្អិត ${report.id}',
                        'Inspect ${report.id}',
                      ),
                      icon: const Icon(
                        Icons.visibility_outlined,
                        size: 19,
                        color: AppColors.tealDark,
                      ),
                      onPressed: () => _openSimilarReportPreview(vm, match, tr),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
        ],

        // Option row: Create a new separate report (unless hard self-blocked <= 50 m)
        if (!hardSelfBlocked) ...[
          const Divider(height: 12, thickness: 1, color: AppColors.border),
          Semantics(
            button: true,
            inMutuallyExclusiveGroup: true,
            selected: isCreatingNew,
            excludeSemantics: true,
            label: tr.primary(
              'បង្កើតរបាយការណ៍ថ្មីដាច់ដោយឡែកនៅទីនេះ · ប្រើជម្រើសនេះប្រសិនបើជាទីតាំង ឬបញ្ហាផ្សេងពីបញ្ជីខាងលើ',
              'Submit as a new separate report here · Choose this if it is a distinct spot or issue from the list above',
            ),
            child: InkWell(
              key: const Key('step3-option-create-new'),
              onTap: () {
                HapticFeedback.selectionClick();
                vm.selectCreateNewReport();
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isCreatingNew ? AppColors.tealSoft : AppColors.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isCreatingNew
                        ? AppColors.teal
                        : AppColors.inputBorder,
                    width: isCreatingNew ? 1.8 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isCreatingNew
                            ? AppColors.paper
                            : AppColors.mutedSurface,
                        shape: BoxShape.circle,
                        border: isCreatingNew
                            ? Border.all(
                                color: AppColors.teal.withValues(alpha: 0.45),
                              )
                            : null,
                      ),
                      child: Icon(
                        isCreatingNew
                            ? Icons.radio_button_checked_rounded
                            : Icons.add_rounded,
                        size: 18,
                        color: isCreatingNew
                            ? AppColors.teal
                            : AppColors.tealDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr.primary(
                              'បង្កើតរបាយការណ៍ថ្មីដាច់ដោយឡែកនៅទីនេះ',
                              'Submit as a new separate report here',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            tr.primary(
                              'ប្រើជម្រើសនេះប្រសិនបើជាទីតាំង ឬបញ្ហាផ្សេងពីបញ្ជីខាងលើ',
                              'Choose this if it is a distinct spot or issue from the list above',
                            ),
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ] else ...[
          Text(
            tr.primary(
              'អ្នកបានរាយការណ៍បញ្ហាប្រភេទដូចគ្នានៅចំណុចនេះរួចហើយ (≤ 50m) — សូមបើករបាយការណ៍របស់អ្នក ឬប្តូរប្រភេទបញ្ហា។',
              'You already reported this same issue type right here (≤ 50 m) — view your ticket or report a different category.',
            ),
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 6),
        ],

        _buildLocationEligibilitySection(vm, tr),
      ],
    );
  }

  /// Pinned Step 3 primary CTA footer so citizens can submit or join without
  /// scrolling through multiple similar reports.
  Widget _buildStep3PrimaryActionFooter({
    required ReportWizardViewModel vm,
    required bool hasSimilar,
    required DuplicateMatch? selectedMatch,
    required PriorityBreakdown priority,
    required double expandFactor,
    required Bilingual tr,
  }) {
    if (vm.requiresOfflineDraftOnly) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr.primary(
              'អ្នកកំពុងគ្មានអ៊ីនធឺណិត — សូមរក្សាទុកសេចក្តីព្រាង ហើយបន្តផ្ញើពេលមានអ៊ីនធឺណិតវិញ (AI នឹងពិនិត្យរូបភាពម្តងទៀត)',
              'You are offline — save as a draft until online (AI will verify your photo on Step 2 when reconnected).',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.saffronInk,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('step3-save-offline-draft-btn'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.saffronInk,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                vm.saveDraft();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr.primary(
                        'បានរក្សាទុកសេចក្តីព្រាង! សូមបន្តផ្ញើពីទំព័រដើមពេលមានអ៊ីនធឺណិតវិញ។',
                        'Draft saved! Resume from Home once you are back online.',
                      ),
                    ),
                  ),
                );
                Navigator.pop(context);
              },
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(
                tr.paired(
                  'រក្សាទុកសេចក្តីព្រាងរង់ចាំអ៊ីនធឺណិត',
                  'Save draft until online',
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (!hasSimilar) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('step3-submit-report-btn'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: vm.canSubmitAtCurrentPin
              ? () => _completeSubmission(vm, tr)
              : null,
          child: Text(tr.paired('បញ្ជូនរបាយការណ៍', 'Submit report')),
        ),
      );
    }

    final isCreatingNew = vm.isCreatingNewDespiteMatches;
    final hardSelfBlocked = vm.isHardSelfBlockedAtPin;
    final selectedOwn =
        selectedMatch != null &&
        selectedMatch.masterReport.isContributedByCurrentUser;

    if (isCreatingNew) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('step3-submit-new-report-btn'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: vm.canSubmitAtCurrentPin
              ? () => _completeSubmission(vm, tr, forceCreateNew: true)
              : null,
          child: Text(
            tr.paired('ដាក់ស្នើរបាយការណ៍ថ្មីនេះ', 'Submit new report'),
          ),
        ),
      );
    }

    if (selectedOwn) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('open-existing-report-btn'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.pushReplacement<void, void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TrackingPage(reportId: selectedMatch.masterReport.id),
                  ),
                );
              },
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text(
                tr.primary(
                  'បើករបាយការណ៍របស់អ្នក (${selectedMatch.masterReport.id})',
                  'View your existing report (${selectedMatch.masterReport.id})',
                ),
              ),
            ),
          ),
          if (hardSelfBlocked && expandFactor > 0.01)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: expandFactor.clamp(0.0, 1.0),
                child: ExcludeSemantics(
                  excluding: expandFactor < 0.5,
                  child: ExcludeFocus(
                    excluding: expandFactor < 0.5,
                    child: Opacity(
                      opacity: expandFactor.clamp(0.0, 1.0),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            key: const Key('different-problem-btn'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: vm.canSubmitAtCurrentPin
                                ? () => _openDifferentProblemSheet(
                                    vm,
                                    selectedMatch.masterReport,
                                    tr,
                                  )
                                : null,
                            child: Text(
                              tr.paired(
                                'ជាបញ្ហាប្រភេទផ្សេង',
                                'Report a different category',
                              ),
                              style: TextStyle(
                                color: vm.canSubmitAtCurrentPin
                                    ? AppColors.tealDark
                                    : AppColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    if (selectedMatch != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('step3-join-report-btn'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: vm.canSubmitAtCurrentPin
              ? () => _completeSubmission(vm, tr, forceCreateNew: false)
              : null,
          child: Text(
            tr.primary(
              'ចូលរួមរបាយការណ៍ ${selectedMatch.masterReport.id} (P${priority.level})',
              'Join ${selectedMatch.masterReport.id} (P${priority.level})',
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Renders the strict universal 150 m zone trust pill or actionable blocker
  /// card inside Step 3's bottom sheet (pure production strictness — zero
  /// commuter/Home District/demo bypasses).
  Widget _buildLocationEligibilitySection(
    ReportWizardViewModel vm,
    Bilingual tr,
  ) {
    final eligibility = vm.locationEligibility;

    Widget buildReturnToZoneButton() {
      return TextButton.icon(
        key: const Key('step3-return-to-zone-btn'),
        onPressed: () => _returnTo150mZone(vm),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(48, 48),
        ),
        icon: const Icon(
          Icons.my_location_rounded,
          size: 16,
          color: AppColors.tealDark,
        ),
        label: Text(
          tr.primary('ត្រឡប់ទៅរង្វង់ 150m', 'Return to 150 m zone'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.tealDark,
          ),
        ),
      );
    }

    switch (eligibility) {
      case ReportLocationEligible(:final tier, :final distanceMeters):
        final isPhotoAnchorTier =
            tier == ReportLocationVerificationTier.photoExifVerified ||
            tier == ReportLocationVerificationTier.liveCameraVerified;
        final distLabel = distanceMeters != null
            ? SupportEligibilityService.formatDistance(
                distanceMeters,
                englishFirst: tr.englishFirst,
              )
            : null;
        final badgeText = switch (tier) {
          ReportLocationVerificationTier.photoExifVerified => tr.primary(
            '✓ ទីតាំង GPS ក្នុងរូបថតត្រឹមត្រូវ (ក្នុង 150m)',
            '✓ Photo GPS verified (within 150 m)',
          ),
          ReportLocationVerificationTier.liveCameraVerified => tr.primary(
            '✓ ផ្ទៀងផ្ទាត់ GPS កាមេរ៉ាផ្ទាល់ (ក្នុង 150m)',
            '✓ Live camera GPS verified (within 150 m)',
          ),
          ReportLocationVerificationTier.verifiedOnSite => tr.primary(
            distLabel != null
                ? '✓ ផ្ទៀងផ្ទាត់ GPS ផ្ទាល់ ($distLabel / 150m)'
                : '✓ ផ្ទៀងផ្ទាត់ GPS ផ្ទាល់ (ក្នុង 150m)',
            distLabel != null
                ? '✓ Live GPS verified ($distLabel / 150 m)'
                : '✓ Live GPS verified (within 150 m)',
          ),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Container(
                key: isPhotoAnchorTier
                    ? const Key('step3-exif-verified-pill')
                    : const Key('step3-location-verified-pill'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        badgeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.tealDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isPhotoAnchorTier &&
                vm.combinedIntegrityAssessment.hasWarning) ...[
              const SizedBox(height: 8),
              Semantics(
                container: true,
                liveRegion: true,
                child: Container(
                  key: const Key('step3-integrity-warning-banner'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.saffronSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.saffron.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 15,
                        color: AppColors.saffronInk,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tr.primary(
                            vm.combinedIntegrityAssessment.khmerSummary ?? '',
                            vm.combinedIntegrityAssessment.englishSummary ?? '',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.saffronInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );

      case ReportLocationDeniedOutOfZone(
        :final anchorSource,
        :final distanceMeters,
        :final maxMeters,
      ):
        final distLabel = SupportEligibilityService.formatDistance(
          distanceMeters,
          englishFirst: tr.englishFirst,
        );
        final sourceCopy = switch (anchorSource) {
          ZoneAnchorSource.photoExif => tr.primary(
            'ម្ជុលផែនទីនៅឆ្ងាយ $distLabel ពីទីតាំង GPS ក្នុងរូបថត។ សូមអូសមកក្នុងរង្វង់ ${maxMeters.round()} ម៉ែត្រ ឬចុច "ត្រឡប់ទៅរង្វង់ 150m"។',
            'Pin is $distLabel away from this photo\'s GPS spot. Move within ${maxMeters.round()} m or tap "Return to 150 m zone".',
          ),
          ZoneAnchorSource.liveCameraCapture => tr.primary(
            'ម្ជុលផែនទីនៅឆ្ងាយ $distLabel ពីទីតាំងថតរូបផ្ទាល់។ សូមអូសមកក្នុងរង្វង់ ${maxMeters.round()} ម៉ែត្រ ឬចុច "ត្រឡប់ទៅរង្វង់ 150m"។',
            'Pin is $distLabel away from where you took this photo. Move within ${maxMeters.round()} m or tap "Return to 150 m zone".',
          ),
          ZoneAnchorSource.liveDeviceGps => tr.primary(
            'ម្ជុលផែនទីនៅឆ្ងាយ $distLabel ពីទីតាំង GPS របស់អ្នក។ សូមអូសមកក្នុងរង្វង់ ${maxMeters.round()} ម៉ែត្រ ឬចុច "ត្រឡប់ទៅរង្វង់ 150m"។',
            'Pin is $distLabel away from your live GPS location. Move within ${maxMeters.round()} m or tap "Return to 150 m zone".',
          ),
        };

        return Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            key: const Key('step3-out-of-zone-blocker'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.wrong_location_outlined,
                      size: 17,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        sourceCopy,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.38,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                buildReturnToZoneButton(),
              ],
            ),
          ),
        );

      case ReportLocationDeniedLocationRequired(
        :final permissionDenied,
        :final serviceDisabled,
        :final outsideCambodia,
        :final staleExifNeedsGps,
        :final pendingGpsCheck,
      ):
        if (vm.isLocating || pendingGpsCheck) {
          return Semantics(
            container: true,
            liveRegion: true,
            child: Container(
              key: const Key('step3-location-checking-pill'),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.teal,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    tr.primary(
                      'កំពុងផ្ទៀងផ្ទាត់ទីតាំង GPS របស់អ្នក...',
                      'Verifying your GPS location...',
                    ),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.tealDark,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final reasonText = staleExifNeedsGps
            ? tr.primary(
                'ទិន្នន័យ GPS ក្នុងរូបថតចាស់ជាង 30 ថ្ងៃ — សូមបើក GPS នៅទីតាំងពិត ឬថតរូបថ្មីដើម្បីបើករង្វង់ 150m។',
                'Photo GPS tag is older than 30 days — turn on live GPS on-site or take a recent photo to unlock the 150 m zone.',
              )
            : serviceDisabled
            ? tr.primary(
                'សូមបើក GPS ដើម្បីផ្ទៀងផ្ទាត់រង្វង់ 150m របស់អ្នក (ឬប្រើរូបថតដែលមាន GPS ថ្មី)។',
                'Turn on GPS to verify your 150 m reporting zone (or attach a recent geotagged photo).',
              )
            : permissionDenied
            ? tr.primary(
                'ត្រូវការសិទ្ធិ GPS ជាចាំបាច់ដើម្បីបើករង្វង់ 150m ឬភ្ជាប់រូបថតដែលមាន GPS។',
                'Location permission is strictly required to unlock the 150 m zone (or attach a geotagged photo).',
              )
            : outsideCambodia
            ? tr.primary(
                'GPS ឧបករណ៍នៅក្រៅប្រទេសកម្ពុជា — ត្រូវការ GPS ក្នុងកម្ពុជា ឬរូបថតមាន GPS នៅកម្ពុជា។',
                'Device GPS is outside Cambodia — live Cambodia GPS or a photo with Cambodia GPS tags is required.',
              )
            : tr.primary(
                'មិនអាចចាប់ GPS បានទេ — សូមបើក GPS ហើយចុចផ្ទៀងផ្ទាត់ម្តងទៀត ឬប្រើរូបថតមាន GPS។',
                'Could not verify GPS — enable GPS and retry, or use a recent geotagged photo.',
              );

        return Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            key: const Key('step3-location-required-banner'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.saffronSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.saffron.withValues(alpha: 0.65),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.gps_off_rounded,
                      size: 16,
                      color: AppColors.saffronInk,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        reasonText,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.38,
                          color: AppColors.saffronInk,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    TextButton.icon(
                      key: const Key('step3-retry-gps-btn'),
                      onPressed: vm.isLocating
                          ? null
                          : () => _verifyGpsLocation(tr),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(
                        Icons.my_location_rounded,
                        size: 15,
                        color: AppColors.tealDark,
                      ),
                      label: Text(
                        tr.primary('ផ្ទៀងផ្ទាត់ GPS', 'Verify GPS'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.tealDark,
                        ),
                      ),
                    ),
                    if (serviceDisabled || permissionDenied)
                      TextButton.icon(
                        onPressed: widget.locationService.openLocationSettings,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(
                          Icons.settings_outlined,
                          size: 15,
                          color: AppColors.saffronInk,
                        ),
                        label: Text(
                          tr.primary('បើក GPS', 'Open GPS'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.saffronInk,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );

      case ReportLocationDeniedMockGps():
        return Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            key: const Key('step3-location-blocked-banner'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.gpp_bad_outlined,
                  size: 17,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    tr.primary(
                      'រកឃើញទីតាំងក្លែងក្លាយ — សូមបិទ Mock GPS មុនដាក់ស្នើ',
                      'Fake GPS detected — disable mock location before submitting.',
                    ),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _verifyGpsLocation(tr),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(
                    tr.primary('ពិនិត្យម្តងទៀត', 'Retry'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.tealDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _AiScanLine extends StatefulWidget {
  const _AiScanLine();

  @override
  State<_AiScanLine> createState() => _AiScanLineState();
}

class _AiScanLineState extends State<_AiScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Positioned(
            left: 12,
            right: 12,
            top: 14 + (_controller.value * 180),
            child: Container(
              height: 2.5,
              decoration: BoxDecoration(
                color: AppColors.saffron,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.saffron.withValues(alpha: 0.8),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FrostedCircleButton extends StatelessWidget {
  const _FrostedCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 48,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.device.withValues(alpha: 0.65),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeverityCard extends StatelessWidget {
  const _SeverityCard({
    required this.score,
    required this.khmer,
    required this.english,
    required this.icon,
    required this.selected,
    required this.tr,
    required this.onTap,
  });

  final int score;
  final String khmer;
  final String english;
  final IconData icon;
  final bool selected;
  final Bilingual tr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.priorityColor(score);
    final highContrastAccent = score >= 5 ? accentColor : AppColors.teal;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: tr.paired(khmer, english),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.14)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? highContrastAccent : AppColors.border,
              width: selected ? 1.8 : 1.1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? highContrastAccent : AppColors.muted,
              ),
              const SizedBox(height: 6),
              Text(
                tr.primary(khmer, english),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.ink : AppColors.muted,
                ),
              ),
              Text(
                tr.secondary(khmer, english),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceLangOption extends StatelessWidget {
  const _VoiceLangOption({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label == 'EN' ? 'English voice input' : 'Khmer voice input',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
          child: Center(
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? AppColors.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.tealDark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DifferentProblemSheet extends StatefulWidget {
  const _DifferentProblemSheet({
    required this.masterReport,
    required this.initialDescription,
    required this.tr,
  });

  final CivicReport masterReport;
  final String initialDescription;
  final Bilingual tr;

  @override
  State<_DifferentProblemSheet> createState() => _DifferentProblemSheetState();
}

class _DifferentProblemSheetState extends State<_DifferentProblemSheet> {
  late IssueCategory _selectedCategory;
  late final TextEditingController _titleController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    // Default to "Other Issue" (never the master incident's category) so the
    // citizen genuinely files a different problem rather than another copy.
    _selectedCategory = widget.masterReport.category == IssueCategory.other
        ? IssueCategory.pothole
        : IssueCategory.other;
    _titleController = TextEditingController();
    _descController = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    final masterReport = widget.masterReport;
    final orderedCategories = [
      IssueCategory.other,
      ...IssueCategory.primaryCategories.where(
        (c) => c != masterReport.category,
      ),
      if (masterReport.category != IssueCategory.other) masterReport.category,
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('different-problem-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BilingualText(
                bilingual: tr,
                khmer: 'រាយការណ៍ជាបញ្ហាផ្សេង',
                english: 'Report a different problem',
                fontSize: 17,
                isHeader: true,
              ),
              const SizedBox(height: 4),
              Text(
                tr.primary(
                  'ជ្រើសប្រភេទបញ្ហាផ្សេងពី ${masterReport.id} (${tr.categoryPrimary(masterReport.category)}) ឬបញ្ជាក់ចំណងជើងថ្មី។',
                  'Choose a different category from ${masterReport.id} (${tr.categoryPrimary(masterReport.category)}) or specify a custom issue title.',
                ),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cat in orderedCategories)
                    ChoiceChip(
                      key: Key('diff-cat-${cat.name}'),
                      avatar: Icon(
                        Bilingual.categoryIcon(cat),
                        size: 16,
                        color: _selectedCategory == cat
                            ? AppColors.tealDark
                            : AppColors.muted,
                      ),
                      label: Text(
                        cat == masterReport.category
                            ? tr.primary(
                                '${cat.khmerName} (ទីតាំងផ្សេង)',
                                'Separate ${cat.englishName}',
                              )
                            : tr.categoryPrimary(cat),
                      ),
                      selected: _selectedCategory == cat,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategory = cat);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('different-problem-title-field'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: tr.paired(
                    'ចំណងជើងបញ្ហា (ជាជម្រើស)',
                    'Problem title (optional)',
                  ),
                  hintText: tr.primary(
                    'ឧ. ផ្លូវដើរខូច ឬ ដើមឈើដួល',
                    'e.g., Broken sidewalk or fallen tree',
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('different-problem-desc-field'),
                controller: _descController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr.paired(
                    'ពិពណ៌នាបន្ថែម (ជាជម្រើស)',
                    'Description (optional)',
                  ),
                  hintText: tr.primary(
                    'បញ្ជាក់ព័ត៌មានលម្អិតអំពីបញ្ហាផ្សេងនេះ...',
                    'Describe this separate issue...',
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('submit-different-problem-btn'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: () => Navigator.pop(context, (
                    category: _selectedCategory,
                    title: _titleController.text.trim(),
                    description: _descController.text.trim(),
                  )),
                  child: Text(
                    tr.paired(
                      'ដាក់ស្នើរបាយការណ៍ផ្សេងនេះ',
                      'Submit separate report',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Read-only in-place modal sheet allowing a citizen on Step 3 to inspect a
/// nearby Master Incident (photo, road, description, citizen count) before
/// choosing to join it or file a separate report.
class _SimilarReportPreviewSheet extends StatelessWidget {
  const _SimilarReportPreviewSheet({required this.match, required this.tr});

  final DuplicateMatch match;
  final Bilingual tr;

  @override
  Widget build(BuildContext context) {
    final report = match.masterReport;
    final distLabel = SupportEligibilityService.formatDistance(
      match.distanceMeters,
      englishFirst: tr.englishFirst,
    );
    final comments = report.effectiveComments
        .where((c) => c.hasText)
        .take(2)
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('similar-report-preview-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: BilingualText(
                      bilingual: tr,
                      khmer: report.khmerTitle,
                      english: report.englishTitle,
                      fontSize: 16,
                      isHeader: true,
                    ),
                  ),
                  PriorityBadge(
                    breakdown: report.priority,
                    bilingual: tr,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${report.id} · $distLabel · ${tr.primary('${report.affectedCitizens} នាក់បានរាយការណ៍', '${report.affectedCitizens} people affected')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr.primary(report.khmerLocation, report.englishLocation),
                style: const TextStyle(fontSize: 12, color: AppColors.ink),
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: tr.primary(
                  'មើលរូបភាពពេញអេក្រង់',
                  'View photo full screen',
                ),
                child: InkWell(
                  onTap: () => PhotoLightboxPage.open(
                    context,
                    category: report.category,
                    bilingual: tr,
                    localPhotoPath: report.localPhotoPath,
                    assetPath: report.photoAssetPath,
                    title: report.id,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  child: ReportPhoto(
                    category: report.category,
                    localPhotoPath: report.localPhotoPath,
                    assetPath: report.photoAssetPath,
                    width: double.infinity,
                    height: 180,
                    borderRadius: 18,
                  ),
                ),
              ),
              if (report.hasDescription) ...[
                const SizedBox(height: 12),
                Text(
                  report.description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.ink,
                  ),
                ),
              ],
              if (comments.length > 1) ...[
                const SizedBox(height: 10),
                Text(
                  tr.primary('មតិពលរដ្ឋបន្ថែម', 'Citizen notes'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                for (final c in comments.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        c.text,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(tr.primary('បិទ', 'Close')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('preview-select-match-btn'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        tr.primary(
                          'ជ្រើសរបាយការណ៍ ${report.id}',
                          'Select ${report.id}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
