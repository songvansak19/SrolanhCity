import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/data/repositories/report_repository.dart';
import 'package:my_app/data/services/audio_player_service.dart';
import 'package:my_app/data/services/audio_recorder_service.dart';
import 'package:my_app/data/services/civic_ai_service.dart';
import 'package:my_app/data/services/comment_translation_service.dart';
import 'package:my_app/data/services/exif_stripper.dart';
import 'package:my_app/data/services/ip_geolocation_service.dart';
import 'package:my_app/data/services/location_service.dart';
import 'package:my_app/data/services/photo_media_types.dart';
import 'package:my_app/data/services/voice_input_service.dart';
import 'package:my_app/domain/models/report_models.dart';
import 'package:my_app/main.dart';
import 'package:my_app/ui/core/report_scope.dart';
import 'package:my_app/ui/core/theme.dart';
import 'package:my_app/ui/core/widgets/before_after_slider.dart';
import 'package:my_app/ui/core/widgets/user_avatar.dart';
import 'package:my_app/ui/core/widgets/voice_waveform.dart';
import 'package:my_app/ui/features/alerts/alerts_page.dart';
import 'package:my_app/ui/features/help/help_center_page.dart';
import 'package:my_app/ui/features/map/map_page.dart';
import 'package:my_app/ui/features/news/area_news_page.dart';
import 'package:my_app/ui/features/profile/edit_profile_page.dart';
import 'package:my_app/ui/features/profile/my_reports_page.dart';
import 'package:my_app/ui/features/profile/profile_page.dart';
import 'package:my_app/ui/features/report/views/fake_gps_page.dart';
import 'package:my_app/ui/features/report/views/report_wizard_page.dart';
import 'package:my_app/ui/features/shell/main_shell.dart';
import 'package:my_app/ui/features/tracking/tracking_page.dart';

Widget _wrapWithScope(ReportRepository repo, Widget child) {
  return ReportScope(
    repository: repo,
    child: MaterialApp(theme: buildSrolanhCityTheme(), home: child),
  );
}

