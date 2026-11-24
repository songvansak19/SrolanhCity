import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/services/audio_player_service.dart';
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
import '../../../../domain/services/spatial_clustering_service.dart';
import '../../../core/l10n.dart';
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
    this.initialPhotoExif,
    this.locationService = const LocationService(),
    this.geocodingService,
    this.voiceInputService,
    this.audioRecorderService,
    this.audioPlayerService,
    this.civicAiService,
    this.ipGeolocationService,
  });

  final IssueCategory initialCategory;
  final LatLng? initialCoordinates;
  final ReportDraft? initialDraft;
  final PhotoExifMetadata? initialPhotoExif;
  final LocationService locationService;
  final ReverseGeocodingService? geocodingService;
  final VoiceInputService? voiceInputService;
  final AudioRecorderService? audioRecorderService;
  final AudioPlayerService? audioPlayerService;
  final CivicAiService? civicAiService;
  final IpGeolocationService? ipGeolocationService;

  @override
  State<ReportWizardPage> createState() => _ReportWizardPageState();
}

class _ReportWizardPageState extends State<ReportWizardPage> {
  ReportWizardViewModel? _viewModel;
  late final TextEditingController _descriptionController;
  late final ReverseGeocodingService _geocodingService;
  late final AudioPlayerService _audioPlayer;
  final MapController _mapController = MapController();
  Timer? _dragDebounce;
  bool _mapReady = false;
  bool _isDraggingMap = false;
  bool _isPlayingVoiceMemo = false;
  int _previousStep = 0;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController();
    _geocodingService = widget.geocodingService ?? ReverseGeocodingService();
    _audioPlayer =
        widget.audioPlayerService ?? AudioPlayerService.createDefault();
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
        voiceInputService: widget.voiceInputService,
        audioRecorderService: widget.audioRecorderService,
        civicAiService: widget.civicAiService,
        ipGeolocationService: widget.ipGeolocationService,
      );
      if (widget.initialPhotoExif != null) {
        _viewModel!.setPhotoExifMetadata(widget.initialPhotoExif);
      }
      _previousStep = _viewModel!.step;
      _descriptionController.text = _viewModel!.description;
    }
  }

  @override
  void dispose() {
    _dragDebounce?.cancel();
    _viewModel?.dispose();
    _descriptionController.dispose();
    _mapController.dispose();
    if (widget.audioPlayerService == null) {
      unawaited(_audioPlayer.dispose());
    } else {
      unawaited(_audioPlayer.stop());
    }
    super.dispose();
  }

  Future<void> _toggleStep2VoiceMemoPlayback(
    ReportWizardViewModel vm,
    Bilingual tr,
  ) async {
    final path = vm.voiceAudioPath;
    if (path == null || path.isEmpty) return;
    HapticFeedback.selectionClick();
    if (_isPlayingVoiceMemo) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _isPlayingVoiceMemo = false);
      return;
    }
    final started = await _audioPlayer.play(
      path,
      onCompleted: () {
        if (mounted) setState(() => _isPlayingVoiceMemo = false);
      },
    );
    if (!mounted) return;
    if (started) {
      setState(() => _isPlayingVoiceMemo = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary(
              'កំណត់ត្រាសំឡេងត្រូវបានរក្សាទុកហើយ នឹងភ្ជាប់ជាមួយរបាយការណ៍',
              'Voice memo saved and ready to submit with your report.',
            ),
          ),
        ),
      );
    }
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
      vm.repository.clearDraft();
    }
    Navigator.pop(context);
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
        PhotoExifMetadata? bestExif;
        var hadUnsupported = false;
        for (final item in results) {
          if (item.isValid) {
            validPaths.add(item.path);
            if (!item.exifMetadata.isEmpty) {
              bestExif ??= item.exifMetadata;
            }
          } else if (item.unsupportedFormat) {
            hadUnsupported = true;
          }
        }
        if (validPaths.isNotEmpty) {
          HapticFeedback.selectionClick();
          _viewModel?.addLocalPhotoPaths(validPaths, exifMetadata: bestExif);
        }
        if (hadUnsupported && mounted) {
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
      HapticFeedback.selectionClick();
      _viewModel?.addLocalPhotoPath(
        result.path,
        exifMetadata: result.exifMetadata,
      );
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

  Future<void> _verifyGpsLocation(Bilingual tr) async {
    final vm = _viewModel;
    if (vm == null || vm.isLocating) return;

    HapticFeedback.selectionClick();
    vm.setLocating(true);
    try {
      final result = await widget.locationService.getCurrentLocation();
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
            vm.setPinLocation(
              point,
              verified: true,
              fromLiveGps: true,
              accuracyMeters: accuracyMeters,
            );
            if (_mapReady) _mapController.move(point, 17.5);
            await _reverseGeocodeCurrentPin(point);
          }
        case LocationMockDetected(
          :final detectedLabel,
          :final reasonKhmer,
          :final reasonEnglish,
        ):
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr.primary(
                  'សូមបើកសេវាកម្ម GPS ឬអូសផែនទីដើម្បីកំណត់ទីតាំង',
                  'Enable GPS services or drag the map under the pin.',
                ),
              ),
            ),
          );
        case LocationPermissionDenied():
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr.primary(
                  'ត្រូវការសិទ្ធិ GPS ឬអូសផែនទីដើម្បីបញ្ជាក់ទីតាំង',
                  'GPS permission required, or drag the map to place the pin.',
                ),
              ),
            ),
          );
        case LocationFailure():
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr.primary(
                  'មិនអាចចាប់ GPS បានទេ — អូសផែនទីដើម្បីជ្រើសទីតាំង',
                  'GPS unavailable — drag the map under the pin.',
                ),
              ),
            ),
          );
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

  Future<void> _openDifferentProblemSheet(
    ReportWizardViewModel vm,
    CivicReport masterReport,
    Bilingual tr,
  ) async {
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

    return ListenableBuilder(
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
                      Container(
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
                          isHeader: true,
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

                const Spacer(),

                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 260,
                          height: 210,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(
                                    color: isScanning
                                        ? AppColors.saffron
                                        : Colors.white.withValues(alpha: 0.45),
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
                                        size: 42,
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
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
                        const SizedBox(height: 14),
                        Semantics(
                          container: true,
                          liveRegion: true,
                          child: buildStatusPill(),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasRealPhoto
                              ? tr.paired(
                                  'បានលុប EXIF ដោយស្វ័យប្រវត្តិ · រូបភាព ${vm.localPhotoPaths.length}/${ReportWizardViewModel.maxPhotos}',
                                  'EXIF stripped · ${vm.localPhotoPaths.length}/${ReportWizardViewModel.maxPhotos} photo(s) attached',
                                )
                              : tr.paired(
                                  'ដាក់បញ្ហានៅកណ្តាលស៊ុម ឬបន្តដោយជ្រើសប្រភេទខាងក្រោម',
                                  'Capture the issue or pick a category below',
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

                const Spacer(),

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
                      FilledButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          vm.nextStep();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.teal,
                          foregroundColor: Colors.white,
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
                                      width: vm.localPhotoPaths.isEmpty
                                          ? 156
                                          : 84,
                                      height: 84,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: vm.localPhotoPaths.isEmpty
                                              ? AppColors.teal.withValues(
                                                  alpha: 0.45,
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
                                                ? AppColors.teal
                                                : AppColors.muted,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            vm.localPhotoPaths.isEmpty
                                                ? tr.primary(
                                                    'បន្ថែមរូបភាព (0/3)',
                                                    'Add photo (0/3)',
                                                  )
                                                : '${tr.primary('បន្ថែម', 'Add')} (${vm.localPhotoPaths.length}/${ReportWizardViewModel.maxPhotos})',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: vm.localPhotoPaths.isEmpty
                                                  ? AppColors.tealDark
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
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          vm.nextStep();
                          _reverseGeocodeCurrentPin(vm.pinLocation);
                        },
                        child: Text(
                          tr.paired(
                            'បន្ទាប់ · បញ្ជាក់ទីតាំង',
                            'Next · Confirm location',
                          ),
                        ),
                      ),
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
        ? AppColors.saffron.withValues(alpha: 0.6)
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
            ActionChip(
              key: const Key('step2-rescan-ai-chip'),
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
      VoiceCaptureMode.offlineAudioMemo => tr.primary('សំឡេង', 'Audio'),
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
                                ? (vm.voiceMode ==
                                          VoiceCaptureMode.offlineAudioMemo
                                      ? tr.primary(
                                          'កំពុងថតសំឡេង... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}',
                                          'Recording voice memo... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}',
                                        )
                                      : tr.primary(
                                          vm.voicePreferEnglish
                                              ? 'កំពុងស្តាប់ភាសាអង់គ្លេស... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}'
                                              : 'កំពុងស្តាប់ភាសាខ្មែរ... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}',
                                          vm.voicePreferEnglish
                                              ? 'Listening in English... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}'
                                              : 'Listening in Khmer... 0:${vm.recordingSeconds.toString().padLeft(2, '0')}',
                                        ))
                                : tr.primary(
                                    'រាយការណ៍ជាសំឡេង (សង្កត់ ឬចុច)',
                                    'Voice Note (Hold or Tap)',
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
                              tr.primary('សំឡេងក្រៅបណ្តាញ', 'Offline Memo'),
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
          if (vm.hasVoiceAudioMemo) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('step2-voice-memo-player'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: AppColors.teal.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: _isPlayingVoiceMemo
                        ? tr.primary('ផ្អាកសំឡេង', 'Pause voice memo')
                        : tr.primary('ចាក់ស្តាប់សំឡេង', 'Play voice memo'),
                    child: InkWell(
                      key: const Key('step2-voice-memo-play-btn'),
                      onTap: () => _toggleStep2VoiceMemoPlayback(vm, tr),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.teal,
                            child: Icon(
                              _isPlayingVoiceMemo
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      tr.primary(
                        'កំណត់ត្រាសំឡេង (0:${(vm.voiceAudioDurationSeconds ?? 1).toString().padLeft(2, '0')})',
                        'Voice Memo (0:${(vm.voiceAudioDurationSeconds ?? 1).toString().padLeft(2, '0')})',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.tealDark,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('step2-voice-memo-delete-btn'),
                    tooltip: tr.primary(
                      'លុបកំណត់ត្រាសំឡេង',
                      'Remove voice memo',
                    ),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    onPressed: () {
                      unawaited(_audioPlayer.stop());
                      setState(() => _isPlayingVoiceMemo = false);
                      vm.clearVoiceAudioMemo();
                    },
                  ),
                ],
              ),
            ),
          ],
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
                    if (vm.showVoiceMemoFallbackAction ||
                        vm.showVoiceDemoFallbackAction) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (vm.showVoiceMemoFallbackAction)
                            ActionChip(
                              key: const Key('voice-record-memo-btn'),
                              avatar: const Icon(
                                Icons.mic_rounded,
                                size: 14,
                                color: AppColors.teal,
                              ),
                              label: Text(
                                tr.primary(
                                  'ថតសំឡេងផ្ទាល់',
                                  'Record Voice Memo',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                unawaited(vm.startOfflineVoiceMemoRecording());
                              },
                            ),
                          if (vm.showVoiceDemoFallbackAction)
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
  /// Draggable Crosshair Pin + 100 m Geofence Ring + ODC GIS Routing Card.
  Widget _buildFullBleedLocationStep(
    ReportWizardViewModel vm,
    List<CivicReport> allReports,
    Bilingual tr,
  ) {
    final duplicate = vm.nearbyDuplicate;
    final routing = vm.gisRouting;
    final priority = vm.estimatedPriority;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: vm.pinLocation,
              initialZoom: 17.0,
              minZoom: LocationService.minMapZoom,
              maxZoom: LocationService.maxMapZoom,
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
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.srolanhcity.app',
                maxNativeZoom: 19,
                maxZoom: 19,
                keepBuffer: 2,
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: vm.pinLocation,
                    radius: SpatialClusteringService.defaultRadiusMeters,
                    useRadiusInMeter: true,
                    color:
                        (duplicate != null ? AppColors.saffron : AppColors.teal)
                            .withValues(alpha: 0.16),
                    borderColor: duplicate != null
                        ? AppColors.priorityColor(4)
                        : AppColors.teal,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final existing in allReports.where(
                    (r) => r.status != ReportStatus.resolved,
                  ))
                    Marker(
                      point: existing.coordinates,
                      width: 32,
                      height: 32,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.priorityColor(
                            existing.priority.level,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          '${existing.affectedCitizens}',
                          style: AppFonts.displayStyle(
                            color: AppColors.priorityForeground(
                              existing.priority.level,
                            ),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Centered Grab-Style Crosshair Pin that lifts slightly while dragging
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
                        child: const Icon(
                          Icons.location_on,
                          color: AppColors.teal,
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
                              Row(
                                children: [
                                  Icon(
                                    vm.usedLiveGps
                                        ? Icons.verified_rounded
                                        : Icons.open_with_rounded,
                                    size: 13,
                                    color: AppColors.teal,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      vm.usedLiveGps
                                          ? tr.primary(
                                              'GPS ពិតប្រាកដ · ±${(vm.gpsAccuracyMeters ?? 5).round()}m · រង្វង់ 100m',
                                              'Real GPS verified · ±${(vm.gpsAccuracyMeters ?? 5).round()}m · 100m match',
                                            )
                                          : tr.primary(
                                              'អូសផែនទីក្រោមម្ជុល · រង្វង់ 100m',
                                              'Drag map under pin · 100 m geofence',
                                            ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.teal,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'wizard-locate',
                        tooltip: tr.primary(
                          'ផ្ទៀងផ្ទាត់ទីតាំង GPS',
                          'Verify GPS location',
                        ),
                        backgroundColor: AppColors.teal,
                        foregroundColor: Colors.white,
                        onPressed: vm.isLocating
                            ? null
                            : () => _verifyGpsLocation(tr),
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
                                'គ្មានអ៊ីនធឺណិត — របាយការណ៍នឹងរក្សាទុកក្នុងឧបករណ៍ និងផ្ញើស្វ័យប្រវត្តិពេលមានសេវា',
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
                  if (vm.isOutsideCambodia && vm.rawOutsideGps != null)
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
                                'GPS ឧបករណ៍នៅក្រៅកម្ពុជា (${vm.rawOutsideGps!.latitude.toStringAsFixed(2)}, ${vm.rawOutsideGps!.longitude.toStringAsFixed(2)})',
                                'Emulator / GPS outside Cambodia (${vm.rawOutsideGps!.latitude.toStringAsFixed(2)}, ${vm.rawOutsideGps!.longitude.toStringAsFixed(2)})',
                              ),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.saffronInk,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              vm.usePhnomPenhCenter();
                              if (_mapReady) {
                                _mapController.move(
                                  LocationService.phnomPenhCenter,
                                  17,
                                );
                              }
                            },
                            child: Text(
                              tr.primary('ភ្នំពេញ', 'Phnom Penh'),
                              style: const TextStyle(
                                color: AppColors.teal,
                                fontWeight: FontWeight.w800,
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

          // Floating Bottom Sheet Card
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                ),
                child: Container(
                  margin: const EdgeInsets.all(14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: SingleChildScrollView(
                    child: duplicate != null
                        ? Builder(
                            builder: (context) {
                              final alreadyMine = duplicate
                                  .masterReport
                                  .isContributedByCurrentUser;
                              final hardBlocked =
                                  alreadyMine &&
                                  duplicate.distanceMeters <=
                                      SpatialClusteringService
                                          .hardSelfBlockRadiusMeters;

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: alreadyMine
                                              ? AppColors.tealSoft
                                              : AppColors.saffronSoft,
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                        child: Icon(
                                          alreadyMine
                                              ? Icons.verified_outlined
                                              : Icons.groups_outlined,
                                          color: alreadyMine
                                              ? AppColors.teal
                                              : AppColors.saffronInk,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: BilingualText(
                                          bilingual: tr,
                                          khmer: alreadyMine
                                              ? 'អ្នកបានរាយការណ៍បញ្ហានេះរួចហើយ (${duplicate.distanceMeters.round()} ម៉ែត្រ)'
                                              : 'រកឃើញរបាយការណ៍ស្រដៀងចម្ងាយ ${duplicate.distanceMeters.round()} ម៉ែត្រ',
                                          english: alreadyMine
                                              ? 'You already reported this issue (${duplicate.distanceMeters.round()} m away)'
                                              : 'Similar report found ${duplicate.distanceMeters.round()} m away',
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(11),
                                    decoration: BoxDecoration(
                                      color: AppColors.paper,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ReportPhoto(
                                          category:
                                              duplicate.masterReport.category,
                                          localPhotoPath: duplicate
                                              .masterReport
                                              .localPhotoPath,
                                          assetPath: duplicate
                                              .masterReport
                                              .photoAssetPath,
                                          width: 50,
                                          height: 50,
                                          borderRadius: 12,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${tr.categoryPrimary(duplicate.masterReport.category)} · ${tr.primary('${duplicate.masterReport.affectedCitizens} នាក់បានរាយការណ៍', '${duplicate.masterReport.affectedCitizens} people reported')}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              Text(
                                                duplicate.masterReport.id,
                                                style: AppFonts.displayStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.muted,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PriorityBadge(
                                          breakdown: alreadyMine
                                              ? duplicate.masterReport.priority
                                              : priority,
                                          bilingual: tr,
                                          compact: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (alreadyMine) ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        key: const Key(
                                          'open-existing-report-btn',
                                        ),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            52,
                                          ),
                                        ),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          Navigator.pushReplacement<void, void>(
                                            context,
                                            MaterialPageRoute<void>(
                                              builder: (_) => TrackingPage(
                                                reportId:
                                                    duplicate.masterReport.id,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          tr.paired(
                                            'បើករបាយការណ៍របស់អ្នក',
                                            'View your existing report',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (hardBlocked) ...[
                                      Text(
                                        tr.primary(
                                          'មិនអាចដាក់ស្នើបញ្ហាដូចគ្នាពីរដងនៅទីតាំងតែមួយបានទេ — អូសផែនទីទៅទីតាំងថ្មី ឬរាយការណ៍ជាបញ្ហាប្រភេទផ្សេង។',
                                          'You cannot submit the same issue twice at the same spot. Move the pin or report a different problem type.',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        width: double.infinity,
                                        child: TextButton(
                                          key: const Key(
                                            'different-problem-btn',
                                          ),
                                          style: TextButton.styleFrom(
                                            minimumSize: const Size.fromHeight(
                                              48,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _openDifferentProblemSheet(
                                                vm,
                                                duplicate.masterReport,
                                                tr,
                                              ),
                                          child: Text(
                                            tr.paired(
                                              'ជាបញ្ហាផ្សេង',
                                              "It's a different problem",
                                            ),
                                            style: const TextStyle(
                                              color: AppColors.teal,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else
                                      SizedBox(
                                        width: double.infinity,
                                        child: TextButton(
                                          key: const Key(
                                            'different-problem-btn',
                                          ),
                                          style: TextButton.styleFrom(
                                            minimumSize: const Size.fromHeight(
                                              48,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _openDifferentProblemSheet(
                                                vm,
                                                duplicate.masterReport,
                                                tr,
                                              ),
                                          child: Text(
                                            tr.paired(
                                              'ជាបញ្ហាផ្សេង',
                                              "It's a different problem",
                                            ),
                                            style: const TextStyle(
                                              color: AppColors.muted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ] else ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            52,
                                          ),
                                        ),
                                        onPressed: () => _completeSubmission(
                                          vm,
                                          tr,
                                          forceCreateNew: false,
                                        ),
                                        child: Text(
                                          tr.paired(
                                            'ចូលរួមរបាយការណ៍នេះ',
                                            'Join this report',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: TextButton(
                                        key: const Key('different-problem-btn'),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                        ),
                                        onPressed: () =>
                                            _openDifferentProblemSheet(
                                              vm,
                                              duplicate.masterReport,
                                              tr,
                                            ),
                                        child: Text(
                                          tr.paired(
                                            'ជាបញ្ហាផ្សេង',
                                            "It's a different problem",
                                          ),
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_outlined,
                                    size: 18,
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
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  PriorityBadge(
                                    breakdown: priority,
                                    bilingual: tr,
                                    compact: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${tr.primary(routing.fullKhmerLocation, routing.fullEnglishLocation)} · ${tr.roadClassLabel(routing.roadClass)} · ODC GIS',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (vm.photoExifAssessment.photoExifVerified) ...[
                                const SizedBox(height: 8),
                                Semantics(
                                  container: true,
                                  liveRegion: true,
                                  child: Container(
                                    key: const Key('step3-exif-verified-pill'),
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
                                        Text(
                                          tr.primary(
                                            '✓ ទីតាំង GPS ក្នុងរូបថតត្រឹមត្រូវ',
                                            '✓ Photo GPS verified',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.tealDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ] else if (vm
                                  .combinedIntegrityAssessment
                                  .hasWarning) ...[
                                const SizedBox(height: 8),
                                Semantics(
                                  container: true,
                                  liveRegion: true,
                                  child: Container(
                                    key: const Key(
                                      'step3-integrity-warning-banner',
                                    ),
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.saffronSoft,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.saffron.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                  vm
                                                          .combinedIntegrityAssessment
                                                          .khmerSummary ??
                                                      '',
                                                  vm
                                                          .combinedIntegrityAssessment
                                                          .englishSummary ??
                                                      '',
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
                                        if (vm.canApplyPhotoExifLocation) ...[
                                          const SizedBox(height: 6),
                                          TextButton.icon(
                                            key: const Key(
                                              'step3-use-photo-gps-btn',
                                            ),
                                            onPressed: () {
                                              HapticFeedback.selectionClick();
                                              final coords = vm
                                                  .applyPhotoExifLocation();
                                              if (coords != null && _mapReady) {
                                                _mapController.move(
                                                  coords,
                                                  17.0,
                                                );
                                                unawaited(
                                                  _reverseGeocodeCurrentPin(
                                                    coords,
                                                  ),
                                                );
                                              }
                                            },
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              minimumSize: const Size(48, 44),
                                            ),
                                            icon: const Icon(
                                              Icons.my_location_rounded,
                                              size: 14,
                                              color: AppColors.teal,
                                            ),
                                            label: Text(
                                              tr.primary(
                                                'ប្រើទីតាំងពីរូបថត',
                                                'Use photo location',
                                              ),
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.teal,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                  ),
                                  onPressed: () => _completeSubmission(vm, tr),
                                  child: Text(
                                    tr.paired(
                                      'បញ្ជូនរបាយការណ៍',
                                      'Submit report',
                                    ),
                                  ),
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
      ),
    );
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
