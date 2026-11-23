import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/models/cambodia_locations.dart';
import '../../domain/models/report_models.dart';
import '../../domain/models/routing_result.dart';
import '../../domain/services/gis_routing_service.dart';
import '../../domain/services/priority_calculator.dart';
import '../../domain/services/relative_time_formatter.dart';
import '../../domain/services/spatial_clustering_service.dart';
import '../../domain/services/support_eligibility_service.dart';
import '../services/local_storage_service.dart';
import '../services/reverse_geocoding_service.dart';

/// Typed outcome when a citizen attempts to withdraw a submitted report.
sealed class ReportRemovalResult {
  const ReportRemovalResult();
}

final class ReportRemoved extends ReportRemovalResult {
  const ReportRemoved();
}

final class RemovalWindowExpired extends ReportRemovalResult {
  const RemovalWindowExpired();
}

final class RemovalLockedByAuthority extends ReportRemovalResult {
  const RemovalLockedByAuthority();
}

final class RemovalNotAllowed extends ReportRemovalResult {
  const RemovalNotAllowed();
}

/// Single source of truth for citizen profile, civic reports, alerts, drafts,
/// and user preferences—with automatic local JSON persistence.
class ReportRepository extends ChangeNotifier {
  ReportRepository({
    List<CivicReport>? initialReports,
    List<AlertItem>? initialAlerts,
    AppSettings? initialSettings,
    UserProfile? initialProfile,
    ReportDraft? initialDraft,
    this.storage,
  }) : _reports = List<CivicReport>.of(initialReports ?? _seedReports()),
       _alerts = List<AlertItem>.of(initialAlerts ?? _seedAlerts()),
       _settings = initialSettings ?? const AppSettings(),
       _profile = initialProfile ?? const UserProfile(),
       _draft = initialDraft;

  final List<CivicReport> _reports;
  final List<AlertItem> _alerts;
  final List<DateTime> _supportVoteTimestamps = <DateTime>[];
  final LocalStorageService? storage;
  AppSettings _settings;
  UserProfile _profile;
  ReportDraft? _draft;
  int _nextTicketNumber = 20540;
  bool _isOnline = true;