void main() {
  testWidgets('WelcomePage toggles language and enters MainShell', (
    tester,
  ) async {
    final repo = ReportRepository();
    await tester.pumpWidget(SrolanhCityApp(repository: repo));

    expect(find.text('ចាប់ផ្តើម'), findsOneWidget);

    await tester.tap(find.text('ខ្មែរ · EN'));
    await tester.pump();
    expect(find.text('Get started'), findsOneWidget);
    expect(repo.settings.englishFirst, isTrue);

    await tester.ensureVisible(find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Spotted a problem?'), findsOneWidget);
    expect(find.text('Tracking'), findsOneWidget);
  });

  testWidgets(
    'MainShell renders 5-slot center FAB on phone and NavigationRail on wide screens',
    (tester) async {
      final repo = ReportRepository();

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapWithScope(repo, const MainShell()));
      expect(find.byKey(const Key('center-report-fab')), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      tester.view.physicalSize = const Size(900, 720);
      await tester.pumpWidget(_wrapWithScope(repo, const MainShell()));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byKey(const Key('center-report-fab')), findsNothing);
    },
  );

  testWidgets(
    'ProfilePage hides Demo Mode and edits profile live across HomePage',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      await tester.pumpWidget(_wrapWithScope(repo, const MainShell()));

      // Navigate to Profile tab
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      // Confirm Hackathon Demo Mode section is NOT shown
      expect(find.textContaining('Hackathon Demo Mode'), findsNothing);
      expect(find.text('Staff Review Console'), findsNothing);
      expect(find.text('Preview Fake GPS Guard'), findsNothing);

      // Open EditProfilePage
      await tester.tap(find.byKey(const Key('edit-profile-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfilePage), findsOneWidget);

      // Update English name & neighborhood
      await tester.enterText(
        find.byKey(const Key('edit-english-name')),
        'Dara Sok',
      );
      await tester.enterText(
        find.byKey(const Key('edit-khmer-name')),
        'តារា សុខ',
      );
      await tester.tap(find.byKey(const Key('save-profile-btn')));
      await tester.pumpAndSettle();

      expect(repo.profile.englishName, equals('Dara Sok'));
      expect(repo.profile.initials, equals('DS'));

      // Return to Home tab and verify greeting reflects updated profile
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Hello, Dara Sok'), findsOneWidget);
    },
  );

  testWidgets('AlertsPage filters All, Active, and Done notifications', (
    tester,
  ) async {
    final repo = ReportRepository(
      initialSettings: const AppSettings(englishFirst: true),
    );
    await tester.pumpWidget(
      _wrapWithScope(repo, const Scaffold(body: AlertsPage())),
    );

    expect(find.text('Crew is on-site now'), findsOneWidget);
    expect(find.text('Resolved · See after photo'), findsOneWidget);

    await tester.tap(find.text('Done · រួចរាល់'));
    await tester.pumpAndSettle();
    expect(find.text('Resolved · See after photo'), findsOneWidget);
    expect(find.text('Crew is on-site now'), findsNothing);
  });

  testWidgets('MyReportsPage filters reports and opens exact TrackingPage', (
    tester,
  ) async {
    final repo = ReportRepository(
      initialSettings: const AppSettings(englishFirst: true),
    );
    await tester.pumpWidget(_wrapWithScope(repo, const MyReportsPage()));

    await tester.tap(find.text('Broken streetlight'));
    await tester.pumpAndSettle();

    expect(find.byType(TrackingPage), findsOneWidget);
    expect(find.text('#SC-20377'), findsOneWidget);
    await tester.drag(
      find
          .descendant(
            of: find.byType(TrackingPage),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('EDC'), findsWidgets);
  });

  testWidgets(
    'TrackingPage resolved view toggles Before/After drag slider and emoji rating',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      await tester.pumpWidget(
        _wrapWithScope(repo, const TrackingPage(reportId: '#SC-20290')),
      );

      expect(find.text('Problem solved'), findsOneWidget);
      expect(find.byType(BeforeAfterSlider), findsNothing);

      // Toggle Compare Slider mode
      await tester.tap(find.text('Compare slider'));
      await tester.pumpAndSettle();
      expect(find.byType(BeforeAfterSlider), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('emoji-rating-5')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('emoji-rating-5')));
      await tester.pumpAndSettle();

      expect(repo.findById('#SC-20290')!.citizenRating, equals(5));
    },
  );

  testWidgets(
    'ReportWizard shows honest capture prompt, explicit voice feedback & Try Sample waveform',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            initialCategory: IssueCategory.drain,
            voiceInputService: _UnavailableTestVoiceService(),
            civicAiService: _UnconfiguredTestAiService(),
          ),
        ),
      );

      expect(find.text('Step 1 of 3 · Photo'), findsOneWidget);
      // Honest Step 1 prompt — never fakes "AI: 90%" before a real photo is captured
      expect(
        find.byKey(const Key('step1-capture-prompt-pill')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('step1-ai-detected-pill')), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Report details'), findsOneWidget);
      expect(find.byKey(const Key('step2-add-photo-btn')), findsOneWidget);

      // Tapping mic when recognizer is unavailable shows explicit feedback + Try Sample
      await tester.ensureVisible(find.byKey(const Key('voice-record-btn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voice-record-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const Key('voice-feedback-box')), findsOneWidget);
      expect(find.byKey(const Key('voice-try-sample-btn')), findsOneWidget);

      // Tap Try Sample -> renders VoiceWaveform & Demo pill, then stop cleanly
      await tester.ensureVisible(find.byKey(const Key('voice-try-sample-btn')));
      await tester.tap(find.byKey(const Key('voice-try-sample-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(VoiceWaveform), findsOneWidget);
      expect(find.byKey(const Key('voice-mode-pill')), findsOneWidget);

      await tester.tap(find.byKey(const Key('voice-record-btn')));
      await tester.pump();
      expect(find.byType(VoiceWaveform), findsNothing);
    },
  );

  testWidgets('FakeGpsPage renders mock-GPS warning & buttons', (tester) async {
    final repo = ReportRepository(
      initialSettings: const AppSettings(englishFirst: true),
    );
    var retried = false;
    await tester.pumpWidget(
      _wrapWithScope(
        repo,
        FakeGpsPage(
          detectedAppLabel: 'Fake GPS Pro',
          onOpenSettings: () {},
          onTryAgain: () => retried = true,
        ),
      ),
    );

    expect(find.text('Fake location detected'), findsOneWidget);
    await tester.tap(find.textContaining('Try again'));
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets(
    'TrackingPage shows live 15-min countdown, Quick Edit, and removes user report cleanly',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      final submitted = repo.submitReport(
        category: IssueCategory.trash,
        description: 'Initial roadside trash pile',
        severity: 3,
        coordinates: const LatLng(11.5450, 104.9050),
        isAnonymous: false,
      );
      final id = submitted.report.id;

      await tester.pumpWidget(_wrapWithScope(repo, TrackingPage(reportId: id)));

      expect(find.byKey(const Key('withdrawal-grace-card')), findsOneWidget);
      expect(find.textContaining('Editable & removable for'), findsOneWidget);

      // Quick edit description
      await tester.tap(find.byKey(const Key('quick-edit-report-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick-edit-description')),
        'Updated huge trash pile near school',
      );
      await tester.tap(find.byKey(const Key('save-quick-edit-btn')));
      await tester.pumpAndSettle();
      expect(repo.findById(id)!.description, contains('near school'));

      // Withdraw report with confirmation dialog
      await tester.tap(find.byKey(const Key('withdraw-report-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-withdraw-report-btn')));
      await tester.pumpAndSettle();

      expect(repo.findById(id), isNull);
      expect(repo.alerts.where((a) => a.reportId == id), isEmpty);
    },
  );

  testWidgets(
    'AlertsPage renders real relative time ages instead of frozen Just now',
    (tester) async {
      final now = DateTime.now();
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
        initialAlerts: [
          AlertItem(
            id: 'a-old',
            reportId: '#SC-20481',
            khmerTitle: 'បានទទួល',
            englishTitle: 'Status updated',
            khmerSubtitle: 'MPWT',
            englishSubtitle: 'MPWT',
            createdAt: now.subtract(const Duration(minutes: 12)),
          ),
        ],
      );

      await tester.pumpWidget(
        _wrapWithScope(repo, const Scaffold(body: AlertsPage())),
      );

      expect(find.textContaining('12m ago'), findsOneWidget);
      expect(find.textContaining('Just now'), findsNothing);
    },
  );

  testWidgets(
    'HomePage My Reports | News switcher and AreaNewsPage switch Sangkat/Khan cleanly',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapWithScope(repo, const MainShell()));
      await tester.pumpAndSettle();

      // Switch to News preview on HomePage — Guest defaults to All Districts · Phnom Penh
      await tester.ensureVisible(find.byKey(const Key('home-tab-area-news')));
      await tester.tap(find.byKey(const Key('home-tab-area-news')));
      await tester.pumpAndSettle();
      expect(find.text('All Districts · Phnom Penh'), findsOneWidget);

      // Open full AreaNewsPage (Guest defaults to All Districts · Phnom Penh)
      await tester.ensureVisible(find.byKey(const Key('open-area-news-btn')));
      await tester.tap(find.byKey(const Key('open-area-news-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(AreaNewsPage), findsOneWidget);
      expect(find.textContaining('All Districts · Phnom Penh'), findsWidgets);
      expect(find.text('Illegal Waste Dumping'), findsWidgets);

      // Switch Khan & Sangkat to Toul Kork -> Boeung Kak 1 (shows Clogged drain)
      await tester.tap(find.byKey(const Key('news-area-picker-btn')));
      await tester.pumpAndSettle();
      final toulKorkChip = find.textContaining('Toul Kork').last;
      await tester.ensureVisible(toulKorkChip);
      await tester.pumpAndSettle();
      await tester.tap(toulKorkChip);
      await tester.pumpAndSettle();
      final boeungKakChip = find.text('Boeung Kak 1').last;
      await tester.ensureVisible(boeungKakChip);
      await tester.pumpAndSettle();
      await tester.tap(boeungKakChip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-news-area-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Clogged drain'), findsOneWidget);
      expect(repo.settings.newsKhanEnglish, equals('Toul Kork'));
      expect(repo.settings.newsSangkatEnglish, equals('Boeung Kak 1'));

      // Switch to All districts view & sort by Priority Score
      await tester.tap(find.byKey(const Key('news-show-all-districts-btn')));
      await tester.pumpAndSettle();
      expect(find.text('All Districts · Phnom Penh'), findsOneWidget);
      expect(
        repo.settings.newsKhanEnglish,
        equals(AppSettings.allPhnomPenhKey),
      );

      await tester.tap(find.byKey(const Key('news-sort-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('news-sort-highestPriority')));
      await tester.pumpAndSettle();
      expect(find.text('Critical Road Crater'), findsOneWidget);
      expect(find.text('5.0'), findsOneWidget);
    },
  );

  testWidgets(
    'TrackingPage renders P5->P1 Priority Threshold Table without raw calculation equation',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      await tester.pumpWidget(
        _wrapWithScope(repo, const TrackingPage(reportId: '#SC-20481')),
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('priority-threshold-table')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('priority-breakdown-card')), findsOneWidget);
      expect(find.byKey(const Key('priority-threshold-table')), findsOneWidget);
      expect(find.byKey(const Key('priority-tier-active-p4')), findsOneWidget);
      expect(find.textContaining('How priority is scored'), findsOneWidget);
      expect(find.textContaining('Major Artery'), findsOneWidget);
      expect(find.text('4.5 – 5.0'), findsOneWidget);
      expect(find.text('3.5 – 4.4'), findsOneWidget);
      expect(find.text('1.0 – 1.4'), findsOneWidget);
      expect(find.textContaining('Total: 2.0'), findsNothing);
    },
  );

  testWidgets(
    'MainShell shows OfflineSyncBanner and Queued badge when offline, then clears on reconnect',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      await tester.pumpWidget(_wrapWithScope(repo, const MainShell()));
      await tester.pumpAndSettle();

      // Hidden while online with 0 queued reports
      expect(find.byKey(const Key('offline-sync-banner')), findsNothing);

      // Go offline & submit a report
      repo.setOnlineStatus(false);
      repo.submitReport(
        category: IssueCategory.trash,
        description: 'Offline roadside trash',
        severity: 4,
        coordinates: const LatLng(11.5390, 104.9020),
        isAnonymous: false,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('offline-sync-banner')), findsOneWidget);
      expect(find.textContaining('1 report(s) queued'), findsOneWidget);
      expect(find.byKey(const Key('sync-status-badge')), findsWidgets);

      // Reconnect -> auto-sync clears banner & badge
      repo.setOnlineStatus(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline-sync-banner')), findsNothing);
      expect(find.byKey(const Key('sync-status-badge')), findsNothing);
    },
  );

  testWidgets(
    'MapPage enforces Cambodia bounds and zoom limits, and Profile stays free of developer AI key settings',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      // Verify MapPage configures Cambodia bounds & zoom limits
      await tester.pumpWidget(_wrapWithScope(repo, const MapPage()));
      await tester.pump();
      final mapWidget = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(mapWidget.options.minZoom, equals(LocationService.minMapZoom));
      expect(mapWidget.options.maxZoom, equals(LocationService.maxMapZoom));
      expect(
        mapWidget.options.cameraConstraint,
        equals(
          CameraConstraint.contain(bounds: LocationService.cambodiaMapBounds),
        ),
      );

      // Verify ProfilePage keeps a clean citizen UI with zero API-key/developer settings
      await tester.pumpWidget(_wrapWithScope(repo, const MainShell()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gemini'), findsNothing);
      expect(find.textContaining('API Key'), findsNothing);
      expect(find.byKey(const Key('profile-ai-engine-tile')), findsNothing);
    },
  );

  testWidgets(
    'TrackingPage enforces distance-aware "Affects me" (allows nearby, blocks >15 km, re-enables on Undo)',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      // #SC-20524 is in Sen Sok (outside default Daun Penh Home Khan)
      final target = repo.findById('#SC-20524')!;
      final beforeCount = target.affectedCitizens;

      // 1. User 230 km away (Siem Reap) & outside Home Khan -> blocked cleanly
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          TrackingPage(
            reportId: '#SC-20524',
            locationService: _FakeLocationService(
              const LocationSuccess(
                point: LatLng(13.3633, 103.8564),
                accuracyMeters: 20,
                isOutsideCambodia: false,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('tracking-support-btn')));
      await tester.pumpAndSettle();

      expect(repo.findById('#SC-20524')!.affectedCitizens, equals(beforeCount));
      expect(find.textContaining('too far'), findsOneWidget);

      // Dismiss the SnackBar before mounting the nearby location scenario
      ScaffoldMessenger.of(tester.element(find.byType(TrackingPage)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // 2. User ~110 m away -> Verified nearby, increments count, Undo re-enables
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          TrackingPage(
            reportId: '#SC-20524',
            locationService: _FakeLocationService(
              LocationSuccess(
                point: LatLng(
                  target.coordinates.latitude + 0.001,
                  target.coordinates.longitude,
                ),
                accuracyMeters: 8,
                isOutsideCambodia: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracking-support-btn')));
      await tester.pumpAndSettle();

      expect(
        repo.findById('#SC-20524')!.affectedCitizens,
        equals(beforeCount + 1),
      );
      expect(find.byKey(const Key('support-tier-badge')), findsOneWidget);
      expect(find.textContaining('Verified nearby'), findsWidgets);

      // Tap Undo -> refunds count and re-enables "Affects me too" button
      await tester.ensureVisible(find.byKey(const Key('undo-support-btn')));
      await tester.tap(find.byKey(const Key('undo-support-btn')));
      await tester.pumpAndSettle();
      expect(repo.findById('#SC-20524')!.affectedCitizens, equals(beforeCount));
      expect(find.text('Affects me too'), findsOneWidget);
    },
  );

  testWidgets(
    'MapPage bottom sheet shows inline distance feedback and disables to Supported after verification',
    (tester) async {
      final seedRepo = ReportRepository();
      final senSokReport = seedRepo.findById('#SC-20524')!;
      final beforeCount = senSokReport.affectedCitizens;

      // 1. Blocked > 15 km -> visible inline banner inside sheet, button stays enabled
      final blockedRepo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
        initialReports: [senSokReport],
      );
      await tester.pumpWidget(
        _wrapWithScope(
          blockedRepo,
          MapPage(
            locationService: const _FakeLocationService(
              LocationSuccess(
                point: LatLng(13.3633, 103.8564),
                accuracyMeters: 20,
                isOutsideCambodia: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('#SC-20524'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('map-support-btn')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('map-support-feedback-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('too far'), findsOneWidget);
      expect(
        blockedRepo.findById('#SC-20524')!.affectedCitizens,
        equals(beforeCount),
      );

      // Dismiss bottom sheet before pumping the Phnom Penh scenario
      Navigator.of(tester.element(find.byKey(const Key('map-support-btn'))))
          .pop();
      await tester.pumpAndSettle();

      // 2. Allowed ~5.3 km (City commuter) -> increments count, disables to Supported
      final allowedRepo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
        initialReports: [senSokReport],
      );
      await tester.pumpWidget(
        _wrapWithScope(
          allowedRepo,
          MapPage(
            locationService: const _FakeLocationService(
              LocationSuccess(
                point: LocationService.phnomPenhCenter,
                accuracyMeters: 15,
                isOutsideCambodia: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('#SC-20524'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('map-support-btn')));
      await tester.pumpAndSettle();

      expect(
        allowedRepo.findById('#SC-20524')!.affectedCitizens,
        equals(beforeCount + 1),
      );
      expect(
        find.byKey(const Key('map-support-feedback-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('City commuter'), findsOneWidget);
      expect(find.text('Supported'), findsOneWidget);
      final supportBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('map-support-btn')),
      );
      expect(supportBtn.onPressed, isNull);
    },
  );

  testWidgets(
    'MapPage province quick-jump shows All Cambodia province bubbles and flies into Siem Reap',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      await tester.pumpWidget(_wrapWithScope(repo, const MapPage()));
      await tester.pump();

      // Open 25-Province Quick-Jump Sheet -> jump to All Cambodia overview
      await tester.tap(find.byKey(const Key('map-province-filter-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('map-jump-all-cambodia')), findsOneWidget);
      await tester.tap(find.byKey(const Key('map-jump-all-cambodia')));
      await tester.pumpAndSettle();

      // Province cluster bubbles appear across Cambodia and bottom carousel hides cleanly
      expect(
        find.byKey(const Key('province-cluster-phnom_penh')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('province-cluster-siem_reap')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('map-nearby-carousel')), findsNothing);

      // Jump directly to Siem Reap -> carousel reappears showing Siem Reap report (#SC-20531)
      await tester.tap(find.byKey(const Key('map-province-filter-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('map-jump-province-siem_reap')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('map-nearby-carousel')), findsOneWidget);
      expect(find.text('Siem Reap'), findsWidgets);
      expect(find.text('#SC-20531'), findsOneWidget);
    },
  );

  testWidgets(
    'AreaNewsPage switches to Siem Reap & All Cambodia, and EditProfilePage saves provincial Home Province',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      await tester.pumpWidget(_wrapWithScope(repo, const AreaNewsPage()));
      await tester.pumpAndSettle();

      // Open 3-level picker -> select Siem Reap
      await tester.tap(find.byKey(const Key('news-area-picker-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('picker-province-siem_reap')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-news-area-btn')));
      await tester.pumpAndSettle();

      expect(find.text('All Districts · Siem Reap'), findsOneWidget);
      expect(find.text('Deep Pothole on Sivutha Blvd'), findsOneWidget);
      expect(repo.settings.newsProvinceCode, equals('siem_reap'));

      // Switch to All Cambodia (25 provinces)
      await tester.tap(find.byKey(const Key('news-area-picker-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('picker-all-cambodia-btn')));
      await tester.pumpAndSettle();
      expect(find.text('All Cambodia · 25 Provinces'), findsOneWidget);
      expect(
        repo.settings.newsProvinceCode,
        equals(AppSettings.allCambodiaKey),
      );

      // EditProfilePage selects Siem Reap as Home Province & persists it
      await tester.pumpWidget(_wrapWithScope(repo, const EditProfilePage()));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -360));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-province-picker-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-province-option-siem_reap')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-profile-btn')));
      await tester.pumpAndSettle();

      expect(repo.profile.homeProvinceCode, equals('siem_reap'));
      expect(repo.profile.englishHomeArea, contains('Siem Reap'));
    },
  );

  testWidgets(
    'TrackingPage displays citizen description or "No comment" when empty',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      final withNote = repo.submitReport(
        category: IssueCategory.pothole,
        description: 'Huge sinkhole right outside school gate',
        severity: 4,
        coordinates: const LatLng(11.5315, 104.9085),
        isAnonymous: false,
      );
      final withoutNote = repo.submitReport(
        category: IssueCategory.drain,
        description: '',
        severity: 3,
        coordinates: const LatLng(11.5335, 104.9085),
        isAnonymous: false,
      );

      await tester.pumpWidget(
        _wrapWithScope(repo, TrackingPage(reportId: withNote.report.id)),
      );
      expect(find.byKey(const Key('report-description-card')), findsOneWidget);
      expect(
        find.text('Huge sinkhole right outside school gate'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _wrapWithScope(repo, TrackingPage(reportId: withoutNote.report.id)),
      );
      expect(find.byKey(const Key('report-description-card')), findsOneWidget);
      expect(find.text('No comment'), findsOneWidget);
    },
  );

  testWidgets(
    'ProfilePage defaults to Guest with empty info and allows saving without phone',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      await tester.pumpWidget(_wrapWithScope(repo, const MainShell()));

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Guest'), findsOneWidget);
      expect(find.byKey(const Key('profile-empty-area-hint')), findsOneWidget);
      expect(find.textContaining('Sovannarith'), findsNothing);
      expect(find.textContaining('+855'), findsNothing);

      // EditProfilePage saves cleanly without forcing phone or home area
      await tester.tap(find.byKey(const Key('edit-profile-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-profile-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfilePage), findsNothing);
      expect(repo.profile.englishName, equals('Guest'));
      expect(repo.profile.phoneNumber, isEmpty);
    },
  );

  testWidgets(
    'MapPage bottom carousel scrolls cleanly past 3+ cards without snapping back',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapWithScope(repo, const MapPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final carouselFinder = find.byKey(const Key('map-nearby-carousel'));
      expect(carouselFinder, findsOneWidget);

      // Swipe left 3 times (0 -> 1 -> 2 -> 3)
      for (var step = 0; step < 3; step++) {
        await tester.drag(carouselFinder, const Offset(-320, 0));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 250));
      }

      final pageView = tester.widget<PageView>(carouselFinder);
      expect(pageView.controller?.page?.round(), greaterThanOrEqualTo(3));
    },
  );

  testWidgets(
    'ReportWizard shows "View your existing report" for seeded My Reports and lets user submit a different problem',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      final seededMine = repo.findById('#SC-20481')!;
      final beforeCount = repo.reports.length;

      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            initialCategory: seededMine.category,
            initialCoordinates: seededMine.coordinates,
            voiceInputService: _UnavailableTestVoiceService(),
            civicAiService: _UnconfiguredTestAiService(),
          ),
        ),
      );

      // Step 1 -> Step 2 -> Step 3
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.textContaining('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Seeded #SC-20481 is in "My Reports" -> shows "already reported" instead of "Join"
      expect(find.textContaining('already reported'), findsOneWidget);
      expect(find.textContaining('View your existing report'), findsOneWidget);
      expect(find.textContaining('Join this report'), findsNothing);

      // Tap "It's a different problem" -> opens sheet defaulting to Other Issue
      final diffBtn = find.byKey(const Key('different-problem-btn'));
      await tester.ensureVisible(diffBtn);
      await tester.tap(diffBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const Key('different-problem-sheet')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('different-problem-title-field')),
        'Fallen tree across road',
      );
      await tester.enterText(
        find.byKey(const Key('different-problem-desc-field')),
        'Large tree branch fell after heavy wind',
      );
      await tester.tap(find.byKey(const Key('submit-different-problem-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(repo.reports.length, equals(beforeCount + 1));
      final created = repo.reports.first;
      expect(created.category, equals(IssueCategory.other));
      expect(created.englishTitle, equals('Fallen tree across road'));
      expect(
        created.description,
        equals('Large tree branch fell after heavy wind'),
      );
    },
  );

  testWidgets(
    'TrackingPage renders multi-citizen comments, silent supporter reconciliation, expand toggle, and Add/Delete note',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      await tester.pumpWidget(
        _wrapWithScope(repo, const TrackingPage(reportId: '#SC-20481')),
      );

      // Shows 3 seeded comments collapsed to 2 + toggle + 8 silent supporters footer
      expect(find.byKey(const Key('citizen-comments-list')), findsOneWidget);
      expect(find.textContaining('(3)'), findsOneWidget);
      expect(find.textContaining('Original reporter'), findsOneWidget);
      expect(find.textContaining('Citizen #2'), findsOneWidget);
      expect(find.byKey(const Key('toggle-all-comments-btn')), findsOneWidget);
      expect(find.byKey(const Key('silent-supporters-footer')), findsOneWidget);
      expect(
        find.textContaining('8 other citizen(s) confirmed without commenting'),
        findsOneWidget,
      );

      // Expand to see 3rd anonymous citizen comment
      await tester.ensureVisible(
        find.byKey(const Key('toggle-all-comments-btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle-all-comments-btn')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Anonymous citizen #3'),
        150,
      );
      expect(find.textContaining('Anonymous citizen #3'), findsOneWidget);

      // Tap "+ Add note" -> opens _AddCommentSheet -> post a new note -> displays immediately
      await tester.ensureVisible(find.byKey(const Key('add-comment-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-comment-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-comment-sheet')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('add-comment-field')),
        'Fresh cone placed next to pothole today',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-comment-btn')));
      await tester.pumpAndSettle();

      expect(
        find.text('Fresh cone placed next to pothole today'),
        findsOneWidget,
      );
      expect(find.textContaining('(4)'), findsOneWidget);

      // Clear snackbar & scroll into center before deleting the user-added note
      ScaffoldMessenger.of(tester.element(find.byType(TrackingPage)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      final addedId = repo.findById('#SC-20481')!.effectiveComments.last.id;
      final deleteBtn = find.byKey(Key('delete-comment-$addedId'));
      await tester.scrollUntilVisible(
        deleteBtn,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Verify delete button sits flush near right edge & vertically aligned with author label
      final cardRect = tester.getRect(
        find.byKey(const Key('report-description-card')),
      );
      final deleteRect = tester.getRect(deleteBtn);
      expect(cardRect.right - deleteRect.right, lessThanOrEqualTo(32.0));

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('Fresh cone placed next to pothole today'),
        findsNothing,
      );
      expect(find.textContaining('(3)'), findsOneWidget);
    },
  );

  testWidgets(
    'MapPage bottom sheet shows "+N more comment(s)" pill on multi-comment Master Incidents',
    (tester) async {
      final seedRepo = ReportRepository();
      final multiCommentReport = seedRepo.findById('#SC-20519')!;
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
        initialReports: [multiCommentReport],
      );

      await tester.pumpWidget(_wrapWithScope(repo, const MapPage()));
      await tester.pump();
      await tester.tap(find.text('#SC-20519'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('map-sheet-more-comments-pill')),
        findsOneWidget,
      );
      expect(find.textContaining('+2 more'), findsOneWidget);
    },
  );

  testWidgets(
    'Joining a neighbor Master Incident via ReportWizard preserves joined comment on ReportSubmittedPage & TrackingPage',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      final neighbor = repo.findById('#SC-20519')!;

      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            initialCategory: neighbor.category,
            initialCoordinates: neighbor.coordinates,
            voiceInputService: _UnavailableTestVoiceService(),
            civicAiService: _UnconfiguredTestAiService(),
          ),
        ),
      );

      // Step 1 -> Step 2: enter a citizen description
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final descField = find.byType(TextField).first;
      await tester.enterText(
        descField,
        'Dangerous puddle hiding the crater during rush hour',
      );
      await tester.pump();

      // Step 2 -> Step 3 -> Join this report
      await tester.tap(find.textContaining('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.textContaining('Join this report'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // ReportSubmittedPage shows user's joined description + combined count (4)
      expect(
        find.byKey(const Key('submitted-description-row')),
        findsOneWidget,
      );
      expect(
        find.text('Dangerous puddle hiding the crater during rush hour'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Combined 4 citizen report notes'),
        findsOneWidget,
      );

      // Tap Track my report -> expands & verifies user's joined comment on TrackingPage
      await tester.tap(find.textContaining('Track my report'));
      await tester.pumpAndSettle();
      final toggleCommentsBtn = find.byKey(
        const Key('toggle-all-comments-btn'),
      );
      await tester.ensureVisible(toggleCommentsBtn);
      await tester.pumpAndSettle();
      await tester.tap(toggleCommentsBtn);
      await tester.pumpAndSettle();
      expect(
        find.text('Dangerous puddle hiding the crater during rush hour'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'UserAvatar renders persistent base64 data URI avatar via Image.memory',
    (tester) async {
      // Valid 1x1 transparent PNG data URI
      const pngDataUri =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      const profile = UserProfile(avatarPhotoPath: pngDataUri);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildSrolanhCityTheme(),
          home: const Scaffold(
            body: Center(child: UserAvatar(profile: profile)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('G'), findsNothing);
    },
  );

  testWidgets(
    'ReportWizard Step 2 shows clear Khmer | EN segmented voice selector and updates active language label',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            initialCategory: IssueCategory.pothole,
            voiceInputService: _UnavailableTestVoiceService(),
            civicAiService: _UnconfiguredTestAiService(),
          ),
        ),
      );

      // Step 1 -> Step 2
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const Key('voice-lang-toggle')), findsOneWidget);
      expect(find.byKey(const Key('voice-lang-km')), findsOneWidget);
      expect(find.byKey(const Key('voice-lang-en')), findsOneWidget);
      expect(find.text('Voice: English (EN)'), findsOneWidget);

      // Switch voice recognition language to Khmer
      await tester.ensureVisible(find.byKey(const Key('voice-lang-km')));
      await tester.tap(find.byKey(const Key('voice-lang-km')));
      await tester.pump();
      expect(find.text('Voice: Khmer (ខ្មែរ)'), findsOneWidget);

      // Switch back to English
      await tester.tap(find.byKey(const Key('voice-lang-en')));
      await tester.pump();
      expect(find.text('Voice: English (EN)'), findsOneWidget);
    },
  );

  testWidgets(
    'Affects me blocks impossible-travel GPS jump (Phnom Penh -> Siem Reap in 2 min) by opening FakeGpsPage',
    (tester) async {
      final now = DateTime.now();
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      repo.recordVerifiedGpsCheckpoint(
        const LatLng(11.5564, 104.9282),
        timestamp: now.subtract(const Duration(minutes: 2)),
      );
      final siemReapReport = repo.reports.firstWhere(
        (r) =>
            r.englishProvince.toLowerCase().contains('siem reap') &&
            !r.isContributedByCurrentUser,
      );

      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          TrackingPage(
            reportId: siemReapReport.id,
            locationService: _FakeLocationService(
              LocationSuccess(
                point: siemReapReport.coordinates,
                accuracyMeters: 12,
                isOutsideCambodia: false,
                timestamp: now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tracking-support-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(FakeGpsPage), findsOneWidget);
      expect(find.byKey(const Key('fake-gps-detail-text')), findsOneWidget);
      expect(find.textContaining('Impossible travel'), findsOneWidget);
    },
  );

  testWidgets(
    'ReportWizard Step 3 displays Photo GPS verified pill when EXIF matches and warning banner with Use photo location when EXIF is far away',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      // Case 1: Matching Phnom Penh EXIF (non-duplicate spot) -> green verified pill
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            initialCoordinates: const LatLng(11.5318, 104.9044),
            initialPhotoExif: PhotoExifMetadata(
              coordinates: const LatLng(11.5319, 104.9045),
              capturedAt: DateTime.now().subtract(const Duration(minutes: 5)),
            ),
            voiceInputService: _UnavailableTestVoiceService(),
            civicAiService: _UnconfiguredTestAiService(),
            ipGeolocationService: const _TestIpGeoService(null),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('step3-exif-verified-pill')), findsOneWidget);
      expect(
        find.byKey(const Key('step3-integrity-warning-banner')),
        findsNothing,
      );

      // Case 2: EXIF in Siem Reap while pinned in Phnom Penh -> saffron warning + 1-tap button
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            key: const ValueKey('wizard-mismatch'),
            initialCoordinates: const LatLng(11.5318, 104.9044),
            initialPhotoExif: PhotoExifMetadata(
              coordinates: const LatLng(13.3633, 103.8564),
              capturedAt: DateTime.now().subtract(const Duration(minutes: 10)),
            ),
            voiceInputService: _UnavailableTestVoiceService(),
            civicAiService: _UnconfiguredTestAiService(),
            ipGeolocationService: const _TestIpGeoService(null),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('step3-integrity-warning-banner')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('step3-use-photo-gps-btn')), findsOneWidget);
    },
  );

  testWidgets(
    'ReportWizard offline records local voice memo on Step 2 and displays Voice Memo card on TrackingPage',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      repo.setOnlineStatus(false);

      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            initialCategory: IssueCategory.pothole,
            initialCoordinates: const LatLng(11.5318, 104.9044),
            voiceInputService: _UnavailableTestVoiceService(),
            audioRecorderService: _WidgetFakeAudioRecorderService(),
            audioPlayerService: _WidgetFakeAudioPlayerService(),
            civicAiService: _UnconfiguredTestAiService(),
            ipGeolocationService: const _TestIpGeoService(null),
          ),
        ),
      );

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('voice-offline-badge')), findsOneWidget);

      // Scroll voice record button into view, tap to start & tap again to stop
      final recordBtn = find.byKey(const Key('voice-record-btn'));
      await tester.ensureVisible(recordBtn);
      await tester.pump();
      await tester.tap(recordBtn);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(recordBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('step2-voice-memo-player')), findsOneWidget);

      // Advance to Step 3 & submit offline report
      await tester.tap(find.textContaining('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Submit report'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final created = repo.reports.first;
      expect(created.syncStatus, equals(SyncStatus.pendingSync));
      expect(created.voiceAudioPath, equals('data:audio/webm;base64,AAAA'));

      // Verify TrackingPage renders Voice Memo card cleanly in a fresh MaterialApp
      await tester.pumpWidget(
        ReportScope(
          key: const ValueKey('tracking-memo-scope'),
          repository: repo,
          child: MaterialApp(
            theme: buildSrolanhCityTheme(),
            home: TrackingPage(
              reportId: created.id,
              audioPlayerService: _WidgetFakeAudioPlayerService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('tracking-voice-memo-card')),
        250,
        scrollable: find
            .descendant(
              of: find.byType(TrackingPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const Key('tracking-voice-memo-card')), findsOneWidget);
    },
  );

  testWidgets(
    'TrackingPage inline comment translation translates English comment to Khmer and shows offline notice when disconnected',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      final fakeTranslator = _WidgetFakeTranslator();

      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          TrackingPage(
            reportId: '#SC-20519',
            translationService: fakeTranslator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final translateBtn = find.byKey(const Key('translate-comment-c-20519-2'));
      expect(translateBtn, findsOneWidget);

      await tester.ensureVisible(translateBtn);
      await tester.tap(translateBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('translated-comment-c-20519-2')),
        findsOneWidget,
      );
      expect(find.text('ការបកប្រែជាភាសាខ្មែរ'), findsOneWidget);

      // Toggle hide translation
      await tester.tap(translateBtn);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('translated-comment-c-20519-2')),
        findsNothing,
      );

      // Go offline -> translating another comment shows clean offline notice
      repo.setOnlineStatus(false);
      await tester.pumpAndSettle();
      final origTranslateBtn = find.byKey(
        const Key('translate-comment-c-20519-1'),
      );
      await tester.ensureVisible(origTranslateBtn);
      await tester.pumpAndSettle();
      await tester.tap(origTranslateBtn);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('translate-error-c-20519-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'EditProfilePage updates avatar immediately on valid pick and shows helpful SnackBar on unsupported HEIC photo',
    (tester) async {
      const pngDataUri =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      // 1. Valid photo selection updates avatar immediately
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          EditProfilePage(
            onPickAvatarPhoto: (_) async =>
                const PersistedPhotoResult(path: pngDataUri),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-change-photo-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avatar-choose-photo-option')));
      await tester.pumpAndSettle();

      expect(repo.profile.avatarPhotoPath, equals(pngDataUri));
      expect(find.text('Profile photo updated!'), findsOneWidget);

      // Clear previous SnackBar before verifying HEIC warning SnackBar
      ScaffoldMessenger.of(tester.element(find.byType(EditProfilePage)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // 2. Unsupported format (e.g. HEIC) shows clear error SnackBar without clearing avatar
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          EditProfilePage(
            key: const ValueKey('edit-profile-heic'),
            onPickAvatarPhoto: (_) async =>
                const PersistedPhotoResult(path: '', unsupportedFormat: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-change-photo-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avatar-choose-photo-option')));
      await tester.pumpAndSettle();

      expect(find.textContaining('HEIC'), findsOneWidget);
    },
  );

  testWidgets(
    'ProfilePage opens HelpCenterPage with hotlines, FAQ accordion, and interactive AI assistant ticket lookup',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      await tester.pumpWidget(
        _wrapWithScope(repo, const Scaffold(body: ProfilePage())),
      );
      await tester.pumpAndSettle();

      final helpTile = find.byKey(const Key('open-help-center-tile'));
      await tester.scrollUntilVisible(helpTile, 250);
      await tester.ensureVisible(helpTile);
      await tester.pumpAndSettle();
      await tester.tap(helpTile);
      await tester.pumpAndSettle();

      expect(find.byType(HelpCenterPage), findsOneWidget);
      expect(find.byKey(const Key('help-hotlines-strip')), findsOneWidget);
      expect(find.text('1190'), findsOneWidget);
      expect(find.text('1298'), findsOneWidget);
      expect(find.byKey(const Key('help-ai-chat')), findsOneWidget);

      // Ask about ticket #SC-20481 -> assistant performs live ticket lookup
      await tester.enterText(
        find.byKey(const Key('help-chat-input')),
        '#SC-20481',
      );
      await tester.tap(find.byKey(const Key('help-chat-send-btn')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Open #SC-20481'), findsOneWidget);

      // Scroll down to verify FAQ accordion renders
      await tester.scrollUntilVisible(
        find.byKey(const Key('help-faq-section')),
        250,
        scrollable: find
            .descendant(
              of: find.byType(HelpCenterPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const Key('help-faq-section')), findsOneWidget);
    },
  );

  group('Accessibility (WCAG 2.1 AA) guidelines', () {
    testWidgets(
      'HelpCenterPage passes tap target, labeled target, and contrast guidelines',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        await tester.pumpWidget(_wrapWithScope(repo, const HelpCenterPage()));
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      },
    );

    testWidgets(
      'FakeGpsPage honors reduced motion and passes tap target & contrast guidelines',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: _wrapWithScope(
              repo,
              FakeGpsPage(
                detectedAppLabel: 'Mock GPS Provider',
                onOpenSettings: () async => true,
                onTryAgain: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      },
    );

    testWidgets(
      'EditProfilePage and TrackingPage pass labeled tap target and contrast guidelines',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );

        await tester.pumpWidget(_wrapWithScope(repo, const EditProfilePage()));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.pumpWidget(
          _wrapWithScope(repo, const TrackingPage(reportId: '#SC-20481')),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        handle.dispose();
      },
    );

    testWidgets(
      'Floating AI Assistant bubble and open chat panel pass tap target, labeled target, and contrast guidelines',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(
            englishFirst: true,
            assistantHintSeen: true,
          ),
        );
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(SrolanhCityApp(repository: repo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

        // Open chat panel and verify tap targets, labels, and contrast
        await tester.tap(find.byKey(const Key('assistant-bubble')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assistant-chat-panel')), findsOneWidget);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        handle.dispose();
      },
    );
  });

  group('Floating AI Assistant Bubble (app-wide)', () {
    testWidgets(
      'Bubble hides on WelcomePage, shows on MainShell, opens panel, looks up #SC-20481, and navigates to TrackingPage',
      (tester) async {
        final repo = ReportRepository(
          initialSettings: const AppSettings(
            englishFirst: true,
            assistantHintSeen: true,
          ),
        );
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(SrolanhCityApp(repository: repo));
        await tester.pumpAndSettle();

        // Suppressed on WelcomePage
        expect(find.byKey(const Key('assistant-bubble')), findsNothing);

        // Enter MainShell -> bubble appears
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);

        // Tap bubble -> opens chat panel and hides bubble while popup is active
        await tester.tap(find.byKey(const Key('assistant-bubble')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assistant-chat-panel')), findsOneWidget);
        expect(find.byKey(const Key('assistant-bubble')), findsNothing);

        // Ask about #SC-20481 -> tap Open #SC-20481 -> navigates to TrackingPage
        await tester.enterText(
          find.byKey(const Key('assistant-panel-input')),
          '#SC-20481',
        );
        await tester.tap(find.byKey(const Key('assistant-panel-send-btn')));
        await tester.pumpAndSettle();
        expect(find.text('Open #SC-20481'), findsOneWidget);

        await tester.tap(find.text('Open #SC-20481'));
        await tester.pumpAndSettle();

        expect(find.byType(TrackingPage), findsOneWidget);
        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);
      },
    );

    testWidgets(
      'Long-press hides bubble with Undo SnackBar and Profile toggle unhides it',
      (tester) async {
        final repo = ReportRepository(
          initialSettings: const AppSettings(
            englishFirst: true,
            assistantHintSeen: true,
          ),
        );
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(SrolanhCityApp(repository: repo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();

        // Long-press bubble -> hides & shows Undo SnackBar
        await tester.longPress(find.byKey(const Key('assistant-bubble')));
        await tester.pumpAndSettle();
        expect(repo.settings.assistantBubbleEnabled, isFalse);
        expect(find.byKey(const Key('assistant-bubble')), findsNothing);
        expect(
          find.byKey(const Key('assistant-bubble-hidden-snackbar')),
          findsOneWidget,
        );

        // Tap Undo -> bubble comes back immediately
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(repo.settings.assistantBubbleEnabled, isTrue);
        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);

        // Hide again via long-press, dismiss SnackBar, then re-enable via Profile switch
        await tester.longPress(find.byKey(const Key('assistant-bubble')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assistant-bubble')), findsNothing);
        ScaffoldMessenger.of(tester.element(find.byType(MainShell)))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();
        final toggle = find.byKey(const Key('assistant-bubble-toggle'));
        await tester.scrollUntilVisible(
          toggle,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ProfilePage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(repo.settings.assistantBubbleEnabled, isTrue);
        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);
      },
    );

    testWidgets(
      'Auto-hides on ReportWizardPage, HelpCenterPage, and open dialogs, then reappears cleanly',
      (tester) async {
        final repo = ReportRepository(
          initialSettings: const AppSettings(
            englishFirst: true,
            assistantHintSeen: true,
          ),
        );
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(SrolanhCityApp(repository: repo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);

        // 1. ReportWizardPage suppresses bubble; popping restores it
        await tester.tap(find.byKey(const Key('center-report-fab')));
        await tester.pumpAndSettle();
        expect(find.byType(ReportWizardPage), findsOneWidget);
        expect(find.byKey(const Key('assistant-bubble')), findsNothing);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);

        // 2. Open Privacy dialog on Profile -> bubble hides while dialog is open
        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();
        final privacyTile = find.text('Privacy & Security');
        await tester.scrollUntilVisible(
          privacyTile,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ProfilePage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(privacyTile);
        await tester.pumpAndSettle();
        await tester.tap(privacyTile);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byKey(const Key('assistant-bubble')), findsNothing);

        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);

        // 3. HelpCenterPage suppresses bubble; popping restores it
        final helpTile = find.byKey(const Key('open-help-center-tile'));
        await tester.scrollUntilVisible(
          helpTile,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ProfilePage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(helpTile);
        await tester.pumpAndSettle();
        await tester.tap(helpTile);
        await tester.pumpAndSettle();
        expect(find.byType(HelpCenterPage), findsOneWidget);
        expect(find.byKey(const Key('assistant-bubble')), findsNothing);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('assistant-bubble')), findsOneWidget);
      },
    );

    testWidgets(
      'Dragging bubble to left half snaps to left edge and persists position',
      (tester) async {
        final repo = ReportRepository(
          initialSettings: const AppSettings(
            englishFirst: true,
            assistantHintSeen: true,
          ),
        );
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(SrolanhCityApp(repository: repo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();

        expect(repo.settings.assistantBubbleOnLeft, isFalse);
        final bubble = find.byKey(const Key('assistant-bubble'));
        await tester.drag(bubble, const Offset(-300, -100));
        await tester.pumpAndSettle();

        expect(repo.settings.assistantBubbleOnLeft, isTrue);
        expect(
          repo.settings.assistantBubbleYFraction,
          inInclusiveRange(0.0, 1.0),
        );
        final snappedLeft = tester.getTopLeft(bubble).dx;
        expect(snappedLeft, lessThan(40));
      },
    );

    testWidgets(
      'Conversation sent in floating bubble panel persists when opening HelpCenterPage',
      (tester) async {
        final repo = ReportRepository(
          initialSettings: const AppSettings(
            englishFirst: true,
            assistantHintSeen: true,
          ),
        );
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(SrolanhCityApp(repository: repo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();

        // Send a question in the floating panel
        await tester.tap(find.byKey(const Key('assistant-bubble')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('assistant-panel-input')),
          'How is P5 priority calculated?',
        );
        await tester.tap(find.byKey(const Key('assistant-panel-send-btn')));
        await tester.pumpAndSettle();
        expect(find.text('How is P5 priority calculated?'), findsOneWidget);

        // Open Help Center directly from the panel menu
        await tester.tap(find.byKey(const Key('assistant-panel-menu-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assistant-menu-help-center')));
        await tester.pumpAndSettle();

        expect(find.byType(HelpCenterPage), findsOneWidget);
        expect(find.text('How is P5 priority calculated?'), findsOneWidget);
      },
    );
  });
}

class _FakeLocationService extends LocationService {
  const _FakeLocationService(this.result);

  final LocationFetchResult result;

  @override
  Future<LocationFetchResult> getCurrentLocation({
    bool enforceMockCheck = true,
    bool fastFix = false,
  }) async => result;
}

class _UnavailableTestVoiceService implements VoiceInputService {
  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) async => false;

  @override
  Future<VoiceLocaleResolution> resolveLocale({
    required bool preferEnglish,
  }) async => const VoiceLocaleResolution(
    localeId: 'en_US',
    exactLanguageAvailable: false,
  );

  @override
  Future<void> startListening({
    required String? localeId,
    required void Function(String text, bool isFinal) onResult,
    required void Function(double normalizedLevel) onSoundLevel,
  }) async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancel() async {}
}

class _UnconfiguredTestAiService implements CivicAiService {
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

class _TestIpGeoService implements IpGeolocationService {
  const _TestIpGeoService(this.info);
  final IpGeoInfo? info;

  @override
  Future<IpGeoInfo?> lookupCurrentIp() async => info;
}

class _WidgetFakeAudioRecorderService implements AudioRecorderService {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> startRecording({bool persistentMemo = false}) async => true;

  @override
  Future<double> getNormalizedAmplitude() async => 0.6;

  @override
  Future<String?> stopRecording() async => 'data:audio/webm;base64,AAAA';

  @override
  Future<void> cancelAndDelete() async {}

  @override
  Future<void> deleteFile(String? path) async {}

  @override
  Future<void> dispose() async {}
}

class _WidgetFakeAudioPlayerService implements AudioPlayerService {
  @override
  bool get isPlaybackSupported => true;

  @override
  Future<bool> play(String source, {VoidCallback? onCompleted}) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _WidgetFakeTranslator implements CommentTranslationService {
  @override
  Future<String?> translate({
    required String text,
    required String targetLang,
  }) async => targetLang == 'km' ? 'ការបកប្រែជាភាសាខ្មែរ' : 'Translated EN';
}
