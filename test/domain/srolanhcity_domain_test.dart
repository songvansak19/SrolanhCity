import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app/data/repositories/report_repository.dart';
import 'package:my_app/data/services/audio_recorder_service.dart';
import 'package:my_app/data/services/civic_ai_service.dart';
import 'package:my_app/data/services/exif_stripper.dart';
import 'package:my_app/data/services/location_service.dart';
import 'package:my_app/data/services/reverse_geocoding_service.dart';
import 'package:my_app/data/services/voice_input_service.dart';
import 'package:my_app/domain/models/cambodia_locations.dart';
import 'package:my_app/domain/models/report_models.dart';
import 'package:my_app/domain/services/ai_classifier_service.dart';
import 'package:my_app/domain/services/gis_routing_service.dart';
import 'package:my_app/domain/services/map_cluster_service.dart';
import 'package:my_app/domain/services/priority_calculator.dart';
import 'package:my_app/domain/services/relative_time_formatter.dart';
import 'package:my_app/domain/services/spatial_clustering_service.dart';
import 'package:my_app/domain/services/support_eligibility_service.dart';
import 'package:my_app/ui/features/report/view_models/report_wizard_view_model.dart';

void main() {
  group('PriorityCalculator', () {
    test('maps report counts to the documented 1-5 scale', () {
      expect(PriorityCalculator.scoreReportCount(1), equals(1));
      expect(PriorityCalculator.scoreReportCount(2), equals(2));
      expect(PriorityCalculator.scoreReportCount(3), equals(2));
      expect(PriorityCalculator.scoreReportCount(4), equals(3));
      expect(PriorityCalculator.scoreReportCount(7), equals(3));
      expect(PriorityCalculator.scoreReportCount(8), equals(4));
      expect(PriorityCalculator.scoreReportCount(14), equals(4));
      expect(PriorityCalculator.scoreReportCount(15), equals(5));
      expect(PriorityCalculator.scoreReportCount(42), equals(5));
    });

    test(
      'computes weighted score (0.4*Traffic + 0.3*Severity + 0.3*Reports)',
      () {
        final breakdown = PriorityCalculator.calculate(
          trafficScore: 5,
          severityScore: 4,
          reportCount: 10,
        );
        expect(breakdown.rawScore, equals(4.4));
        expect(breakdown.level, equals(4));
        expect(breakdown.englishLevelName, equals('High'));
      },
    );

    test(
      'reaches Critical P5 for severe crater with 15+ reports on artery',
      () {
        final breakdown = PriorityCalculator.calculate(
          trafficScore: 5,
          severityScore: 5,
          reportCount: 20,
        );
        expect(breakdown.rawScore, equals(5.0));
        expect(breakdown.level, equals(5));
        expect(breakdown.englishLevelName, equals('Critical'));
      },
    );

    test('stays Minor P1 for minor alley issue with 1 report', () {
      final breakdown = PriorityCalculator.calculate(
        trafficScore: 1,
        severityScore: 1,
        reportCount: 1,
      );
      expect(breakdown.rawScore, equals(1.0));
      expect(breakdown.level, equals(1));
      expect(breakdown.englishLevelName, equals('Minor'));
    });
  });

  group('AiClassifierService', () {
    test('does not misclassify pothole near ភ្លើងស្តុប (traffic light) as streetlight', () {
      final result = AiClassifierService.classify(
        description: 'រណ្តៅធំនៅជិតភ្លើងស្តុប ម៉ូតូជាច្រើនធ្លាក់ពេលភ្លៀង',
        selectedCategory: IssueCategory.pothole,
      );
      expect(result.category, equals(IssueCategory.pothole));
      expect(result.matchedFromText, isTrue);
    });

    test('classifies Khmer broken streetlight text accurately', () {
      final result = AiClassifierService.classify(
        description: 'ភ្លើងផ្លូវរលត់ងងឹតខ្លាំងពេលយប់',
        selectedCategory: IssueCategory.pothole,
      );
      expect(result.category, equals(IssueCategory.streetlight));
      expect(result.matchedFromText, isTrue);
    });

    test('classifies Khmer flooded drain text accurately', () {
      final result = AiClassifierService.classify(
        description: 'លូស្ទះសំរាម លិចទឹកពេញផ្លូវ',
        selectedCategory: IssueCategory.pothole,
      );
      expect(result.category, equals(IssueCategory.drain));
    });

    test('classifies illegal waste dumping accurately', () {
      final result = AiClassifierService.classify(
        description: 'Illegal garbage dump with bad smell',
        selectedCategory: IssueCategory.pothole,
      );
      expect(result.category, equals(IssueCategory.trash));
    });
  });

  group('LocationService & GisRoutingService', () {
    test(
      'detects Cambodia bounds and Android Emulator Mountain View default',
      () {
        const phnomPenh = LatLng(11.5564, 104.9282);
        const mountainView = LatLng(37.421998, -122.084000);

        expect(LocationService.isInsideCambodia(phnomPenh), isTrue);
        expect(LocationService.isInsideCambodia(mountainView), isFalse);
        expect(LocationService.isLikelyEmulatorDefault(mountainView), isTrue);
        expect(LocationService.isLikelyEmulatorDefault(phnomPenh), isFalse);
      },
    );

    test('routes Norodom Blvd pothole to MPWT on a major artery', () {
      final route = GisRoutingService.resolve(
        coordinates: const LatLng(11.5564, 104.9282),
        category: IssueCategory.pothole,
      );
      expect(route.roadClass, equals(RoadClass.majorArtery));
      expect(route.englishAgency, contains('MPWT'));
    });

    test(
      'uses live geocoded road & ODC bilingual Khan/Sangkat when supplied',
      () {
        final route = GisRoutingService.resolve(
          coordinates: const LatLng(11.5564, 104.9282),
          category: IssueCategory.pothole,
          geocodedPlace: const GeocodedPlace(
            roadName: 'Street 178',
            sangkat: 'Chey Chumneas',
            khan: 'Daun Penh',
            displayName: 'Street 178, Chey Chumneas, Daun Penh, Phnom Penh',
            countryCode: 'kh',
          ),
        );
        expect(route.englishRoadName, equals('Street 178'));
        expect(route.englishSangkat, contains('Chey Chumneas'));
        expect(route.khmerSangkat, equals('សង្កាត់ជ័យជម្នះ'));
        expect(route.khmerKhan, equals('ខណ្ឌដូនពេញ'));

        // Verify Cambodia map bounds contain Phnom Penh and clamp zoom safely
        expect(
          LocationService.cambodiaMapBounds.contains(
            LocationService.phnomPenhCenter,
          ),
          isTrue,
        );
        expect(LocationService.minMapZoom, greaterThanOrEqualTo(7.0));
        expect(LocationService.maxMapZoom, equals(19.0));
      },
    );

    test('does not falsely label California coordinates as Khan Sen Sok', () {
      final route = GisRoutingService.resolve(
        coordinates: const LatLng(37.421998, -122.084000),
        category: IssueCategory.pothole,
      );
      expect(route.englishSangkat, contains('Outside Cambodia'));
      expect(
        route.englishAgency,
        anyOf(contains('Outside'), contains('Cambodia')),
      );
    });

    test('routes broken streetlight to EDC', () {
      final route = GisRoutingService.resolve(
        coordinates: const LatLng(11.5656, 104.9142),
        category: IssueCategory.streetlight,
      );
      expect(route.englishAgency, contains('EDC'));
    });
  });

  group('UserProfile, JSON Serialization & Multi-Photo Wizard', () {
    test(
      'serializes and restores UserProfile, CivicReport, and ReportDraft',
      () {
        const profile = UserProfile(
          khmerName: 'សុខា',
          englishName: 'Sokha Dara',
          phoneNumber: '+855 12 999 777',
          khmerHomeArea: 'សង្កាត់បឹងកេងកង ១, ខណ្ឌបឹងកេងកង',
          englishHomeArea: 'BKK 1, Boeung Keng Kang',
        );
        expect(profile.initials, equals('SD'));
        expect(profile.maskedPhone, equals('+855 *** 777'));

        final restoredProfile = UserProfile.fromJson(profile.toJson());
        expect(restoredProfile.khmerName, equals('សុខា'));
        expect(restoredProfile.englishName, equals('Sokha Dara'));
        expect(restoredProfile.phoneNumber, equals('+855 12 999 777'));

        final repo = ReportRepository();
        final report = repo.findById('#SC-20481')!;
        final restoredReport = CivicReport.fromJson(report.toJson());
        expect(restoredReport.id, equals(report.id));
        expect(
          restoredReport.affectedCitizens,
          equals(report.affectedCitizens),
        );
        expect(restoredReport.timeline.length, equals(report.timeline.length));

        const draft = ReportDraft(
          category: IssueCategory.drain,
          severity: 5,
          description: 'Flooded street',
          isAnonymous: true,
          localPhotoPaths: ['/tmp/a.jpg', '/tmp/b.jpg'],
        );
        final restoredDraft = ReportDraft.fromJson(draft.toJson());
        expect(restoredDraft.category, equals(IssueCategory.drain));
        expect(restoredDraft.localPhotoPaths.length, equals(2));
      },
    );

    test('ReportWizardViewModel manages up to 3 photos and draft saving', () {
      final repo = ReportRepository();
      final vm = ReportWizardViewModel(repository: repo);

      vm.addLocalPhotoPath('/tmp/photo1.jpg');
      vm.addLocalPhotoPath('/tmp/photo2.jpg');
      vm.addLocalPhotoPath('/tmp/photo3.jpg');
      expect(vm.localPhotoPaths.length, equals(3));
      expect(vm.canAddMorePhotos, isFalse);
      expect(vm.additionalLocalPhotoPaths.length, equals(2));

      vm.removeLocalPhotoAt(1);
      expect(
        vm.localPhotoPaths,
        equals(['/tmp/photo1.jpg', '/tmp/photo3.jpg']),
      );
      expect(vm.canAddMorePhotos, isTrue);

      vm.saveDraft();
      expect(repo.draft, isNotNull);
      expect(repo.draft!.localPhotoPaths.length, equals(2));

      vm.dispose();
    });
  });

  group('SpatialClusteringService & ReportRepository', () {
    test(
      'merges same-category report within 15 meters into Master Incident',
      () {
        final repo = ReportRepository();
        final beforeCount = repo.reports.length;
        final existing = repo.findById('#SC-20481')!;
        final previousAffected = existing.affectedCitizens;

        const nearbyPoint = LatLng(11.55649, 104.9282);
        expect(
          SpatialClusteringService.distanceMeters(
            existing.coordinates,
            nearbyPoint,
          ),
          lessThan(15.0),
        );

        final result = repo.submitReport(
          category: IssueCategory.pothole,
          description: 'Deep pothole here too',
          severity: 5,
          coordinates: nearbyPoint,
          isAnonymous: true,
        );

        expect(result.mergedIntoExisting, isTrue);
        expect(result.report.id, equals('#SC-20481'));
        expect(repo.reports.length, equals(beforeCount));
        expect(
          repo.findById('#SC-20481')!.affectedCitizens,
          equals(previousAffected + 1),
        );
      },
    );

    test('forceCreateNew creates a separate ticket even within 15m', () {
      final repo = ReportRepository();
      final beforeCount = repo.reports.length;

      final result = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Separate pothole across the lane',
        severity: 4,
        coordinates: const LatLng(11.55645, 104.9282),
        isAnonymous: false,
        forceCreateNew: true,
      );

      expect(result.mergedIntoExisting, isFalse);
      expect(repo.reports.length, equals(beforeCount + 1));
    });

    test('does not merge into already resolved incidents', () {
      final repo = ReportRepository();
      final resolved = repo.findById('#SC-20290')!;
      expect(resolved.status, equals(ReportStatus.resolved));

      final duplicate = repo.findDuplicateNearby(
        point: resolved.coordinates,
        category: resolved.category,
      );
      expect(duplicate, isNull);
    });

    test('dispatches crew, resolves with proof, and fires alerts', () {
      final repo = ReportRepository();
      final initialAlerts = repo.alerts.length;

      final dispatched = repo.approveAndDispatch('#SC-20519', crewCode: 'B-07');
      expect(dispatched?.status, equals(ReportStatus.crewDispatched));
      expect(repo.alerts.length, equals(initialAlerts + 1));

      final resolved = repo.markResolvedWithProof('#SC-20519');
      expect(resolved?.status, equals(ReportStatus.resolved));
      expect(
        resolved?.resolvedAfterAssetPath,
        equals('assets/pothole-after.jpg'),
      );
      expect(repo.alerts.length, equals(initialAlerts + 2));

      final rated = repo.rateResolvedReport('#SC-20519', 5);
      expect(rated?.citizenRating, equals(5));
    });
  });

  group('RelativeTimeFormatter, Timed Withdrawal & Sangkat/Khan Catalog', () {
    test('formats bilingual relative ages accurately instead of stuck Now', () {
      final base = DateTime(2026, 11, 23, 12, 30);

      expect(
        RelativeTimeFormatter.formatRelative(
          base.subtract(const Duration(seconds: 30)),
          englishFirst: true,
          now: base,
        ),
        equals('Just now'),
      );
      expect(
        RelativeTimeFormatter.formatRelative(
          base.subtract(const Duration(seconds: 30)),
          englishFirst: false,
          now: base,
        ),
        equals('ឥឡូវនេះ'),
      );
      expect(
        RelativeTimeFormatter.formatRelative(
          base.subtract(const Duration(minutes: 5)),
          englishFirst: true,
          now: base,
        ),
        equals('5m ago'),
      );
      expect(
        RelativeTimeFormatter.formatRelative(
          base.subtract(const Duration(minutes: 5)),
          englishFirst: false,
          now: base,
        ),
        equals('៥ នាទីមុន'),
      );
      expect(
        RelativeTimeFormatter.formatRelative(
          base.subtract(const Duration(hours: 2)),
          englishFirst: true,
          now: base,
        ),
        equals('2h ago'),
      );
      expect(
        RelativeTimeFormatter.formatRelative(
          base.subtract(const Duration(days: 1, hours: 2)),
          englishFirst: false,
          now: base,
        ),
        equals('ម្សិលមិញ'),
      );
      expect(
        RelativeTimeFormatter.formatCountdown(
          const Duration(minutes: 14, seconds: 5),
        ),
        equals('14:05'),
      );
    });

    test('enforces 15-minute withdrawal window, authority lock, quick edit & undo support', () {
      final repo = ReportRepository();
      final submittedAt = DateTime(2026, 11, 23, 12, 0);

      final created = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Trash pile near corner',
        severity: 3,
        coordinates: const LatLng(11.5450, 104.9050),
        isAnonymous: false,
        now: submittedAt,
      );
      final id = created.report.id;
      expect(created.report.createdByCurrentUser, isTrue);
      expect(
        created.report.canWithdraw(
          now: submittedAt.add(const Duration(minutes: 10)),
        ),
        isTrue,
      );
      expect(
        created.report.canWithdraw(
          now: submittedAt.add(const Duration(minutes: 15, seconds: 1)),
        ),
        isFalse,
      );

      // Quick edit works within 15 minutes
      final edited = repo.quickEditUserReport(
        id,
        description: 'Updated large trash pile blocking walkway',
        severity: 5,
        now: submittedAt.add(const Duration(minutes: 4)),
      );
      expect(edited, isNotNull);
      expect(edited!.severity, equals(5));
      expect(edited.description, contains('walkway'));

      // Expired withdrawal returns RemovalWindowExpired
      expect(
        repo.withdrawUserReport(
          id,
          now: submittedAt.add(const Duration(minutes: 16)),
        ),
        isA<RemovalWindowExpired>(),
      );

      // Valid withdrawal within 15 minutes removes report and its alerts
      expect(
        repo.withdrawUserReport(
          id,
          now: submittedAt.add(const Duration(minutes: 5)),
        ),
        isA<ReportRemoved>(),
      );
      expect(repo.findById(id), isNull);
      expect(repo.alerts.where((a) => a.reportId == id), isEmpty);

      // Seeded reports not created by user cannot be withdrawn
      expect(
        repo.withdrawUserReport('#SC-20512', now: submittedAt),
        isA<RemovalNotAllowed>(),
      );

      // Authority lock blocks withdrawal once dispatched
      final created2 = repo.submitReport(
        category: IssueCategory.drain,
        description: 'Blocked drain',
        severity: 4,
        coordinates: const LatLng(11.5350, 104.9010),
        isAnonymous: false,
        now: submittedAt,
      );
      repo.approveAndDispatch(created2.report.id, now: submittedAt);
      expect(
        repo.withdrawUserReport(
          created2.report.id,
          now: submittedAt.add(const Duration(minutes: 2)),
        ),
        isA<RemovalLockedByAuthority>(),
      );

      // Joining / supporting an existing report can be undone cleanly
      final beforeCount = repo.findById('#SC-20519')!.affectedCitizens;
      repo.supportReport('#SC-20519');
      expect(
        repo.findById('#SC-20519')!.affectedCitizens,
        equals(beforeCount + 1),
      );
      expect(repo.findById('#SC-20519')!.canUndoSupport, isTrue);

      repo.undoSupportReport('#SC-20519');
      expect(repo.findById('#SC-20519')!.affectedCitizens, equals(beforeCount));
      expect(repo.findById('#SC-20519')!.isMine, isFalse);
    });

    test('matches Sangkat/Khan from profile and persists AlertItem.createdAt & News settings', () {
      final matched = CambodiaLocationCatalog.matchFromProfileArea(
        khmerArea: 'សង្កាត់បឹងកេងកង ១, ខណ្ឌបឹងកេងកង',
        englishArea: 'BKK 1, Boeung Keng Kang',
      );
      expect(matched.khan?.english, equals('Boeung Keng Kang'));
      expect(matched.sangkat?.english, equals('BKK 1'));

      final ts = DateTime(2026, 11, 23, 11, 45);
      final alert = AlertItem(
        id: 'alert-test',
        reportId: '#SC-20999',
        khmerTitle: 'បានទទួល',
        englishTitle: 'Received',
        khmerSubtitle: 'MPWT',
        englishSubtitle: 'MPWT',
        createdAt: ts,
      );
      final restoredAlert = AlertItem.fromJson(alert.toJson());
      expect(restoredAlert.createdAt, equals(ts));

      const settings = AppSettings(
        englishFirst: true,
        newsKhanEnglish: 'Toul Kork',
        newsSangkatEnglish: 'Boeung Kak 1',
      );
      final restoredSettings = AppSettings.fromJson(settings.toJson());
      expect(restoredSettings.newsKhanEnglish, equals('Toul Kork'));
      expect(restoredSettings.newsSangkatEnglish, equals('Boeung Kak 1'));

      // Every issue category has a real bundled photo asset (including Illegal Waste)
      for (final category in IssueCategory.values) {
        expect(category.defaultAssetPath, isNotNull);
        expect(category.defaultAssetPath, isNotEmpty);
      }

      // Area News includes uploaded My Reports + multi-district community reports
      final repo = ReportRepository();
      final daunPenh = CambodiaLocationCatalog.findKhanByEnglish('Daun Penh')!;
      final phsarThmei = CambodiaLocationCatalog.findSangkatInKhan(
        daunPenh,
        'Phsar Thmei',
      )!;
      final phsarThmeiNews = repo.newsReportsForArea(
        khan: daunPenh,
        sangkat: phsarThmei,
      );
      expect(phsarThmeiNews.any((r) => r.isMine), isTrue);
      expect(phsarThmeiNews.any((r) => !r.isMine), isTrue);

      // Every Phnom Penh Khan in the catalog has at least 1 community report
      for (final khan in CambodiaLocationCatalog.phnomPenhKhans) {
        expect(
          repo.reportCountForKhan(khan),
          greaterThanOrEqualTo(1),
          reason: '${khan.english} should have at least one Area News report',
        );
      }

      // All-districts view returns all reports across Phnom Penh
      final allDistrictNews = repo.newsReportsForArea(khan: null);
      expect(allDistrictNews.length, equals(repo.reports.length));

      // Priority score sorting orders highest priority score first (P5 -> P1)
      final byPriority = repo.newsReportsForArea(
        khan: null,
        sort: ReportSortOption.highestPriority,
      );
      for (var i = 1; i < byPriority.length; i++) {
        expect(
          byPriority[i - 1].priority.rawScore,
          greaterThanOrEqualTo(byPriority[i].priority.rawScore),
        );
      }

      // Duplicate detection catches same-category reports 41.6 m apart (Koh Pich case)
      // AND prevents the same user from self-inflating affectedCitizens or duplicating
      final firstKohPich = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Garbage pile on Samdech Sothearos',
        severity: 3,
        coordinates: const LatLng(11.548007, 104.931225),
        isAnonymous: false,
      );
      expect(firstKohPich.mergedIntoExisting, isFalse);
      expect(firstKohPich.alreadyReportedByUser, isFalse);

      final secondKohPich = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Same garbage pile 42m down the block',
        severity: 4,
        coordinates: const LatLng(11.547650, 104.931111),
        isAnonymous: false,
      );
      expect(secondKohPich.mergedIntoExisting, isTrue);
      expect(secondKohPich.alreadyReportedByUser, isTrue);
      expect(secondKohPich.report.id, equals(firstKohPich.report.id));
      expect(secondKohPich.report.affectedCitizens, equals(1));

      // Even forceCreateNew within 50 m of user's own report is blocked
      final forcedSelfDup = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Trying to force duplicate',
        severity: 4,
        coordinates: const LatLng(11.547650, 104.931111),
        isAnonymous: false,
        forceCreateNew: true,
      );
      expect(forcedSelfDup.alreadyReportedByUser, isTrue);
      expect(forcedSelfDup.report.id, equals(firstKohPich.report.id));

      // 88.6 m corner duplicate (Preah Norodom / Samdech Sothearos case) is also caught
      final corner1 = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Corner waste',
        severity: 3,
        coordinates: const LatLng(11.544558, 104.927740),
        isAnonymous: false,
      );
      final corner2 = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Same corner waste 89m away',
        severity: 3,
        coordinates: const LatLng(11.544007, 104.928328),
        isAnonymous: false,
      );
      expect(corner2.mergedIntoExisting, isTrue);
      expect(corner2.alreadyReportedByUser, isTrue);
      expect(corner2.report.id, equals(corner1.report.id));

      // Self-voting on own report via supportReport does not inflate count
      repo.supportReport(corner1.report.id);
      expect(repo.findById(corner1.report.id)!.affectedCitizens, equals(1));

      // Nominatim "Khan Chamkar Mon" spacing variant matches Chamkarmon in Area News
      final chamkarmon = CambodiaLocationCatalog.findKhanByEnglish(
        'Chamkarmon',
      )!;
      expect(
        CambodiaLocationCatalog.locationMatchesArea(
          khmerLocation: 'ផ្លូវលេខ ៣ · កោះពេជ្រ, ខណ្ឌចំការមន',
          englishLocation:
              'Samdech Sothearos Boulevard · Koh Pich, Khan Chamkar Mon',
          khan: chamkarmon,
        ),
        isTrue,
      );
    });

    test('ReportWizardViewModel appends multi-photos without overwriting earlier ones', () {
      final repo = ReportRepository();
      final vm = ReportWizardViewModel(repository: repo);

      expect(vm.addLocalPhotoPath('/tmp/p1.jpg'), isTrue);
      expect(vm.addLocalPhotoPath('/tmp/p2.jpg'), isTrue);
      expect(vm.localPhotoPaths, equals(['/tmp/p1.jpg', '/tmp/p2.jpg']));
      expect(vm.latestLocalPhotoPath, equals('/tmp/p2.jpg'));

      expect(vm.addLocalPhotoPaths(['/tmp/p3.jpg', '/tmp/p4.jpg']), equals(1));
      // Full at 3 photos — 4th photo must NOT overwrite photo 3
      expect(
        vm.localPhotoPaths,
        equals(['/tmp/p1.jpg', '/tmp/p2.jpg', '/tmp/p3.jpg']),
      );
      expect(vm.addLocalPhotoPath('/tmp/p5.jpg'), isFalse);
      vm.dispose();
    });
  });

  group('Offline Sync Queue & Live VoiceInputService', () {
    test('queues reports offline with SyncStatus.pendingSync and auto-syncs on reconnect', () {
      final repo = ReportRepository();
      expect(repo.isOnline, isTrue);
      expect(repo.pendingSyncCount, equals(0));

      // Go offline and submit a new report
      repo.setOnlineStatus(false);
      expect(repo.isOnline, isFalse);

      final offlineResult = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Offline road crater',
        severity: 4,
        coordinates: const LatLng(11.5390, 104.9020),
        isAnonymous: false,
      );
      expect(offlineResult.report.syncStatus, equals(SyncStatus.pendingSync));
      expect(repo.pendingSyncCount, equals(1));

      // Verify JSON round-trip preserves pendingSync status
      final restored = CivicReport.fromJson(offlineResult.report.toJson());
      expect(restored.syncStatus, equals(SyncStatus.pendingSync));

      // Reconnect — pending report auto-syncs & fires sync confirmation alert
      final alertsBeforeSync = repo.alerts.length;
      repo.setOnlineStatus(true);
      expect(repo.isOnline, isTrue);
      expect(repo.pendingSyncCount, equals(0));
      expect(
        repo.findById(offlineResult.report.id)!.syncStatus,
        equals(SyncStatus.synced),
      );
      expect(repo.alerts.length, equals(alertsBeforeSync + 1));
      expect(repo.alerts.first.englishTitle, contains('Synced 1'));
    });

    test('streams live Khmer speech, surfaces silence/errors explicitly, and supports Sample fallback', () async {
      final repo = ReportRepository();
      final fakeLiveVoice = _FakeVoiceInputService(available: true);
      final vm = ReportWizardViewModel(
        repository: repo,
        initialCategory: IssueCategory.pothole,
        voiceInputService: fakeLiveVoice,
        civicAiService: _UnconfiguredFakeCivicAiService(),
      );

      // Initial description starts empty (never pre-filled fake sample text)
      expect(vm.description, isEmpty);
      expect(vm.photoAi.status, equals(PhotoAiStatus.noPhoto));

      await vm.toggleVoiceRecording();
      expect(vm.isRecordingVoice, isTrue);
      expect(vm.voiceMode, equals(VoiceCaptureMode.deviceSpeech));
      expect(fakeLiveVoice.lastLocaleId, equals('km_KH'));

      // Simulate real spoken Khmer words for broken streetlight
      fakeLiveVoice.emitResult('ភ្លើងផ្លូវរលត់ងងឹតខ្លាំងពេលយប់', isFinal: true);
      expect(vm.isRecordingVoice, isFalse);
      expect(vm.description, equals('ភ្លើងផ្លូវរលត់ងងឹតខ្លាំងពេលយប់'));
      expect(vm.classification.category, equals(IssueCategory.streetlight));
      vm.dispose();

      // Unavailable speech engine shows explicit feedback + working 1-tap Sample
      final unavailableVoice = _FakeVoiceInputService(available: false);
      final fallbackVm = ReportWizardViewModel(
        repository: repo,
        voiceInputService: unavailableVoice,
        civicAiService: _UnconfiguredFakeCivicAiService(),
      );
      await fallbackVm.toggleVoiceRecording();
      expect(fallbackVm.isRecordingVoice, isFalse);
      expect(fallbackVm.voiceFeedbackEnglish, isNotNull);
      expect(fallbackVm.showVoiceDemoFallbackAction, isTrue);

      fallbackVm.runSampleVoiceDemo();
      expect(fallbackVm.isRecordingVoice, isTrue);
      expect(fallbackVm.voiceMode, equals(VoiceCaptureMode.demoFallback));
      await fallbackVm.toggleVoiceRecording();
      expect(fallbackVm.isRecordingVoice, isFalse);
      expect(fallbackVm.voiceTranscript, isNotNull);
      fallbackVm.dispose();
    });
  });

  group('Free-Tier Gemini Multimodal AI, EXIF Stripping & Hybrid Voice', () {
    test(
      'ExifStripper removes APP1 EXIF & COM metadata while keeping JPEG image',
      () {
        // Synthetic JPEG: SOI + APP0 (JFIF) + APP1 (EXIF GPS) + COM + SOS + scan + EOI
        final jpegWithExif = Uint8List.fromList([
          0xFF, 0xD8, // SOI
          0xFF, 0xE0, 0x00, 0x06, 0x4A, 0x46, 0x49, 0x46, // APP0 (kept)
          0xFF,
          0xE1,
          0x00,
          0x08,
          0x45,
          0x78,
          0x69,
          0x66,
          0x00,
          0x00, // APP1 EXIF (strip)
          0xFF, 0xFE, 0x00, 0x05, 0x41, 0x42, 0x43, // COM (strip)
          0xFF, 0xDA, 0x01, 0x02, 0x03, 0xFF, 0xD9, // SOS + payload + EOI
        ]);

        final stripped = ExifStripper.stripJpegMetadata(jpegWithExif);
        expect(stripped.sublist(0, 2), equals([0xFF, 0xD8]));
        // APP0 kept, APP1 and COM removed, SOS + EOI preserved
        expect(
          stripped,
          equals(
            Uint8List.fromList([
              0xFF,
              0xD8,
              0xFF,
              0xE0,
              0x00,
              0x06,
              0x4A,
              0x46,
              0x49,
              0x46,
              0xFF,
              0xDA,
              0x01,
              0x02,
              0x03,
              0xFF,
              0xD9,
            ]),
          ),
        );
      },
    );

    test('BackendCivicAiService stays cleanly in draft mode without API_BASE_URL and parses backend JSON when connected', () async {
      // Client-only draft mode (no API_BASE_URL): zero API keys or network calls
      final draftService = BackendCivicAiService(baseUrl: '');
      expect(draftService.isBackendConfigured, isFalse);
      final draftAnalysis = await draftService.analyzeIssuePhoto(
        imagePath: '/tmp/any.jpg',
        englishFirst: false,
      );
      expect(draftAnalysis.status, equals(PhotoAiStatus.awaitingBackend));

      // Backend-connected mode builds clean SrolanhCity API paths & payloads
      final backendService = BackendCivicAiService(
        baseUrl: 'https://api.srolanhcity.kh/',
      );
      expect(backendService.isBackendConfigured, isTrue);
      expect(
        backendService
            .endpointUri(BackendCivicAiService.classifyPath)
            .toString(),
        equals('https://api.srolanhcity.kh/api/v1/ai/classify-issue'),
      );
      expect(
        backendService
            .endpointUri(BackendCivicAiService.transcribePath)
            .toString(),
        equals('https://api.srolanhcity.kh/api/v1/ai/transcribe-voice'),
      );

      final photoBody = backendService.buildPhotoRequestBody(
        base64Image: 'AAAA',
        mimeType: 'image/jpeg',
        englishFirst: false,
        descriptionHint: 'គំនរសំរាមតាមផ្លូវ',
      );
      expect(photoBody['mime_type'], equals('image/jpeg'));
      expect(photoBody['language'], equals('km'));
      expect(photoBody['description_hint'], equals('គំនរសំរាមតាមផ្លូវ'));

      final audioBody = backendService.buildAudioRequestBody(
        base64Audio: 'UklGRg==',
        mimeType: 'audio/wav',
        englishFirst: true,
      );
      expect(audioBody['mime_type'], equals('audio/wav'));
      expect(audioBody['language'], equals('en'));

      final analyzed = BackendCivicAiService.parsePhotoResponseJson(
        '{"is_civic_issue":true,"category":"trash","confidence_percent":95,"severity":5,"khmer_summary":"មានគំនរសំរាមចោលពេញផ្លូវ","english_summary":"Large illegal waste pile blocking road","khmer_reason":"រកឃើញគំនរសំរាមក្នុងរូបភាព","english_reason":"Visible roadside garbage dump"}',
      );
      expect(analyzed.status, equals(PhotoAiStatus.analyzed));
      expect(analyzed.detectedCategory, equals(IssueCategory.trash));
      expect(analyzed.confidencePercent, equals(95));
      expect(analyzed.suggestedSeverity, equals(5));

      final nonIssue = BackendCivicAiService.parsePhotoResponseJson(
        '{"is_civic_issue":false,"category":"other","confidence_percent":92,"severity":2,"khmer_summary":"រូបភាពក្នុងបន្ទប់","english_summary":"Indoor photo","khmer_reason":"មិនមែនជាបញ្ហាផ្លូវ","english_reason":"Not a street issue"}',
      );
      expect(nonIssue.status, equals(PhotoAiStatus.notCivicIssue));

      final audio = BackendCivicAiService.parseAudioResponseJson(
        '{"transcript":"មានលូស្ទះលិចទឹកខ្លាំង","category":"drain"}',
      );
      expect(audio.success, isTrue);
      expect(audio.transcript, equals('មានលូស្ទះលិចទឹកខ្លាំង'));
      expect(audio.detectedCategory, equals(IssueCategory.drain));
    });

    test('ReportWizardViewModel runs backend Photo AI on real photo and Tier-1 Backend Audio with silence guard', () async {
      final repo = ReportRepository();
      final fakeAi = _FakeConfiguredCivicAiService(
        photoResult: const PhotoAiAnalysis(
          status: PhotoAiStatus.analyzed,
          detectedCategory: IssueCategory.trash,
          confidencePercent: 94,
          suggestedSeverity: 5,
          khmerSummary: 'មានគំនរសំរាមធំចោលក្បែរផ្លូវ',
          englishSummary: 'Large illegal waste pile dumped by the curb',
          khmerReason: 'រកឃើញគំនរសំរាមក្នុងរូបភាព',
          englishReason: 'Garbage bags and waste visible along road',
        ),
        audioResult: const AudioTranscriptionResult(
          success: true,
          transcript: 'មានគំនរសំរាមធំ និងក្លិនស្អុយខ្លាំង',
          detectedCategory: IssueCategory.trash,
        ),
      );
      final fakeRecorder = _FakeAudioRecorderService(amplitude: 0.65);

      final vm = ReportWizardViewModel(
        repository: repo,
        initialCategory: IssueCategory.pothole,
        civicAiService: fakeAi,
        audioRecorderService: fakeRecorder,
      );

      // Before real photo, no fake detection runs
      expect(vm.photoAi.status, equals(PhotoAiStatus.noPhoto));
      expect(vm.description, isEmpty);

      // Attaching a real photo triggers backend classification and updates fields
      vm.addLocalPhotoPath('/tmp/real_trash.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(vm.photoAi.status, equals(PhotoAiStatus.analyzed));
      expect(vm.category, equals(IssueCategory.trash));
      expect(vm.severity, equals(5));
      expect(vm.description, equals('មានគំនរសំរាមធំចោលក្បែរផ្លូវ'));

      // Tier-1 Telegram Hold-to-Speak records audio & transcribes via backend
      await vm.startHoldVoiceRecording();
      expect(vm.isRecordingVoice, isTrue);
      expect(vm.voiceMode, equals(VoiceCaptureMode.backendAudio));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      await vm.finishHoldVoiceRecording();
      expect(vm.isRecordingVoice, isFalse);
      expect(vm.voiceTranscript, equals('មានគំនរសំរាមធំ និងក្លិនស្អុយខ្លាំង'));
      expect(fakeRecorder.deletedPaths, isNotEmpty);
      vm.dispose();

      // Silent emulator microphone triggers explicit silence notice
      final silentRecorder = _FakeAudioRecorderService(amplitude: 0.0);
      final silentVm = ReportWizardViewModel(
        repository: repo,
        civicAiService: fakeAi,
        audioRecorderService: silentRecorder,
      );
      await silentVm.toggleVoiceRecording();
      await silentVm.toggleVoiceRecording();
      expect(silentVm.voiceFeedbackEnglish, contains('No speech heard'));
      expect(silentVm.showVoiceDemoFallbackAction, isTrue);
      silentVm.dispose();
    });
  });

  group('Distance-Aware "Affects me" Eligibility & Anti-Abuse Guardrails', () {
    test('classifies <= 500 m as Verified Nearby, <= 15 km as City Commuter, and > 15 km outside Home Khan as Too Far', () {
      final repo = ReportRepository();
      // Default profile Home Khan is Daun Penh; pick Sen Sok report (#SC-20524)
      final senSokReport = repo.findById('#SC-20524')!;
      final profile = repo.profile;

      // 1. ~110 m away -> Verified Nearby
      final nearby = SupportEligibilityService.evaluateWithLocation(
        report: senSokReport,
        profile: profile,
        locationResult: LocationSuccess(
          point: LatLng(
            senSokReport.coordinates.latitude + 0.001,
            senSokReport.coordinates.longitude,
          ),
          accuracyMeters: 8,
          isOutsideCambodia: false,
        ),
        supportsInLast24Hours: 0,
      );
      expect(nearby, isA<SupportEligible>());
      expect(
        (nearby as SupportEligible).tier,
        equals(SupportVerificationTier.verifiedNearby),
      );
      expect(nearby.distanceMeters, lessThanOrEqualTo(500));

      // 2. ~5.3 km away (Phnom Penh center) -> City Commuter
      final commuter = SupportEligibilityService.evaluateWithLocation(
        report: senSokReport,
        profile: profile,
        locationResult: const LocationSuccess(
          point: LocationService.phnomPenhCenter,
          accuracyMeters: 15,
          isOutsideCambodia: false,
        ),
        supportsInLast24Hours: 0,
      );
      expect(commuter, isA<SupportEligible>());
      expect(
        (commuter as SupportEligible).tier,
        equals(SupportVerificationTier.cityCommuter),
      );

      // 3. Siem Reap (~230 km away) & outside Home Khan -> Denied Too Far
      final tooFar = SupportEligibilityService.evaluateWithLocation(
        report: senSokReport,
        profile: profile,
        locationResult: const LocationSuccess(
          point: LatLng(13.3633, 103.8564),
          accuracyMeters: 20,
          isOutsideCambodia: false,
        ),
        supportsInLast24Hours: 0,
      );
      expect(tooFar, isA<SupportDeniedTooFar>());
      expect(
        (tooFar as SupportDeniedTooFar).distanceMeters,
        greaterThan(15000),
      );

      // 4. GPS disabled outside Home Khan -> Denied Location Required
      final gpsOffOutside = SupportEligibilityService.evaluateWithLocation(
        report: senSokReport,
        profile: profile,
        locationResult: const LocationServiceDisabled(),
        supportsInLast24Hours: 0,
      );
      expect(gpsOffOutside, isA<SupportDeniedLocationRequired>());

      // 5. GPS disabled OR >15 km away INSIDE user's saved Home Khan (Daun Penh) -> Home Resident
      final daunPenhReport = repo.findById('#SC-20519')!;
      final homeFallback = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
        profile: profile,
        locationResult: const LocationServiceDisabled(),
        supportsInLast24Hours: 0,
      );
      expect(homeFallback, isA<SupportEligible>());
      expect(
        (homeFallback as SupportEligible).tier,
        equals(SupportVerificationTier.homeResident),
      );

      final homeFromSiemReap = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
        profile: profile,
        locationResult: const LocationSuccess(
          point: LatLng(13.3633, 103.8564),
          accuracyMeters: 20,
          isOutsideCambodia: false,
        ),
        supportsInLast24Hours: 0,
      );
      expect(homeFromSiemReap, isA<SupportEligible>());
      expect(
        (homeFromSiemReap as SupportEligible).tier,
        equals(SupportVerificationTier.homeResident),
      );

      // 6. Mock GPS is ALWAYS blocked, even inside Home Khan
      final mockBlocked = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
        profile: profile,
        locationResult: LocationMockDetected(point: daunPenhReport.coordinates),
        supportsInLast24Hours: 0,
      );
      expect(mockBlocked, isA<SupportDeniedMockGps>());
    });

    test('enforces 10/24h daily cap, persists tier metadata, and refunds slot on undo', () {
      final repo = ReportRepository();
      final now = DateTime(2026, 11, 23, 16, 0);

      // Persist userSupportTier & distance through JSON round-trip
      final supported = repo.supportReport(
        '#SC-20519',
        tier: SupportVerificationTier.verifiedNearby,
        distanceMeters: 220,
        now: now,
      );
      expect(supported, isNotNull);
      expect(
        supported!.userSupportTier,
        equals(SupportVerificationTier.verifiedNearby),
      );
      expect(repo.supportsUsedInLast24Hours(now: now), equals(1));

      final restored = CivicReport.fromJson(supported.toJson());
      expect(
        restored.userSupportTier,
        equals(SupportVerificationTier.verifiedNearby),
      );
      expect(restored.userSupportDistanceMeters, equals(220));

      // Undo refunds daily slot and clears support metadata
      final undone = repo.undoSupportReport('#SC-20519');
      expect(undone?.userSupportTier, isNull);
      expect(repo.supportsUsedInLast24Hours(now: now), equals(0));

      // Pre-check blocks at 10 votes in last 24h
      final limitDenied = SupportEligibilityService.evaluatePreCheck(
        report: repo.findById('#SC-20519')!,
        supportsInLast24Hours: SupportEligibilityService.maxSupportsPer24Hours,
      );
      expect(limitDenied, isA<SupportDeniedDailyLimit>());

      // Backend support payload shape
      final payload = repo.buildSupportApiPayload(
        reportId: '#SC-20519',
        tier: SupportVerificationTier.cityCommuter,
        distanceMeters: 3420.6,
        userCoordinates: LocationService.phnomPenhCenter,
      );
      expect(payload['report_id'], equals('#SC-20519'));
      expect(payload['verification_tier'], equals('cityCommuter'));
      expect(payload['distance_meters'], equals(3421));
    });
  });

  group('Nationwide 25-Province Catalog, GIS Routing & Map Clustering', () {
    test('catalog covers all 25 Cambodia provinces and routes provincial reports accurately', () {
      expect(CambodiaLocationCatalog.provinces.length, equals(25));
      for (final province in CambodiaLocationCatalog.provinces) {
        expect(LocationService.isInsideCambodia(province.center), isTrue);
      }

      // Alias matching for OSM Nominatim variants
      expect(
        CambodiaLocationCatalog.findProvinceByName('Sihanoukville')?.code,
        equals('preah_sihanouk'),
      );
      expect(
        CambodiaLocationCatalog.findProvinceByName('Tboung Khmum')?.code,
        equals('tbong_khmum'),
      );
      expect(
        CambodiaLocationCatalog.findProvinceByName('សៀមរាប')?.code,
        equals('siem_reap'),
      );

      // Local road pothole in Siem Reap routes to Siem Reap DPWT (never PPCH)
      final srLocal = GisRoutingService.resolve(
        coordinates: const LatLng(13.3633, 103.8564),
        category: IssueCategory.pothole,
        geocodedPlace: const GeocodedPlace(
          roadName: 'Wat Bo Road',
          sangkat: 'Sala Kamreuk',
          khan: 'Krong Siem Reap',
          province: 'Siem Reap',
          displayName: 'Wat Bo Road, Sala Kamreuk, Krong Siem Reap, Siem Reap',
          countryCode: 'kh',
        ),
      );
      expect(srLocal.provinceCode, equals('siem_reap'));
      expect(srLocal.englishAgency, contains('Siem Reap'));
      expect(srLocal.englishAgency, contains('DPWT'));
      expect(srLocal.englishAgency, isNot(contains('Phnom Penh')));

      // National Road 6 pothole in Siem Reap routes to MPWT
      final srHighway = GisRoutingService.resolve(
        coordinates: const LatLng(13.3665, 103.8640),
        category: IssueCategory.pothole,
        geocodedPlace: const GeocodedPlace(
          roadName: 'National Road 6',
          sangkat: 'Sla Kram',
          khan: 'Krong Siem Reap',
          province: 'Siem Reap',
          displayName: 'National Road 6, Sla Kram, Siem Reap',
          countryCode: 'kh',
        ),
      );
      expect(srHighway.englishAgency, contains('MPWT'));

      // Kampot streetlight -> EDC Kampot; Battambang drain -> Battambang DPW
      final kampotLight = GisRoutingService.resolve(
        coordinates: const LatLng(10.6104, 104.1814),
        category: IssueCategory.streetlight,
      );
      expect(kampotLight.provinceCode, equals('kampot'));
      expect(kampotLight.englishAgency, contains('Kampot'));
      expect(kampotLight.englishAgency, contains('EDC'));

      final battambangDrain = GisRoutingService.resolve(
        coordinates: const LatLng(13.0957, 103.2022),
        category: IssueCategory.drain,
      );
      expect(battambangDrain.provinceCode, equals('battambang'));
      expect(battambangDrain.englishAgency, contains('Battambang'));
      expect(battambangDrain.englishAgency, isNot(contains('PPCH')));

      // Offline landmark search finds provincial capitals
      expect(GisRoutingService.findLandmarkByQuery('Kampot'), isNotNull);
      expect(GisRoutingService.findLandmarkByQuery('សៀមរាប'), isNotNull);
    });

    test('MapClusterService clusters by Province at low zoom, spatial grid at mid zoom, and filters viewport', () {
      final repo = ReportRepository();

      // Country zoom -> Province cluster bubbles across 5 active seeded provinces
      final provinceClusters = MapClusterService.clusterForZoom(
        reports: repo.reports,
        zoom: 7.6,
      );
      expect(
        provinceClusters.every((item) => item is ProvinceClusterItem),
        isTrue,
      );
      final byCode = {
        for (final item in provinceClusters.whereType<ProvinceClusterItem>())
          item.province.code: item,
      };
      expect(
        byCode.keys,
        containsAll([
          'phnom_penh',
          'siem_reap',
          'preah_sihanouk',
          'battambang',
          'kampot',
        ]),
      );
      expect(byCode['phnom_penh']!.count, equals(13));
      expect(byCode['siem_reap']!.count, equals(2));

      // Mid-zoom over Phnom Penh -> produces spatial AreaClusterItem bubbles
      final ppBounds = LatLngBounds(
        const LatLng(11.48, 104.84),
        const LatLng(11.63, 104.98),
      );
      final areaItems = MapClusterService.clusterForZoom(
        reports: repo.reports,
        zoom: 11.5,
        visibleBounds: ppBounds,
      );
      expect(areaItems.any((item) => item is AreaClusterItem), isTrue);

      // Street zoom -> individual SingleReportPinItem pins only
      final streetItems = MapClusterService.clusterForZoom(
        reports: repo.reports,
        zoom: 15.0,
        visibleBounds: ppBounds,
      );
      expect(streetItems.every((item) => item is SingleReportPinItem), isTrue);

      // Viewport filter centered on Phnom Penh excludes Siem Reap (#SC-20531)
      final ppViewport = MapClusterService.reportsInViewport(
        reports: repo.reports,
        bounds: ppBounds,
        center: LocationService.phnomPenhCenter,
      );
      expect(ppViewport.any((r) => r.id == '#SC-20481'), isTrue);
      expect(ppViewport.any((r) => r.id == '#SC-20531'), isFalse);

      // Backend viewport query helper
      final query = repo.buildMapViewportQuery(
        bounds: ppBounds,
        zoom: 13.8,
        provinceCode: 'phnom_penh',
        category: IssueCategory.pothole,
      );
      expect(query['province_code'], equals('phnom_penh'));
      expect(query['category'], equals('pothole'));
      expect(query['zoom'], equals('13.8'));
    });

    test('SupportEligibilityService respects provincial Home District without falling back to Daun Penh', () {
      final repo = ReportRepository();
      const siemReapProfile = UserProfile(
        khmerHomeArea: 'សង្កាត់ស្វាយដង្គំ, ក្រុងសៀមរាប, ខេត្តសៀមរាប',
        englishHomeArea: 'Svay Dangkum, Krong Siem Reap, Siem Reap',
        homeProvinceCode: 'siem_reap',
      );

      final siemReapReport = repo.findById('#SC-20531')!;
      final daunPenhReport = repo.findById('#SC-20519')!;

      // GPS off on Siem Reap report -> allowed as Home Resident!
      final allowedHome = SupportEligibilityService.evaluateWithLocation(
        report: siemReapReport,
        profile: siemReapProfile,
        locationResult: const LocationServiceDisabled(),
        supportsInLast24Hours: 0,
      );
      expect(allowedHome, isA<SupportEligible>());
      expect(
        (allowedHome as SupportEligible).tier,
        equals(SupportVerificationTier.homeResident),
      );

      // GPS off on Daun Penh (Phnom Penh) report -> blocked cleanly!
      final blockedPp = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
        profile: siemReapProfile,
        locationResult: const LocationServiceDisabled(),
        supportsInLast24Hours: 0,
      );
      expect(blockedPp, isA<SupportDeniedLocationRequired>());

      // Profile & provincial report JSON round-trip
      final restoredProfile = UserProfile.fromJson(siemReapProfile.toJson());
      expect(restoredProfile.homeProvinceCode, equals('siem_reap'));
      final restoredReport = CivicReport.fromJson(siemReapReport.toJson());
      expect(restoredReport.provinceCode, equals('siem_reap'));
      expect(restoredReport.englishProvince, equals('Siem Reap'));
    });
  });
}

