import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app/data/repositories/report_repository.dart';
import 'package:my_app/data/services/audio_recorder_service.dart';
import 'package:my_app/data/services/civic_ai_service.dart';
import 'package:my_app/data/services/comment_translation_service.dart';
import 'package:my_app/data/services/exif_stripper.dart';
import 'package:my_app/data/services/ip_geolocation_service.dart';
import 'package:my_app/data/services/local_storage_service.dart';
import 'package:my_app/data/services/location_service.dart';
import 'package:my_app/data/services/reverse_geocoding_service.dart';
import 'package:my_app/data/services/voice_input_service.dart';
import 'package:my_app/domain/models/cambodia_locations.dart';
import 'package:my_app/domain/models/report_models.dart';
import 'package:my_app/domain/services/ai_classifier_service.dart';
import 'package:my_app/domain/services/anti_spoof_service.dart';
import 'package:my_app/domain/services/gis_routing_service.dart';
import 'package:my_app/domain/services/help_assistant_service.dart';
import 'package:my_app/domain/services/map_cluster_service.dart';
import 'package:my_app/domain/services/priority_calculator.dart';
import 'package:my_app/domain/services/relative_time_formatter.dart';
import 'package:my_app/domain/services/report_location_eligibility_service.dart';
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
    test('merges same-category report within 15 meters into neighbor Master Incident', () {
      final repo = ReportRepository();
      final beforeCount = repo.reports.length;
      // #SC-20519 is a neighbor's community report (not owned by current user)
      final existing = repo.findById('#SC-20519')!;
      expect(existing.isContributedByCurrentUser, isFalse);
      final previousAffected = existing.affectedCitizens;

      final nearbyPoint = LatLng(
        existing.coordinates.latitude + 0.00008,
        existing.coordinates.longitude,
      );
      expect(
        SpatialClusteringService.distanceMeters(
          existing.coordinates,
          nearbyPoint,
        ),
        lessThan(15.0),
      );

      final result = repo.submitReport(
        category: existing.category,
        description: 'Same neighbor issue here too',
        severity: 5,
        coordinates: nearbyPoint,
        isAnonymous: true,
      );

      expect(result.mergedIntoExisting, isTrue);
      expect(result.alreadyReportedByUser, isFalse);
      expect(result.report.id, equals('#SC-20519'));
      expect(repo.reports.length, equals(beforeCount));
      expect(
        repo.findById('#SC-20519')!.affectedCitizens,
        equals(previousAffected + 1),
      );
    });

    test('forceCreateNew creates a separate ticket even within 15m of neighbor report', () {
      final repo = ReportRepository();
      final beforeCount = repo.reports.length;
      final neighbor = repo.findById('#SC-20519')!;

      final result = repo.submitReport(
        category: neighbor.category,
        description: 'Separate issue across the lane',
        severity: 4,
        coordinates: LatLng(
          neighbor.coordinates.latitude + 0.00005,
          neighbor.coordinates.longitude,
        ),
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

      // Seeded demo reports carry explicit photo assets while photo-less citizen
      // records keep photoAssetPath null (never fabricating stock images).
      final repo = ReportRepository();
      for (final seeded in repo.reports) {
        expect(seeded.photoAssetPath, isNotNull);
        expect(seeded.photoAssetPath, isNotEmpty);
      }

      // Area News includes uploaded My Reports + multi-district community reports
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
      // Resident with saved Home Khan = Daun Penh; pick Sen Sok report (#SC-20524)
      final senSokReport = repo.findById('#SC-20524')!;
      const profile = UserProfile(
        khmerName: 'តារា',
        englishName: 'Dara',
        phoneNumber: '+855 12 345 881',
        khmerHomeArea: 'សង្កាត់ផ្សារថ្មី, ខណ្ឌដូនពេញ',
        englishHomeArea: 'Phsar Thmei, Daun Penh',
        homeProvinceCode: 'phnom_penh',
      );

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

  group('QA Fixes: Descriptions, Guest Defaults, Priority Tiers, Different Problem & Self-Duplicate', () {
    test('preserves empty description without injecting sample text and allows clearing via quickEdit', () {
      final repo = ReportRepository();
      final emptyResult = repo.submitReport(
        category: IssueCategory.pothole,
        description: '   ',
        severity: 3,
        coordinates: const LatLng(11.5310, 104.9090),
        isAnonymous: false,
      );
      expect(emptyResult.report.description, isEmpty);
      expect(emptyResult.report.hasDescription, isFalse);

      final commented = repo.submitReport(
        category: IssueCategory.drain,
        description: 'Flooded outside market gate',
        severity: 4,
        coordinates: const LatLng(11.5320, 104.9095),
        isAnonymous: false,
      );
      expect(commented.report.hasDescription, isTrue);
      expect(
        commented.report.description,
        equals('Flooded outside market gate'),
      );

      final cleared = repo.quickEditUserReport(
        commented.report.id,
        description: '',
        severity: 4,
      );
      expect(cleared?.hasDescription, isFalse);
    });

    test('defaults profile to Guest with blank fields, migrates untouched Sovannarith cache, and blocks Home Resident bypass', () {
      const guest = UserProfile();
      expect(guest.khmerName, equals('ភ្ញៀវ'));
      expect(guest.englishName, equals('Guest'));
      expect(guest.phoneNumber, isEmpty);
      expect(guest.maskedPhone, isEmpty);
      expect(guest.khmerHomeArea, isEmpty);
      expect(guest.englishHomeArea, isEmpty);
      expect(guest.homeProvinceCode, isNull);
      expect(guest.hasHomeArea, isFalse);
      expect(guest.initials, equals('G'));

      // Legacy untouched Sovannarith JSON auto-migrates to Guest
      final migrated = UserProfile.fromJson(const {
        'khmerName': 'សុវណ្ណារិទ្ធ',
        'englishName': 'Sovannarith',
        'phoneNumber': '+855 12 345 881',
        'khmerHomeArea': 'សង្កាត់ផ្សារថ្មី, ខណ្ឌដូនពេញ',
        'englishHomeArea': 'Phsar Thmei, Daun Penh',
      });
      expect(migrated.englishName, equals('Guest'));
      expect(migrated.phoneNumber, isEmpty);
      expect(migrated.hasHomeArea, isFalse);

      // Customized user profile is preserved untouched
      final custom = UserProfile.fromJson(const {
        'khmerName': 'សុខា',
        'englishName': 'Sokha',
        'phoneNumber': '+855 12 999 000',
        'khmerHomeArea': 'សង្កាត់ផ្សារថ្មី, ខណ្ឌដូនពេញ',
        'englishHomeArea': 'Phsar Thmei, Daun Penh',
        'homeProvinceCode': 'phnom_penh',
      });
      expect(custom.englishName, equals('Sokha'));
      expect(custom.hasHomeArea, isTrue);

      // Guest with no home area does NOT get automatic Daun Penh Home Resident bypass
      final repo = ReportRepository();
      final daunPenhReport = repo.findById('#SC-20519')!;
      final guestGpsOff = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
        profile: guest,
        locationResult: const LocationServiceDisabled(),
        supportsInLast24Hours: 0,
      );
      expect(guestGpsOff, isA<SupportDeniedLocationRequired>());
    });

    test('PriorityCalculator.tierTable aligns with P5 -> P1 thresholds', () {
      expect(PriorityCalculator.tierTable.length, equals(5));
      expect(
        PriorityCalculator.tierTable.map((r) => r.level).toList(),
        equals([5, 4, 3, 2, 1]),
      );
      expect(
        PriorityCalculator.tierTable.first.scoreRange,
        equals('4.5 – 5.0'),
      );
      expect(PriorityCalculator.tierTable.last.scoreRange, equals('1.0 – 1.4'));
    });

    test('Different problem submission uses IssueCategory.other and customTitle without copying master incident', () {
      final repo = ReportRepository();
      final master = repo.findById('#SC-20481')!;
      final beforeCount = repo.reports.length;

      final result = repo.submitReport(
        category: IssueCategory.other,
        customTitle: 'Fallen tree blocking lane',
        description: 'Large branch fell across road after storm',
        severity: 4,
        coordinates: master.coordinates,
        isAnonymous: false,
        forceCreateNew: true,
      );

      expect(result.mergedIntoExisting, isFalse);
      expect(result.alreadyReportedByUser, isFalse);
      expect(repo.reports.length, equals(beforeCount + 1));
      expect(result.report.category, equals(IssueCategory.other));
      expect(result.report.englishTitle, equals('Fallen tree blocking lane'));
      expect(result.report.khmerTitle, equals('Fallen tree blocking lane'));
      expect(
        result.report.description,
        equals('Large branch fell across road after storm'),
      );
    });

    test('seeded My Reports block self-duplicate merging and self-voting via isContributedByCurrentUser', () {
      final repo = ReportRepository();
      final seededMine = repo.findById('#SC-20481')!;
      expect(seededMine.isMine, isTrue);
      expect(seededMine.isContributedByCurrentUser, isTrue);
      final beforeAffected = seededMine.affectedCitizens;

      // Re-reporting same issue at seeded My Report's location -> alreadyReportedByUser
      final res = repo.submitReport(
        category: seededMine.category,
        description: 'Trying to report my own seeded pothole again',
        severity: 4,
        coordinates: seededMine.coordinates,
        isAnonymous: false,
      );
      expect(res.mergedIntoExisting, isTrue);
      expect(res.alreadyReportedByUser, isTrue);
      expect(res.report.id, equals('#SC-20481'));
      expect(
        repo.findById('#SC-20481')!.affectedCitizens,
        equals(beforeAffected),
      );

      // supportReport & SupportEligibilityService pre-check also guard seeded My Reports
      repo.supportReport('#SC-20481');
      expect(
        repo.findById('#SC-20481')!.affectedCitizens,
        equals(beforeAffected),
      );
      expect(
        SupportEligibilityService.evaluatePreCheck(
          report: seededMine,
          supportsInLast24Hours: 0,
        ),
        isA<SupportDeniedAlreadyContributed>(),
      );
    });

    test('MapClusterService.reportsInViewport order is stable regardless of camera center', () {
      final repo = ReportRepository();
      final ppBounds = LatLngBounds(
        const LatLng(11.48, 104.84),
        const LatLng(11.63, 104.98),
      );
      final orderA = MapClusterService.reportsInViewport(
        reports: repo.reports,
        bounds: ppBounds,
        center: const LatLng(11.5564, 104.9282),
      ).map((r) => r.id).toList();
      final orderB = MapClusterService.reportsInViewport(
        reports: repo.reports,
        bounds: ppBounds,
        center: const LatLng(11.5800, 104.8900),
      ).map((r) => r.id).toList();
      expect(orderA, equals(orderB));
      expect(orderA.length, greaterThanOrEqualTo(5));
    });

    test('PWA web/manifest.json and web/index.html are branded SrolanhCity with no my_app leftovers', () {
      final manifest = File('web/manifest.json').readAsStringSync();
      final indexHtml = File('web/index.html').readAsStringSync();

      expect(manifest, contains('"name": "SrolanhCity"'));
      expect(manifest, contains('"short_name": "SrolanhCity"'));
      expect(manifest, contains('"theme_color": "#006657"'));
      expect(manifest, isNot(contains('my_app')));

      expect(indexHtml, contains('SrolanhCity'));
      expect(indexHtml, contains('apple-touch-icon.png'));
      expect(indexHtml, contains("register('sw.js'"));
      expect(
        indexHtml,
        contains('rel="preconnect" href="https://tile.openstreetmap.org"'),
      );
      expect(indexHtml, isNot(contains('my_app')));

      // Offline-first PWA service worker & custom bootstrap
      final swJs = File('web/sw.js').readAsStringSync();
      final bootstrapJs = File('web/flutter_bootstrap.js').readAsStringSync();
      expect(swJs, contains('srolanhcity-app-v5'));
      expect(swJs, contains('srolanhcity-tiles-v3'));
      expect(swJs, contains('canvaskit/canvaskit.wasm'));
      expect(swJs, contains('tile.openstreetmap.org'));
      expect(swJs, isNot(contains('basemaps.cartocdn.com')));
      expect(swJs, contains('WARM_TILE_URLS'));
      expect(bootstrapJs, contains('_flutter.loader.load()'));
      expect(bootstrapJs, isNot(contains('serviceWorkerSettings')));
    });

    test('hydrate backfills seeded multi-citizen comments on legacy cached reports while keeping user notes', () async {
      final seed = ReportRepository().findById('#SC-20519')!;
      final userNote = CitizenComment(
        id: 'c-note-user-1',
        text: 'My live update before backfill',
        createdAt: DateTime(2026, 11, 24, 2, 30),
        isOriginalReporter: false,
        isCurrentUser: true,
        isAnonymous: true,
      );
      // Simulate pre-update cached JSON that lacked seeded extra comments
      final legacyCachedReport = seed.copyWith(
        citizenComments: [
          CitizenComment(
            id: 'c-orig-#SC-20519',
            text: seed.description,
            createdAt: seed.createdAt,
            isOriginalReporter: true,
          ),
          userNote,
        ],
      );

      final fakeStore = _InMemoryLocalStorage({
        'reports': [legacyCachedReport.toJson()],
      });
      final repo = ReportRepository(storage: fakeStore);
      await repo.hydrate();

      final restored = repo.findById('#SC-20519')!;
      expect(restored.effectiveComments.length, equals(4));
      expect(
        restored.effectiveComments.any((c) => c.id == 'c-20519-2'),
        isTrue,
      );
      expect(
        restored.effectiveComments.any((c) => c.id == 'c-note-user-1'),
        isTrue,
      );
    });

    test('SpeechToTextVoiceInputService preserves Khmer locale request without overriding to English', () async {
      final service = SpeechToTextVoiceInputService();
      final km = await service.resolveLocale(preferEnglish: false);
      final en = await service.resolveLocale(preferEnglish: true);
      expect(km.localeId?.toLowerCase(), startsWith('km'));
      expect(en.localeId?.toLowerCase(), startsWith('en'));
    });

    test('Multi-citizen comments: merges join comments, supports add/delete, syncs quickEdit/undo, and round-trips JSON', () {
      final repo = ReportRepository();
      final master = repo.findById('#SC-20519')!;
      final initialComments = master.effectiveComments.length;
      expect(initialComments, equals(3));
      expect(master.extraCommentCount, equals(2));
      expect(master.silentSupporterCount, equals(15));

      // 1. Joining a neighbor Master Incident appends the joining citizen's comment
      final joined = repo.submitReport(
        category: master.category,
        description: 'Crater grew wider after tonight rain!',
        severity: 5,
        coordinates: LatLng(
          master.coordinates.latitude + 0.00005,
          master.coordinates.longitude,
        ),
        isAnonymous: false,
      );
      expect(joined.mergedIntoExisting, isTrue);
      expect(
        joined.submittedDescription,
        equals('Crater grew wider after tonight rain!'),
      );
      expect(
        joined.report.effectiveComments.length,
        equals(initialComments + 1),
      );
      expect(
        joined.report.effectiveComments.last.text,
        equals('Crater grew wider after tonight rain!'),
      );
      expect(joined.report.effectiveComments.last.isCurrentUser, isTrue);

      // JSON round-trip preserves all citizenComments
      final restored = CivicReport.fromJson(joined.report.toJson());
      expect(restored.effectiveComments.length, equals(initialComments + 1));
      expect(
        restored.effectiveComments.last.text,
        equals('Crater grew wider after tonight rain!'),
      );

      // 2. Undoing support cleans up the joined comment without deleting original comments
      final undone = repo.undoSupportReport('#SC-20519')!;
      expect(undone.effectiveComments.length, equals(initialComments));

      // 3. Adding a direct follow-up note rejects blank input, appends note, and allows deleting it
      expect(repo.addCitizenComment('#SC-20519', text: '   '), isNull);
      final withNote = repo.addCitizenComment(
        '#SC-20519',
        text: 'Cones placed near the crater this morning',
        isAnonymous: true,
      )!;
      expect(withNote.effectiveComments.length, equals(initialComments + 1));
      final addedNote = withNote.effectiveComments.last;
      expect(addedNote.isAnonymous, isTrue);
      expect(addedNote.isCurrentUser, isTrue);

      // Backend API payload builder
      final apiPayload = repo.buildCommentApiPayload(
        reportId: '#SC-20519',
        text: '  Cones placed  ',
        isAnonymous: true,
      );
      expect(apiPayload['report_id'], equals('#SC-20519'));
      expect(apiPayload['text'], equals('Cones placed'));
      expect(apiPayload['is_anonymous'], isTrue);

      // Cannot delete original reporter's comment, CAN delete own follow-up note
      final origId = withNote.effectiveComments.first.id;
      final afterBadDelete = repo.deleteCitizenComment('#SC-20519', origId)!;
      expect(
        afterBadDelete.effectiveComments.length,
        equals(initialComments + 1),
      );

      final afterDelete = repo.deleteCitizenComment('#SC-20519', addedNote.id)!;
      expect(afterDelete.effectiveComments.length, equals(initialComments));

      // 4. quickEditUserReport syncs both description & original CitizenComment
      final created = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Initial pile',
        severity: 3,
        coordinates: const LatLng(11.5318, 104.9044),
        isAnonymous: false,
      );
      final edited = repo.quickEditUserReport(
        created.report.id,
        description: 'Expanded trash pile blocking sidewalk',
        severity: 4,
      )!;
      expect(
        edited.effectiveComments.first.text,
        equals('Expanded trash pile blocking sidewalk'),
      );
    });

    test('Reopen-online auto-sync: hydrate automatically syncs pendingSync reports with voice memos and restores GPS checkpoint', () async {
      final offlineRepo = ReportRepository();
      offlineRepo.setOnlineStatus(false);
      final queued = offlineRepo.submitReport(
        category: IssueCategory.drain,
        description: 'Offline flooded drain',
        severity: 4,
        coordinates: const LatLng(11.5564, 104.9282),
        isAnonymous: false,
        voiceAudioPath: 'data:audio/webm;base64,AAAA',
        voiceAudioDurationSeconds: 7,
      );
      expect(queued.report.syncStatus, equals(SyncStatus.pendingSync));
      expect(
        queued.report.voiceAudioPath,
        equals('data:audio/webm;base64,AAAA'),
      );
      expect(queued.report.voiceAudioDurationSeconds, equals(7));

      final savedCheckpoint = GpsCheckpoint(
        point: const LatLng(11.5564, 104.9282),
        timestamp: DateTime(2026, 11, 24, 10, 0),
      );
      final fakeStore = _InMemoryLocalStorage({
        'reports': [queued.report.toJson()],
        'alerts': const <Map<String, dynamic>>[],
        'lastVerifiedGpsCheckpoint': savedCheckpoint.toJson(),
      });

      // Reopen online -> hydrate() must immediately auto-sync pendingSync!
      final reopenedRepo = ReportRepository(storage: fakeStore);
      await reopenedRepo.hydrate();
      expect(reopenedRepo.hasPendingSync, isFalse);
      final synced = reopenedRepo.findById(queued.report.id)!;
      expect(synced.syncStatus, equals(SyncStatus.synced));
      expect(synced.voiceAudioPath, equals('data:audio/webm;base64,AAAA'));
      expect(reopenedRepo.alerts.first.englishTitle, contains('Synced 1'));
      expect(reopenedRepo.lastVerifiedGpsCheckpoint, isNotNull);
      expect(
        reopenedRepo.lastVerifiedGpsCheckpoint!.point.latitude,
        closeTo(11.5564, 0.0001),
      );
    });

    test('ExifStripper extracts GPS & DateTimeOriginal in both II and MM TIFF headers before stripping APP1 completely', () {
      for (final endian in [Endian.little, Endian.big]) {
        final jpeg = _buildSyntheticExifJpeg(
          endian: endian,
          latDeg: 11,
          latMin: 33,
          latSecNum: 2304,
          latSecDen: 100,
          lngDeg: 104,
          lngMin: 55,
          lngSecNum: 4152,
          lngSecDen: 100,
          dateTimeOriginal: '2026:11:20 09:30:00',
        );
        final meta = ExifStripper.extractJpegMetadata(jpeg);
        expect(meta.hasCoordinates, isTrue);
        expect(meta.coordinates!.latitude, closeTo(11.5564, 0.001));
        expect(meta.coordinates!.longitude, closeTo(104.9282, 0.001));
        expect(meta.capturedAt, equals(DateTime(2026, 11, 20, 9, 30, 0)));

        // Strip must remove APP1 completely while preserving JPEG SOI + EOI.
        final stripped = ExifStripper.stripJpegMetadata(jpeg);
        expect(stripped.length, lessThan(jpeg.length));
        expect(ExifStripper.extractJpegMetadata(stripped).isEmpty, isTrue);
      }
    });

    test('AntiSpoofService catches impossible travel, synthetic accuracy, photo EXIF mismatch, and non-KH IP while keeping honest users unblocked', () {
      const phnomPenh = LatLng(11.5564, 104.9282);
      const siemReap = LatLng(13.3633, 103.8564);
      final t0 = DateTime(2026, 11, 24, 10, 0);

      // 1. Impossible travel (232 km in 3 minutes) -> blocked
      final impossible = AntiSpoofService.evaluateGpsFix(
        current: GpsReadingSample(
          point: siemReap,
          timestamp: t0.add(const Duration(minutes: 3)),
          accuracyMeters: 12.0,
        ),
        lastCheckpoint: GpsCheckpoint(point: phnomPenh, timestamp: t0),
      );
      expect(impossible.isBlocked, isTrue);
      expect(impossible.reasons, contains(SpoofSignalReason.impossibleTravel));

      // 2. Realistic travel (232 km in 5 hours) -> trusted
      final realistic = AntiSpoofService.evaluateGpsFix(
        current: GpsReadingSample(
          point: siemReap,
          timestamp: t0.add(const Duration(hours: 5)),
          accuracyMeters: 12.0,
        ),
        lastCheckpoint: GpsCheckpoint(point: phnomPenh, timestamp: t0),
      );
      expect(realistic.riskLevel, equals(SpoofRiskLevel.trusted));

      // 3. Synthetic GPS accuracy (0.1 m) -> blocked
      final synthetic = AntiSpoofService.evaluateGpsFix(
        current: GpsReadingSample(
          point: phnomPenh,
          timestamp: t0,
          accuracyMeters: 0.1,
        ),
      );
      expect(synthetic.isBlocked, isTrue);
      expect(synthetic.reasons, contains(SpoofSignalReason.syntheticAccuracy));

      // 4. Photo EXIF verified within 500 m, warning when > 5 km or > 30 days, clean when null
      final exifOk = AntiSpoofService.evaluatePhotoExif(
        exif: PhotoExifMetadata(coordinates: phnomPenh, capturedAt: t0),
        pinnedLocation: const LatLng(11.5565, 104.9283),
        now: t0.add(const Duration(minutes: 5)),
      );
      expect(exifOk.photoExifVerified, isTrue);
      expect(exifOk.riskLevel, equals(SpoofRiskLevel.trusted));

      final exifFarAndOld = AntiSpoofService.evaluatePhotoExif(
        exif: PhotoExifMetadata(
          coordinates: siemReap,
          capturedAt: t0.subtract(const Duration(days: 45)),
        ),
        pinnedLocation: phnomPenh,
        now: t0,
      );
      expect(exifFarAndOld.hasWarning, isTrue);
      expect(
        exifFarAndOld.reasons,
        containsAll([
          SpoofSignalReason.photoExifLocationMismatch,
          SpoofSignalReason.photoExifStale,
        ]),
      );

      expect(
        AntiSpoofService.evaluatePhotoExif(
          exif: null,
          pinnedLocation: phnomPenh,
        ).riskLevel,
        equals(SpoofRiskLevel.trusted),
      );

      // 5. IP geolocation soft warning on non-KH, clean on KH or offline null
      expect(
        AntiSpoofService.evaluateIpGeo(ipCountryCode: 'KH').riskLevel,
        equals(SpoofRiskLevel.trusted),
      );
      expect(
        AntiSpoofService.evaluateIpGeo(ipCountryCode: null).riskLevel,
        equals(SpoofRiskLevel.trusted),
      );
      final foreignIp = AntiSpoofService.evaluateIpGeo(ipCountryCode: 'US');
      expect(foreignIp.hasWarning, isTrue);
      expect(foreignIp.reasons, contains(SpoofSignalReason.ipCountryMismatch));
      expect(
        foreignIp.toIntegrityJson(ipCountryCode: 'US')['attestation'],
        isNotNull,
      );
    });

    test('ReportWizardViewModel records local voice memos offline and enables Brave speech fallback', () async {
      final repo = ReportRepository();
      repo.setOnlineStatus(false);
      final fakeRecorder = _FakeAudioRecorderService(amplitude: 0.55);
      final vm = ReportWizardViewModel(
        repository: repo,
        initialCoordinates: const LatLng(11.5318, 104.9044),
        voiceInputService: _FakeVoiceInputService(available: false),
        audioRecorderService: fakeRecorder,
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: _FakeIpGeoService(null),
      );
      addTearDown(vm.dispose);

      await vm.toggleVoiceRecording();
      expect(vm.isRecordingVoice, isTrue);
      expect(vm.voiceMode, equals(VoiceCaptureMode.offlineAudioMemo));
      expect(fakeRecorder.lastPersistentMemo, isTrue);

      await vm.toggleVoiceRecording();
      expect(vm.isRecordingVoice, isFalse);
      expect(vm.hasVoiceAudioMemo, isTrue);
      expect(vm.voiceAudioDurationSeconds, greaterThanOrEqualTo(1));

      final submitted = vm.submit();
      expect(submitted.report.syncStatus, equals(SyncStatus.pendingSync));
      expect(submitted.report.voiceAudioPath, equals(vm.voiceAudioPath));

      // Online with blocked Web Speech (Brave) offers Record Voice Memo fallback
      repo.setOnlineStatus(true);
      final vmOnline = ReportWizardViewModel(
        repository: repo,
        voiceInputService: _FakeVoiceInputService(available: false),
        audioRecorderService: _FakeAudioRecorderService(amplitude: 0.5),
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: _FakeIpGeoService(
          const IpGeoInfo(countryCode: 'KH'),
        ),
      );
      addTearDown(vmOnline.dispose);
      await vmOnline.toggleVoiceRecording();
      expect(vmOnline.showVoiceMemoFallbackAction, isTrue);
    });

    test('CommentTranslationService detects Khmer vs English target language accurately', () {
      expect(
        CommentTranslationService.detectTargetLanguage(
          'Water completely hides the hole after heavy rain.',
        ),
        equals('km'),
      );
      expect(
        CommentTranslationService.detectTargetLanguage(
          'រណ្តៅជ្រៅខ្លាំងលើមហាវិថីព្រះមុនីវង្ស',
        ),
        equals('en'),
      );
    });

    test('HelpAssistantService performs live ticket lookup, answers bilingual FAQs, and uses backend AI when configured', () async {
      final repo = ReportRepository();
      final onDevice = HelpAssistantService(
        civicAiService: _UnconfiguredFakeCivicAiService(),
      );

      // 1. Live ticket lookup for #SC-20481
      final ticketReply = await onDevice.respond(
        message: 'Check status of #SC-20481',
        history: const [],
        repository: repo,
        englishFirst: true,
      );
      expect(ticketReply.success, isTrue);
      expect(ticketReply.fromBackendAi, isFalse);
      expect(ticketReply.referencedReportId, equals('#SC-20481'));
      expect(
        ticketReply.suggestedAction,
        equals(HelpSuggestedAction.openTicket),
      );
      expect(ticketReply.text, contains('MPWT'));

      // 2. Khmer streetlight ministry question -> EDC 1298
      final edcReply = await onDevice.respond(
        message: 'ក្រសួងណាជួសជុលភ្លើងផ្លូវខូច?',
        history: const [],
        repository: repo,
        englishFirst: false,
      );
      expect(edcReply.text, contains('1298'));
      expect(
        edcReply.suggestedAction,
        equals(HelpSuggestedAction.callPowerHotline1298),
      );

      // 3. Backend LLM reply when configured & online
      final backendHelper = HelpAssistantService(
        civicAiService: _FakeConfiguredCivicAiService(
          photoResult: PhotoAiAnalysis.awaitingBackend,
          audioResult: const AudioTranscriptionResult(success: false),
          helpReply: const HelpChatReply(
            success: true,
            text: 'Live backend AI answer for your civic question.',
            fromBackendAi: true,
          ),
        ),
      );
      final liveReply = await backendHelper.respond(
        message: 'Hello AI',
        history: const [],
        repository: repo,
        englishFirst: true,
      );
      expect(liveReply.fromBackendAi, isTrue);
      expect(liveReply.text, contains('Live backend AI answer'));

      // Falls back cleanly to on-device when offline
      repo.setOnlineStatus(false);
      final offlineReply = await backendHelper.respond(
        message: 'How is P5 priority calculated?',
        history: const [],
        repository: repo,
        englishFirst: true,
      );
      expect(offlineReply.fromBackendAi, isFalse);
      expect(offlineReply.text, contains('40%'));
    });

    test('AppSettings persists floating assistant bubble preferences and defaults legacy JSON to enabled', () {
      final legacy = AppSettings.fromJson(const {'englishFirst': true});
      expect(legacy.englishFirst, isTrue);
      expect(legacy.assistantBubbleEnabled, isTrue);
      expect(legacy.assistantBubbleOnLeft, isFalse);
      expect(legacy.assistantBubbleYFraction, closeTo(0.45, 0.001));
      expect(legacy.assistantHintSeen, isFalse);

      final custom = legacy.copyWith(
        assistantBubbleEnabled: false,
        assistantBubbleOnLeft: true,
        assistantBubbleYFraction: 1.4, // clamped to 1.0
        assistantHintSeen: true,
      );
      expect(custom.assistantBubbleYFraction, equals(1.0));

      final restored = AppSettings.fromJson(custom.toJson());
      expect(restored.assistantBubbleEnabled, isFalse);
      expect(restored.assistantBubbleOnLeft, isTrue);
      expect(restored.assistantBubbleYFraction, equals(1.0));
      expect(restored.assistantHintSeen, isTrue);
    });
  });

  group('ReportLocationEligibilityService (Rule #1 Smart Distance Gate)', () {
    const phnomPenhPin = LatLng(11.5564, 104.9282); // Daun Penh, Phnom Penh
    const siemReapGps = LatLng(13.3633, 103.8564); // ~234 km north-west
    final ppRouting = GisRoutingService.resolve(
      coordinates: phnomPenhPin,
      category: IssueCategory.pothole,
    );
    const guestProfile = UserProfile(); // no Home District set
    const daunPenhProfile = UserProfile(
      homeProvinceCode: 'PP',
      khmerHomeArea: 'ផ្សារថ្មី, ខណ្ឌដូនពេញ',
      englishHomeArea: 'Phsar Thmei, Daun Penh',
    );

    test('blocks cross-province submission (Siem Reap -> Phnom Penh) when outside Home District with no matching photo EXIF', () {
      final res = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        routing: ppRouting,
        profile: guestProfile,
        liveGpsResult: const LocationSuccess(
          point: siemReapGps,
          accuracyMeters: 12,
          isOutsideCambodia: false,
        ),
      );
      expect(res, isA<ReportLocationDeniedTooFar>());
      final denied = res as ReportLocationDeniedTooFar;
      expect(denied.distanceMeters, greaterThan(200000));
      expect(denied.liveProvinceEnglish, equals('Siem Reap'));
    });

    test(
      'allows <= 500 m as verifiedOnSite and 500 m – 15 km as sameCityCommuter',
      () {
        final onSite = ReportLocationEligibilityService.evaluate(
          pinnedLocation: phnomPenhPin,
          routing: ppRouting,
          profile: guestProfile,
          liveGpsResult: const LocationSuccess(
            point: LatLng(11.5572, 104.9285), // ~95 m
            accuracyMeters: 8,
            isOutsideCambodia: false,
          ),
        );
        expect(onSite, isA<ReportLocationEligible>());
        expect(
          (onSite as ReportLocationEligible).tier,
          equals(ReportLocationVerificationTier.verifiedOnSite),
        );

        final commuter = ReportLocationEligibilityService.evaluate(
          pinnedLocation: phnomPenhPin,
          routing: ppRouting,
          profile: guestProfile,
          liveGpsResult: const LocationSuccess(
            point: LatLng(11.5920, 104.8850), // ~6.1 km (Sen Sok)
            accuracyMeters: 15,
            isOutsideCambodia: false,
          ),
        );
        expect(commuter, isA<ReportLocationEligible>());
        expect(
          (commuter as ReportLocationEligible).tier,
          equals(ReportLocationVerificationTier.sameCityCommuter),
        );
      },
    );

    test('allows Siem Reap -> Phnom Penh delayed upload when fresh photo EXIF matches pin (<= 500 m, <= 30 days) but rejects stale EXIF', () {
      final now = DateTime(2026, 11, 24, 18, 0);
      final allowed = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        routing: ppRouting,
        profile: guestProfile,
        liveGpsResult: const LocationSuccess(
          point: siemReapGps,
          accuracyMeters: 12,
          isOutsideCambodia: false,
        ),
        photoExif: PhotoExifMetadata(
          coordinates: const LatLng(11.5566, 104.9283),
          capturedAt: now.subtract(const Duration(hours: 6)),
        ),
        now: now,
      );
      expect(allowed, isA<ReportLocationEligible>());
      expect(
        (allowed as ReportLocationEligible).tier,
        equals(ReportLocationVerificationTier.photoExifVerified),
      );

      // Stale EXIF (45 days old) does NOT bypass the 15 km distance gate
      final stale = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        routing: ppRouting,
        profile: guestProfile,
        liveGpsResult: const LocationSuccess(
          point: siemReapGps,
          accuracyMeters: 12,
          isOutsideCambodia: false,
        ),
        photoExif: PhotoExifMetadata(
          coordinates: const LatLng(11.5566, 104.9283),
          capturedAt: now.subtract(const Duration(days: 45)),
        ),
        now: now,
      );
      expect(stale, isA<ReportLocationDeniedTooFar>());
    });

    test('allows saved Home District from afar and when GPS is off, but never lets Mock GPS bypass', () {
      // 1. Siem Reap GPS + saved Daun Penh Home District -> allowed
      final fromAfar = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        routing: ppRouting,
        profile: daunPenhProfile,
        liveGpsResult: const LocationSuccess(
          point: siemReapGps,
          accuracyMeters: 14,
          isOutsideCambodia: false,
        ),
      );
      expect(fromAfar, isA<ReportLocationEligible>());
      expect(
        (fromAfar as ReportLocationEligible).tier,
        equals(ReportLocationVerificationTier.homeResident),
      );

      // 2. GPS off + saved Daun Penh Home District -> allowed
      final gpsOffHome = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        routing: ppRouting,
        profile: daunPenhProfile,
        liveGpsResult: const LocationServiceDisabled(),
      );
      expect(gpsOffHome, isA<ReportLocationEligible>());

      // 3. GPS off + Guest (no Home District) -> blocked (LocationRequired)
      final gpsOffGuest = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        routing: ppRouting,
        profile: guestProfile,
        liveGpsResult: const LocationServiceDisabled(),
      );
      expect(gpsOffGuest, isA<ReportLocationDeniedLocationRequired>());
      expect(
        (gpsOffGuest as ReportLocationDeniedLocationRequired).serviceDisabled,
        isTrue,
      );

      // 4. Mock GPS -> ALWAYS blocked even with Home District + matching EXIF
      final mocked = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        routing: ppRouting,
        profile: daunPenhProfile,
        liveGpsResult: const LocationMockDetected(point: phnomPenhPin),
        photoExif: PhotoExifMetadata(
          coordinates: phnomPenhPin,
          capturedAt: DateTime.now(),
        ),
      );
      expect(mocked, isA<ReportLocationDeniedMockGps>());
    });

    test('Photo-Anchored Hard Fence (<= 250 m) blocks pins dragged > 250 m from EXIF or live camera even inside Home District & live GPS', () {
      final now = DateTime(2026, 11, 24, 19, 0);
      const photoSpot = LatLng(11.5564, 104.9282); // Daun Penh
      // ~180 m north (inside 250 m adjustment fence)
      const within250mPin = LatLng(11.5580, 104.9282);
      // ~400 m north (outside 250 m fence, still in Daun Penh!)
      const dragged400mPin = LatLng(11.5600, 104.9282);
      final draggedRouting = GisRoutingService.resolve(
        coordinates: dragged400mPin,
        category: IssueCategory.pothole,
      );

      // 1. EXIF within 250 m -> allowed as photoExifVerified
      final okExif = ReportLocationEligibilityService.evaluate(
        pinnedLocation: within250mPin,
        routing: ppRouting,
        profile: guestProfile,
        liveGpsResult: const LocationSuccess(
          point: siemReapGps,
          accuracyMeters: 12,
          isOutsideCambodia: false,
        ),
        photoExif: PhotoExifMetadata(
          coordinates: photoSpot,
          capturedAt: now.subtract(const Duration(hours: 1)),
        ),
        now: now,
      );
      expect(okExif, isA<ReportLocationEligible>());
      expect(
        (okExif as ReportLocationEligible).tier,
        equals(ReportLocationVerificationTier.photoExifVerified),
      );

      // 2. EXIF dragged 400 m away -> HARD BLOCKED even when live GPS is at
      //    the dragged pin AND pin is inside saved Home District!
      final blockedExif = ReportLocationEligibilityService.evaluate(
        pinnedLocation: dragged400mPin,
        routing: draggedRouting,
        profile: daunPenhProfile,
        liveGpsResult: const LocationSuccess(
          point: dragged400mPin,
          accuracyMeters: 8,
          isOutsideCambodia: false,
        ),
        photoExif: PhotoExifMetadata(
          coordinates: photoSpot,
          capturedAt: now.subtract(const Duration(minutes: 5)),
        ),
        now: now,
      );
      expect(blockedExif, isA<ReportLocationDeniedPhotoAnchorMismatch>());
      final denied = blockedExif as ReportLocationDeniedPhotoAnchorMismatch;
      expect(denied.anchorSource, equals(PhotoAnchorSource.photoExif));
      expect(denied.distanceMeters, greaterThan(250));

      // 3. Live camera capture anchor: allowed <= 250 m, blocked > 250 m
      final liveCamAnchor = PhotoLocationAnchor(
        point: photoSpot,
        source: PhotoAnchorSource.liveCameraCapture,
        capturedAt: now,
      );
      final okCam = ReportLocationEligibilityService.evaluate(
        pinnedLocation: within250mPin,
        routing: ppRouting,
        profile: guestProfile,
        photoAnchor: liveCamAnchor,
        now: now,
      );
      expect(okCam, isA<ReportLocationEligible>());
      expect(
        (okCam as ReportLocationEligible).tier,
        equals(ReportLocationVerificationTier.liveCameraVerified),
      );

      final blockedCam = ReportLocationEligibilityService.evaluate(
        pinnedLocation: dragged400mPin,
        routing: draggedRouting,
        profile: daunPenhProfile,
        liveGpsResult: const LocationSuccess(
          point: dragged400mPin,
          accuracyMeters: 8,
          isOutsideCambodia: false,
        ),
        photoAnchor: liveCamAnchor,
        now: now,
      );
      expect(blockedCam, isA<ReportLocationDeniedPhotoAnchorMismatch>());
      expect(
        (blockedCam as ReportLocationDeniedPhotoAnchorMismatch).anchorSource,
        equals(PhotoAnchorSource.liveCameraCapture),
      );
    });

    test('Dual Master Incident duplicate check catches existing report at photo anchor even when pin is dragged 180 m away', () {
      final repo = ReportRepository();
      final master = repo.findById('#SC-20481')!; // Open pothole on Norodom
      // Dragged ~180 m east-northeast: outside 100 m / 150 m pin radius,
      // still inside 250 m photo fence!
      final draggedPin = LatLng(
        master.coordinates.latitude + 0.0014,
        master.coordinates.longitude + 0.0010,
      );

      // Pin alone does NOT detect the duplicate
      final pinOnly = repo.findDuplicateNearby(
        point: draggedPin,
        category: master.category,
      );
      expect(pinOnly, isNull);

      // Dual check with photo anchor right at master DOES detect it!
      final dual = repo.findDuplicateNearby(
        point: draggedPin,
        category: master.category,
        photoAnchorPoint: master.coordinates,
      );
      expect(dual, isNotNull);
      expect(dual!.masterReport.id, equals(master.id));
      expect(dual.matchedViaPhotoAnchor, isTrue);

      // Submitting defensively merges into the existing Master Incident
      final beforeCount = repo.reports.length;
      final submitted = repo.submitReport(
        category: master.category,
        description: 'Trying to slide pin away from photo spot',
        severity: 4,
        coordinates: draggedPin,
        photoAnchorCoordinates: master.coordinates,
        isAnonymous: false,
        locationVerificationTier:
            ReportLocationVerificationTier.photoExifVerified,
      );
      expect(submitted.mergedIntoExisting, isTrue);
      expect(submitted.report.id, equals(master.id));
      expect(repo.reports.length, equals(beforeCount));
    });

    test('CivicReport JSON round-trip preserves verification tier & unverified photo flag, and ViewModel clears per-photo anchors on delete', () {
      final repo = ReportRepository();
      final vm = ReportWizardViewModel(
        repository: repo,
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: const _FakeIpGeoService(null),
      );

      // Add geotagged photo #1 -> auto-snaps pin & activePhotoAnchor is set
      const spot = LatLng(11.5318, 104.9044);
      vm.addLocalPhotoPath(
        'data:image/png;base64,AAA',
        exifMetadata: PhotoExifMetadata(
          coordinates: spot,
          capturedAt: DateTime(2026, 11, 24, 18, 0),
        ),
      );
      expect(vm.activePhotoAnchor?.point, equals(spot));
      expect(vm.pinLocation, equals(spot));
      expect(vm.isGalleryPhotoWithoutLocationAnchor, isFalse);

      // Add gallery photo #2 without EXIF, then remove photo #1 -> anchor clears
      vm.addLocalPhotoPath('data:image/png;base64,BBB');
      vm.removeLocalPhotoAt(0);
      expect(vm.activePhotoAnchor, isNull);
      expect(vm.isGalleryPhotoWithoutLocationAnchor, isTrue);

      // Submit and verify JSON serialization round-trip
      vm.recordLiveGpsResult(
        const LocationSuccess(
          point: spot,
          accuracyMeters: 10,
          isOutsideCambodia: false,
        ),
      );
      final res = vm.submit();
      expect(res.report.photoLocationUnverified, isTrue);
      expect(
        res.report.locationVerificationTier,
        equals(ReportLocationVerificationTier.verifiedOnSite),
      );

      final restored = CivicReport.fromJson(res.report.toJson());
      expect(restored.photoLocationUnverified, isTrue);
      expect(
        restored.locationVerificationTier,
        equals(ReportLocationVerificationTier.verifiedOnSite),
      );

      // Legacy JSON without new fields defaults cleanly
      final legacyJson = Map<String, dynamic>.from(res.report.toJson())
        ..remove('locationVerificationTier')
        ..remove('photoLocationUnverified');
      final legacyRestored = CivicReport.fromJson(legacyJson);
      expect(legacyRestored.locationVerificationTier, isNull);
      expect(legacyRestored.photoLocationUnverified, isFalse);

      // Submitting WITHOUT a photo never attaches a fake sample asset photo
      final noPhotoRes = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Text-only report without picture',
        severity: 3,
        coordinates: const LatLng(11.5390, 104.9090),
        isAnonymous: false,
      );
      expect(noPhotoRes.report.localPhotoPath, isNull);
      expect(noPhotoRes.report.photoAssetPath, isNull);
      expect(noPhotoRes.report.hasPhoto, isFalse);
      expect(noPhotoRes.report.exifStripped, isFalse);
      final reloadedNoPhoto = CivicReport.fromJson(noPhotoRes.report.toJson());
      expect(reloadedNoPhoto.photoAssetPath, isNull);
      expect(reloadedNoPhoto.hasPhoto, isFalse);
    });

    test('ReportWizardViewModel enforces mandatory >= 1 photo gate, preserves photoAnchor in ReportDraft, and resumes legacy photo-less draft at Step 0', () {
      final repo = ReportRepository();
      const spot = LatLng(11.5318, 104.9044);

      final vm = ReportWizardViewModel(
        repository: repo,
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: const _FakeIpGeoService(null),
      );
      vm.recordLiveGpsResult(
        const LocationSuccess(
          point: spot,
          accuracyMeters: 8,
          isOutsideCambodia: false,
        ),
      );

      // 0 photos -> cannot advance or submit
      expect(vm.hasRequiredPhoto, isFalse);
      expect(vm.canSubmitAtCurrentPin, isFalse);
      vm.nextStep();
      expect(vm.step, equals(0));

      // Add geotagged photo -> unlocks Step 1 -> Step 2 & saves anchor in draft
      vm.addLocalPhotoPath(
        'data:image/png;base64,AAA',
        exifMetadata: PhotoExifMetadata(
          coordinates: spot,
          capturedAt: DateTime(2026, 11, 24, 19, 0),
        ),
      );
      expect(vm.hasRequiredPhoto, isTrue);
      vm.nextStep();
      expect(vm.step, equals(1));
      expect(vm.canSubmitAtCurrentPin, isTrue);

      final savedDraft = vm.toDraft();
      final restoredDraft = ReportDraft.fromJson(savedDraft.toJson());
      expect(restoredDraft.hasPhotoAnchor, isTrue);
      expect(restoredDraft.photoAnchorLat, closeTo(spot.latitude, 0.0001));
      expect(restoredDraft.photoAnchorSource, equals('photoExif'));

      // Resumed VM starts on Step 1 with photo anchor intact
      final resumedVm = ReportWizardViewModel(
        repository: repo,
        initialDraft: restoredDraft,
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: const _FakeIpGeoService(null),
      );
      expect(resumedVm.step, equals(1));
      expect(resumedVm.activePhotoAnchor?.point, equals(spot));
      expect(resumedVm.isGalleryPhotoWithoutLocationAnchor, isFalse);

      // Removing last photo re-locks advancement and submission
      resumedVm.removeLocalPhotoAt(0);
      expect(resumedVm.hasRequiredPhoto, isFalse);
      expect(resumedVm.canSubmitAtCurrentPin, isFalse);
      resumedVm.nextStep();
      expect(resumedVm.step, equals(1));

      // Legacy photo-less draft resumes on Step 0 (Photo)
      const legacyDraft = ReportDraft(
        category: IssueCategory.pothole,
        severity: 3,
        description: 'Old draft before photo requirement',
        isAnonymous: false,
        localPhotoPaths: <String>[],
      );
      final legacyVm = ReportWizardViewModel(
        repository: repo,
        initialDraft: legacyDraft,
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: const _FakeIpGeoService(null),
      );
      expect(legacyVm.step, equals(0));
    });

    test('ReportWizardViewModel.stopVoiceRecordingIfActive finalizes an in-progress offline audio memo before leaving Step 2', () async {
      final repo = ReportRepository();
      repo.setOnlineStatus(false);
      final fakeRecorder = _FakeAudioRecorderService(amplitude: 0.7);
      final vm = ReportWizardViewModel(
        repository: repo,
        initialPhotoPaths: const ['data:image/png;base64,AAA'],
        voiceInputService: _FakeVoiceInputService(available: false),
        audioRecorderService: fakeRecorder,
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: const _FakeIpGeoService(null),
      );

      await vm.toggleVoiceRecording();
      expect(vm.isRecordingVoice, isTrue);
      expect(vm.hasVoiceAudioMemo, isFalse);

      await vm.stopVoiceRecordingIfActive();
      expect(vm.isRecordingVoice, isFalse);
      expect(vm.hasVoiceAudioMemo, isTrue);
      expect(vm.voiceAudioPath, equals('data:audio/webm;base64,AAAA'));
      vm.dispose();
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

  @override
  Future<HelpChatReply> askHelpAssistant({
    required String message,
    required List<HelpChatTurn> history,
    required bool englishFirst,
    Map<String, dynamic>? citizenContext,
  }) async => const HelpChatReply(success: false, text: '');
}

class _FakeConfiguredCivicAiService implements CivicAiService {
  _FakeConfiguredCivicAiService({
    required this.photoResult,
    required this.audioResult,
    this.helpReply = const HelpChatReply(success: false, text: ''),
  });

  final PhotoAiAnalysis photoResult;
  final AudioTranscriptionResult audioResult;
  final HelpChatReply helpReply;

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

  @override
  Future<HelpChatReply> askHelpAssistant({
    required String message,
    required List<HelpChatTurn> history,
    required bool englishFirst,
    Map<String, dynamic>? citizenContext,
  }) async => helpReply;
}

class _FakeAudioRecorderService implements AudioRecorderService {
  _FakeAudioRecorderService({required this.amplitude});

  final double amplitude;
  final List<String> deletedPaths = [];
  String? _activePath;
  bool lastPersistentMemo = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> startRecording({bool persistentMemo = false}) async {
    lastPersistentMemo = persistentMemo;
    _activePath = persistentMemo
        ? 'data:audio/webm;base64,AAAA'
        : '${Directory.systemTemp.path}/fake_voice.wav';
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

class _InMemoryLocalStorage extends LocalStorageService {
  _InMemoryLocalStorage(this._state);

  Map<String, dynamic>? _state;

  @override
  Future<Map<String, dynamic>?> readState() async => _state;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {
    _state = state;
  }
}

class _FakeIpGeoService implements IpGeolocationService {
  const _FakeIpGeoService(this.info);
  final IpGeoInfo? info;

  @override
  Future<IpGeoInfo?> lookupCurrentIp() async => info;
}

/// Builds a minimal valid JPEG containing an APP1 EXIF/TIFF block with GPS
/// DMS rationals and `DateTimeOriginal` in the specified byte order (`II`/`MM`).
Uint8List _buildSyntheticExifJpeg({
  required Endian endian,
  required int latDeg,
  required int latMin,
  required int latSecNum,
  required int latSecDen,
  required int lngDeg,
  required int lngMin,
  required int lngSecNum,
  required int lngSecDen,
  required String dateTimeOriginal,
}) {
  final tiff = ByteData(220);
  if (endian == Endian.little) {
    tiff.setUint8(0, 0x49);
    tiff.setUint8(1, 0x49);
  } else {
    tiff.setUint8(0, 0x4D);
    tiff.setUint8(1, 0x4D);
  }
  tiff.setUint16(2, 0x002A, endian);
  tiff.setUint32(4, 8, endian);

  void writeEntry(int off, int tag, int type, int count, int value) {
    tiff.setUint16(off, tag, endian);
    tiff.setUint16(off + 2, type, endian);
    tiff.setUint32(off + 4, count, endian);
    tiff.setUint32(off + 8, value, endian);
  }

  // IFD0 at 8
  tiff.setUint16(8, 2, endian);
  writeEntry(10, 0x8769, 4, 1, 40); // ExifIFD pointer
  writeEntry(22, 0x8825, 4, 1, 70); // GPSIFD pointer
  tiff.setUint32(34, 0, endian);

  // ExifIFD at 40
  tiff.setUint16(40, 1, endian);
  writeEntry(42, 0x9003, 2, 20, 140); // DateTimeOriginal
  tiff.setUint32(54, 0, endian);

  // GPSIFD at 70
  tiff.setUint16(70, 4, endian);
  tiff.setUint16(72, 0x0001, endian);
  tiff.setUint16(74, 2, endian);
  tiff.setUint32(76, 2, endian);
  tiff.setUint8(80, 0x4E); // 'N'
  tiff.setUint8(81, 0x00);
  writeEntry(84, 0x0002, 5, 3, 164);
  tiff.setUint16(96, 0x0003, endian);
  tiff.setUint16(98, 2, endian);
  tiff.setUint32(100, 2, endian);
  tiff.setUint8(104, 0x45); // 'E'
  tiff.setUint8(105, 0x00);
  writeEntry(108, 0x0004, 5, 3, 188);
  tiff.setUint32(120, 0, endian);

  final dtBytes = dateTimeOriginal.codeUnits;
  for (var i = 0; i < dtBytes.length && i < 19; i++) {
    tiff.setUint8(140 + i, dtBytes[i]);
  }
  tiff.setUint8(140 + dtBytes.length, 0);

  void writeRational(int off, int num, int den) {
    tiff.setUint32(off, num, endian);
    tiff.setUint32(off + 4, den, endian);
  }

  writeRational(164, latDeg, 1);
  writeRational(172, latMin, 1);
  writeRational(180, latSecNum, latSecDen);

  writeRational(188, lngDeg, 1);
  writeRational(196, lngMin, 1);
  writeRational(204, lngSecNum, lngSecDen);

  final tiffBytes = tiff.buffer.asUint8List();
  final app1PayloadLen = 2 + 6 + tiffBytes.length;
  final out = BytesBuilder()
    ..add([0xFF, 0xD8])
    ..add([0xFF, 0xE1, (app1PayloadLen >> 8) & 0xFF, app1PayloadLen & 0xFF])
    ..add([0x45, 0x78, 0x69, 0x66, 0x00, 0x00])
    ..add(tiffBytes)
    ..add([0xFF, 0xDA, 0x00, 0x04, 0x11, 0x22])
    ..add([0xFF, 0xD9]);
  return out.toBytes();
}
