import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:srolanhcity/data/repositories/report_repository.dart';
import 'package:srolanhcity/data/services/audio_recorder_service.dart';
import 'package:srolanhcity/data/services/civic_ai_service.dart';
import 'package:srolanhcity/data/services/civic_backend_api_service.dart';
import 'package:srolanhcity/data/services/comment_translation_service.dart';
import 'package:srolanhcity/data/services/exif_stripper.dart';
import 'package:srolanhcity/data/services/ip_geolocation_service.dart';
import 'package:srolanhcity/data/services/local_storage_service.dart';
import 'package:srolanhcity/data/services/location_service.dart';
import 'package:srolanhcity/data/services/reverse_geocoding_service.dart';
import 'package:srolanhcity/data/services/voice_input_service.dart';
import 'package:srolanhcity/domain/models/cambodia_locations.dart';
import 'package:srolanhcity/domain/models/report_models.dart';
import 'package:srolanhcity/domain/services/ai_classifier_service.dart';
import 'package:srolanhcity/domain/services/anti_spoof_service.dart';
import 'package:srolanhcity/domain/services/gis_routing_service.dart';
import 'package:srolanhcity/domain/services/help_assistant_service.dart';
import 'package:srolanhcity/domain/services/map_cluster_service.dart';
import 'package:srolanhcity/domain/services/priority_calculator.dart';
import 'package:srolanhcity/domain/services/relative_time_formatter.dart';
import 'package:srolanhcity/domain/services/report_location_eligibility_service.dart';
import 'package:srolanhcity/domain/services/spatial_clustering_service.dart';
import 'package:srolanhcity/domain/services/support_eligibility_service.dart';
import 'package:srolanhcity/ui/features/report/view_models/report_wizard_view_model.dart';

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

    test('dispatches crew, resolves with proof, and fires alerts only when contributed by current user', () {
      final repo = ReportRepository();
      final initialAlerts = repo.alerts.length;

      // #SC-20519 is not owned/supported by the current user -> no alerts fired.
      final unrelated = repo.findById('#SC-20519')!;
      expect(unrelated.isContributedByCurrentUser, isFalse);

      final dispatchedUnrelated = repo.approveAndDispatch(
        '#SC-20519',
        crewCode: 'B-07',
      );
      expect(dispatchedUnrelated?.status, equals(ReportStatus.crewDispatched));
      expect(repo.alerts.length, equals(initialAlerts));

      final resolvedUnrelated = repo.markResolvedWithProof('#SC-20519');
      expect(resolvedUnrelated?.status, equals(ReportStatus.resolved));
      expect(
        resolvedUnrelated?.resolvedAfterAssetPath,
        equals('assets/pothole-after.jpg'),
      );
      expect(repo.alerts.length, equals(initialAlerts));

      final rated = repo.rateResolvedReport('#SC-20519', 5);
      expect(rated?.citizenRating, equals(5));

      // Supporting/contributing to #SC-20524 enables targeted notifications with location.
      final supported = repo.supportReport(
        '#SC-20524',
        tier: SupportVerificationTier.verifiedNearby,
        distanceMeters: 45,
      )!;
      expect(supported.isContributedByCurrentUser, isTrue);

      repo.approveAndDispatch('#SC-20524', crewCode: 'C-02');
      expect(repo.alerts.length, equals(initialAlerts + 1));
      expect(
        repo.alerts.first.englishSubtitle,
        contains(supported.englishLocation),
      );
      expect(
        repo.alerts.first.khmerSubtitle,
        contains(supported.khmerLocation),
      );

      repo.markResolvedWithProof('#SC-20524');
      expect(repo.alerts.length, equals(initialAlerts + 2));
      expect(
        repo.alerts.first.englishSubtitle,
        contains(supported.englishLocation),
      );
      expect(
        repo.alerts.first.khmerSubtitle,
        contains(supported.khmerLocation),
      );
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

  group('Strict GPS "Affects me" Eligibility & Transparent Remote Support Tagging', () {
    test('allows <= 150 m on-site, requires hierarchical Village/District/Province remote reason > 150 m, and strictly requires Cambodia GPS', () {
      final repo = ReportRepository();
      // Pick Sen Sok report (#SC-20524) in Phnom Penh
      final senSokReport = repo.findById('#SC-20524')!;

      // 1. ~110 m away (<= 150 m) -> instant Verified on-site
      final nearby = SupportEligibilityService.evaluateWithLocation(
        report: senSokReport,
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
      expect(nearby.distanceMeters, lessThanOrEqualTo(150));

      // 2. ~400 m away inside same District (Sen Sok) -> Remote Village / Sangkat
      final sameDistrictVillage =
          SupportEligibilityService.evaluateWithLocation(
            report: senSokReport,
            locationResult: LocationSuccess(
              point: LatLng(
                senSokReport.coordinates.latitude + 0.0036,
                senSokReport.coordinates.longitude,
              ),
              accuracyMeters: 10,
              isOutsideCambodia: false,
            ),
            supportsInLast24Hours: 0,
            userGeocodedPlace: const GeocodedPlace(
              roadName: 'Street 1986',
              sangkat: 'Sangkat Phnom Penh Thmei',
              khan: 'Khan Sen Sok',
              province: 'Phnom Penh',
              village: 'Phum Bayab',
              displayName: 'Phum Bayab, Khan Sen Sok, Phnom Penh',
              countryCode: 'kh',
            ),
          );
      expect(sameDistrictVillage, isA<SupportRequiresRemoteReason>());
      final villageReq = sameDistrictVillage as SupportRequiresRemoteReason;
      expect(villageReq.tier, equals(SupportVerificationTier.remoteVillage));
      expect(villageReq.userAreaEnglish, equals('Phum Bayab'));
      expect(villageReq.requiresDetailedNote, isFalse);

      // 3. ~5.3 km away (Daun Penh supporting Sen Sok) -> Remote District
      final diffDistrict = SupportEligibilityService.evaluateWithLocation(
        report: senSokReport,
        locationResult: const LocationSuccess(
          point: LocationService.phnomPenhCenter,
          accuracyMeters: 15,
          isOutsideCambodia: false,
        ),
        supportsInLast24Hours: 0,
      );
      expect(diffDistrict, isA<SupportRequiresRemoteReason>());
      final districtReq = diffDistrict as SupportRequiresRemoteReason;
      expect(districtReq.tier, equals(SupportVerificationTier.remoteDistrict));
      expect(districtReq.userAreaEnglish, contains('Daun Penh'));
      expect(districtReq.requiresDetailedNote, isFalse);

      // 4. Siem Reap supporting Phnom Penh -> Remote Province (+ mandatory note)
      final diffProvince = SupportEligibilityService.evaluateWithLocation(
        report: senSokReport,
        locationResult: const LocationSuccess(
          point: LatLng(13.3633, 103.8564),
          accuracyMeters: 20,
          isOutsideCambodia: false,
        ),
        supportsInLast24Hours: 0,
      );
      expect(diffProvince, isA<SupportRequiresRemoteReason>());
      final provReq = diffProvince as SupportRequiresRemoteReason;
      expect(provReq.tier, equals(SupportVerificationTier.remoteProvince));
      expect(provReq.userAreaEnglish, equals('Siem Reap'));
      expect(provReq.requiresDetailedNote, isTrue);

      // 4b. Cross-province cap (3/24h) blocks 4th remote province support
      final provCapped = SupportEligibilityService.evaluateWithLocation(
        report: senSokReport,
        locationResult: const LocationSuccess(
          point: LatLng(13.3633, 103.8564),
          accuracyMeters: 20,
          isOutsideCambodia: false,
        ),
        supportsInLast24Hours: 3,
        remoteProvinceSupportsInLast24Hours:
            SupportEligibilityService.maxRemoteProvinceSupportsPer24Hours,
      );
      expect(provCapped, isA<SupportDeniedDailyLimit>());
      expect(
        (provCapped as SupportDeniedDailyLimit).isRemoteProvinceLimit,
        isTrue,
      );

      // 5. GPS disabled / outside Cambodia -> ALWAYS blocked (strict Option A)
      final daunPenhReport = repo.findById('#SC-20519')!;
      final gpsOff = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
        locationResult: const LocationServiceDisabled(),
        supportsInLast24Hours: 0,
      );
      expect(gpsOff, isA<SupportDeniedLocationRequired>());
      expect((gpsOff as SupportDeniedLocationRequired).serviceDisabled, isTrue);

      final outsideKh = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
        locationResult: const LocationSuccess(
          point: LatLng(37.7749, -122.4194),
          accuracyMeters: 20,
          isOutsideCambodia: true,
        ),
        supportsInLast24Hours: 0,
      );
      expect(outsideKh, isA<SupportDeniedLocationRequired>());
      expect(
        (outsideKh as SupportDeniedLocationRequired).outsideCambodia,
        isTrue,
      );

      // 6. Mock GPS is ALWAYS blocked
      final mockBlocked = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
        locationResult: LocationMockDetected(point: daunPenhReport.coordinates),
        supportsInLast24Hours: 0,
      );
      expect(mockBlocked, isA<SupportDeniedMockGps>());
    });

    test('enforces daily caps, persists remote area/reason comment metadata, and cleans up on undo', () {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      final now = DateTime(2026, 11, 23, 16, 0);
      final initialComments = repo
          .findById('#SC-20519')!
          .effectiveComments
          .length;

      // Persist remoteProvince tier, area, reason, and tagged CitizenComment
      final supported = repo.supportReport(
        '#SC-20519',
        tier: SupportVerificationTier.remoteProvince,
        distanceMeters: 230000,
        supportAreaKhmer: 'ខេត្តសៀមរាប',
        supportAreaEnglish: 'Siem Reap',
        reasonCategory: SupportReasonCategory.liveOrFamilyNearby,
        reasonNote: 'My parents commute along Monivong Blvd every morning',
        now: now,
      );
      expect(supported, isNotNull);
      expect(
        supported!.userSupportTier,
        equals(SupportVerificationTier.remoteProvince),
      );
      expect(supported.userSupportAreaEnglish, equals('Siem Reap'));
      expect(supported.effectiveComments.length, equals(initialComments + 1));
      expect(supported.effectiveComments.last.isRemoteSupport, isTrue);
      expect(
        supported.effectiveComments.last.supportAreaEnglish,
        equals('Siem Reap'),
      );
      expect(repo.supportsUsedInLast24Hours(now: now), equals(1));
      expect(repo.remoteProvinceSupportsUsedInLast24Hours(now: now), equals(1));

      final restored = CivicReport.fromJson(supported.toJson());
      expect(
        restored.userSupportTier,
        equals(SupportVerificationTier.remoteProvince),
      );
      expect(restored.userSupportAreaEnglish, equals('Siem Reap'));
      expect(restored.userSupportDistanceMeters, equals(230000));
      expect(restored.effectiveComments.last.isRemoteSupport, isTrue);

      // Undo refunds both total & remote-province slots and removes remote comment
      final undone = repo.undoSupportReport('#SC-20519');
      expect(undone?.userSupportTier, isNull);
      expect(undone?.userSupportAreaEnglish, isNull);
      expect(undone?.effectiveComments.length, equals(initialComments));
      expect(repo.supportsUsedInLast24Hours(now: now), equals(0));
      expect(repo.remoteProvinceSupportsUsedInLast24Hours(now: now), equals(0));

      // Pre-check blocks at 10 votes in last 24h
      final limitDenied = SupportEligibilityService.evaluatePreCheck(
        report: repo.findById('#SC-20519')!,
        supportsInLast24Hours: SupportEligibilityService.maxSupportsPer24Hours,
      );
      expect(limitDenied, isA<SupportDeniedDailyLimit>());

      // Backend support payload shape includes remote_area & reason
      final payload = repo.buildSupportApiPayload(
        reportId: '#SC-20519',
        tier: SupportVerificationTier.remoteDistrict,
        distanceMeters: 3420.6,
        userCoordinates: LocationService.phnomPenhCenter,
        supportAreaEnglish: 'Khan Toul Kork',
        reasonCategory: SupportReasonCategory.dailyCommute,
        reasonNote: 'Ride through every weekday',
      );
      expect(payload['report_id'], equals('#SC-20519'));
      expect(payload['verification_tier'], equals('remoteDistrict'));
      expect(payload['remote_area'], equals('Khan Toul Kork'));
      expect(payload['support_reason_category'], equals('dailyCommute'));
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
      expect(byCode['phnom_penh']!.count, equals(12));
      expect(byCode['siem_reap']!.count, equals(2));

      // Opt-in includeResolved: true includes resolved #SC-20290 in Phnom Penh (13)
      final withResolvedClusters = MapClusterService.clusterForZoom(
        reports: repo.reports,
        zoom: 7.6,
        includeResolved: true,
      );
      final ppWithResolved = withResolvedClusters
          .whereType<ProvinceClusterItem>()
          .firstWhere((item) => item.province.code == 'phnom_penh');
      expect(ppWithResolved.count, equals(13));

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

      // Street zoom -> individual SingleReportPinItem pins only (excluding resolved #SC-20290)
      final streetItems = MapClusterService.clusterForZoom(
        reports: repo.reports,
        zoom: 15.0,
        visibleBounds: ppBounds,
      );
      expect(streetItems.every((item) => item is SingleReportPinItem), isTrue);
      expect(
        streetItems.whereType<SingleReportPinItem>().any(
          (item) => item.report.id == '#SC-20290',
        ),
        isFalse,
      );

      // Viewport filter centered on Phnom Penh excludes Siem Reap (#SC-20531) and resolved #SC-20290
      final ppViewport = MapClusterService.reportsInViewport(
        reports: repo.reports,
        bounds: ppBounds,
        center: LocationService.phnomPenhCenter,
      );
      expect(ppViewport.any((r) => r.id == '#SC-20481'), isTrue);
      expect(ppViewport.any((r) => r.id == '#SC-20531'), isFalse);
      expect(ppViewport.any((r) => r.id == '#SC-20290'), isFalse);

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

    test('SupportEligibilityService blocks GPS-off even with provincial Home District and preserves provincial profile/report JSON', () {
      final repo = ReportRepository();
      const siemReapProfile = UserProfile(
        khmerHomeArea: 'សង្កាត់ស្វាយដង្គំ, ក្រុងសៀមរាប, ខេត្តសៀមរាប',
        englishHomeArea: 'Svay Dangkum, Krong Siem Reap, Siem Reap',
        homeProvinceCode: 'siem_reap',
      );

      final siemReapReport = repo.findById('#SC-20531')!;
      final daunPenhReport = repo.findById('#SC-20519')!;

      // Home Area helper still matches Siem Reap cleanly for Area News
      expect(
        SupportEligibilityService.isInUserHomeArea(
          report: siemReapReport,
          profile: siemReapProfile,
        ),
        isTrue,
      );
      expect(
        SupportEligibilityService.isInUserHomeArea(
          report: daunPenhReport,
          profile: siemReapProfile,
        ),
        isFalse,
      );

      // Strict Option A: GPS off is blocked even for saved Home District
      final blockedHome = SupportEligibilityService.evaluateWithLocation(
        report: siemReapReport,
        locationResult: const LocationServiceDisabled(),
        supportsInLast24Hours: 0,
      );
      expect(blockedHome, isA<SupportDeniedLocationRequired>());

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

      // Guest with GPS off -> strictly blocked
      final repo = ReportRepository();
      final daunPenhReport = repo.findById('#SC-20519')!;
      final guestGpsOff = SupportEligibilityService.evaluateWithLocation(
        report: daunPenhReport,
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

    test('Reopen-online auto-sync: hydrate automatically syncs pendingSync reports with voice transcripts and restores GPS checkpoint', () async {
      final offlineRepo = ReportRepository();
      offlineRepo.setOnlineStatus(false);
      final queued = offlineRepo.submitReport(
        category: IssueCategory.drain,
        description: 'Offline flooded drain',
        severity: 4,
        coordinates: const LatLng(11.5564, 104.9282),
        isAnonymous: false,
        voiceTranscript: 'Clogged drain flooding lane',
      );
      expect(queued.report.syncStatus, equals(SyncStatus.pendingSync));
      expect(
        queued.report.voiceTranscript,
        equals('Clogged drain flooding lane'),
      );

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
      expect(synced.voiceTranscript, equals('Clogged drain flooding lane'));
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

    test('ReportWizardViewModel is transcript-only: shows honest offline voice guidance without saving audio memos', () async {
      final repo = ReportRepository();
      repo.setOnlineStatus(false);
      final fakeRecorder = _FakeAudioRecorderService(amplitude: 0.55);
      final vm = ReportWizardViewModel(
        repository: repo,
        initialCoordinates: const LatLng(11.5318, 104.9044),
        initialPhotoPaths: const ['data:image/png;base64,AAA'],
        voiceInputService: _FakeVoiceInputService(available: false),
        audioRecorderService: fakeRecorder,
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: _FakeIpGeoService(null),
      );
      addTearDown(vm.dispose);

      // Tapping mic offline must NOT record a saved audio memo; shows honest guidance
      await vm.toggleVoiceRecording();
      expect(vm.isRecordingVoice, isFalse);
      expect(
        vm.voiceFeedbackEnglish,
        contains('voice-to-text requires internet'),
      );
      expect(vm.showVoiceDemoFallbackAction, isTrue);

      // Online with blocked Web Speech (Brave) keeps clean transcript fallback
      repo.setOnlineStatus(true);
      final vmOnline = ReportWizardViewModel(
        repository: repo,
        initialPhotoPaths: const ['data:image/png;base64,AAA'],
        voiceInputService: _FakeVoiceInputService(available: false),
        audioRecorderService: _FakeAudioRecorderService(amplitude: 0.5),
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: _FakeIpGeoService(
          const IpGeoInfo(countryCode: 'KH'),
        ),
      );
      addTearDown(vmOnline.dispose);
      await vmOnline.toggleVoiceRecording();
      expect(vmOnline.isRecordingVoice, isFalse);
      expect(vmOnline.showVoiceDemoFallbackAction, isTrue);
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

  group('Strict Universal 150 m Zone & Multi-Incident Detection', () {
    const phnomPenhPin = LatLng(11.5564, 104.9282); // Daun Penh, Phnom Penh
    const siemReapGps = LatLng(13.3633, 103.8564); // ~234 km north-west

    test('strictly blocks any pin > 150 m from live GPS (even same-city 6 km or cross-province) with ReportLocationDeniedOutOfZone', () {
      // 1. Live GPS within 150 m (~95 m) -> allowed (verifiedOnSite)
      final onSite = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
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
      expect(onSite.anchorSource, equals(ZoneAnchorSource.liveDeviceGps));

      // 2. Live GPS 400 m away -> blocked (ReportLocationDeniedOutOfZone)
      final dragged400m = ReportLocationEligibilityService.evaluate(
        pinnedLocation: const LatLng(11.5600, 104.9282),
        liveGpsResult: const LocationSuccess(
          point: phnomPenhPin,
          accuracyMeters: 8,
          isOutsideCambodia: false,
        ),
      );
      expect(dragged400m, isA<ReportLocationDeniedOutOfZone>());
      final outOfZone = dragged400m as ReportLocationDeniedOutOfZone;
      expect(outOfZone.anchorSource, equals(ZoneAnchorSource.liveDeviceGps));
      expect(outOfZone.distanceMeters, greaterThan(150));

      // 3. Siem Reap GPS trying to pin Phnom Penh -> blocked (OutOfZone)
      final crossProvince = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        liveGpsResult: const LocationSuccess(
          point: siemReapGps,
          accuracyMeters: 12,
          isOutsideCambodia: false,
        ),
      );
      expect(crossProvince, isA<ReportLocationDeniedOutOfZone>());
      expect(
        (crossProvince as ReportLocationDeniedOutOfZone).distanceMeters,
        greaterThan(200000),
      );
    });

    test('prioritizes Live Device GPS over Photo EXIF, allows delayed upload with fresh EXIF when live GPS is unavailable, and rejects stale EXIF', () {
      final now = DateTime(2026, 11, 24, 18, 0);
      // 1. Live GPS unavailable (disabled) + fresh EXIF <= 30 days -> allowed via EXIF fallback
      final allowedFallback = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        liveGpsResult: const LocationServiceDisabled(),
        photoExif: PhotoExifMetadata(
          coordinates: const LatLng(11.5566, 104.9283),
          capturedAt: now.subtract(const Duration(hours: 6)),
        ),
        now: now,
      );
      expect(allowedFallback, isA<ReportLocationEligible>());
      expect(
        (allowedFallback as ReportLocationEligible).tier,
        equals(ReportLocationVerificationTier.photoExifVerified),
      );

      // 2. Live GPS available in Siem Reap takes priority over Phnom Penh EXIF -> OutOfZone
      final livePriority = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
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
      expect(livePriority, isA<ReportLocationDeniedOutOfZone>());
      expect(
        (livePriority as ReportLocationDeniedOutOfZone).anchorSource,
        equals(ZoneAnchorSource.liveDeviceGps),
      );

      // Stale EXIF (45 days old) + GPS off -> blocked with staleExifNeedsGps
      final staleGpsOff = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        liveGpsResult: const LocationServiceDisabled(),
        photoExif: PhotoExifMetadata(
          coordinates: const LatLng(11.5566, 104.9283),
          capturedAt: now.subtract(const Duration(days: 45)),
        ),
        now: now,
      );
      expect(staleGpsOff, isA<ReportLocationDeniedLocationRequired>());
      expect(
        (staleGpsOff as ReportLocationDeniedLocationRequired).staleExifNeedsGps,
        isTrue,
      );

      // Stale EXIF + live GPS far away -> blocked as OutOfZone
      final staleFar = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
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
      expect(staleFar, isA<ReportLocationDeniedOutOfZone>());
    });

    test('strictly blocks GPS off / outside Cambodia without fresh EXIF (zero Home District bypass) and always blocks Mock GPS', () {
      final gpsOff = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        liveGpsResult: const LocationServiceDisabled(),
      );
      expect(gpsOff, isA<ReportLocationDeniedLocationRequired>());
      expect(
        (gpsOff as ReportLocationDeniedLocationRequired).serviceDisabled,
        isTrue,
      );

      final outsideKh = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        liveGpsResult: const LocationSuccess(
          point: LatLng(37.7749, -122.4194),
          accuracyMeters: 20,
          isOutsideCambodia: true,
        ),
      );
      expect(outsideKh, isA<ReportLocationDeniedLocationRequired>());
      expect(
        (outsideKh as ReportLocationDeniedLocationRequired).outsideCambodia,
        isTrue,
      );

      // Mock GPS -> ALWAYS blocked even with matching fresh EXIF
      final mocked = ReportLocationEligibilityService.evaluate(
        pinnedLocation: phnomPenhPin,
        liveGpsResult: const LocationMockDetected(point: phnomPenhPin),
        photoExif: PhotoExifMetadata(
          coordinates: phnomPenhPin,
          capturedAt: DateTime.now(),
        ),
      );
      expect(mocked, isA<ReportLocationDeniedMockGps>());
    });

    test('Photo-Anchored Hard Fence (<= 150 m) blocks pins dragged > 150 m from EXIF or live camera fallback when live GPS is unavailable', () {
      final now = DateTime(2026, 11, 24, 19, 0);
      const photoSpot = LatLng(11.5564, 104.9282);
      const within150mPin = LatLng(11.5574, 104.9282); // ~111 m
      const dragged400mPin = LatLng(11.5600, 104.9282); // ~400 m

      final okExif = ReportLocationEligibilityService.evaluate(
        pinnedLocation: within150mPin,
        liveGpsResult: const LocationServiceDisabled(),
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

      final blockedExif = ReportLocationEligibilityService.evaluate(
        pinnedLocation: dragged400mPin,
        liveGpsResult: const LocationServiceDisabled(),
        photoExif: PhotoExifMetadata(
          coordinates: photoSpot,
          capturedAt: now.subtract(const Duration(minutes: 5)),
        ),
        now: now,
      );
      expect(blockedExif, isA<ReportLocationDeniedOutOfZone>());
      final denied = blockedExif as ReportLocationDeniedOutOfZone;
      expect(denied.anchorSource, equals(ZoneAnchorSource.photoExif));
      expect(denied.distanceMeters, greaterThan(150));

      final liveCamAnchor = PhotoLocationAnchor(
        point: photoSpot,
        source: PhotoAnchorSource.liveCameraCapture,
        capturedAt: now,
      );
      final okCam = ReportLocationEligibilityService.evaluate(
        pinnedLocation: within150mPin,
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
        liveGpsResult: const LocationServiceDisabled(),
        photoAnchor: liveCamAnchor,
        now: now,
      );
      expect(blockedCam, isA<ReportLocationDeniedOutOfZone>());
      expect(
        (blockedCam as ReportLocationDeniedOutOfZone).anchorSource,
        equals(ZoneAnchorSource.liveCameraCapture),
      );
    });

    test('SpatialClusteringService finds ALL open same-category reports within 150 m sorted nearest-first and supports joining a specific Master Incident or creating a new one', () {
      const origin = LatLng(11.5318, 104.9044);
      final base = ReportRepository().findById('#SC-20519')!;
      // Report A: 70 m north (neighbor); Report B: 120 m east (neighbor); Report C: 320 m north (outside 150 m)
      final reportA = base.copyWith(
        coordinates: const LatLng(11.53243, 104.9044), // ~70 m
        englishTitle: 'Crater A (70 m)',
      );
      final reportB = CivicReport.fromJson({
        ...base.toJson(),
        'id': '#SC-29902',
        'englishTitle': 'Crater B (120 m)',
        'lat': 11.5318,
        'lng': 104.9055, // ~120 m
        'isMine': false,
        'createdByCurrentUser': false,
        'joinedByCurrentUser': false,
      });
      final reportC = CivicReport.fromJson({
        ...base.toJson(),
        'id': '#SC-29903',
        'englishTitle': 'Crater C (320 m)',
        'lat': 11.5347,
        'lng': 104.9044, // ~320 m (excluded)
        'isMine': false,
        'createdByCurrentUser': false,
        'joinedByCurrentUser': false,
      });

      final repo = ReportRepository(
        initialReports: [reportC, reportB, reportA],
      );

      final matches = repo.findSimilarReportsNearby(
        point: origin,
        category: IssueCategory.pothole,
      );
      expect(matches.length, equals(2));
      expect(matches[0].masterReport.id, equals('#SC-20519'));
      expect(matches[1].masterReport.id, equals('#SC-29902'));
      expect(matches[0].distanceMeters, lessThan(matches[1].distanceMeters));

      // Explicitly join the 2nd match (#SC-29902) via targetMasterReportId
      final beforeB = repo.findById('#SC-29902')!.affectedCitizens;
      final joinedB = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'This is definitely Crater B!',
        severity: 4,
        coordinates: origin,
        isAnonymous: false,
        targetMasterReportId: '#SC-29902',
      );
      expect(joinedB.mergedIntoExisting, isTrue);
      expect(joinedB.report.id, equals('#SC-29902'));
      expect(repo.findById('#SC-29902')!.affectedCitizens, equals(beforeB + 1));

      // Explicitly create a NEW separate pothole report at origin (> 50 m from own)
      final beforeCount = repo.reports.length;
      final createdNew = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Distinct 3rd pothole on opposite sidewalk',
        severity: 3,
        coordinates: origin,
        isAnonymous: false,
        forceCreateNew: true,
      );
      expect(createdNew.mergedIntoExisting, isFalse);
      expect(repo.reports.length, equals(beforeCount + 1));

      // Self-duplicate guard STILL blocks forceCreateNew <= 50 m from user's own report
      final selfBlocked = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Trying to double-submit my own spot',
        severity: 3,
        coordinates: origin,
        isAnonymous: false,
        forceCreateNew: true,
      );
      expect(selfBlocked.alreadyReportedByUser, isTrue);
      expect(selfBlocked.report.id, equals(createdNew.report.id));
    });

    test('CivicReport JSON round-trip preserves verification tier and Step 1 auto-saves photo anchor drafts', () {
      final repo = ReportRepository();
      final vm = ReportWizardViewModel(
        repository: repo,
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: const _FakeIpGeoService(null),
      );

      // Add geotagged photo #1 -> auto-snaps pin & AUTO-SAVES draft with anchor!
      const spot = LatLng(11.5318, 104.9044);
      vm.addLocalPhotoPath(
        'data:image/png;base64,AAA',
        exifMetadata: PhotoExifMetadata(
          coordinates: spot,
          capturedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      expect(vm.activeFreshPhotoAnchor?.point, equals(spot));
      expect(vm.pinLocation, equals(spot));
      expect(vm.autoSavedPhotoAnchorDraft, isTrue);
      expect(repo.draft?.hasPhotoAnchor, isTrue);
      expect(repo.draft?.photoAnchorLat, closeTo(spot.latitude, 0.0001));

      // Add gallery photo #2 without EXIF, then remove photo #1 -> anchor clears
      vm.addLocalPhotoPath('data:image/png;base64,BBB');
      vm.removeLocalPhotoAt(0);
      expect(vm.activePhotoAnchor, isNull);

      // Submit with live GPS and verify JSON serialization round-trip
      vm.recordLiveGpsResult(
        const LocationSuccess(
          point: spot,
          accuracyMeters: 10,
          isOutsideCambodia: false,
        ),
      );
      final res = vm.submit();
      expect(
        res.report.locationVerificationTier,
        equals(ReportLocationVerificationTier.verifiedOnSite),
      );

      final restored = CivicReport.fromJson(res.report.toJson());
      expect(
        restored.locationVerificationTier,
        equals(ReportLocationVerificationTier.verifiedOnSite),
      );

      // Legacy JSON without new fields defaults cleanly
      final legacyJson = Map<String, dynamic>.from(res.report.toJson())
        ..remove('locationVerificationTier');
      final legacyRestored = CivicReport.fromJson(legacyJson);
      expect(legacyRestored.locationVerificationTier, isNull);

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
          capturedAt: DateTime.now().subtract(const Duration(minutes: 10)),
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
      expect(resumedVm.activeFreshPhotoAnchor?.point, equals(spot));

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

    test('ReportWizardViewModel.returnTo150mZone snaps pin back to zone anchor and clears out-of-zone state', () {
      final repo = ReportRepository();
      const spot = LatLng(11.5318, 104.9044);
      final vm = ReportWizardViewModel(
        repository: repo,
        initialCoordinates: const LatLng(11.5356, 104.9044), // ~420 m away
        initialPhotoPaths: const ['data:image/png;base64,AAA'],
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: const _FakeIpGeoService(null),
      );
      vm.setPhotoLocationAnchor(
        PhotoLocationAnchor(
          point: spot,
          source: PhotoAnchorSource.liveCameraCapture,
          capturedAt: DateTime.now(),
        ),
      );
      expect(vm.isOutside150mZone, isTrue);
      expect(vm.canSubmitAtCurrentPin, isFalse);

      final returned = vm.returnTo150mZone();
      expect(returned, equals(spot));
      expect(vm.isOutside150mZone, isFalse);
      expect(vm.canSubmitAtCurrentPin, isTrue);
      vm.dispose();
    });

    test('Anchors 150 m detection to Live GPS while measuring <= 50 m self-duplicate guard from dragged pin inside the 150 m zone', () {
      const spotA = LatLng(11.5620, 104.9228); // User report A
      const spotB = LatLng(11.5618, 104.9221); // User report B (~80 m west)
      const spotNew = LatLng(
        11.5611,
        104.9225,
      ); // Distinct 3rd spot (~105 m from A, ~90 m from B)
      const nearB = LatLng(11.5617, 104.9222); // ~16 m from B, ~75 m from A

      final base = ReportRepository().findById('#SC-20519')!;
      final ownA = CivicReport.fromJson({
        ...base.toJson(),
        'id': '#SC-20519',
        'lat': spotA.latitude,
        'lng': spotA.longitude,
        'isMine': true,
        'createdByCurrentUser': true,
        'joinedByCurrentUser': true,
      });
      final ownB = CivicReport.fromJson({
        ...base.toJson(),
        'id': '#SC-20540',
        'lat': spotB.latitude,
        'lng': spotB.longitude,
        'isMine': true,
        'createdByCurrentUser': true,
        'joinedByCurrentUser': false,
      });

      final repo = ReportRepository(initialReports: [ownA, ownB]);
      final vm = ReportWizardViewModel(
        repository: repo,
        initialCategory: IssueCategory.pothole,
        initialCoordinates: spotA,
        initialPhotoPaths: const ['data:image/png;base64,AAA'],
        civicAiService: _UnconfiguredFakeCivicAiService(),
        ipGeolocationService: const _FakeIpGeoService(null),
      );
      vm.recordLiveGpsResult(
        const LocationSuccess(
          point: spotA,
          accuracyMeters: 8,
          isOutsideCambodia: false,
        ),
      );

      // 1. Pinned right on A -> A is hard self-blocked (<= 50 m)
      expect(vm.isHardSelfBlockedAtPin, isTrue);
      expect(vm.hardSelfBlockedMatch?.masterReport.id, equals('#SC-20519'));

      // 2. Drag pin to distinct 3rd spot inside 150 m (> 50 m from BOTH A & B)
      //    while Live GPS stays at spotA: 150 m candidate list stays anchored
      //    to Live GPS, and self-duplicate block clears so new report unlocks.
      vm.setPinLocation(spotNew, verified: true, fromLiveGps: false);
      expect(vm.isOutside150mZone, isFalse);
      expect(vm.nearbySimilarReports.length, equals(2));
      expect(vm.isHardSelfBlockedAtPin, isFalse);
      expect(vm.isCreatingNewDespiteMatches, isTrue);
      expect(vm.selectedMasterMatch, isNull);

      // Submitting creates a brand-new 3rd separate report cleanly at spotNew
      final created = vm.submit(forceCreateNew: true);
      expect(created.mergedIntoExisting, isFalse);
      expect(repo.reports.length, equals(3));

      // 3. Drag pin within <= 50 m of B -> switches self-block to B
      vm.setPinLocation(nearB, verified: true, fromLiveGps: false);
      expect(vm.isHardSelfBlockedAtPin, isTrue);
      expect(vm.hardSelfBlockedMatch?.masterReport.id, equals('#SC-20540'));
      expect(vm.selectedMasterMatch?.masterReport.id, equals('#SC-20540'));
      vm.dispose();
    });
  });

  group('R1–R4 Comment GPS Tags, Real Author Names & Deletable Alerts', () {
    test('R1: SupportEligibilityService.evaluateCommentLocation validates Cambodia GPS and resolves 3-level remote hierarchy without ownership/cap blocks', () {
      final repo = ReportRepository();
      // Even an already-supported report can be commented on.
      final supported = repo.supportReport(
        '#SC-20519',
        tier: SupportVerificationTier.verifiedNearby,
        distanceMeters: 25,
      )!;
      expect(supported.isContributedByCurrentUser, isTrue);

      // Mock GPS -> denied
      final mockDecision = SupportEligibilityService.evaluateCommentLocation(
        report: supported,
        locationResult: LocationMockDetected(
          point: supported.coordinates,
          detectedLabel: 'Fake GPS JoyStick',
        ),
      );
      expect(mockDecision, isA<CommentLocationMockGps>());

      // GPS off -> denied
      final disabledDecision =
          SupportEligibilityService.evaluateCommentLocation(
            report: supported,
            locationResult: const LocationServiceDisabled(),
          );
      expect(
        disabledDecision,
        isA<CommentLocationDenied>().having(
          (d) => d.serviceDisabled,
          'serviceDisabled',
          isTrue,
        ),
      );

      // Outside Cambodia -> denied
      final outsideDecision = SupportEligibilityService.evaluateCommentLocation(
        report: supported,
        locationResult: const LocationSuccess(
          point: LatLng(37.422, -122.084),
          accuracyMeters: 15,
          isOutsideCambodia: true,
        ),
      );
      expect(
        outsideDecision,
        isA<CommentLocationDenied>().having(
          (d) => d.outsideCambodia,
          'outsideCambodia',
          isTrue,
        ),
      );

      // <= 150 m -> verifiedNearby (`✓ On-site`)
      final onsiteDecision = SupportEligibilityService.evaluateCommentLocation(
        report: supported,
        locationResult: LocationSuccess(
          point: LatLng(
            supported.coordinates.latitude + 0.0005,
            supported.coordinates.longitude,
          ),
          accuracyMeters: 8,
          isOutsideCambodia: false,
        ),
      );
      expect(
        onsiteDecision,
        isA<CommentLocationVerified>().having(
          (r) => r.tier,
          'tier',
          SupportVerificationTier.verifiedNearby,
        ),
      );
      expect(
        SupportVerificationTier.verifiedNearby.formatCommentLocationTag(
          englishFirst: true,
        ),
        equals('✓ On-site'),
      );
      expect(
        SupportVerificationTier.verifiedNearby.formatCommentLocationTag(
          englishFirst: false,
        ),
        equals('✓ នៅទីតាំង'),
      );

      // Same district > 150 m with village -> remoteVillage (`Remote · <Village>`)
      final villageDecision = SupportEligibilityService.evaluateCommentLocation(
        report: supported,
        locationResult: LocationSuccess(
          point: LatLng(
            supported.coordinates.latitude + 0.003,
            supported.coordinates.longitude,
          ),
          accuracyMeters: 12,
          isOutsideCambodia: false,
        ),
        userGeocodedPlace: const GeocodedPlace(
          roadName: 'Street 178',
          sangkat: 'Chey Chumneah',
          khan: 'Daun Penh',
          village: 'Phum 4',
          displayName: 'Phum 4, Chey Chumneah, Daun Penh',
          countryCode: 'kh',
        ),
      ) as CommentLocationVerified;
      expect(
        villageDecision.tier,
        equals(SupportVerificationTier.remoteVillage),
      );
      expect(
        villageDecision.tier.formatCommentLocationTag(
          englishFirst: true,
          areaKhmer: villageDecision.userAreaKhmer,
          areaEnglish: villageDecision.userAreaEnglish,
        ),
        equals('Remote · Phum 4'),
      );

      // Same province, different Khan -> remoteDistrict (`Remote · <District>`)
      final senSokReport = repo.findById('#SC-20524')!;
      final districtDecision =
          SupportEligibilityService.evaluateCommentLocation(
            report: senSokReport,
            locationResult: const LocationSuccess(
              point: LocationService.phnomPenhCenter,
              accuracyMeters: 15,
              isOutsideCambodia: false,
            ),
          ) as CommentLocationVerified;
      expect(
        districtDecision.tier,
        equals(SupportVerificationTier.remoteDistrict),
      );
      expect(
        districtDecision.tier.formatCommentLocationTag(
          englishFirst: true,
          areaKhmer: districtDecision.userAreaKhmer,
          areaEnglish: districtDecision.userAreaEnglish,
        ),
        equals('Remote · Khan Daun Penh'),
      );

      // Different province -> remoteProvince (`Remote · <Province>`)
      final provinceDecision =
          SupportEligibilityService.evaluateCommentLocation(
            report: senSokReport,
            locationResult: const LocationSuccess(
              point: LatLng(13.3633, 103.8564),
              accuracyMeters: 20,
              isOutsideCambodia: false,
            ),
          ) as CommentLocationVerified;
      expect(
        provinceDecision.tier,
        equals(SupportVerificationTier.remoteProvince),
      );
      expect(
        provinceDecision.tier.formatCommentLocationTag(
          englishFirst: true,
          areaKhmer: provinceDecision.userAreaKhmer,
          areaEnglish: provinceDecision.userAreaEnglish,
        ),
        equals('Remote · Siem Reap'),
      );
      expect(
        provinceDecision.tier.formatCommentLocationTag(
          englishFirst: false,
          areaKhmer: provinceDecision.userAreaKhmer,
          areaEnglish: provinceDecision.userAreaEnglish,
        ),
        equals('ពីចម្ងាយ · ខេត្តសៀមរាប'),
      );
    });

    test('R2: CitizenComment persists optional authorName with backward-compatible JSON and Guest/Anonymous rules', () {
      // Legacy JSON lacking authorName deserializes cleanly with null authorName
      final legacyComment = CitizenComment.fromJson({
        'id': 'c-legacy-1',
        'text': 'Water rising quickly',
        'createdAt': '2026-11-20T10:00:00.000Z',
        'isOriginalReporter': false,
        'isCurrentUser': true,
        'isAnonymous': false,
      });
      expect(legacyComment.authorName, isNull);
      expect(legacyComment.toJson().containsKey('authorName'), isFalse);

      // Non-empty authorName round-trips through JSON
      final namedComment = legacyComment.copyWith(authorName: 'Dara Sok');
      final roundTripped = CitizenComment.fromJson(namedComment.toJson());
      expect(roundTripped.authorName, equals('Dara Sok'));

      // UserProfile helper detects Guest / Khmer Guest / empty
      expect(UserProfile.isDefaultOrEmptyName(null), isTrue);
      expect(UserProfile.isDefaultOrEmptyName('  '), isTrue);
      expect(UserProfile.isDefaultOrEmptyName('Guest'), isTrue);
      expect(UserProfile.isDefaultOrEmptyName('ភ្ញៀវ'), isTrue);
      expect(UserProfile.isDefaultOrEmptyName('Dara Sok'), isFalse);
      expect(const UserProfile().realDisplayName(englishFirst: true), isNull);
      expect(
        const UserProfile(
          englishName: 'Dara Sok',
          khmerName: 'តារា សុខ',
        ).realDisplayName(englishFirst: false),
        equals('តារា សុខ'),
      );

      // Repository attaches authorName only when !isAnonymous and non-Guest
      final guestRepo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      final guestNote = guestRepo
          .addCitizenComment(
            '#SC-20481',
            text: 'Guest note',
            isAnonymous: false,
          )!
          .effectiveComments
          .last;
      expect(guestNote.authorName, isNull);

      guestRepo.updateProfile(
        const UserProfile(englishName: 'Dara Sok', khmerName: 'តារា សុខ'),
      );
      final namedNote = guestRepo
          .addCitizenComment(
            '#SC-20481',
            text: 'Real name note',
            isAnonymous: false,
            supportTier: SupportVerificationTier.verifiedNearby,
          )!
          .effectiveComments
          .last;
      expect(namedNote.authorName, equals('Dara Sok'));
      expect(
        namedNote.supportTier,
        equals(SupportVerificationTier.verifiedNearby),
      );

      final anonNote = guestRepo
          .addCitizenComment(
            '#SC-20481',
            text: 'Anonymous note',
            isAnonymous: true,
          )!
          .effectiveComments
          .last;
      expect(anonNote.authorName, isNull);
      expect(anonNote.isAnonymous, isTrue);
    });

    test('R3 & R4: reportCountForProvince excludes resolved when requested, and alert removal/clear/restore/hydrate never delete CivicReports', () async {
      final storage = _InMemoryLocalStorage(null);
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
        storage: storage,
      );

      // R3 province count distinction (AreaNews all=13 vs Map active=12)
      expect(
        repo.reportCountForProvince(CambodiaLocationCatalog.phnomPenh),
        equals(13),
      );
      expect(
        repo.reportCountForProvince(
          CambodiaLocationCatalog.phnomPenh,
          includeResolved: false,
        ),
        equals(12),
      );

      // R4: remove single alert + restore at original index; underlying report intact
      final initialReportCount = repo.reports.length;
      final initialAlerts = repo.alerts.toList();
      expect(initialAlerts.length, greaterThanOrEqualTo(3));
      final targetAlert = initialAlerts[1];
      expect(repo.findById(targetAlert.reportId), isNotNull);

      final removed = repo.removeAlert(targetAlert.id);
      expect(removed, isNotNull);
      expect(removed!.index, equals(1));
      expect(repo.alerts.length, equals(initialAlerts.length - 1));
      expect(repo.reports.length, equals(initialReportCount));
      expect(repo.findById(targetAlert.reportId), isNotNull);

      repo.restoreAlert(removed.alert, index: removed.index);
      expect(repo.alerts.length, equals(initialAlerts.length));
      expect(repo.alerts[1].id, equals(targetAlert.id));

      // R4: clearReadAlerts removes only read alerts
      repo.markAlertRead(initialAlerts.first.id);
      final clearedRead = repo.clearReadAlerts();
      expect(clearedRead.isNotEmpty, isTrue);
      expect(repo.alerts.any((a) => a.isRead), isFalse);
      expect(repo.reports.length, equals(initialReportCount));
      repo.restoreAlerts(clearedRead);
      expect(repo.alerts.length, equals(initialAlerts.length));

      // R4: clearAllAlerts empties alerts and persists empty list across hydrate()
      final clearedAll = repo.clearAllAlerts();
      expect(clearedAll.length, equals(initialAlerts.length));
      expect(repo.alerts, isEmpty);
      expect(repo.reports.length, equals(initialReportCount));

      // Wait for fire-and-forget _persist() microtask then re-hydrate
      await Future<void>.delayed(Duration.zero);
      final rehydratedRepo = ReportRepository(storage: storage);
      await rehydratedRepo.hydrate();
      expect(rehydratedRepo.alerts, isEmpty);
      expect(rehydratedRepo.reports.length, equals(initialReportCount));
    });
  });

  group('Backend integration models & services', () {
    test('fromJson factories parse FastAPI snake_case payloads', () {
      final report = CivicReport.fromJson(<String, dynamic>{
        'id': '#SC-90001',
        'category': 'pothole',
        'khmer_title': 'រន្ធផ្លូវធំ',
        'english_title': 'Large pothole',
        'description': 'Deep pothole near intersection',
        'khmer_location': 'ខណ្ឌដូនពេញ, រាជធានីភ្នំពេញ',
        'english_location': 'Daun Penh, Phnom Penh',
        'lat': 11.57,
        'lng': 104.92,
        'province_code': 'PP',
        'khmer_province': 'រាជធានីភ្នំពេញ',
        'english_province': 'Phnom Penh',
        'road_class': 'primary',
        'severity': 4,
        'affected_citizens': 5,
        'status': 'crewDispatched',
        'khmer_agency': 'មន្ទីរសាធារណការ',
        'english_agency': 'Department of Public Works',
        'is_anonymous': true,
        'is_mine': true,
        'created_by_current_user': true,
        'joined_by_current_user': false,
        'created_at': '2026-11-26T10:00:00Z',
        'timeline': [
          <String, dynamic>{
            'stage': 'submitted',
            'khmer_title': 'បានទទួល',
            'english_title': 'Submitted',
            'khmer_subtitle': 'រួចរាល់',
            'english_subtitle': 'Received',
            'complete': true,
            'timestamp': '2026-11-26T10:00:00Z',
          },
        ],
        'citizen_comments': [
          <String, dynamic>{
            'id': 'c-1',
            'text': 'Needs urgent repair',
            'created_at': '2026-11-26T10:05:00Z',
            'is_original_reporter': true,
            'is_current_user': true,
            'is_anonymous': true,
            'support_tier': 'remoteDistrict',
            'support_area_khmer': 'ទួលគោក',
            'support_area_english': 'Toul Kork',
            'support_reason_category': 'dailyCommute',
          },
        ],
      });

      expect(report.id, equals('#SC-90001'));
      expect(report.englishTitle, equals('Large pothole'));
      expect(report.affectedCitizens, equals(5));
      expect(report.status, equals(ReportStatus.crewDispatched));
      expect(report.createdByCurrentUser, isTrue);
      expect(report.timeline.single.englishTitle, equals('Submitted'));
      expect(
        report.citizenComments.single.supportTier,
        equals(SupportVerificationTier.remoteDistrict),
      );

      final alert = AlertItem.fromJson(<String, dynamic>{
        'id': 'a-1',
        'report_id': '#SC-90001',
        'khmer_title': 'ព័ត៌មាន',
        'english_title': 'Update',
        'khmer_subtitle': 'កំពុងជួសជុល',
        'english_subtitle': 'Crew dispatched',
        'created_at': '2026-11-26T11:00:00Z',
        'is_read': true,
      });
      expect(alert.reportId, equals('#SC-90001'));
      expect(alert.isRead, isTrue);
    });

    test(
      'CivicBackendApiService handles guest auth and viewport reports',
      () async {
        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/guest' &&
              request.method == 'POST') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'access_token': 'tok-123',
                'token_type': 'bearer',
                'role': 'citizen',
                'user_id': 'guest-1',
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/reports' &&
              request.method == 'GET') {
            expect(request.headers['Authorization'], equals('Bearer tok-123'));
            return http.Response.bytes(
              utf8.encode(
                jsonEncode(<String, dynamic>{
                  'pins': [
                    <String, dynamic>{
                      'tier': 'single',
                      'report': <String, dynamic>{
                        'id': '#SC-777',
                        'category': 'flooding',
                        'khmer_title': 'ទឹកជំនន់',
                        'english_title': 'Street flooding',
                        'description': 'Water knee-deep',
                        'khmer_location': 'ភ្នំពេញ',
                        'english_location': 'Phnom Penh',
                        'lat': 11.55,
                        'lng': 104.92,
                        'severity': 4,
                        'affected_citizens': 3,
                        'status': 'submitted',
                        'khmer_agency': 'មន្ទីរ',
                        'english_agency': 'DPWT',
                        'created_at': '2026-11-26T10:00:00Z',
                        'timeline': const <Map<String, dynamic>>[],
                        'citizen_comments': const <Map<String, dynamic>>[],
                      },
                    },
                  ],
                }),
              ),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response('Not found', 404);
        });

        final api = CivicBackendApiService(
          httpClient: mockClient,
          baseUrl: 'http://localhost:8000/',
        );
        final session = await api.ensureGuestSession(deviceId: 'dev-1');
        expect(session?.accessToken, equals('tok-123'));
        expect(session?.userId, equals('guest-1'));

        final reports = await api.fetchReportsViewport();
        expect(reports, isNotNull);
        expect(reports!.single.id, equals('#SC-777'));

        final unconfigured = CivicBackendApiService(
          httpClient: mockClient,
          baseUrl: '',
        );
        expect(unconfigured.isConfigured, isFalse);
        expect(await unconfigured.ensureGuestSession(), isNull);
      },
    );

    test(
      'HttpCommentTranslationService uses backend /ai/translate with fallback',
      () async {
        final backendFirstClient = MockClient((request) async {
          if (request.url.path == '/api/v1/ai/translate') {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode(<String, dynamic>{'translated_text': 'ជួសជុលរួច'}),
              ),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response('unexpected', 500);
        });

        final backendService = HttpCommentTranslationService(
          httpClient: backendFirstClient,
          baseUrl: 'http://localhost:8000',
        );
        expect(
          await backendService.translate(text: 'Fixed', targetLang: 'km'),
          equals('ជួសជុលរួច'),
        );

        final fallbackClient = MockClient((request) async {
          if (request.url.path == '/api/v1/ai/translate') {
            return http.Response('unavailable', 503);
          }
          if (request.url.host == 'translate.googleapis.com') {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode([
                  [
                    ['Fallback OK', 'សួស្តី'],
                  ],
                ]),
              ),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response('not found', 404);
        });

        final fallbackService = HttpCommentTranslationService(
          httpClient: fallbackClient,
          baseUrl: 'http://localhost:8000',
        );
        expect(
          await fallbackService.translate(text: 'សួស្តី', targetLang: 'en'),
          equals('Fallback OK'),
        );
      },
    );

    test('CivicReport.fromJson treats timezone-less ISO timestamps as UTC', () {
      final now = DateTime.now();
      final naiveUtc = now.toUtc().toIso8601String().replaceFirst('Z', '');
      final report = CivicReport.fromJson(<String, dynamic>{
        'id': '#SC-UTC1',
        'category': 'pothole',
        'khmer_title': 'រន្ធផ្លូវ',
        'english_title': 'Pothole',
        'description': 'Test',
        'khmer_location': 'ភ្នំពេញ',
        'english_location': 'Phnom Penh',
        'lat': 11.55,
        'lng': 104.92,
        'severity': 3,
        'affected_citizens': 1,
        'status': 'submitted',
        'khmer_agency': 'មន្ទីរ',
        'english_agency': 'DPWT',
        'created_at': naiveUtc,
        'timeline': const <Map<String, dynamic>>[],
        'citizen_comments': const <Map<String, dynamic>>[],
      });

      expect(
        report.createdAt.difference(now).abs(),
        lessThan(const Duration(seconds: 5)),
      );
    });

    test('ReportRepository allows commenting with local ID after server ID remap', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/guest' &&
            request.method == 'POST') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'access_token': 'tok-remap',
                'token_type': 'bearer',
                'role': 'citizen',
                'user_id': 'guest-remap',
              }),
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (request.url.path == '/api/v1/reports' && request.method == 'POST') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'id': '#SC-SRV1',
                'category': 'pothole',
                'khmer_title': 'រន្ធផ្លូវ',
                'english_title': 'Pothole',
                'description': 'Initial desc',
                'khmer_location': 'ភ្នំពេញ',
                'english_location': 'Phnom Penh',
                'lat': 11.55,
                'lng': 104.92,
                'severity': 3,
                'affected_citizens': 1,
                'status': 'submitted',
                'khmer_agency': 'មន្ទីរ',
                'english_agency': 'DPWT',
                'created_by_current_user': true,
                'is_mine': true,
                'created_at': DateTime.now().toUtc().toIso8601String(),
                'timeline': const <Map<String, dynamic>>[],
                'citizen_comments': const <Map<String, dynamic>>[],
              }),
            ),
            201,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (request.url.path == '/api/v1/reports/%23SC-SRV1/comments' &&
            request.method == 'POST') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'id': 'c-srv-1',
                'text': 'Follow up note',
                'created_at': DateTime.now().toUtc().toIso8601String(),
                'is_original_reporter': false,
                'is_current_user': true,
                'is_anonymous': false,
              }),
            ),
            201,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        return http.Response('Not found', 404);
      });

      final api = CivicBackendApiService(
        httpClient: mockClient,
        baseUrl: 'http://localhost:8000',
      );
      final repo = ReportRepository(initialReports: const [], apiService: api);
      final result = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Initial desc',
        severity: 3,
        coordinates: const LatLng(11.55, 104.92),
        isAnonymous: false,
      );
      final localId = result.report.id;

      // Let background _syncCreatedReport finish remapping localId -> #SC-SRV1.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.findById(localId)?.id, equals('#SC-SRV1'));
      final updated = repo.addCitizenComment(localId, text: 'Follow up note');
      expect(updated, isNotNull);
      expect(updated!.citizenComments.last.text, equals('Follow up note'));
      repo.dispose();
    });

    test('CivicReport.fromJson treats timezone-less ISO timestamps as UTC', () {
      final now = DateTime.now();
      final naiveUtc = now.toUtc().toIso8601String().replaceFirst('Z', '');
      final report = CivicReport.fromJson(<String, dynamic>{
        'id': '#SC-UTC1',
        'category': 'pothole',
        'khmer_title': 'រន្ធផ្លូវ',
        'english_title': 'Pothole',
        'description': 'Test',
        'khmer_location': 'ភ្នំពេញ',
        'english_location': 'Phnom Penh',
        'lat': 11.55,
        'lng': 104.92,
        'severity': 3,
        'affected_citizens': 1,
        'status': 'submitted',
        'khmer_agency': 'មន្ទីរ',
        'english_agency': 'DPWT',
        'created_at': naiveUtc,
        'timeline': const <Map<String, dynamic>>[],
        'citizen_comments': const <Map<String, dynamic>>[],
      });

      expect(
        report.createdAt.difference(now).abs(),
        lessThan(const Duration(seconds: 5)),
      );
    });

    test('ReportRepository allows commenting with local ID after server ID remap', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/guest' &&
            request.method == 'POST') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'access_token': 'tok-remap',
                'token_type': 'bearer',
                'role': 'citizen',
                'user_id': 'guest-remap',
              }),
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (request.url.path == '/api/v1/reports' && request.method == 'POST') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'id': '#SC-SRV1',
                'category': 'pothole',
                'khmer_title': 'រន្ធផ្លូវ',
                'english_title': 'Pothole',
                'description': 'Initial desc',
                'khmer_location': 'ភ្នំពេញ',
                'english_location': 'Phnom Penh',
                'lat': 11.55,
                'lng': 104.92,
                'severity': 3,
                'affected_citizens': 1,
                'status': 'submitted',
                'khmer_agency': 'មន្ទីរ',
                'english_agency': 'DPWT',
                'created_by_current_user': true,
                'is_mine': true,
                'created_at': DateTime.now().toUtc().toIso8601String(),
                'timeline': const <Map<String, dynamic>>[],
                'citizen_comments': const <Map<String, dynamic>>[],
              }),
            ),
            201,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (request.url.path == '/api/v1/reports/%23SC-SRV1/comments' &&
            request.method == 'POST') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'id': 'c-srv-1',
                'text': 'Follow up note',
                'created_at': DateTime.now().toUtc().toIso8601String(),
                'is_original_reporter': false,
                'is_current_user': true,
                'is_anonymous': false,
              }),
            ),
            201,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        return http.Response('Not found', 404);
      });

      final api = CivicBackendApiService(
        httpClient: mockClient,
        baseUrl: 'http://localhost:8000',
      );
      final repo = ReportRepository(initialReports: const [], apiService: api);
      final result = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Initial desc',
        severity: 3,
        coordinates: const LatLng(11.55, 104.92),
        isAnonymous: false,
      );
      final localId = result.report.id;

      // Let background _syncCreatedReport finish remapping localId -> #SC-SRV1.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.findById(localId)?.id, equals('#SC-SRV1'));
      final updated = repo.addCitizenComment(localId, text: 'Follow up note');
      expect(updated, isNotNull);
      expect(updated!.citizenComments.last.text, equals('Follow up note'));
      repo.dispose();
    });

    test('Offline report with legit photo uploads on reconnect and is never wiped by refreshFromBackend', () async {
      var createdCount = 0;
      final syncedFromServer = <Map<String, dynamic>>[];
      final mockClient = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/guest') {
          return http.Response(
            jsonEncode({'access_token': 'tok-1', 'user_id': 'u-1'}),
            200,
          );
        }
        if (req.url.path == '/api/v1/reports' && req.method == 'POST') {
          createdCount++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final srv = {
            'id': '#SC-LEGIT1',
            'category': body['category'],
            'khmer_title': 'រណ្តៅផ្លូវ',
            'english_title': 'Deep Pothole',
            'description': body['description'],
            'khmer_location': 'ភ្នំពេញ',
            'english_location': 'Phnom Penh',
            'lat': body['lat'],
            'lng': body['lng'],
            'province_code': 'PP',
            'khmer_province': 'ភ្នំពេញ',
            'english_province': 'Phnom Penh',
            'road_class': 'artery',
            'severity': body['severity'],
            'affected_citizens': 1,
            'status': 'submitted',
            'khmer_agency': 'MPWT',
            'english_agency': 'MPWT',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'timeline': const <Map<String, dynamic>>[],
            'citizen_comments': const <Map<String, dynamic>>[],
          };
          syncedFromServer.add(srv);
          return http.Response.bytes(
            utf8.encode(jsonEncode(srv)),
            201,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (req.url.path == '/api/v1/reports' && req.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'tier': 'pin',
                'zoom': 15.0,
                'total_matching': syncedFromServer.length,
                'provinces': const [],
                'areas': const [],
                'pins': syncedFromServer
                    .map((r) => {'tier': 'pin', 'report': r})
                    .toList(),
              }),
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (req.url.path == '/api/v1/alerts') {
          return http.Response('[]', 200);
        }
        return http.Response('Not found', 404);
      });

      final api = CivicBackendApiService(
        httpClient: mockClient,
        baseUrl: 'http://localhost:8000',
      );
      final ai = _FakeConfiguredCivicAiService(
        photoResult: const PhotoAiAnalysis(
          status: PhotoAiStatus.analyzed,
          detectedCategory: IssueCategory.pothole,
          confidencePercent: 92,
        ),
        audioResult: const AudioTranscriptionResult(success: false),
      );
      final repo = ReportRepository(
        initialReports: const [],
        apiService: api,
        civicAiService: ai,
      );
      repo.setOnlineStatus(false);
      final submitted = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Offline pothole photo',
        severity: 3,
        coordinates: const LatLng(11.5564, 104.9282),
        isAnonymous: false,
        localPhotoPath: 'data:image/jpeg;base64,/9j/4AAQ',
      );
      expect(submitted.report.syncStatus, equals(SyncStatus.pendingSync));

      repo.setOnlineStatus(true);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(createdCount, equals(1));
      expect(repo.reports.length, equals(1));
      expect(repo.reports.first.id, equals('#SC-LEGIT1'));
      expect(repo.reports.first.syncStatus, equals(SyncStatus.synced));
      repo.dispose();
    });

    test('Offline report with unrelated photo is NOT uploaded on reconnect, marked rejectedByAi, and can be deleted past 15 min', () async {
      var createdCount = 0;
      final mockClient = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/guest') {
          return http.Response(
            jsonEncode({'access_token': 'tok-1', 'user_id': 'u-1'}),
            200,
          );
        }
        if (req.url.path == '/api/v1/reports' && req.method == 'POST') {
          createdCount++;
          return http.Response('{}', 201);
        }
        if (req.url.path == '/api/v1/reports' && req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'tier': 'pin',
              'zoom': 15.0,
              'total_matching': 0,
              'provinces': const [],
              'areas': const [],
              'pins': const [],
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/alerts') {
          return http.Response('[]', 200);
        }
        return http.Response('Not found', 404);
      });

      final api = CivicBackendApiService(
        httpClient: mockClient,
        baseUrl: 'http://localhost:8000',
      );
      final ai = _FakeConfiguredCivicAiService(
        photoResult: const PhotoAiAnalysis(
          status: PhotoAiStatus.notCivicIssue,
          khmerReason: 'រូបភាពនេះជារបស់ផ្ទាល់ខ្លួន',
          englishReason: 'Private backyard photo, not a public civic issue.',
        ),
        audioResult: const AudioTranscriptionResult(success: false),
      );
      final repo = ReportRepository(
        initialReports: const [],
        apiService: api,
        civicAiService: ai,
      );
      repo.setOnlineStatus(false);
      final submitted = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Offline backyard photo',
        severity: 2,
        coordinates: const LatLng(11.5564, 104.9282),
        isAnonymous: false,
        localPhotoPath: 'data:image/jpeg;base64,/9j/4AAQ',
      );

      repo.setOnlineStatus(true);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(createdCount, equals(0));
      final rejected = repo.findById(submitted.report.id);
      expect(rejected, isNotNull);
      expect(rejected!.syncStatus, equals(SyncStatus.rejectedByAi));
      expect(
        rejected.aiRejectionReasonEnglish,
        contains('Private backyard photo'),
      );
      expect(repo.rejectedByAiCount, equals(1));
      expect(repo.alerts.any((a) => a.reportId == submitted.report.id), isTrue);

      // Even 2 hours later, the citizen can delete the AI-rejected local report.
      final removal = repo.withdrawUserReport(
        submitted.report.id,
        now: submitted.report.createdAt.add(const Duration(hours: 2)),
      );
      expect(removal, isA<ReportRemoved>());
      expect(repo.findById(submitted.report.id), isNull);
      repo.dispose();
    });

    test('Step 2 draft resume automatically re-runs AI photo check and blocks advancing if unrelated', () async {
      final repo = ReportRepository(initialReports: const []);
      repo.setOnlineStatus(true);
      final ai = _FakeConfiguredCivicAiService(
        photoResult: const PhotoAiAnalysis(
          status: PhotoAiStatus.notCivicIssue,
          englishReason: 'Not a public civic infrastructure issue.',
        ),
        audioResult: const AudioTranscriptionResult(success: false),
      );
      final draft = ReportDraft(
        category: IssueCategory.trash,
        severity: 3,
        description: 'Saved draft',
        isAnonymous: false,
        localPhotoPaths: const ['data:image/jpeg;base64,/9j/4AAQ'],
      );

      final vm = ReportWizardViewModel(
        repository: repo,
        initialDraft: draft,
        civicAiService: ai,
      );
      // Immediately blocked while analyzing on resume.
      expect(vm.step, equals(1));
      expect(vm.isPhotoAiBlockedForNextStep, isTrue);
      vm.nextStep();
      expect(vm.step, equals(1));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(vm.photoAi.status, equals(PhotoAiStatus.notCivicIssue));
      expect(vm.isPhotoAiBlockedForNextStep, isTrue);
      vm.nextStep();
      expect(vm.step, equals(1));
      vm.dispose();
      repo.dispose();
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