class _FakeVoiceInputService implements VoiceInputService {
  _FakeVoiceInputService({required this.available});

  final bool available;
  String? lastLocaleId;
  void Function(String text, bool isFinal)? _onResult;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) async => available;

  @override
  Future<VoiceLocaleResolution> resolveLocale({
    required bool preferEnglish,
  }) async => VoiceLocaleResolution(
    localeId: preferEnglish ? 'en_US' : 'km_KH',
    exactLanguageAvailable: true,
  );

  @override
  Future<void> startListening({
    required String? localeId,
    required void Function(String text, bool isFinal) onResult,
    required void Function(double normalizedLevel) onSoundLevel,
  }) async {
    lastLocaleId = localeId;
    _onResult = onResult;
    onSoundLevel(0.8);
  }

  void emitResult(String text, {bool isFinal = false}) {
    _onResult?.call(text, isFinal);
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancel() async {}
}

class _UnconfiguredFakeCivicAiService implements CivicAiService {
  @override
  bool get isBackendConfigured => false;

  @override
  Future<PhotoAiAnalysis> analyzeIssuePhoto({
    required String imagePath,
    required bool englishFirst,
    String? descriptionHint,
    bool forceRefresh = false,
  }) async => PhotoAiAnalysis.awaitingBackend;