  /// Number of "Affects me" votes cast by the citizen in the trailing 24 hours.
  int supportsUsedInLast24Hours({DateTime? now}) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(const Duration(hours: 24));
    _supportVoteTimestamps.removeWhere((ts) => ts.isBefore(cutoff));
    return _supportVoteTimestamps.length;
  }

  UnmodifiableListView<CivicReport> get reports =>
      UnmodifiableListView(_reports);

  UnmodifiableListView<AlertItem> get alerts => UnmodifiableListView(_alerts);

  AppSettings get settings => _settings;

  UserProfile get profile => _profile;

  ReportDraft? get draft => _draft;

  bool get isOnline => _isOnline;

  int get pendingSyncCount =>
      _reports.where((r) => r.syncStatus == SyncStatus.pendingSync).length;

  bool get hasPendingSync => pendingSyncCount > 0;

  /// Active Province, District (`ខណ្ឌ / ក្រុង / ស្រុក`), & optional Commune
  /// (`សង្កាត់ / ឃុំ`) for Area News. Defaults to the citizen's Home Area from
  /// [profile] unless overridden in [settings].
  /// - `(province: null, khan: null, sangkat: null)` -> All Cambodia (25 provinces)
  /// - `(province: P, khan: null, sangkat: null)` -> All Districts in Province P
  ({ProvinceOption? province, KhanOption? khan, SangkatOption? sangkat})
  get resolvedNewsArea {
    if (_settings.newsProvinceCode == AppSettings.allCambodiaKey) {
      return (province: null, khan: null, sangkat: null);
    }

    final hasHome = _profile.hasHomeArea;
    final home = hasHome
        ? CambodiaLocationCatalog.matchFromProfileArea(
            khmerArea: _profile.khmerHomeArea,
            englishArea: _profile.englishHomeArea,
            provinceCode: _profile.homeProvinceCode,
          )
        : (
            province: CambodiaLocationCatalog.phnomPenh,
            khan: null,
            sangkat: null,
          );

    final activeProvince =
        CambodiaLocationCatalog.findProvinceByCode(
          _settings.newsProvinceCode,
        ) ??
        home.province;

    if (_settings.newsKhanEnglish == AppSettings.allPhnomPenhKey) {
      return (province: activeProvince, khan: null, sangkat: null);
    }

    if (_settings.newsKhanEnglish != null) {
      final overrideKhan =
          CambodiaLocationCatalog.findDistrictInProvince(
            activeProvince,
            _settings.newsKhanEnglish,
          ) ??
          CambodiaLocationCatalog.findKhanByEnglish(_settings.newsKhanEnglish);
      if (overrideKhan != null) {
        final overrideSangkat = CambodiaLocationCatalog.findSangkatInKhan(
          overrideKhan,
          _settings.newsSangkatEnglish,
        );
        return (
          province: activeProvince,
          khan: overrideKhan,
          sangkat: overrideSangkat,
        );
      }
    }

    // If user explicitly switched to another province without picking a district
    // yet, show all districts in that province.
    if (_settings.newsProvinceCode != null &&
        _settings.newsProvinceCode != home.province.code) {
      return (province: activeProvince, khan: null, sangkat: null);
    }

    return (province: home.province, khan: home.khan, sangkat: home.sangkat);
  }

  /// All community + user-uploaded reports matching the chosen Province/District/Commune
  /// and optional [category], sorted by [sort] (default: newest first).
  List<CivicReport> newsReportsForArea({
    ProvinceOption? province,
    KhanOption? khan,
    SangkatOption? sangkat,
    IssueCategory? category,
    ReportSortOption sort = ReportSortOption.newest,
  }) {
    final matches = _reports.where((report) {
      if (category != null && report.category != category) return false;
      return CambodiaLocationCatalog.locationMatchesArea(
        khmerLocation: report.khmerLocation,
        englishLocation: report.englishLocation,
        reportProvinceCode: report.provinceCode,
        province: province,
        khan: khan,
        sangkat: sangkat,
      );
    }).toList();
    sortReportsInPlace(matches, sort);
    return matches;
  }

  /// Sorts a mutable report list in-place according to [sort].
  static void sortReportsInPlace(
    List<CivicReport> list,
    ReportSortOption sort,
  ) {
    switch (sort) {
      case ReportSortOption.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ReportSortOption.highestPriority:
        list.sort((a, b) {
          final scoreCmp = b.priority.rawScore.compareTo(a.priority.rawScore);
          if (scoreCmp != 0) return scoreCmp;
          final countCmp = b.affectedCitizens.compareTo(a.affectedCitizens);
          if (countCmp != 0) return countCmp;
          return b.createdAt.compareTo(a.createdAt);
        });
      case ReportSortOption.mostAffected:
        list.sort((a, b) {
          final countCmp = b.affectedCitizens.compareTo(a.affectedCitizens);
          if (countCmp != 0) return countCmp;
          final scoreCmp = b.priority.rawScore.compareTo(a.priority.rawScore);
          if (scoreCmp != 0) return scoreCmp;
          return b.createdAt.compareTo(a.createdAt);
        });
    }
  }

  /// Counts total reports in a given [province] (used for 25-province pickers).
  int reportCountForProvince(ProvinceOption province) => _reports
      .where(
        (report) => CambodiaLocationCatalog.locationMatchesArea(
          khmerLocation: report.khmerLocation,
          englishLocation: report.englishLocation,
          reportProvinceCode: report.provinceCode,
          province: province,
        ),
      )
      .length;

  /// Counts total reports matching a given [khan] (used for picker badges).
  int reportCountForKhan(KhanOption khan, {ProvinceOption? province}) =>
      _reports
          .where(
            (report) => CambodiaLocationCatalog.locationMatchesArea(
              khmerLocation: report.khmerLocation,
              englishLocation: report.englishLocation,
              reportProvinceCode: report.provinceCode,
              province: province,
              khan: khan,
            ),
          )
          .length;

  /// Builds the backend-ready query parameters for `GET /api/v1/reports?bbox=...`
  /// so nationwide map viewport loading stays fast once the PostGIS server connects.
  Map<String, String> buildMapViewportQuery({
    required LatLngBounds bounds,
    required double zoom,
    String? provinceCode,
    IssueCategory? category,
  }) => {
    'min_lat': bounds.south.toStringAsFixed(5),
    'min_lng': bounds.west.toStringAsFixed(5),
    'max_lat': bounds.north.toStringAsFixed(5),
    'max_lng': bounds.east.toStringAsFixed(5),
    'zoom': zoom.toStringAsFixed(1),
    if (provinceCode != null && provinceCode.isNotEmpty)
      'province_code': provinceCode,
    if (category != null) 'category': category.name,
  };

  int get unreadAlertCount => _settings.notificationsEnabled
      ? _alerts.where((alert) => !alert.isRead).length
      : 0;

  List<CivicReport> get myReports =>
      _reports.where((report) => report.isMine).toList(growable: false);

  List<CivicReport> get activeTrackingReports => _reports
      .where(
        (report) => report.isMine && report.status != ReportStatus.resolved,
      )
      .toList(growable: false);

  int get totalCitizensHelped =>
      myReports.fold<int>(0, (sum, report) => sum + report.affectedCitizens);

  int get myResolvedCount => myReports
      .where((report) => report.status == ReportStatus.resolved)
      .length;

  /// Open incidents sorted highest Priority Score first.
  List<CivicReport> get staffVerificationQueue {
    final open = _reports
        .where((r) => r.status != ReportStatus.resolved)
        .toList();
    open.sort((a, b) {
      final scoreCmp = b.priority.rawScore.compareTo(a.priority.rawScore);
      if (scoreCmp != 0) return scoreCmp;
      return b.affectedCitizens.compareTo(a.affectedCitizens);
    });
    return open;
  }

  /// Hydrates saved reports, profile, alerts, settings, and draft from disk.
  Future<void> hydrate() async {
    final store = storage;
    if (store == null) return;
    final data = await store.readState();
    if (data == null) return;

    final rawReports = data['reports'];
    if (rawReports is List && rawReports.isNotEmpty) {
      final parsed = rawReports
          .whereType<Map<String, dynamic>>()
          .map(CivicReport.fromJson)
          .toList();
      if (parsed.isNotEmpty) {
        _reports
          ..clear()
          ..addAll(parsed);
      }
    }

    final rawAlerts = data['alerts'];
    if (rawAlerts is List && rawAlerts.isNotEmpty) {
      final parsed = rawAlerts
          .whereType<Map<String, dynamic>>()
          .map(AlertItem.fromJson)
          .toList();
      if (parsed.isNotEmpty) {
        _alerts
          ..clear()
          ..addAll(parsed);
      }
    }

    final rawSettings = data['settings'];
    if (rawSettings is Map<String, dynamic>) {
      _settings = AppSettings.fromJson(rawSettings);
    }

    final rawProfile = data['profile'];
    if (rawProfile is Map<String, dynamic>) {
      _profile = UserProfile.fromJson(rawProfile);
    }

    final rawDraft = data['draft'];
    if (rawDraft is Map<String, dynamic>) {
      _draft = ReportDraft.fromJson(rawDraft);
    }

    final savedNext = data['nextTicketNumber'];
    if (savedNext is num && savedNext.toInt() > _nextTicketNumber) {
      _nextTicketNumber = savedNext.toInt();
    }

    final rawVotes = data['supportVoteTimestamps'];
    if (rawVotes is List) {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      _supportVoteTimestamps
        ..clear()
        ..addAll(
          rawVotes
              .whereType<String>()
              .map(DateTime.tryParse)
              .whereType<DateTime>()
              .where((ts) => !ts.isBefore(cutoff)),
        );
    }

    notifyListeners();
  }

  void _persist() {
    final store = storage;
    if (store == null) return;
    unawaited(
      store.writeState({
        'reports': _reports.map((r) => r.toJson()).toList(),
        'alerts': _alerts.map((a) => a.toJson()).toList(),
        'settings': _settings.toJson(),
        'profile': _profile.toJson(),
        'draft': _draft?.toJson(),
        'nextTicketNumber': _nextTicketNumber,
        'supportVoteTimestamps': _supportVoteTimestamps
            .map((ts) => ts.toIso8601String())
            .toList(),
      }),
    );
  }

  void updateProfile(UserProfile next) {
    _profile = next;
    _persist();
    notifyListeners();
  }

  /// Updates live network connectivity state. When connectivity returns and
  /// queued offline reports exist, automatically syncs them.
  void setOnlineStatus(bool online, {DateTime? now}) {
    final wasOffline = !_isOnline;
    if (_isOnline == online) return;
    _isOnline = online;
    if (online && wasOffline && hasPendingSync) {
      syncPendingReports(now: now);
      return;
    }
    notifyListeners();
  }

  /// Marks all queued offline reports as synced, persists state, and fires a
  /// citizen confirmation notification.
  int syncPendingReports({DateTime? now}) {
    var syncedCount = 0;
    String? latestReportId;
    for (var i = 0; i < _reports.length; i++) {
      if (_reports[i].syncStatus == SyncStatus.pendingSync) {
        _reports[i] = _reports[i].copyWith(syncStatus: SyncStatus.synced);
        latestReportId ??= _reports[i].id;
        syncedCount++;
      }
    }
    if (syncedCount == 0) {
      notifyListeners();
      return 0;
    }

    final syncedAt = now ?? DateTime.now();
    _alerts.insert(
      0,
      AlertItem(
        id: 'alert-sync-${syncedAt.microsecondsSinceEpoch}',
        reportId: latestReportId ?? _reports.first.id,
        khmerTitle: 'បានផ្ញើរបាយការណ៍ក្រៅបណ្តាញ ($syncedCount) រួចរាល់',
        englishTitle: 'Synced $syncedCount queued report(s)',
        khmerSubtitle:
            'របាយការណ៍ដែលរក្សាទុកពេលគ្មានអ៊ីនធឺណិតត្រូវបានបញ្ជូនទៅអាជ្ញាធរហើយ',
        englishSubtitle:
            'Offline-queued report(s) uploaded and routed automatically.',
        createdAt: syncedAt,
        isRead: false,
      ),
    );
    _persist();
    notifyListeners();
    return syncedCount;
  }

  void setNewsArea({
    ProvinceOption? province,
    required KhanOption? khan,
    SangkatOption? sangkat,
  }) {
    if (province == null && khan == null) {
      _settings = _settings.copyWith(
        newsProvinceCode: AppSettings.allCambodiaKey,
        newsKhanEnglish: AppSettings.allPhnomPenhKey,
        clearNewsSangkat: true,
      );
    } else if (khan == null) {
      _settings = _settings.copyWith(
        newsProvinceCode: province!.code,
        newsKhanEnglish: AppSettings.allPhnomPenhKey,
        clearNewsSangkat: true,
      );
    } else {
      final resolvedProvince =
          province ??
          resolvedNewsArea.province ??
          CambodiaLocationCatalog.phnomPenh;
      _settings = _settings.copyWith(
        newsProvinceCode: resolvedProvince.code,
        newsKhanEnglish: khan.english,
        newsSangkatEnglish: sangkat?.english,
        clearNewsSangkat: sangkat == null,
      );
    }
    _persist();
    notifyListeners();
  }

  /// Views all districts inside the currently active province (defaults to Phnom Penh).
  void setNewsAreaAllPhnomPenh() => setNewsArea(
    province: resolvedNewsArea.province ?? CambodiaLocationCatalog.phnomPenh,
    khan: null,
  );

  /// Views live civic reports across all 25 provinces of Cambodia.
  void setNewsAreaAllCambodia() => setNewsArea(province: null, khan: null);

  void resetNewsAreaToHome() {
    _settings = _settings.copyWith(clearNewsArea: true);
    _persist();
    notifyListeners();
  }

  void saveDraft(ReportDraft draft) {
    _draft = draft;
    _persist();
    notifyListeners();
  }

  void clearDraft() {
    if (_draft == null) return;
    _draft = null;
    _persist();
    notifyListeners();
  }

  CivicReport? findById(String id) {
    for (final report in _reports) {
      if (report.id == id) return report;
    }
    return null;
  }

  /// Checks whether an open Master Incident of the same [category] exists
  /// within the 50 m spatial clustering radius (or 120 m on the same road).
  DuplicateMatch? findDuplicateNearby({
    required LatLng point,
    required IssueCategory category,
    double radiusMeters = SpatialClusteringService.defaultRadiusMeters,
    String? roadName,
  }) {
    return SpatialClusteringService.findNearestDuplicate(
      point: point,
      category: category,
      existingReports: _reports,
      radiusMeters: radiusMeters,
      roadName: roadName,
    );
  }

  /// Submits a citizen report. Merges into an existing Master Incident if an
  /// open same-category incident lies within 50 m (or 120 m on the same road)
  /// unless [forceCreateNew] is set ("It's a different problem").
  ReportSubmissionResult submitReport({
    required IssueCategory category,
    required String description,
    required int severity,
    required LatLng coordinates,
    required bool isAnonymous,
    String? customTitle,
    String? localPhotoPath,
    List<String> additionalLocalPhotoPaths = const [],
    String? voiceTranscript,
    GeocodedPlace? geocodedPlace,
    bool forceCreateNew = false,
    DateTime? now,
  }) {
    final submittedAt = now ?? DateTime.now();
    _draft = null;
    final duplicate = findDuplicateNearby(
      point: coordinates,
      category: category,
      roadName: geocodedPlace?.roadName,
    );

    // Block the same user from duplicating or self-inflating a report they
    // already own, created, or joined at the same spot.
    if (duplicate != null) {
      final existing = duplicate.masterReport;
      final alreadyContributedByUser = existing.isContributedByCurrentUser;

      if (alreadyContributedByUser &&
          (!forceCreateNew ||
              duplicate.distanceMeters <=
                  SpatialClusteringService.hardSelfBlockRadiusMeters)) {
        return ReportSubmissionResult(
          report: existing,
          mergedIntoExisting: true,
          alreadyReportedByUser: true,
          mergedDistanceMeters: duplicate.distanceMeters,
        );
      }

      if (!forceCreateNew) {
        final index = _reports.indexWhere((r) => r.id == existing.id);
        final updatedSeverity = math.max(
          existing.severity,
          severity.clamp(1, 5),
        );
        final updatedCount = existing.affectedCitizens + 1;
        final merged = existing.copyWith(
          severity: updatedSeverity,
          affectedCitizens: updatedCount,
          isMine: true,
          joinedByCurrentUser: true,
          localPhotoPath: localPhotoPath ?? existing.localPhotoPath,
          additionalLocalPhotoPaths: additionalLocalPhotoPaths.isNotEmpty
              ? additionalLocalPhotoPaths
              : existing.additionalLocalPhotoPaths,
          voiceTranscript: voiceTranscript ?? existing.voiceTranscript,
        );

        if (index != -1) {
          _reports[index] = merged;
        }

        _alerts.insert(
          0,
          AlertItem(
            id: 'alert-join-${submittedAt.microsecondsSinceEpoch}',
            reportId: merged.id,
            khmerTitle: 'បានចូលរួមរបាយការណ៍ ${merged.id}',
            englishTitle: 'Joined Master Incident ${merged.id}',
            khmerSubtitle:
                'ប្រជាពលរដ្ឋរងផលប៉ះពាល់កើនដល់ $updatedCount នាក់ · P${merged.priority.level}',
            englishSubtitle:
                'Affected citizens increased to $updatedCount · P${merged.priority.level}',
            createdAt: submittedAt,
            isRead: false,
          ),
        );

        _persist();
        notifyListeners();
        return ReportSubmissionResult(
          report: merged,
          mergedIntoExisting: true,
          mergedDistanceMeters: duplicate.distanceMeters,
        );
      }
    }

    final routing = GisRoutingService.resolve(
      coordinates: coordinates,
      category: category,
      geocodedPlace: geocodedPlace,
    );
    final ticketId = '#SC-${_nextTicketNumber++}';
    final clampedSeverity = severity.clamp(1, 5);
    final priority = PriorityCalculator.calculate(
      trafficScore: routing.roadClass.trafficScore,
      severityScore: clampedSeverity,
      reportCount: 1,
    );

    final trimmedTitle = customTitle?.trim() ?? '';
    final created = CivicReport(
      id: ticketId,
      category: category,
      khmerTitle: trimmedTitle.isNotEmpty
          ? trimmedTitle
          : category.defaultKhmerTitle,
      englishTitle: trimmedTitle.isNotEmpty
          ? trimmedTitle
          : category.defaultEnglishTitle,
      description: description.trim(),
      khmerLocation: routing.fullKhmerLocation,
      englishLocation: routing.fullEnglishLocation,
      coordinates: coordinates,
      provinceCode: routing.provinceCode,
      khmerProvince: routing.khmerProvince,
      englishProvince: routing.englishProvince,
      roadClass: routing.roadClass,
      severity: clampedSeverity,
      affectedCitizens: 1,
      status: ReportStatus.submitted,
      khmerAgency: routing.khmerAgency,
      englishAgency: routing.englishAgency,
      photoAssetPath: category.defaultAssetPath,
      localPhotoPath: localPhotoPath,
      additionalLocalPhotoPaths: additionalLocalPhotoPaths,
      isAnonymous: isAnonymous,
      exifStripped: true,
      isMine: true,
      createdByCurrentUser: true,
      syncStatus: _isOnline ? SyncStatus.synced : SyncStatus.pendingSync,
      voiceTranscript: voiceTranscript,
      beforeDateLabel: RelativeTimeFormatter.formatShortDate(submittedAt),
      afterDateLabel: 'Pending',
      createdAt: submittedAt,
      timeline: _buildTimeline(
        status: ReportStatus.submitted,
        khmerAgency: routing.khmerAgency,
        englishAgency: routing.englishAgency,
        priority: priority,
        submittedAt: submittedAt,
      ),
    );

    _reports.insert(0, created);
    _alerts.insert(
      0,
      AlertItem(
        id: 'alert-${submittedAt.microsecondsSinceEpoch}',
        reportId: created.id,
        khmerTitle: _isOnline
            ? 'បានទទួលរបាយការណ៍ ${created.id}'
            : 'រក្សាទុកក្រៅបណ្តាញ ${created.id}',
        englishTitle: _isOnline
            ? 'Report ${created.id} received'
            : 'Report ${created.id} queued offline',
        khmerSubtitle: _isOnline
            ? 'បញ្ជូនទៅ ${created.khmerAgency}'
            : 'នឹងផ្ញើស្វ័យប្រវត្តិទៅ ${created.khmerAgency} ពេលមានអ៊ីនធឺណិត',
        englishSubtitle: _isOnline
            ? 'Routed to ${created.englishAgency}'
            : 'Saved locally — auto-syncs to ${created.englishAgency} when online',
        createdAt: submittedAt,
        isRead: false,
      ),
    );

    _persist();
    notifyListeners();
    return ReportSubmissionResult(report: created, mergedIntoExisting: false);
  }

  /// Withdraws a report created by the current citizen if it is still
  /// [ReportStatus.submitted] and within [CivicReport.withdrawalWindow].
  ReportRemovalResult withdrawUserReport(String reportId, {DateTime? now}) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return const RemovalNotAllowed();

    final report = _reports[index];
    if (!report.createdByCurrentUser) return const RemovalNotAllowed();
    if (report.status != ReportStatus.submitted) {
      return const RemovalLockedByAuthority();
    }
    if (!report.canWithdraw(now: now)) {
      return const RemovalWindowExpired();
    }

    _reports.removeAt(index);
    _alerts.removeWhere((a) => a.reportId == reportId);
    _persist();
    notifyListeners();
    return const ReportRemoved();
  }

  /// Allows a citizen to quick-edit description & severity during the same
  /// 15-minute grace window before authorities verify the report.
  CivicReport? quickEditUserReport(
    String reportId, {
    required String description,
    required int severity,
    DateTime? now,
  }) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return null;

    final existing = _reports[index];
    if (!existing.canWithdraw(now: now)) return null;

    final nextSeverity = severity.clamp(1, 5);
    final nextPriority = PriorityCalculator.calculate(
      trafficScore: existing.roadClass.trafficScore,
      severityScore: nextSeverity,
      reportCount: existing.affectedCitizens,
    );
    final updated = existing.copyWith(
      description: description.trim(),
      severity: nextSeverity,
      timeline: _buildTimeline(
        status: existing.status,
        khmerAgency: existing.khmerAgency,
        englishAgency: existing.englishAgency,
        priority: nextPriority,
        submittedAt: existing.createdAt,
      ),
    );
    _reports[index] = updated;
    _persist();
    notifyListeners();
    return updated;
  }

  /// Undoes a citizen's `+1 Support` or duplicate join without deleting
  /// another neighbor's Master Incident, refunding the citizen's daily slot.
  CivicReport? undoSupportReport(String reportId) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return null;

    final existing = _reports[index];
    if (!existing.canUndoSupport) return null;

    final updated = existing.copyWith(
      affectedCitizens: math.max(1, existing.affectedCitizens - 1),
      isMine: false,
      joinedByCurrentUser: false,
      clearUserSupportMeta: true,
    );
    _reports[index] = updated;
    if (_supportVoteTimestamps.isNotEmpty) {
      _supportVoteTimestamps.removeLast();
    }
    _alerts.removeWhere(
      (a) => a.reportId == reportId && a.id.startsWith('alert-join-'),
    );
    _persist();
    notifyListeners();
    return updated;
  }

  /// Increments Affected Citizens & recalculates weighted Priority Score live.
  /// Prevents citizens from voting twice on a report they created or joined,
  /// and enforces the 24-hour anti-spam vote cap.
  CivicReport? supportReport(
    String reportId, {
    SupportVerificationTier? tier,
    double? distanceMeters,
    DateTime? now,
  }) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return null;

    final existing = _reports[index];
    final eventTime = now ?? DateTime.now();
    if (existing.status == ReportStatus.resolved ||
        existing.isContributedByCurrentUser) {
      return existing;
    }
    if (supportsUsedInLast24Hours(now: eventTime) >=
        SupportEligibilityService.maxSupportsPer24Hours) {
      return null;
    }

    final updated = existing.copyWith(
      affectedCitizens: existing.affectedCitizens + 1,
      isMine: true,
      joinedByCurrentUser: true,
      userSupportTier: tier,
      userSupportDistanceMeters: distanceMeters,
    );
    _reports[index] = updated;
    _supportVoteTimestamps.add(eventTime);
    _persist();
    notifyListeners();
    return updated;
  }

  /// Builds the backend-ready JSON payload for `POST /api/v1/reports/{id}/support`.
  Map<String, dynamic> buildSupportApiPayload({
    required String reportId,
    required SupportVerificationTier tier,
    double? distanceMeters,
    LatLng? userCoordinates,
  }) => <String, dynamic>{
    'report_id': reportId,
    'verification_tier': tier.name,
    if (distanceMeters != null) 'distance_meters': distanceMeters.round(),
    if (userCoordinates != null) 'lat': userCoordinates.latitude,
    if (userCoordinates != null) 'lng': userCoordinates.longitude,
  };

  /// Records a citizen's 1–5 emoji satisfaction rating on a resolved repair.
  CivicReport? rateResolvedReport(String reportId, int rating) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return null;
    final clamped = rating.clamp(1, 5);
    final updated = _reports[index].copyWith(citizenRating: clamped);
    _reports[index] = updated;
    _persist();
    notifyListeners();
    return updated;
  }

  /// Approves a pending/scheduled report and dispatches a maintenance crew.
  CivicReport? approveAndDispatch(
    String reportId, {
    String crewCode = 'B-07',
    DateTime? now,
  }) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return null;
    final eventTime = now ?? DateTime.now();
    final existing = _reports[index];
    final nextStatus = ReportStatus.crewDispatched;
    final updated = existing.copyWith(
      status: nextStatus,
      crewCode: crewCode,
      timeline: _buildTimeline(
        status: nextStatus,
        khmerAgency: existing.khmerAgency,
        englishAgency: existing.englishAgency,
        priority: existing.priority,
        crewCode: crewCode,
        submittedAt: existing.createdAt,
        dispatchedAt: eventTime,
      ),
    );
    _reports[index] = updated;
    _alerts.insert(
      0,
      AlertItem(
        id: 'alert-dispatch-${eventTime.microsecondsSinceEpoch}',
        reportId: updated.id,
        khmerTitle: 'ក្រុមជួសជុល $crewCode នៅទីតាំងហើយ',
        englishTitle: 'Crew $crewCode dispatched on-site',
        khmerSubtitle: '${updated.khmerTitle} · ${updated.khmerLocation}',
        englishSubtitle: '${updated.englishTitle} · ${updated.englishLocation}',
        createdAt: eventTime,
        isRead: false,
      ),
    );
    _persist();
    notifyListeners();
    return updated;
  }

  /// Marks a repair resolved with after-photo proof and notifies citizens.
  CivicReport? markResolvedWithProof(String reportId, {DateTime? now}) {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index == -1) return null;
    final eventTime = now ?? DateTime.now();
    final existing = _reports[index];
    final crew = existing.crewCode ?? 'B-07';
    final updated = existing.copyWith(
      status: ReportStatus.resolved,
      crewCode: crew,
      resolvedAfterAssetPath: 'assets/pothole-after.jpg',
      afterDateLabel: RelativeTimeFormatter.formatShortDate(eventTime),
      fixedDurationKhmer: 'ជួសជុលរួចរាល់',
      fixedDurationEnglish: 'Fixed & verified',
      timeline: _buildTimeline(
        status: ReportStatus.resolved,
        khmerAgency: existing.khmerAgency,
        englishAgency: existing.englishAgency,
        priority: existing.priority,
        crewCode: crew,
        submittedAt: existing.createdAt,
        resolvedAt: eventTime,
      ),
    );
    _reports[index] = updated;
    _alerts.insert(
      0,
      AlertItem(
        id: 'alert-resolved-${eventTime.microsecondsSinceEpoch}',
        reportId: updated.id,
        khmerTitle: 'បានដោះស្រាយ · មើលរូបក្រោយជួសជុល',
        englishTitle: 'Resolved · See after photo',
        khmerSubtitle: 'ក្រុម $crew បានបញ្ចូលរូបភាពបញ្ជាក់ការជួសជុលរួចរាល់',
        englishSubtitle: 'Crew $crew uploaded completion Before & After proof',
        createdAt: eventTime,
        isRead: false,
      ),
    );
    _persist();
    notifyListeners();
    return updated;
  }

  bool rejectReport(String reportId) {
    final before = _reports.length;
    _reports.removeWhere((r) => r.id == reportId);
    if (_reports.length == before) return false;
    _alerts.removeWhere((a) => a.reportId == reportId);
    _persist();
    notifyListeners();
    return true;
  }

  void markAlertRead(String alertId) {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index == -1 || _alerts[index].isRead) return;
    _alerts[index] = _alerts[index].copyWith(isRead: true);
    _persist();
    notifyListeners();
  }

  void markAllAlertsRead() {
    var changed = false;
    for (var i = 0; i < _alerts.length; i++) {
      if (!_alerts[i].isRead) {
        _alerts[i] = _alerts[i].copyWith(isRead: true);
        changed = true;
      }
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
  }

  void updateSettings(AppSettings next) {
    _settings = next;
    _persist();
    notifyListeners();
  }

  static List<TimelineEntry> _buildTimeline({
    required ReportStatus status,
    required String khmerAgency,
    required String englishAgency,
    required PriorityBreakdown priority,
    String? crewCode,
    DateTime? submittedAt,
    DateTime? dispatchedAt,
    DateTime? resolvedAt,
  }) {
    final stage = status.stageNumber;
    return [
      TimelineEntry(
        stage: ReportStatus.submitted,
        khmerTitle: 'បានទទួល',
        englishTitle: 'Received',
        khmerSubtitle: khmerAgency,
        englishSubtitle: englishAgency,
        complete: stage >= 1,
        timestamp: submittedAt,
      ),
      TimelineEntry(
        stage: ReportStatus.scheduled,
        khmerTitle: 'បានផ្ទៀងផ្ទាត់ និងកំណត់អាទិភាព',
        englishTitle: 'Verified & prioritised',
        khmerSubtitle: 'P${priority.level} · ${priority.khmerSla}',
        englishSubtitle: 'P${priority.level} · ${priority.englishSla}',
        complete: stage >= 2,
      ),
      TimelineEntry(
        stage: ReportStatus.crewDispatched,
        khmerTitle: 'ក្រុមជួសជុលនៅទីតាំង',
        englishTitle: 'Crew on-site',
        khmerSubtitle: stage >= 3
            ? '🚧 ក្រុម ${crewCode ?? 'B-07'} មកដល់ទីតាំងហើយ'
            : 'រង់ចាំការចាត់តាំងក្រុមជួសជុល',
        englishSubtitle: stage >= 3
            ? '🚧 Team ${crewCode ?? 'B-07'} actively working on-site'
            : 'Awaiting crew dispatch',
        complete: stage >= 3,
        timestamp: stage >= 3 ? dispatchedAt : null,
      ),
      TimelineEntry(
        stage: ReportStatus.resolved,
        khmerTitle: 'បានដោះស្រាយ',
        englishTitle: 'Resolved',
        khmerSubtitle: stage >= 4
            ? 'បានបញ្ចូលរូបភាពមុន និងក្រោយការជួសជុល'
            : 'ប៉ាន់ស្មាន · តម្រូវឲ្យមានរូបភាពបញ្ជាក់ក្រោយជួសជុល',
        englishSubtitle: stage >= 4
            ? 'Before & After completion photos verified'
            : 'Est. · Before & After photo required to close',
        complete: stage >= 4,
        timestamp: stage >= 4 ? resolvedAt : null,
      ),
    ];
  }

  static List<CivicReport> _seedReports() {
    final now = DateTime.now();
    final r1Created = now.subtract(const Duration(hours: 18));
    final r1Verified = now.subtract(const Duration(hours: 12));
    final r1Crew = now.subtract(const Duration(minutes: 25));
    final r2Created = now.subtract(const Duration(hours: 6));
    final r3Created = now.subtract(const Duration(hours: 29));
    final r4Created = now.subtract(const Duration(hours: 4));
    final r5Created = now.subtract(const Duration(days: 3));

    return [
      CivicReport(
        id: '#SC-20481',
        category: IssueCategory.pothole,
        khmerTitle: 'រណ្តៅផ្លូវជ្រៅ',
        englishTitle: 'Deep pothole',
        description: 'រណ្តៅធំ និងដក់ទឹកនៅមហាវិថីព្រះនរោត្តម ម៉ូតូជាច្រើនងាយធ្លាក់ពេលភ្លៀង',
        khmerLocation: 'មហាវិថីព្រះនរោត្តម · សង្កាត់ផ្សារថ្មី, ខណ្ឌដូនពេញ',
        englishLocation: 'Norodom Blvd · Phsar Thmei, Daun Penh',
        coordinates: const LatLng(11.5564, 104.9282),
        roadClass: RoadClass.majorArtery,
        severity: 4,
        affectedCitizens: 11,
        status: ReportStatus.crewDispatched,
        khmerAgency: 'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
        englishAgency: 'Ministry of Public Works & Transport (MPWT)',
        photoAssetPath: 'assets/pothole-before.jpg',
        isMine: true,
        crewCode: 'B-07',
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(r1Created),
        afterDateLabel: 'In progress',
        createdAt: r1Created,
        timeline: [
          TimelineEntry(
            stage: ReportStatus.submitted,
            khmerTitle: 'បានទទួល',
            englishTitle: 'Received',
            khmerSubtitle: 'ក្រសួងសាធារណការ (MPWT)',
            englishSubtitle: 'Ministry of Public Works',
            complete: true,
            timestamp: r1Created,
          ),
          TimelineEntry(
            stage: ReportStatus.scheduled,
            khmerTitle: 'បានផ្ទៀងផ្ទាត់ និងកំណត់អាទិភាព',
            englishTitle: 'Verified & prioritised',
            khmerSubtitle: 'P4 អាទិភាពខ្ពស់',
            englishSubtitle: 'P4 High priority',
            complete: true,
            timestamp: r1Verified,
          ),
          TimelineEntry(
            stage: ReportStatus.crewDispatched,
            khmerTitle: 'ក្រុមជួសជុលនៅទីតាំង',
            englishTitle: 'Crew on-site',
            khmerSubtitle: '🚧 ក្រុម B-07 មកដល់ទីតាំងហើយ',
            englishSubtitle: '🚧 Team B-07 arrived on-site',
            complete: true,
            timestamp: r1Crew,
          ),
          const TimelineEntry(
            stage: ReportStatus.resolved,
            khmerTitle: 'បានដោះស្រាយ',
            englishTitle: 'Resolved',
            khmerSubtitle: 'រង់ចាំរូបភាពបញ្ជាក់ក្រោយជួសជុល',
            englishSubtitle: 'Awaiting After photo proof',
            complete: false,
          ),
        ],
      ),
      CivicReport(
        id: '#SC-20519',
        category: IssueCategory.pothole,
        khmerTitle: 'រណ្តៅផ្លូវគ្រោះថ្នាក់ខ្លាំង',
        englishTitle: 'Critical Road Crater',
        description: 'រណ្តៅជ្រៅខ្លាំងលើមហាវិថីព្រះមុនីវង្ស បង្កគ្រោះថ្នាក់ដល់អ្នកជិះម៉ូតូ',
        khmerLocation: 'មហាវិថីព្រះមុនីវង្ស · សង្កាត់បឹងរាំង, ខណ្ឌដូនពេញ',
        englishLocation: 'Monivong Blvd · Boeung Raing, Daun Penh',
        coordinates: const LatLng(11.5620, 104.9228),
        roadClass: RoadClass.majorArtery,
        severity: 5,
        affectedCitizens: 18,
        status: ReportStatus.submitted,
        khmerAgency: 'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
        englishAgency: 'Ministry of Public Works & Transport (MPWT)',
        photoAssetPath: 'assets/pothole-before.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(r2Created),
        createdAt: r2Created,
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
          englishAgency: 'Ministry of Public Works & Transport (MPWT)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.majorArtery.trafficScore,
            severityScore: 5,
            reportCount: 18,
          ),
          submittedAt: r2Created,
        ),
      ),
      CivicReport(
        id: '#SC-20377',
        category: IssueCategory.streetlight,
        khmerTitle: 'ភ្លើងផ្លូវខូច',
        englishTitle: 'Broken streetlight',
        description: 'ភ្លើងផ្លូវមិនភ្លឺ ៣ បង្គោល ងងឹតពេលយប់',
        khmerLocation: 'មហាវិថីកម្ពុជាក្រោម · សង្កាត់មិត្តភាព, ខណ្ឌ ៧ មករា',
        englishLocation: 'Kampuchea Krom Blvd · Mittapheap, 7 Makara',
        coordinates: const LatLng(11.5656, 104.9142),
        roadClass: RoadClass.secondary,
        severity: 3,
        affectedCitizens: 4,
        status: ReportStatus.scheduled,
        khmerAgency: 'អគ្គិសនីកម្ពុជា (EDC)',
        englishAgency: 'Electricité du Cambodge (EDC)',
        photoAssetPath: 'assets/streetlight.jpg',
        isMine: true,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(r3Created),
        createdAt: r3Created,
        timeline: _buildTimeline(
          status: ReportStatus.scheduled,
          khmerAgency: 'អគ្គិសនីកម្ពុជា (EDC)',
          englishAgency: 'Electricité du Cambodge (EDC)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.secondary.trafficScore,
            severityScore: 3,
            reportCount: 4,
          ),
          submittedAt: r3Created,
        ),
      ),
      CivicReport(
        id: '#SC-20512',
        category: IssueCategory.drain,
        khmerTitle: 'លូស្ទះ និងលិចទឹក',
        englishTitle: 'Clogged drain',
        description: 'លូស្ទះសំរាម ធ្វើឲ្យទឹកដក់លិចផ្លូវពេលភ្លៀង',
        khmerLocation: 'ផ្លូវលេខ ២៨៩ · សង្កាត់បឹងកក់ ១, ខណ្ឌទួលគោក',
        englishLocation: 'Street 289 · Boeung Kak 1, Toul Kork',
        coordinates: const LatLng(11.5730, 104.8990),
        roadClass: RoadClass.commercial,
        severity: 3,
        affectedCitizens: 6,
        status: ReportStatus.submitted,
        khmerAgency: 'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ',
        englishAgency: 'Dept. of Public Works & Drainage (PPCH)',
        photoAssetPath: 'assets/drain.jpg',
        isMine: true,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(r4Created),
        createdAt: r4Created,
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ',
          englishAgency: 'Dept. of Public Works & Drainage (PPCH)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 3,
            reportCount: 6,
          ),
          submittedAt: r4Created,
        ),
      ),
      CivicReport(
        id: '#SC-20290',
        category: IssueCategory.pothole,
        khmerTitle: 'ជួសជុលរណ្តៅផ្លូវរួចរាល់',
        englishTitle: 'Repaired pothole',
        description: 'រណ្តៅផ្លូវជិតសាលារៀនត្រូវបានជួសជុល និងចាក់កៅស៊ូឡើងវិញ',
        khmerLocation: 'ផ្លូវលេខ ៣១០ · សង្កាត់បឹងកេងកង ១, ខណ្ឌបឹងកេងកង',
        englishLocation: 'Street 310 · BKK 1, Boeung Keng Kang',
        coordinates: const LatLng(11.5498, 104.9210),
        roadClass: RoadClass.commercial,
        severity: 4,
        affectedCitizens: 9,
        status: ReportStatus.resolved,
        khmerAgency: 'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
        englishAgency: 'Ministry of Public Works & Transport (MPWT)',
        photoAssetPath: 'assets/pothole-before.jpg',
        resolvedAfterAssetPath: 'assets/pothole-after.jpg',
        isMine: true,
        crewCode: 'B-07',
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(r5Created),
        afterDateLabel: RelativeTimeFormatter.formatShortDate(
          r5Created.add(const Duration(days: 2)),
        ),
        fixedDurationKhmer: 'ជួសជុលរួចក្នុង ២ ថ្ងៃ',
        fixedDurationEnglish: 'Fixed in 2 days',
        createdAt: r5Created,
        timeline: _buildTimeline(
          status: ReportStatus.resolved,
          khmerAgency: 'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
          englishAgency: 'Ministry of Public Works & Transport (MPWT)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 4,
            reportCount: 9,
          ),
          crewCode: 'B-07',
          submittedAt: r5Created,
          resolvedAt: r5Created.add(const Duration(days: 2)),
        ),
      ),
      // Additional community reports across different Phnom Penh Khans for Area News & Map
      CivicReport(
        id: '#SC-20521',
        category: IssueCategory.trash,
        khmerTitle: 'គំនរសំរាមខុសច្បាប់',
        englishTitle: 'Illegal Waste Dumping',
        description: 'មានគំនរសំរាមចោលក្បែរចិញ្ចើមផ្លូវក្បែរផ្សារថ្មី មានក្លិនស្អុយ និងបិទផ្លូវដើរ',
        khmerLocation: 'ផ្លូវលេខ ១៣០ · សង្កាត់ផ្សារថ្មី, ខណ្ឌដូនពេញ',
        englishLocation: 'Street 130 · Phsar Thmei, Daun Penh',
        coordinates: const LatLng(11.5692, 104.9221),
        roadClass: RoadClass.commercial,
        severity: 3,
        affectedCitizens: 5,
        status: ReportStatus.submitted,
        khmerAgency: 'រដ្ឋបាលខណ្ឌដូនពេញ និងសេវាប្រមូលសំរាម',
        englishAgency: 'Khan Daun Penh Admin & Waste Management',
        photoAssetPath: 'assets/trash.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(minutes: 42)),
        ),
        createdAt: now.subtract(const Duration(minutes: 42)),
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'រដ្ឋបាលខណ្ឌដូនពេញ និងសេវាប្រមូលសំរាម',
          englishAgency: 'Khan Daun Penh Admin & Waste Management',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 3,
            reportCount: 5,
          ),
          submittedAt: now.subtract(const Duration(minutes: 42)),
        ),
      ),
      CivicReport(
        id: '#SC-20522',
        category: IssueCategory.streetlight,
        khmerTitle: 'ភ្លើងផ្លូវមិនភ្លឺ',
        englishTitle: 'Broken Streetlight',
        description: 'ភ្លើងផ្លូវរលត់ ២ បង្គោលតាមផ្លូវលេខ ៥១ ងងឹតខ្លាំងពេលយប់',
        khmerLocation: 'ផ្លូវលេខ ៥១ · សង្កាត់បឹងកេងកង ១, ខណ្ឌបឹងកេងកង',
        englishLocation: 'Street 51 · BKK 1, Boeung Keng Kang',
        coordinates: const LatLng(11.5522, 104.9255),
        roadClass: RoadClass.commercial,
        severity: 3,
        affectedCitizens: 7,
        status: ReportStatus.scheduled,
        khmerAgency: 'អគ្គិសនីកម្ពុជា (EDC)',
        englishAgency: 'Electricité du Cambodge (EDC)',
        photoAssetPath: 'assets/streetlight.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 2)),
        ),
        createdAt: now.subtract(const Duration(hours: 2)),
        timeline: _buildTimeline(
          status: ReportStatus.scheduled,
          khmerAgency: 'អគ្គិសនីកម្ពុជា (EDC)',
          englishAgency: 'Electricité du Cambodge (EDC)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 3,
            reportCount: 7,
          ),
          submittedAt: now.subtract(const Duration(hours: 2)),
        ),
      ),
      CivicReport(
        id: '#SC-20523',
        category: IssueCategory.trash,
        khmerTitle: 'គំនរសំរាមខុសច្បាប់',
        englishTitle: 'Illegal Waste Dumping',
        description: 'សំរាមគរច្រើននៅក្បែរផ្សារទួលទំពូង ប៉ះពាល់សោភ័ណភាព និងបិទផ្លូវថ្មើរជើង',
        khmerLocation: 'ផ្លូវលេខ ២៧១ · សង្កាត់ទួលទំពូង ២, ខណ្ឌចំការមន',
        englishLocation: 'Street 271 · Toul Tompoung, Chamkarmon',
        coordinates: const LatLng(11.5415, 104.9110),
        roadClass: RoadClass.majorArtery,
        severity: 4,
        affectedCitizens: 9,
        status: ReportStatus.submitted,
        khmerAgency: 'រដ្ឋបាលខណ្ឌចំការមន និងសេវាប្រមូលសំរាម',
        englishAgency: 'Khan Chamkarmon Admin & Waste Management',
        photoAssetPath: 'assets/trash.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 3)),
        ),
        createdAt: now.subtract(const Duration(hours: 3)),
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'រដ្ឋបាលខណ្ឌចំការមន និងសេវាប្រមូលសំរាម',
          englishAgency: 'Khan Chamkarmon Admin & Waste Management',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.majorArtery.trafficScore,
            severityScore: 4,
            reportCount: 9,
          ),
          submittedAt: now.subtract(const Duration(hours: 3)),
        ),
      ),
      CivicReport(
        id: '#SC-20524',
        category: IssueCategory.streetlight,
        khmerTitle: 'ភ្លើងផ្លូវខូចពេលយប់',
        englishTitle: 'Dark Roadway Streetlights',
        description: 'ភ្លើងបំភ្លឺផ្លូវមហាវិថីសហព័ន្ធរុស្ស៊ីមិនភ្លឺ ៤ បង្គោល បង្កគ្រោះថ្នាក់ចរាចរណ៍',
        khmerLocation: 'មហាវិថីសហព័ន្ធរុស្ស៊ី · សង្កាត់ទឹកថ្លា, ខណ្ឌសែនសុខ',
        englishLocation: 'Russian Federation Blvd · Teuk Thla, Sen Sok',
        coordinates: const LatLng(11.5680, 104.8810),
        roadClass: RoadClass.majorArtery,
        severity: 4,
        affectedCitizens: 12,
        status: ReportStatus.scheduled,
        khmerAgency: 'អគ្គិសនីកម្ពុជា (EDC)',
        englishAgency: 'Electricité du Cambodge (EDC)',
        photoAssetPath: 'assets/streetlight.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 5)),
        ),
        createdAt: now.subtract(const Duration(hours: 5)),
        timeline: _buildTimeline(
          status: ReportStatus.scheduled,
          khmerAgency: 'អគ្គិសនីកម្ពុជា (EDC)',
          englishAgency: 'Electricité du Cambodge (EDC)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.majorArtery.trafficScore,
            severityScore: 4,
            reportCount: 12,
          ),
          submittedAt: now.subtract(const Duration(hours: 5)),
        ),
      ),
      CivicReport(
        id: '#SC-20518',
        category: IssueCategory.pothole,
        khmerTitle: 'រណ្តៅផ្លូវជាតិ ៦A',
        englishTitle: 'Deep Pothole on NR6A',
        description: 'រណ្តៅផ្លូវធំនៅលើផ្លូវជាតិលេខ ៦A ធ្វើឲ្យរថយន្ត និងម៉ូតូបន្ថយល្បឿនភ្លាមៗ',
        khmerLocation: 'ផ្លូវជាតិលេខ ៦A · សង្កាត់ជ្រោយចង្វារ, ខណ្ឌជ្រោយចង្វារ',
        englishLocation: 'National Road 6A · Chroy Changvar, Chroy Changvar',
        coordinates: const LatLng(11.5845, 104.9335),
        roadClass: RoadClass.majorArtery,
        severity: 4,
        affectedCitizens: 10,
        status: ReportStatus.crewDispatched,
        khmerAgency: 'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
        englishAgency: 'Ministry of Public Works & Transport (MPWT)',
        photoAssetPath: 'assets/pothole-before.jpg',
        isMine: false,
        crewCode: 'C-03',
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 8)),
        ),
        createdAt: now.subtract(const Duration(hours: 8)),
        timeline: _buildTimeline(
          status: ReportStatus.crewDispatched,
          khmerAgency: 'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
          englishAgency: 'Ministry of Public Works & Transport (MPWT)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.majorArtery.trafficScore,
            severityScore: 4,
            reportCount: 10,
          ),
          crewCode: 'C-03',
          submittedAt: now.subtract(const Duration(hours: 8)),
          dispatchedAt: now.subtract(const Duration(hours: 1)),
        ),
      ),
      CivicReport(
        id: '#SC-20515',
        category: IssueCategory.drain,
        khmerTitle: 'លូស្ទះ និងលិចទឹកផ្លូវជាតិ ១',
        englishTitle: 'Blocked Drain on NR1',
        description:
            'លូស្ទះសំរាម ទឹកដក់លិចផ្លូវជាតិលេខ ១ នៅពេលភ្លៀងធ្លាក់ខ្លាំង',
        khmerLocation: 'ផ្លូវជាតិលេខ ១ · សង្កាត់ច្បារអំពៅ ១, ខណ្ឌច្បារអំពៅ',
        englishLocation: 'National Road 1 · Chbar Ampov 1, Chbar Ampov',
        coordinates: const LatLng(11.5290, 104.9380),
        roadClass: RoadClass.majorArtery,
        severity: 4,
        affectedCitizens: 8,
        status: ReportStatus.submitted,
        khmerAgency: 'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ',
        englishAgency: 'Dept. of Public Works & Drainage (PPCH)',
        photoAssetPath: 'assets/drain.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 11)),
        ),
        createdAt: now.subtract(const Duration(hours: 11)),
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ',
          englishAgency: 'Dept. of Public Works & Drainage (PPCH)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.majorArtery.trafficScore,
            severityScore: 4,
            reportCount: 8,
          ),
          submittedAt: now.subtract(const Duration(hours: 11)),
        ),
      ),
      CivicReport(
        id: '#SC-20510',
        category: IssueCategory.trash,
        khmerTitle: 'គំនរសំរាមតាមផ្លូវវេងស្រេង',
        englishTitle: 'Roadside Garbage Pile on Veng Sreng',
        description:
            'មានគំនរសំរាមធំចោលក្បែរផ្លូវវេងស្រេង បង្កក្លិនស្អុយដល់ប្រជាពលរដ្ឋ',
        khmerLocation: 'ផ្លូវវេងស្រេង · សង្កាត់ស្ទឹងមានជ័យ, ខណ្ឌមានជ័យ',
        englishLocation: 'Veng Sreng Blvd · Stung Meanchey, Meanchey',
        coordinates: const LatLng(11.5315, 104.8920),
        roadClass: RoadClass.commercial,
        severity: 3,
        affectedCitizens: 6,
        status: ReportStatus.scheduled,
        khmerAgency: 'រដ្ឋបាលខណ្ឌមានជ័យ និងសេវាប្រមូលសំរាម',
        englishAgency: 'Khan Meanchey Admin & Waste Management',
        photoAssetPath: 'assets/trash.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 14)),
        ),
        createdAt: now.subtract(const Duration(hours: 14)),
        timeline: _buildTimeline(
          status: ReportStatus.scheduled,
          khmerAgency: 'រដ្ឋបាលខណ្ឌមានជ័យ និងសេវាប្រមូលសំរាម',
          englishAgency: 'Khan Meanchey Admin & Waste Management',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 3,
            reportCount: 6,
          ),
          submittedAt: now.subtract(const Duration(hours: 14)),
        ),
      ),
      CivicReport(
        id: '#SC-20506',
        category: IssueCategory.drain,
        khmerTitle: 'លូស្ទះជិតសាលារៀន',
        englishTitle: 'Flooded Drain Near School',
        description:
            'លូបង្ហូរទឹកស្ទះនៅសង្កាត់ទួលសង្កែ ១ ធ្វើឲ្យទឹកលិចផ្លូវសិស្សទៅសាលា',
        khmerLocation: 'ផ្លូវជាតិលេខ ៥ · សង្កាត់ទួលសង្កែ ១, ខណ្ឌឫស្សីកែវ',
        englishLocation: 'National Road 5 · Toul Sangke 1, Russey Keo',
        coordinates: const LatLng(11.5920, 104.9125),
        roadClass: RoadClass.commercial,
        severity: 3,
        affectedCitizens: 5,
        status: ReportStatus.submitted,
        khmerAgency: 'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ',
        englishAgency: 'Dept. of Public Works & Drainage (PPCH)',
        photoAssetPath: 'assets/drain.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(days: 1, hours: 3)),
        ),
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ',
          englishAgency: 'Dept. of Public Works & Drainage (PPCH)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 3,
            reportCount: 5,
          ),
          submittedAt: now.subtract(const Duration(days: 1, hours: 3)),
        ),
      ),
      // Nationwide provincial community reports across major Cambodia provinces
      CivicReport(
        id: '#SC-20531',
        category: IssueCategory.pothole,
        khmerTitle: 'រណ្តៅផ្លូវជ្រៅមហាវិថីស៊ីវុត្ថា',
        englishTitle: 'Deep Pothole on Sivutha Blvd',
        description: 'រណ្តៅផ្លូវធំនៅលើមហាវិថីស៊ីវុត្ថា ក្រុងសៀមរាប មានទឹកដក់ពេលភ្លៀង និងគ្រោះថ្នាក់ដល់ម៉ូតូ',
        khmerLocation:
            'មហាវិថីស៊ីវុត្ថា · សង្កាត់ស្វាយដង្គំ, ក្រុងសៀមរាប, ខេត្តសៀមរាប',
        englishLocation:
            'Sivutha Blvd · Svay Dangkum, Krong Siem Reap, Siem Reap',
        coordinates: const LatLng(13.3578, 103.8548),
        provinceCode: 'siem_reap',
        khmerProvince: 'ខេត្តសៀមរាប',
        englishProvince: 'Siem Reap',
        roadClass: RoadClass.majorArtery,
        severity: 4,
        affectedCitizens: 11,
        status: ReportStatus.scheduled,
        khmerAgency: 'មន្ទីរសាធារណការ និងដឹកជញ្ជូន ខេត្តសៀមរាប (DPWT)',
        englishAgency: 'Dept. of Public Works & Transport · Siem Reap (DPWT)',
        photoAssetPath: 'assets/pothole-before.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 4)),
        ),
        createdAt: now.subtract(const Duration(hours: 4)),
        timeline: _buildTimeline(
          status: ReportStatus.scheduled,
          khmerAgency: 'មន្ទីរសាធារណការ និងដឹកជញ្ជូន ខេត្តសៀមរាប (DPWT)',
          englishAgency: 'Dept. of Public Works & Transport · Siem Reap (DPWT)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.majorArtery.trafficScore,
            severityScore: 4,
            reportCount: 11,
          ),
          submittedAt: now.subtract(const Duration(hours: 4)),
        ),
      ),
      CivicReport(
        id: '#SC-20532',
        category: IssueCategory.streetlight,
        khmerTitle: 'ភ្លើងផ្លូវរលត់តាមផ្លូវជាតិ ៦',
        englishTitle: 'Dark Streetlights on National Road 6',
        description: 'បង្គោលភ្លើងបំភ្លឺផ្លូវ ៣ ដើមមិនភ្លឺនៅសង្កាត់ស្លក្រាម ក្រុងសៀមរាប ងងឹតពេលយប់',
        khmerLocation:
            'ផ្លូវជាតិលេខ ៦ · សង្កាត់ស្លក្រាម, ក្រុងសៀមរាប, ខេត្តសៀមរាប',
        englishLocation:
            'National Road 6 · Sla Kram, Krong Siem Reap, Siem Reap',
        coordinates: const LatLng(13.3665, 103.8640),
        provinceCode: 'siem_reap',
        khmerProvince: 'ខេត្តសៀមរាប',
        englishProvince: 'Siem Reap',
        roadClass: RoadClass.commercial,
        severity: 3,
        affectedCitizens: 6,
        status: ReportStatus.submitted,
        khmerAgency: 'អគ្គិសនីកម្ពុជា · សាខាខេត្តសៀមរាប (EDC)',
        englishAgency: 'Electricité du Cambodge · Siem Reap (EDC)',
        photoAssetPath: 'assets/streetlight.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 6)),
        ),
        createdAt: now.subtract(const Duration(hours: 6)),
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'អគ្គិសនីកម្ពុជា · សាខាខេត្តសៀមរាប (EDC)',
          englishAgency: 'Electricité du Cambodge · Siem Reap (EDC)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 3,
            reportCount: 6,
          ),
          submittedAt: now.subtract(const Duration(hours: 6)),
        ),
      ),
      CivicReport(
        id: '#SC-20533',
        category: IssueCategory.drain,
        khmerTitle: 'លូស្ទះ និងទឹកជន់ផ្លូវឯករាជ្យ',
        englishTitle: 'Flooded Drain on Ekareach St',
        description:
            'លូបង្ហូរទឹកស្ទះសំរាមតាមផ្លូវឯករាជ្យ សង្កាត់លេខ ៤ ក្រុងព្រះសីហនុ',
        khmerLocation:
            'ផ្លូវឯករាជ្យ · សង្កាត់លេខ ៤, ក្រុងព្រះសីហនុ, ខេត្តព្រះសីហនុ',
        englishLocation:
            'Ekareach St · Sangkat 4, Krong Preah Sihanouk, Preah Sihanouk',
        coordinates: const LatLng(10.6253, 103.5236),
        provinceCode: 'preah_sihanouk',
        khmerProvince: 'ខេត្តព្រះសីហនុ',
        englishProvince: 'Preah Sihanouk',
        roadClass: RoadClass.majorArtery,
        severity: 4,
        affectedCitizens: 9,
        status: ReportStatus.crewDispatched,
        khmerAgency: 'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ ខេត្តព្រះសីហនុ',
        englishAgency: 'Preah Sihanouk Public Works & Drainage',
        photoAssetPath: 'assets/drain.jpg',
        isMine: false,
        crewCode: 'SHV-02',
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 7)),
        ),
        createdAt: now.subtract(const Duration(hours: 7)),
        timeline: _buildTimeline(
          status: ReportStatus.crewDispatched,
          khmerAgency: 'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ ខេត្តព្រះសីហនុ',
          englishAgency: 'Preah Sihanouk Public Works & Drainage',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.majorArtery.trafficScore,
            severityScore: 4,
            reportCount: 9,
          ),
          crewCode: 'SHV-02',
          submittedAt: now.subtract(const Duration(hours: 7)),
          dispatchedAt: now.subtract(const Duration(hours: 1)),
        ),
      ),
      CivicReport(
        id: '#SC-20534',
        category: IssueCategory.pothole,
        khmerTitle: 'ផ្លូវខូចជិតផ្សារណាត់បាត់ដំបង',
        englishTitle: 'Broken Asphalt Near Psar Nat',
        description: 'ផ្ទៃផ្លូវប្រេះ និងមានរណ្តៅធំលើផ្លូវលេខ ៣ សង្កាត់ស្វាយប៉ោ ក្រុងបាត់ដំបង',
        khmerLocation:
            'ផ្លូវលេខ ៣ · សង្កាត់ស្វាយប៉ោ, ក្រុងបាត់ដំបង, ខេត្តបាត់ដំបង',
        englishLocation: 'Street 3 · Svay Por, Krong Battambang, Battambang',
        coordinates: const LatLng(13.0992, 103.1995),
        provinceCode: 'battambang',
        khmerProvince: 'ខេត្តបាត់ដំបង',
        englishProvince: 'Battambang',
        roadClass: RoadClass.commercial,
        severity: 4,
        affectedCitizens: 8,
        status: ReportStatus.submitted,
        khmerAgency: 'មន្ទីរសាធារណការ និងដឹកជញ្ជូន ខេត្តបាត់ដំបង (DPWT)',
        englishAgency: 'Dept. of Public Works & Transport · Battambang (DPWT)',
        photoAssetPath: 'assets/pothole-before.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 10)),
        ),
        createdAt: now.subtract(const Duration(hours: 10)),
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'មន្ទីរសាធារណការ និងដឹកជញ្ជូន ខេត្តបាត់ដំបង (DPWT)',
          englishAgency:
              'Dept. of Public Works & Transport · Battambang (DPWT)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 4,
            reportCount: 8,
          ),
          submittedAt: now.subtract(const Duration(hours: 10)),
        ),
      ),
      CivicReport(
        id: '#SC-20535',
        category: IssueCategory.trash,
        khmerTitle: 'គំនរសំរាមតាមដងព្រែកកំពត',
        englishTitle: 'Riverside Waste Pile in Kampot',
        description:
            'សំរាមគរច្រើនក្បែរផ្លូវជាតិលេខ ៣ សង្កាត់កំពង់កណ្តាល ក្រុងកំពត',
        khmerLocation:
            'ផ្លូវជាតិលេខ ៣ · សង្កាត់កំពង់កណ្តាល, ក្រុងកំពត, ខេត្តកំពត',
        englishLocation:
            'National Road 3 · Kampong Kandal, Krong Kampot, Kampot',
        coordinates: const LatLng(10.6112, 104.1806),
        provinceCode: 'kampot',
        khmerProvince: 'ខេត្តកំពត',
        englishProvince: 'Kampot',
        roadClass: RoadClass.commercial,
        severity: 3,
        affectedCitizens: 5,
        status: ReportStatus.submitted,
        khmerAgency: 'រដ្ឋបាលក្រុងកំពត និងសេវាប្រមូលសំរាម (កំពត)',
        englishAgency: 'Krong Kampot Admin & Waste Management (Kampot)',
        photoAssetPath: 'assets/trash.jpg',
        isMine: false,
        beforeDateLabel: RelativeTimeFormatter.formatShortDate(
          now.subtract(const Duration(hours: 16)),
        ),
        createdAt: now.subtract(const Duration(hours: 16)),
        timeline: _buildTimeline(
          status: ReportStatus.submitted,
          khmerAgency: 'រដ្ឋបាលក្រុងកំពត និងសេវាប្រមូលសំរាម (កំពត)',
          englishAgency: 'Krong Kampot Admin & Waste Management (Kampot)',
          priority: PriorityCalculator.calculate(
            trafficScore: RoadClass.commercial.trafficScore,
            severityScore: 3,
            reportCount: 5,
          ),
          submittedAt: now.subtract(const Duration(hours: 16)),
        ),
      ),
    ];
  }

  static List<AlertItem> _seedAlerts() {
    final now = DateTime.now();
    return [
      AlertItem(
        id: 'alert-1',
        reportId: '#SC-20481',
        khmerTitle: 'ក្រុមជួសជុលនៅទីតាំងហើយ',
        englishTitle: 'Crew is on-site now',
        khmerSubtitle: 'ក្រុម B-07 កំពុងជួសជុលរណ្តៅផ្លូវនៅមហាវិថីព្រះនរោត្តម',
        englishSubtitle: 'Team B-07 is repairing the pothole on Norodom Blvd',
        createdAt: now.subtract(const Duration(minutes: 5)),
        isRead: false,
      ),
      AlertItem(
        id: 'alert-2',
        reportId: '#SC-20377',
        khmerTitle: 'បានផ្ទៀងផ្ទាត់ · អាទិភាព ៣',
        englishTitle: 'Verified · Priority 3',
        khmerSubtitle: 'EDC បានបញ្ចូលក្នុងផែនការជួសជុលប្រចាំសប្តាហ៍',
        englishSubtitle: 'EDC added this streetlight to the weekly route',
        createdAt: now.subtract(const Duration(hours: 1)),
        isRead: false,
      ),
      AlertItem(
        id: 'alert-3',
        reportId: '#SC-20512',
        khmerTitle: 'បានទទួលរបាយការណ៍',
        englishTitle: 'Report received',
        khmerSubtitle: 'បានបញ្ជូនទៅមន្ទីរសាធារណការ និងប្រព័ន្ធលូ',
        englishSubtitle: 'Assigned to Dept. of Public Works & Drainage',
        createdAt: now.subtract(const Duration(days: 1)),
        isRead: true,
      ),
      AlertItem(
        id: 'alert-4',
        reportId: '#SC-20290',
        khmerTitle: 'បានដោះស្រាយ · មើលរូបក្រោយ',
        englishTitle: 'Resolved · See after photo',
        khmerSubtitle: 'ក្រុម B-07 បានបញ្ចូលរូបភាពមុន និងក្រោយការជួសជុល',
        englishSubtitle: 'Crew B-07 uploaded Before & After completion proof',
        createdAt: now.subtract(const Duration(days: 3)),
        isRead: true,
      ),
    ];
  }
}
