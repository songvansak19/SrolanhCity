import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/report_repository.dart';
import '../../../data/services/location_service.dart';
import '../../../data/services/reverse_geocoding_service.dart';
import '../../../domain/models/cambodia_locations.dart';
import '../../../domain/models/report_models.dart';
import '../../../domain/services/gis_routing_service.dart';
import '../../../domain/services/map_cluster_service.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/support_action_coordinator.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/photo_lightbox_page.dart';
import '../../core/widgets/priority_badge.dart';
import '../../core/widgets/report_photo.dart';
import '../report/views/fake_gps_page.dart';
import '../report/views/report_wizard_page.dart';
import '../tracking/tracking_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    this.onBack,
    this.focusedReportId,
    this.locationService = const LocationService(),
    this.geocodingService,
  });

  final VoidCallback? onBack;
  final String? focusedReportId;
  final LocationService locationService;
  final ReverseGeocodingService? geocodingService;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const LatLng _phnomPenh = LocationService.phnomPenhCenter;

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final PageController _carouselController = PageController(
    viewportFraction: 0.86,
  );
  late final ReverseGeocodingService _geocodingService;

  LatLng _center = _phnomPenh;
  LatLngBounds? _visibleBounds;
  LatLngBounds? _carouselBounds;
  LatLng? _customPin;
  String? _customPinLabel;
  double? _lastAccuracyMeters;
  bool _outsideCambodiaDetected = false;
  LatLng? _rawOutsidePoint;
  double _zoom = 13.8;
  MapClusterTier _clusterTier = MapClusterTier.single;
  int _areaGridZoomBucket = 28;
  Timer? _viewportDebounce;
  String _query = '';
  IssueCategory? _selectedCategory;
  String? _activeReportId;
  bool _showLegend = false;
  bool _isSearchingPlace = false;
  bool _isLocating = false;
  bool _mapReady = false;
  bool _didApplyInitialFocus = false;

  @override
  void initState() {
    super.initState();
    _geocodingService = widget.geocodingService ?? ReverseGeocodingService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didApplyInitialFocus) {
      final repo = ReportScope.read(context);
      if (widget.focusedReportId != null) {
        final focused = repo.findById(widget.focusedReportId!);
        if (focused != null) {
          _center = focused.coordinates;
          _activeReportId = focused.id;
          _zoom = 16.0;
          _clusterTier = MapClusterService.tierForZoom(_zoom);
        }
      } else if (repo.profile.hasHomeArea) {
        final homeProvince = CambodiaLocationCatalog.matchFromProfileArea(
          khmerArea: repo.profile.khmerHomeArea,
          englishArea: repo.profile.englishHomeArea,
          provinceCode: repo.profile.homeProvinceCode,
        ).province;
        _center = homeProvince.center;
        _zoom = homeProvince.isCapital ? 13.8 : 13.6;
        _clusterTier = MapClusterService.tierForZoom(_zoom);
      } else {
        _center = _phnomPenh;
        _zoom = 13.8;
        _clusterTier = MapClusterService.tierForZoom(_zoom);
      }
      _didApplyInitialFocus = true;
    }
  }

  @override
  void dispose() {
    _viewportDebounce?.cancel();
    _searchController.dispose();
    _carouselController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  List<CivicReport> _filterReports(List<CivicReport> reports) {
    final q = _query.trim().toLowerCase();
    return reports
        .where((report) {
          if (_selectedCategory != null &&
              report.category != _selectedCategory) {
            return false;
          }
          if (q.isEmpty) return true;
          return report.id.toLowerCase().contains(q) ||
              report.khmerTitle.toLowerCase().contains(q) ||
              report.englishTitle.toLowerCase().contains(q) ||
              report.khmerLocation.toLowerCase().contains(q) ||
              report.englishLocation.toLowerCase().contains(q) ||
              report.khmerProvince.toLowerCase().contains(q) ||
              report.englishProvince.toLowerCase().contains(q) ||
              report.khmerAgency.toLowerCase().contains(q) ||
              report.englishAgency.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  void _flyToPoint(LatLng target, double targetZoom) {
    final clampedZoom = targetZoom
        .clamp(LocationService.minMapZoom, LocationService.maxMapZoom)
        .toDouble();
    final nextTier = MapClusterService.tierForZoom(clampedZoom);
    setState(() {
      _center = target;
      _zoom = clampedZoom;
      _clusterTier = nextTier;
      _areaGridZoomBucket = (clampedZoom * 2).round();
      _customPin = null;
      _outsideCambodiaDetected = false;
    });
    if (_mapReady) {
      _mapController.move(target, clampedZoom);
      _visibleBounds = _mapController.camera.visibleBounds;
      _carouselBounds = _visibleBounds;
    }
    if (_carouselController.hasClients) {
      _carouselController.jumpToPage(0);
    }
  }

  void _flyToAllCambodia() {
    HapticFeedback.selectionClick();
    _flyToPoint(
      CambodiaLocationCatalog.cambodiaOverviewCenter,
      CambodiaLocationCatalog.cambodiaOverviewZoom,
    );
  }

  void _handleCameraPositionChanged(
    MapCamera camera, {
    required bool hasGesture,
  }) {
    _center = camera.center;
    _zoom = camera.zoom;
    _visibleBounds = camera.visibleBounds;

    final nextTier = MapClusterService.tierForZoom(_zoom);
    final nextBucket = (_zoom * 2).round();
    final tierChanged = nextTier != _clusterTier;
    final gridBucketChanged =
        nextTier == MapClusterTier.area && nextBucket != _areaGridZoomBucket;

    if (tierChanged || gridBucketChanged) {
      _viewportDebounce?.cancel();
      if (mounted) {
        setState(() {
          _clusterTier = nextTier;
          _areaGridZoomBucket = nextBucket;
          if (hasGesture) {
            _carouselBounds = camera.visibleBounds;
          }
        });
      }
      return;
    }

    // Only rebuild the bottom viewport carousel when the user explicitly
    // drags/pinches the map — never on programmatic pans triggered by swiping
    // carousel cards (which previously caused a 2-card ping-pong loop).
    if (!hasGesture) return;

    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _carouselBounds = camera.visibleBounds;
      });
    });
  }

  Future<void> _openProvinceJumpSheet(
    ReportRepository repo,
    Bilingual tr,
  ) async {
    var sheetQuery = '';
    final isOverview = _zoom < MapClusterService.provinceClusterMaxZoom;
    final activeProvince = isOverview
        ? null
        : CambodiaLocationCatalog.nearestProvinceForPoint(_center);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final needle = sheetQuery.trim().toLowerCase();
          final matches = CambodiaLocationCatalog.provinces
              .where((p) {
                if (needle.isEmpty) return true;
                return p.english.toLowerCase().contains(needle) ||
                    p.khmer.toLowerCase().contains(needle) ||
                    p.aliases.any((a) => a.toLowerCase().contains(needle));
              })
              .toList(growable: false);

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.80,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BilingualText(
                      bilingual: tr,
                      khmer: 'ទៅកាន់រាជធានី / ខេត្ត (២៥)',
                      english: 'Jump to Province (25)',
                      fontSize: 17,
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      key: const Key('map-jump-all-cambodia'),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _flyToAllCambodia();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: isOverview
                              ? AppColors.tealSoft
                              : AppColors.saffronSoft,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isOverview
                                ? AppColors.teal.withValues(alpha: 0.4)
                                : AppColors.saffron.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.public_rounded,
                              color: isOverview
                                  ? AppColors.teal
                                  : AppColors.saffronInk,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr.primary(
                                      'ទូទាំងប្រទេសកម្ពុជា (២៥ រាជធានី-ខេត្ត)',
                                      'All Cambodia (25 Provinces)',
                                    ),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: isOverview
                                          ? AppColors.tealDark
                                          : AppColors.saffronInk,
                                    ),
                                  ),
                                  Text(
                                    tr.primary(
                                      'ពង្រីកមើលពពុះរបាយការណ៍តាមខេត្តនីមួយៗ',
                                      'Zoom out to view report bubbles by province',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Chip(
                              label: Text(
                                '${repo.reports.length}',
                                style: AppFonts.displayStyle(
                                  fontSize: 11.5,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('map-province-search'),
                      decoration: InputDecoration(
                        hintText: tr.primary(
                          'ស្វែងរកខេត្ត (ឧ. សៀមរាប, ព្រះសីហនុ, កំពត)...',
                          'Search province (e.g., Siem Reap, Kampot)...',
                        ),
                        prefixIcon: const Icon(Icons.search, size: 19),
                        isDense: true,
                      ),
                      onChanged: (v) => setSheetState(() => sheetQuery = v),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, index) {
                          final province = matches[index];
                          final count = repo.reportCountForProvince(province);
                          final isSelected =
                              activeProvince?.code == province.code;
                          return ListTile(
                            key: Key('map-jump-province-${province.code}'),
                            dense: true,
                            leading: Icon(
                              province.isCapital
                                  ? Icons.location_city_rounded
                                  : Icons.place_outlined,
                              color: isSelected
                                  ? AppColors.teal
                                  : (count > 0
                                        ? AppColors.ink
                                        : AppColors.muted),
                              size: 20,
                            ),
                            title: Text(
                              tr.primary(province.khmer, province.english),
                              style: TextStyle(
                                fontWeight: isSelected || count > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.tealDark
                                    : AppColors.ink,
                              ),
                            ),
                            subtitle: Text(
                              tr.secondary(province.khmer, province.english),
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: count > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.teal
                                          : AppColors.tealSoft,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: AppFonts.displayStyle(
                                        fontSize: 11.5,
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.tealDark,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    '0',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.muted,
                                    ),
                                  ),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              HapticFeedback.selectionClick();
                              _flyToPoint(
                                province.center,
                                province.isCapital ? 13.8 : 13.6,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updatePinLabel(LatLng point) async {
    final fallback = GisRoutingService.resolve(
      coordinates: point,
      category: IssueCategory.pothole,
    );
    setState(() {
      _customPinLabel = fallback.englishRoadName;
    });
    final place = await _geocodingService.reverseGeocode(point);
    if (!mounted || _customPin != point || place == null) return;
    final parts = [
      if (place.roadName != null) place.roadName!,
      if (place.sangkat != null) place.sangkat!,
      if (place.khan != null) place.khan!,
    ];
    if (parts.isNotEmpty) {
      setState(() => _customPinLabel = parts.take(2).join(' · '));
    }
  }

  Future<void> _handleSearchSubmit(
    String value,
    List<CivicReport> allReports,
    Bilingual tr,
  ) async {
    FocusScope.of(context).unfocus();
    final matches = _filterReports(allReports);
    if (matches.isNotEmpty) {
      final target = matches.first;
      setState(() {
        _activeReportId = target.id;
        _customPin = null;
      });
      if (_mapReady) _mapController.move(target.coordinates, 16);
      _openIncidentSheet(target, tr);
      return;
    }

    final landmark = GisRoutingService.findLandmarkByQuery(value);
    if (landmark != null) {
      setState(() {
        _customPin = landmark.center;
        _customPinLabel = tr.primary(landmark.khmerRoad, landmark.englishRoad);
      });
      if (_mapReady) _mapController.move(landmark.center, 15.8);
      return;
    }

    // Live Nominatim Cambodia forward search (e.g., Wat Phnom, AEON, RUPP)
    setState(() => _isSearchingPlace = true);
    try {
      final result = await _geocodingService.searchPlaceInCambodia(value);
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _customPin = result.point;
          _customPinLabel = result.title;
        });
        if (_mapReady) _mapController.move(result.point, 16);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary(
              'រកមិនឃើញ "$value" នៅក្នុងប្រទេសកម្ពុជាទេ',
              'No matching reports or places in Cambodia for "$value".',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSearchingPlace = false);
    }
  }

  Future<void> _locateMe(Bilingual tr) async {
    if (_isLocating) return;
    HapticFeedback.selectionClick();
    setState(() => _isLocating = true);
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
            setState(() {
              _outsideCambodiaDetected = true;
              _rawOutsidePoint = point;
              _lastAccuracyMeters = accuracyMeters;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr.primary(
                    'GPS ឧបករណ៍នៅក្រៅប្រទេសកម្ពុជា (${point.latitude.toStringAsFixed(3)}, ${point.longitude.toStringAsFixed(3)})',
                    'Device GPS is outside Cambodia (${point.latitude.toStringAsFixed(3)}, ${point.longitude.toStringAsFixed(3)}) — likely emulator default.',
                  ),
                ),
                action: SnackBarAction(
                  label: tr.primary('ទៅភ្នំពេញ', 'Phnom Penh'),
                  onPressed: _centerOnPhnomPenh,
                ),
              ),
            );
          } else {
            setState(() {
              _outsideCambodiaDetected = false;
              _rawOutsidePoint = null;
              _center = point;
              _customPin = point;
              _lastAccuracyMeters = accuracyMeters;
              _zoom = 16.5;
            });
            if (_mapReady) {
              _mapController.move(point, 16.5);
              _visibleBounds = _mapController.camera.visibleBounds;
              _carouselBounds = _visibleBounds;
            }
            await _updatePinLabel(point);
          }
        case LocationMockDetected():
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => FakeGpsPage(
                onOpenSettings: widget.locationService.openLocationSettings,
                onTryAgain: () => Navigator.pop(context),
              ),
            ),
          );
        case LocationServiceDisabled():
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr.primary(
                  'សូមបើកសេវាកម្មទីតាំង (GPS)',
                  'Please enable GPS location services.',
                ),
              ),
            ),
          );
        case LocationPermissionDenied():
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr.primary(
                  'ត្រូវការសិទ្ធិចូលប្រើទីតាំង GPS',
                  'Location permission is required.',
                ),
              ),
            ),
          );
        case LocationFailure():
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr.primary(
                  'មិនអាចរកទីតាំង GPS បានទេ សូមចុចលើផែនទីដើម្បីដាក់ម្ជុល',
                  'Could not acquire GPS fix — tap the map to drop a pin.',
                ),
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _centerOnPhnomPenh() {
    setState(() {
      _outsideCambodiaDetected = false;
      _center = _phnomPenh;
      _customPin = _phnomPenh;
      _zoom = 15.5;
    });
    if (_mapReady) {
      _mapController.move(_phnomPenh, 15.5);
      _visibleBounds = _mapController.camera.visibleBounds;
      _carouselBounds = _visibleBounds;
    }
    _updatePinLabel(_phnomPenh);
  }

  void _setZoom(double nextZoom) {
    final clamped = nextZoom
        .clamp(LocationService.minMapZoom, LocationService.maxMapZoom)
        .toDouble();
    final currentCenter = _mapReady ? _mapController.camera.center : _center;
    if (_mapReady) {
      _mapController.move(currentCenter, clamped);
    }
    final resolvedZoom = _mapReady ? _mapController.camera.zoom : clamped;
    final resolvedCenter = _mapReady
        ? _mapController.camera.center
        : currentCenter;
    final resolvedBounds = _mapReady
        ? _mapController.camera.visibleBounds
        : null;
    final nextTier = MapClusterService.tierForZoom(resolvedZoom);
    setState(() {
      _zoom = resolvedZoom;
      _center = resolvedCenter;
      _clusterTier = nextTier;
      _areaGridZoomBucket = (resolvedZoom * 2).round();
      if (resolvedBounds != null) {
        _visibleBounds = resolvedBounds;
        _carouselBounds = resolvedBounds;
      }
    });
  }

  void _openIncidentSheet(CivicReport report, Bilingual tr) {
    final repo = ReportScope.read(context);
    var isCheckingSupport = false;
    SupportActionOutcome? supportOutcome;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return ListenableBuilder(
              listenable: repo,
              builder: (context, _) {
                final live = repo.findById(report.id) ?? report;
                final priority = live.priority;
                final alreadyContributed = live.isContributedByCurrentUser;
                final isOwnReport =
                    live.createdByCurrentUser ||
                    (live.isMine && !live.joinedByCurrentUser);

                Future<void> handleMapSupport() async {
                  if (isCheckingSupport || alreadyContributed) return;
                  setSheetState(() {
                    isCheckingSupport = true;
                    supportOutcome = null;
                  });
                  final outcome = await SupportActionCoordinator.requestSupport(
                    context: sheetContext,
                    repository: repo,
                    report: live,
                    locationService: widget.locationService,
                    bilingual: tr,
                  );
                  if (!sheetContext.mounted) return;
                  setSheetState(() {
                    isCheckingSupport = false;
                    supportOutcome = outcome;
                  });
                }

                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            InkWell(
                              onTap: () => PhotoLightboxPage.open(
                                context,
                                category: live.category,
                                bilingual: tr,
                                localPhotoPath: live.localPhotoPath,
                                assetPath: live.photoAssetPath,
                                title: tr.primary(
                                  live.khmerTitle,
                                  live.englishTitle,
                                ),
                                subtitle: live.id,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              child: ReportPhoto(
                                category: live.category,
                                localPhotoPath: live.localPhotoPath,
                                assetPath: live.photoAssetPath,
                                width: 76,
                                height: 76,
                                borderRadius: 16,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        live.id,
                                        style: AppFonts.displayStyle(
                                          fontSize: 13,
                                          color: AppColors.teal,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      PriorityBadge(
                                        breakdown: priority,
                                        bilingual: tr,
                                        compact: true,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  BilingualText(
                                    bilingual: tr,
                                    khmer: live.khmerTitle,
                                    english: live.englishTitle,
                                    fontSize: 16,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tr.primary(
                                      live.khmerLocation,
                                      live.englishLocation,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          key: const Key('map-sheet-description'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 1),
                                child: Icon(
                                  Icons.notes_rounded,
                                  size: 15,
                                  color: AppColors.teal,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      live.hasDescription
                                          ? live.description.trim()
                                          : tr.primary(
                                              'គ្មានមតិបន្ថែម',
                                              'No comment',
                                            ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        color: live.hasDescription
                                            ? AppColors.ink
                                            : AppColors.muted,
                                        fontStyle: live.hasDescription
                                            ? FontStyle.normal
                                            : FontStyle.italic,
                                      ),
                                    ),
                                    if (live.extraCommentCount > 0) ...[
                                      const SizedBox(height: 5),
                                      Container(
                                        key: const Key(
                                          'map-sheet-more-comments-pill',
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.tealSoft,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          tr.primary(
                                            '+${live.extraCommentCount} មតិផ្សេងទៀត',
                                            '+${live.extraCommentCount} more comment(s)',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.tealDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Chip(
                              avatar: const Icon(
                                Icons.groups_outlined,
                                size: 16,
                                color: AppColors.teal,
                              ),
                              label: Text(
                                tr.primary(
                                  '${live.affectedCitizens} នាក់រងផលប៉ះពាល់',
                                  '${live.affectedCitizens} affected',
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Chip(
                              avatar: const Icon(
                                Icons.account_balance_outlined,
                                size: 15,
                                color: AppColors.muted,
                              ),
                              label: Text(
                                tr.primary(
                                  live.khmerAgency,
                                  live.englishAgency,
                                ),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            if (live.provinceCode !=
                                CambodiaLocationCatalog.phnomPenhCode)
                              Chip(
                                avatar: const Icon(
                                  Icons.public_rounded,
                                  size: 15,
                                  color: AppColors.teal,
                                ),
                                label: Text(
                                  tr.primary(
                                    live.khmerProvince,
                                    live.englishProvince,
                                  ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              size: 14,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                tr.primary(
                                  'ផែនទីសាធារណៈ · អត្តសញ្ញាណអ្នករាយការណ៍ត្រូវបានលាក់ដោយស្វ័យប្រវត្តិ',
                                  'Public map · Reporter identity is anonymized automatically.',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (supportOutcome?.message != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            key: const Key('map-support-feedback-banner'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: supportOutcome!.isError
                                  ? AppColors.saffronSoft
                                  : AppColors.tealSoft,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: supportOutcome!.isError
                                    ? AppColors.saffron.withValues(alpha: 0.65)
                                    : AppColors.teal.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  supportOutcome!.isError
                                      ? Icons.location_off_outlined
                                      : Icons.verified_rounded,
                                  size: 16,
                                  color: supportOutcome!.isError
                                      ? AppColors.saffronInk
                                      : AppColors.teal,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    supportOutcome!.message!,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: supportOutcome!.isError
                                          ? AppColors.saffronInk
                                          : AppColors.tealDark,
                                    ),
                                  ),
                                ),
                                if (supportOutcome!.canOpenLocationSettings)
                                  TextButton(
                                    onPressed: widget
                                        .locationService
                                        .openLocationSettings,
                                    child: Text(
                                      tr.primary('បើក GPS', 'GPS'),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (live.status != ReportStatus.resolved) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const Key('map-support-btn'),
                                  onPressed:
                                      (alreadyContributed || isCheckingSupport)
                                      ? null
                                      : handleMapSupport,
                                  icon: isCheckingSupport
                                      ? const SizedBox(
                                          width: 15,
                                          height: 15,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          alreadyContributed
                                              ? Icons.check
                                              : Icons.thumb_up_alt_outlined,
                                          size: 17,
                                        ),
                                  label: Text(
                                    isCheckingSupport
                                        ? tr.primary(
                                            'កំពុងផ្ទៀងផ្ទាត់...',
                                            'Verifying...',
                                          )
                                        : isOwnReport
                                        ? tr.primary(
                                            'របាយការណ៍របស់អ្នក',
                                            'Your report',
                                          )
                                        : alreadyContributed
                                        ? tr.primary('បានគាំទ្រ', 'Supported')
                                        : tr.primary(
                                            'ខ្ញុំក៏ប៉ះពាល់',
                                            'Affects me',
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  Navigator.push<void>(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => TrackingPage(
                                        reportId: live.id,
                                        locationService: widget.locationService,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.route, size: 17),
                                label: Text(
                                  tr.primary('តាមដានការជួសជុល', 'Track Repair'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final filteredReports = _filterReports(repo.reports);
    final highlightedId = _activeReportId ?? widget.focusedReportId;
    final clusterItems = MapClusterService.clusterForZoom(
      reports: filteredReports,
      zoom: _zoom,
      visibleBounds: _visibleBounds,
    );
    final viewportReports =
        _zoom < MapClusterService.provinceClusterMaxZoom ||
            _query.trim().isNotEmpty
        ? filteredReports
        : MapClusterService.reportsInViewport(
            reports: filteredReports,
            bounds: _carouselBounds ?? _visibleBounds,
            center: _center,
          );
    final isOverviewZoom = _zoom < MapClusterService.provinceClusterMaxZoom;
    final showBottomCarousel =
        _customPin == null &&
        (!isOverviewZoom || _query.trim().isNotEmpty) &&
        viewportReports.isNotEmpty;
    final showEmptyAreaBanner =
        _customPin == null &&
        !isOverviewZoom &&
        viewportReports.isEmpty &&
        filteredReports.isNotEmpty;
    final currentProvince = isOverviewZoom
        ? null
        : CambodiaLocationCatalog.nearestProvinceForPoint(_center);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              minZoom: LocationService.minMapZoom,
              maxZoom: LocationService.maxMapZoom,
              cameraConstraint: CameraConstraint.contain(
                bounds: LocationService.cambodiaMapBounds,
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                _mapReady = true;
                _visibleBounds = _mapController.camera.visibleBounds;
                _carouselBounds = _visibleBounds;
                if (mounted) setState(() {});
              },
              onPositionChanged: (camera, hasGesture) =>
                  _handleCameraPositionChanged(camera, hasGesture: hasGesture),
              onTap: (_, point) {
                HapticFeedback.selectionClick();
                setState(() {
                  _customPin = point;
                  _outsideCambodiaDetected = false;
                });
                _updatePinLabel(point);
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
              MarkerLayer(
                markers: [
                  if (_customPin != null)
                    Marker(
                      point: _customPin!,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on,
                        color: AppColors.teal,
                        size: 44,
                      ),
                    ),
                  for (final item in clusterItems)
                    switch (item) {
                      ProvinceClusterItem() => Marker(
                        point: item.position,
                        width: 148,
                        height: 38,
                        child: _ProvinceClusterBubble(
                          key: Key('province-cluster-${item.province.code}'),
                          label: tr.primary(
                            item.province.shortKhmer,
                            item.province.english,
                          ),
                          count: item.count,
                          color: item.allResolved
                              ? AppColors.success
                              : AppColors.priorityColor(item.maxPriorityLevel),
                          countForeground: item.allResolved
                              ? Colors.white
                              : AppColors.priorityForeground(
                                  item.maxPriorityLevel,
                                ),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _flyToPoint(
                              item.position,
                              item.province.isCapital ? 13.8 : 13.6,
                            );
                          },
                        ),
                      ),
                      AreaClusterItem() => Marker(
                        point: item.position,
                        width: 52,
                        height: 52,
                        child: _AreaClusterMarker(
                          count: item.count,
                          color: item.allResolved
                              ? AppColors.success
                              : AppColors.priorityColor(item.maxPriorityLevel),
                          foreground: item.allResolved
                              ? Colors.white
                              : AppColors.priorityForeground(
                                  item.maxPriorityLevel,
                                ),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _flyToPoint(
                              item.position,
                              (_zoom + 2.2).clamp(13.6, 16.0).toDouble(),
                            );
                          },
                        ),
                      ),
                      SingleReportPinItem(:final report) => Marker(
                        point: report.coordinates,
                        width: highlightedId == report.id ? 52 : 44,
                        height: highlightedId == report.id ? 52 : 44,
                        child: _PriorityMarker(
                          label: report.status == ReportStatus.resolved
                              ? '✓'
                              : 'P${report.priority.level}',
                          color: report.status == ReportStatus.resolved
                              ? AppColors.success
                              : AppColors.priorityColor(report.priority.level),
                          foreground: report.status == ReportStatus.resolved
                              ? Colors.white
                              : AppColors.priorityForeground(
                                  report.priority.level,
                                ),
                          highlighted: highlightedId == report.id,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _activeReportId = report.id;
                              _customPin = null;
                            });
                            _openIncidentSheet(report, tr);
                          },
                        ),
                      ),
                    },
                ],
              ),
            ],
          ),

          // Floating Search Bar, Category Chips & Collapsible Priority Legend
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
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
                          tooltip: tr.primary('ត្រឡប់', 'Back'),
                          onPressed: () {
                            if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            } else {
                              widget.onBack?.call();
                            }
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SearchBar(
                          controller: _searchController,
                          backgroundColor: const WidgetStatePropertyAll(
                            Colors.white,
                          ),
                          hintText: tr.primary(
                            'ស្វែងរកផ្លូវ ទីតាំង ឬលេខកូដ...',
                            'Search street, place, or ID...',
                          ),
                          leading: _isSearchingPlace
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search),
                          trailing: [
                            if (_query.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                            IconButton(
                              key: const Key('map-legend-toggle'),
                              tooltip: tr.primary(
                                'កម្រិតអាទិភាព P1–P5',
                                'Priority legend',
                              ),
                              icon: Icon(
                                _showLegend
                                    ? Icons.info_rounded
                                    : Icons.info_outline_rounded,
                                size: 20,
                                color: _showLegend
                                    ? AppColors.teal
                                    : AppColors.muted,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() => _showLegend = !_showLegend);
                              },
                            ),
                          ],
                          elevation: const WidgetStatePropertyAll(3),
                          onChanged: (value) => setState(() => _query = value),
                          onSubmitted: (value) =>
                              _handleSearchSubmit(value, repo.reports, tr),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ActionChip(
                          key: const Key('map-province-filter-btn'),
                          backgroundColor: AppColors.teal,
                          side: BorderSide.none,
                          avatar: const Icon(
                            Icons.public_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentProvince == null
                                    ? tr.primary(
                                        'ទូទាំងកម្ពុជា',
                                        'All Cambodia',
                                      )
                                    : tr.primary(
                                        currentProvince.shortKhmer,
                                        currentProvince.english,
                                      ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ],
                          ),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _openProvinceJumpSheet(repo, tr);
                          },
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: Text(
                            tr.primary(
                              'ទាំងអស់ (${repo.reports.length})',
                              'All (${repo.reports.length})',
                            ),
                          ),
                          selected: _selectedCategory == null,
                          backgroundColor: Colors.white,
                          onSelected: (_) {
                            setState(() => _selectedCategory = null);
                            if (_carouselController.hasClients) {
                              _carouselController.jumpToPage(0);
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        for (final cat in IssueCategory.values) ...[
                          FilterChip(
                            label: Text(tr.categoryPrimary(cat)),
                            selected: _selectedCategory == cat,
                            backgroundColor: Colors.white,
                            onSelected: (selected) {
                              setState(
                                () => _selectedCategory = selected ? cat : null,
                              );
                              if (_carouselController.hasClients) {
                                _carouselController.jumpToPage(0);
                              }
                            },
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                  if (_showLegend)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          _LegendDot(
                            color: AppColors.priorityColor(5),
                            label: 'P5 ${tr.primary('បន្ទាន់', 'Critical')}',
                          ),
                          _LegendDot(
                            color: AppColors.priorityColor(4),
                            label: 'P4 ${tr.primary('ខ្ពស់', 'High')}',
                          ),
                          _LegendDot(
                            color: AppColors.priorityColor(3),
                            label: 'P3 ${tr.primary('មធ្យម', 'Medium')}',
                          ),
                          _LegendDot(
                            color: AppColors.priorityColor(2),
                            label: 'P2 ${tr.primary('ទាប', 'Low')}',
                          ),
                          _LegendDot(
                            color: AppColors.success,
                            label: '✓ ${tr.primary('ជួសជុលរួច', 'Resolved')}',
                          ),
                        ],
                      ),
                    ),
                  if (_outsideCambodiaDetected && _rawOutsidePoint != null)
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tr.primary(
                                'GPS ឧបករណ៍នៅក្រៅកម្ពុជា (${_rawOutsidePoint!.latitude.toStringAsFixed(2)}, ${_rawOutsidePoint!.longitude.toStringAsFixed(2)})',
                                'Emulator / GPS outside Cambodia (${_rawOutsidePoint!.latitude.toStringAsFixed(2)}, ${_rawOutsidePoint!.longitude.toStringAsFixed(2)})',
                              ),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.saffronInk,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _centerOnPhnomPenh,
                            child: Text(
                              tr.primary('ភ្នំពេញ', 'Phnom Penh'),
                              style: const TextStyle(
                                color: AppColors.teal,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
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

          // Right-hand Zoom & Locate FAB Stack
          Positioned(
            right: 16,
            bottom: _customPin != null
                ? 24
                : showBottomCarousel
                ? 132
                : showEmptyAreaBanner
                ? 76
                : 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'map-zoom-in',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                    onPressed: () => _setZoom(_zoom + 1),
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'map-zoom-out',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                    onPressed: () => _setZoom(_zoom - 1),
                    child: const Icon(Icons.remove),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'map-locate',
                    backgroundColor: AppColors.teal,
                    foregroundColor: Colors.white,
                    onPressed: _isLocating ? null : () => _locateMe(tr),
                    child: _isLocating
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
            ),
          ),

          // Bottom Action Card (Custom Pin) OR Swipeable Nearby Incidents Carousel
          if (_customPin != null)
            Positioned(
              left: 16,
              right: 84,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: AppColors.teal,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _customPinLabel ??
                                  '${_customPin!.latitude.toStringAsFixed(4)}, ${_customPin!.longitude.toStringAsFixed(4)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          if (_lastAccuracyMeters != null)
                            Text(
                              '±${_lastAccuracyMeters!.round()}m',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.teal,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 17),
                            onPressed: () => setState(() => _customPin = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ReportWizardPage(
                                initialCoordinates: _customPin,
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.add_location_alt_outlined,
                            size: 18,
                          ),
                          label: Text(
                            tr.primary(
                              'រាយការណ៍នៅចំណុចនេះ',
                              'Report at Pinned Spot',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (showBottomCarousel)
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        key: const Key('map-viewport-count-pill'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.border),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Text(
                          isOverviewZoom
                              ? tr.primary(
                                  'ទូទាំងកម្ពុជា · ${viewportReports.length} របាយការណ៍',
                                  'All Cambodia · ${viewportReports.length} report(s)',
                                )
                              : tr.primary(
                                  'ក្នុងផែនទីនេះ · ${viewportReports.length} របាយការណ៍',
                                  'In this area · ${viewportReports.length} report(s)',
                                ),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 102,
                      child: PageView.builder(
                        key: const Key('map-nearby-carousel'),
                        controller: _carouselController,
                        itemCount: viewportReports.length,
                        onPageChanged: (index) {
                          if (index < 0 || index >= viewportReports.length) {
                            return;
                          }
                          HapticFeedback.selectionClick();
                          final report = viewportReports[index];
                          setState(() => _activeReportId = report.id);
                          if (_mapReady) {
                            final targetZoom =
                                _zoom < MapClusterService.provinceClusterMaxZoom
                                ? _zoom
                                : (_zoom >= 13.4 ? _zoom : 15.6);
                            _mapController.move(report.coordinates, targetZoom);
                          }
                        },
                        itemBuilder: (context, index) {
                          final report = viewportReports[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: InkWell(
                              onTap: () => _openIncidentSheet(report, tr),
                              borderRadius: BorderRadius.circular(22),
                              child: Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: highlightedId == report.id
                                        ? AppColors.teal
                                        : AppColors.border,
                                    width: highlightedId == report.id ? 1.6 : 1,
                                  ),
                                  boxShadow: AppColors.cardShadow,
                                ),
                                child: Row(
                                  children: [
                                    ReportPhoto(
                                      category: report.category,
                                      localPhotoPath: report.localPhotoPath,
                                      assetPath:
                                          report.status == ReportStatus.resolved
                                          ? (report.resolvedAfterAssetPath ??
                                                report.photoAssetPath)
                                          : report.photoAssetPath,
                                      width: 72,
                                      height: 72,
                                      borderRadius: 14,
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                report.id,
                                                style: AppFonts.displayStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.teal,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              PriorityBadge(
                                                breakdown: report.priority,
                                                bilingual: tr,
                                                compact: true,
                                              ),
                                              const Spacer(),
                                              Text(
                                                '×${report.affectedCitizens}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            tr.primary(
                                              report.khmerTitle,
                                              report.englishTitle,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          Text(
                                            tr.primary(
                                              report.khmerLocation,
                                              report.englishLocation,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
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
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (showEmptyAreaBanner)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.explore_outlined,
                        color: AppColors.teal,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr.primary(
                            'គ្មានរបាយការណ៍ក្នុងតំបន់នេះទេ',
                            'No reports in this map area',
                          ),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('map-empty-area-all-cambodia-btn'),
                        onPressed: _flyToAllCambodia,
                        child: Text(
                          tr.primary('ទូទាំងកម្ពុជា', 'All Cambodia'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _ProvinceClusterBubble extends StatelessWidget {
  const _ProvinceClusterBubble({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.countForeground,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final Color countForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color, width: 2.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 7,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: AppFonts.displayStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: countForeground,
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

class _AreaClusterMarker extends StatelessWidget {
  const _AreaClusterMarker({
    required this.count,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  final int count;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.24),
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(5),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            '$count',
            style: AppFonts.displayStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _PriorityMarker extends StatelessWidget {
  const _PriorityMarker({
    required this.label,
    required this.color,
    required this.foreground,
    required this.onTap,
    this.highlighted = false,
  });

  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: highlighted ? AppColors.ink : Colors.white,
            width: highlighted ? 3.5 : 3,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: AppFonts.displayStyle(
            color: foreground,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