  @override
  Future<AudioTranscriptionResult> transcribeVoiceAudio({
    required String audioPath,
    required bool englishFirst,
  }) async => const AudioTranscriptionResult(success: false);
}

class _FakeConfiguredCivicAiService implements CivicAiService {
  _FakeConfiguredCivicAiService({
    required this.photoResult,
    required this.audioResult,
  });

  final PhotoAiAnalysis photoResult;
  final AudioTranscriptionResult audioResult;

  @override
  bool get isBackendConfigured => true;

  @override
  Future<PhotoAiAnalysis> analyzeIssuePhoto({
    required String imagePath,
    required bool englishFirst,
    String? descriptionHint,
    bool forceRefresh = false,
  }) async => photoResult;

  @override
  Future<AudioTranscriptionResult> transcribeVoiceAudio({
    required String audioPath,
    required bool englishFirst,
  }) async => audioResult;
}

class _FakeAudioRecorderService implements AudioRecorderService {
  _FakeAudioRecorderService({required this.amplitude});

  final double amplitude;
  final List<String> deletedPaths = [];
  String? _activePath;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> startRecording() async {
    _activePath = '${Directory.systemTemp.path}/fake_voice.wav';
    return true;
  }

  @override
  Future<double> getNormalizedAmplitude() async => amplitude;

  @override
  Future<String?> stopRecording() async => _activePath;

  @override
  Future<void> cancelAndDelete() async {
    if (_activePath != null) deletedPaths.add(_activePath!);
    _activePath = null;
  }

  @override
  Future<void> deleteFile(String? path) async {
    if (path != null) deletedPaths.add(path);
  }

  @override
  Future<void> dispose() async {}
}
