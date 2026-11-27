import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:srolanhcity/data/repositories/report_repository.dart';
import 'package:srolanhcity/data/services/audio_recorder_service.dart';
import 'package:srolanhcity/data/services/civic_ai_service.dart';
import 'package:srolanhcity/data/services/comment_translation_service.dart';
import 'package:srolanhcity/data/services/exif_stripper.dart';
import 'package:srolanhcity/data/services/ip_geolocation_service.dart';
import 'package:srolanhcity/data/services/location_service.dart';
import 'package:srolanhcity/data/services/photo_media_types.dart';
import 'package:srolanhcity/data/services/reverse_geocoding_service.dart';
import 'package:srolanhcity/data/services/voice_input_service.dart';
import 'package:srolanhcity/domain/models/report_models.dart';
import 'package:srolanhcity/domain/services/report_location_eligibility_service.dart';
import 'package:srolanhcity/main.dart';
import 'package:srolanhcity/ui/core/report_scope.dart';
import 'package:srolanhcity/ui/core/theme.dart';
import 'package:srolanhcity/ui/core/widgets/before_after_slider.dart';
import 'package:srolanhcity/ui/core/widgets/user_avatar.dart';
import 'package:srolanhcity/ui/core/widgets/voice_waveform.dart';
import 'package:srolanhcity/ui/features/alerts/alert_detail_page.dart';
import 'package:srolanhcity/ui/features/alerts/alerts_page.dart';
import 'package:srolanhcity/ui/features/help/help_center_page.dart';
import 'package:srolanhcity/ui/features/map/map_page.dart';
import 'package:srolanhcity/ui/features/news/area_news_page.dart';
import 'package:srolanhcity/ui/features/profile/edit_profile_page.dart';
import 'package:srolanhcity/ui/features/profile/my_reports_page.dart';
import 'package:srolanhcity/ui/features/profile/profile_page.dart';
import 'package:srolanhcity/ui/features/report/views/fake_gps_page.dart';
import 'package:srolanhcity/ui/features/report/views/report_wizard_page.dart';
import 'package:srolanhcity/ui/features/shell/main_shell.dart';
import 'package:srolanhcity/ui/features/tracking/tracking_page.dart';

const String _testPhotoDataUri =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

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
      // Next is disabled until at least 1 photo is attached
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('step1-next-btn')))
            .onPressed,
        isNull,
      );

      // Re-mount with a captured photo to verify Step 2 voice feedback & Try Sample
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            key: const ValueKey('wizard-with-photo-voice-test'),
            initialCategory: IssueCategory.drain,
            initialPhotoPaths: const [_testPhotoDataUri],
            voiceInputService: _UnavailableTestVoiceService(),
            civicAiService: _UnconfiguredTestAiService(),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('step1-next-btn')));
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

      // Verify MapPage configures Cambodia bounds, zoom limits, and fast CDN tile layer
      await tester.pumpWidget(_wrapWithScope(repo, const MapPage()));
      await tester.pump();
      final mapWidget = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(mapWidget.options.minZoom, equals(LocationService.minMapZoom));
      expect(mapWidget.options.maxZoom, equals(LocationService.maxMapZoom));
      expect(mapWidget.options.backgroundColor, equals(AppColors.mutedSurface));
      expect(
        mapWidget.options.cameraConstraint,
        equals(
          CameraConstraint.contain(bounds: LocationService.cambodiaMapBounds),
        ),
      );
      final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(
        tileLayer.urlTemplate,
        equals('https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      );
      expect(tileLayer.panBuffer, equals(0));
      expect(tileLayer.fallbackUrl, isNull);
      expect(find.text('© OpenStreetMap'), findsOneWidget);

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
    'TrackingPage enforces strict GPS "Affects me": instant <= 150 m on-site, mandatory Remote Province reason sheet > 150 m with WCAG 2.1 AA, and Undo cleanup',
    (tester) async {
      final handle = tester.ensureSemantics();
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );
      final target = repo.findById('#SC-20524')!;
      final beforeCount = target.affectedCitizens;

      // 1. GPS off -> strictly blocked even if user later sets Home District
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          const TrackingPage(
            reportId: '#SC-20524',
            locationService: _FakeLocationService(LocationServiceDisabled()),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('tracking-support-btn')));
      await tester.pumpAndSettle();
      expect(repo.findById('#SC-20524')!.affectedCitizens, equals(beforeCount));
      expect(find.textContaining('Turn on GPS'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(TrackingPage)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // 2. Different Province (Siem Reap supporting Phnom Penh #SC-20524)
      //    -> strictly opens "Why does this issue affect you?" sheet tagged "Remote support · Siem Reap"
      await tester.pumpWidget(
        ReportScope(
          key: const ValueKey('tracking-remote-province'),
          repository: repo,
          child: MaterialApp(
            theme: buildSrolanhCityTheme(),
            home: const TrackingPage(
              reportId: '#SC-20524',
              locationService: _FakeLocationService(
                LocationSuccess(
                  point: LatLng(13.3633, 103.8564),
                  accuracyMeters: 20,
                  isOutsideCambodia: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracking-support-btn')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('remote-support-reason-sheet')),
        findsOneWidget,
      );
      expect(find.textContaining('Remote support · Siem Reap'), findsOneWidget);

      // Confirm button disabled until reason chip AND >= 10 char explanation entered
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-remote-support-btn')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const Key('support-reason-liveOrFamilyNearby')),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-remote-support-btn')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('remote-support-note-field')),
        'My parents drive through Sen Sok every morning',
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(find.byKey(const Key('confirm-remote-support-btn')));
      await tester.pumpAndSettle();

      expect(
        repo.findById('#SC-20524')!.affectedCitizens,
        equals(beforeCount + 1),
      );
      expect(find.byKey(const Key('support-tier-badge')), findsOneWidget);
      expect(find.textContaining('Remote support · Siem Reap'), findsWidgets);

      // Undo removes support, comment, and re-enables button
      await tester.ensureVisible(find.byKey(const Key('undo-support-btn')));
      await tester.tap(find.byKey(const Key('undo-support-btn')));
      await tester.pumpAndSettle();
      expect(repo.findById('#SC-20524')!.affectedCitizens, equals(beforeCount));
      expect(find.text('Affects me too'), findsOneWidget);

      // 3. Within <= 150 m (~110 m) 6 hours later (plausible travel time from
      // Siem Reap) -> instant 1-tap Verified on-site (no sheet!)
      await tester.pumpWidget(
        ReportScope(
          key: const ValueKey('tracking-onsite-support'),
          repository: repo,
          child: MaterialApp(
            theme: buildSrolanhCityTheme(),
            home: TrackingPage(
              reportId: '#SC-20524',
              locationService: _FakeLocationService(
                LocationSuccess(
                  point: LatLng(
                    target.coordinates.latitude + 0.001,
                    target.coordinates.longitude,
                  ),
                  accuracyMeters: 8,
                  isOutsideCambodia: false,
                  timestamp: DateTime.now().add(const Duration(hours: 6)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracking-support-btn')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('remote-support-reason-sheet')),
        findsNothing,
      );
      expect(
        repo.findById('#SC-20524')!.affectedCitizens,
        equals(beforeCount + 1),
      );
      expect(find.byKey(const Key('support-tier-badge')), findsOneWidget);
      expect(find.textContaining('Verified on-site'), findsWidgets);
      handle.dispose();
    },
  );

  testWidgets(
    'MapPage Priority Sort chip opens sort sheet, reorders carousel P5->P1, and passes WCAG 2.1 AA',
    (tester) async {
      final handle = tester.ensureSemantics();
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      await tester.pumpWidget(_wrapWithScope(repo, const MapPage()));
      await tester.pump();

      final sortBtn = find.byKey(const Key('map-priority-sort-btn'));
      expect(sortBtn, findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(sortBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('map-sort-sheet')), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(
        find.byKey(const Key('map-sort-option-priorityHighToLow')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('map-sort-sheet')), findsNothing);
      expect(find.text('Priority P5→P1'), findsOneWidget);

      // Highest priority open report in Phnom Penh (#SC-20519, P5) is now first in carousel
      expect(find.text('#SC-20519'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets(
    'MapPage bottom sheet blocks GPS-off and requires transparent Remote District reason sheet when supporting from another Khan',
    (tester) async {
      final seedRepo = ReportRepository();
      final senSokReport = seedRepo.findById('#SC-20524')!;
      final beforeCount = senSokReport.affectedCitizens;

      // 1. GPS disabled -> visible inline error banner inside sheet, button stays enabled
      final blockedRepo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
        initialReports: [senSokReport],
      );
      await tester.pumpWidget(
        _wrapWithScope(
          blockedRepo,
          const MapPage(
            locationService: _FakeLocationService(LocationServiceDisabled()),
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
      expect(find.textContaining('Turn on GPS'), findsOneWidget);
      expect(
        blockedRepo.findById('#SC-20524')!.affectedCitizens,
        equals(beforeCount),
      );

      // Dismiss bottom sheet before pumping the Remote District scenario
      Navigator.of(tester.element(find.byKey(const Key('map-support-btn'))))
          .pop();
      await tester.pumpAndSettle();

      // 2. Different District (Khan Daun Penh supporting Khan Sen Sok ~5.3 km)
      //    -> opens reason sheet tagged "Remote support · Khan Daun Penh", confirms -> disables to Supported
      final allowedRepo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
        initialReports: [senSokReport],
      );
      await tester.pumpWidget(
        ReportScope(
          key: const ValueKey('map-remote-district-scope'),
          repository: allowedRepo,
          child: MaterialApp(
            theme: buildSrolanhCityTheme(),
            home: const MapPage(
              locationService: _FakeLocationService(
                LocationSuccess(
                  point: LocationService.phnomPenhCenter,
                  accuracyMeters: 15,
                  isOutsideCambodia: false,
                ),
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
        find.byKey(const Key('remote-support-reason-sheet')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Remote support · Khan Daun Penh'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('support-reason-dailyCommute')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-remote-support-btn')));
      await tester.pumpAndSettle();

      expect(
        allowedRepo.findById('#SC-20524')!.affectedCitizens,
        equals(beforeCount + 1),
      );
      expect(
        find.byKey(const Key('map-support-feedback-banner')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Remote support · Khan Daun Penh'),
        findsOneWidget,
      );
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
      await tester.scrollUntilVisible(
        find.byKey(const Key('report-description-card')),
        250,
      );
      expect(find.byKey(const Key('report-description-card')), findsOneWidget);
      expect(
        find.text('Huge sinkhole right outside school gate'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _wrapWithScope(repo, TrackingPage(reportId: withoutNote.report.id)),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('report-description-card')),
        250,
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
            initialPhotoPaths: const [_testPhotoDataUri],
            locationService: _FakeLocationService(
              LocationSuccess(
                point: seededMine.coordinates,
                accuracyMeters: 8,
                isOutsideCambodia: false,
              ),
            ),
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

      // Seeded #SC-20481 is in "My Reports" within 50 m -> self-duplicate guard shows "View your existing report"
      expect(find.textContaining('View your existing report'), findsOneWidget);
      expect(find.byKey(const Key('step3-join-report-btn')), findsNothing);
      expect(find.byKey(const Key('step3-option-create-new')), findsNothing);

      // Tap "Report a different category" -> opens sheet defaulting to Other Issue
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

      // Shows 2 follow-up citizen comments + 8 silent supporters footer (original description is in Hero Summary)
      await tester.scrollUntilVisible(
        find.byKey(const Key('citizen-comments-list')),
        250,
      );
      expect(find.byKey(const Key('citizen-comments-list')), findsOneWidget);
      expect(find.textContaining('(2)'), findsOneWidget);
      expect(find.textContaining('Citizen #2'), findsOneWidget);
      expect(find.textContaining('Anonymous citizen #3'), findsOneWidget);
      expect(find.byKey(const Key('silent-supporters-footer')), findsOneWidget);
      expect(
        find.textContaining('8 other citizen(s) confirmed without commenting'),
        findsOneWidget,
      );

      // Tap "Write a comment..." -> opens _AddCommentSheet -> post a new note -> displays immediately
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

      // Adding a note auto-expands to show all 3 follow-up comments & toggle button
      expect(find.textContaining('(3)'), findsOneWidget);
      expect(find.byKey(const Key('toggle-all-comments-btn')), findsOneWidget);
      expect(
        find.text('Fresh cone placed next to pothole today'),
        findsOneWidget,
      );

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

      // Verify delete button sits inline inside the comment card bounds
      final cardRect = tester.getRect(
        find.byKey(const Key('citizen-comments-list')),
      );
      final deleteRect = tester.getRect(deleteBtn);
      expect(deleteRect.left, greaterThanOrEqualTo(cardRect.left));
      expect(deleteRect.right, lessThanOrEqualTo(cardRect.right));

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('Fresh cone placed next to pothole today'),
        findsNothing,
      );
      expect(find.textContaining('(2)'), findsOneWidget);
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
            initialPhotoPaths: const [_testPhotoDataUri],
            locationService: _FakeLocationService(
              LocationSuccess(
                point: neighbor.coordinates,
                accuracyMeters: 10,
                isOutsideCambodia: false,
              ),
            ),
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

      // Step 2 -> Step 3 -> Join selected Master Incident (#SC-20519)
      await tester.tap(find.textContaining('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('step3-join-report-btn')));
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
      await tester.scrollUntilVisible(toggleCommentsBtn, 250);
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
            initialPhotoPaths: const [_testPhotoDataUri],
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
    'ReportWizard Step 1 shows fail-fast Photo GPS pill and Step 3 hard-blocks > 150 m with floating & card Return to 150 m zone',
    (tester) async {
      final repo = ReportRepository(
        initialSettings: const AppSettings(englishFirst: true),
      );

      // Case 1: Matching Phnom Penh EXIF (<= 150 m) -> Step 1 green pill + Step 3 verified pill
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            initialCoordinates: const LatLng(11.5318, 104.9044),
            initialPhotoPaths: const [_testPhotoDataUri],
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
      expect(find.byKey(const Key('step1-photo-gps-pill')), findsOneWidget);
      expect(find.textContaining('Photo GPS locked'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Confirm location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('step3-exif-verified-pill')), findsOneWidget);
      expect(find.byKey(const Key('step3-out-of-zone-blocker')), findsNothing);

      // Case 2: EXIF in Siem Reap while pinned in Phnom Penh when live GPS is disabled
      // -> hard-blocked by 150 m Zone + floating & card Return to 150 m zone
      await tester.pumpWidget(
        _wrapWithScope(
          repo,
          ReportWizardPage(
            key: const ValueKey('wizard-mismatch'),
            initialCoordinates: const LatLng(11.5318, 104.9044),
            initialPhotoPaths: const [_testPhotoDataUri],
            initialPhotoExif: PhotoExifMetadata(
              coordinates: const LatLng(13.3633, 103.8564),
              capturedAt: DateTime.now().subtract(const Duration(minutes: 10)),
            ),
            locationService: const _FakeLocationService(
              LocationServiceDisabled(),
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
        find.byKey(const Key('step3-out-of-zone-blocker')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('step3-floating-return-zone-btn')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('step3-submit-report-btn')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('step3-return-to-zone-btn')), findsOneWidget);

      // 1-tap "Return to 150 m zone" moves pin to photo EXIF and enables Submit
      await tester.tap(find.byKey(const Key('step3-floating-return-zone-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('step3-exif-verified-pill')), findsOneWidget);
      expect(
        find.byKey(const Key('step3-floating-return-zone-btn')),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('step3-submit-report-btn')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'ReportWizard Step 2 is transcript-only offline (shows honest offline notice, zero audio players)',
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
            initialPhotoPaths: const [_testPhotoDataUri],
            locationService: const _FakeLocationService(
              LocationSuccess(
                point: LatLng(11.5319, 104.9044),
                accuracyMeters: 9,
                isOutsideCambodia: false,
              ),
            ),
            voiceInputService: _UnavailableTestVoiceService(),
            audioRecorderService: _WidgetFakeAudioRecorderService(),
            civicAiService: _UnconfiguredTestAiService(),
            ipGeolocationService: const _TestIpGeoService(null),
          ),
        ),
      );

      // Step 1 shows fail-fast "No GPS tag in photo" hint for non-EXIF photo
      expect(find.byKey(const Key('step1-photo-gps-pill')), findsOneWidget);
      expect(find.textContaining('No GPS tag in photo'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('voice-offline-badge')), findsOneWidget);

      // Tapping mic offline shows honest voice-to-text guidance (no saved audio memo)
      final recordBtn = find.byKey(const Key('voice-record-btn'));
      await tester.ensureVisible(recordBtn);
      await tester.pump();
      await tester.tap(recordBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('voice-feedback-box')), findsOneWidget);
      expect(
        find.textContaining('voice-to-text requires internet'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('voice-record-memo-btn')), findsNothing);
      expect(find.byKey(const Key('step2-voice-memo-player')), findsNothing);
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
      await tester.scrollUntilVisible(translateBtn, 250);
      await tester.pumpAndSettle();
      expect(translateBtn, findsOneWidget);

      await tester.ensureVisible(translateBtn);
      await tester.pumpAndSettle();
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
      final thirdTranslateBtn = find.byKey(
        const Key('translate-comment-c-20519-3'),
      );
      await tester.ensureVisible(thirdTranslateBtn);
      await tester.pumpAndSettle();
      await tester.tap(thirdTranslateBtn);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('translate-error-c-20519-3')),
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

  group('ReportWizard Step 3 Smart Distance Gate (Rule #1)', () {
    testWidgets(
      'Blocks Siem Reap GPS from submitting in Phnom Penh, and Jump to my GPS unblocks submission',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        const siemReapGps = LatLng(13.3633, 103.8564);
        const phnomPenhSpot = LatLng(11.5318, 104.9044);

        await tester.pumpWidget(
          _wrapWithScope(
            repo,
            ReportWizardPage(
              initialCategory: IssueCategory.pothole,
              initialCoordinates: phnomPenhSpot,
              initialPhotoPaths: const [_testPhotoDataUri],
              locationService: const _FakeLocationService(
                LocationSuccess(
                  point: siemReapGps,
                  accuracyMeters: 12,
                  isOutsideCambodia: false,
                ),
              ),
              voiceInputService: _UnavailableTestVoiceService(),
              civicAiService: _UnconfiguredTestAiService(),
              ipGeolocationService: const _TestIpGeoService(null),
            ),
          ),
        );

        // Step 1 -> Step 2 -> Step 3
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.textContaining('Confirm location'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // Out-of-zone blocker & floating Return to 150 m zone shown, Submit disabled
        expect(
          find.byKey(const Key('step3-out-of-zone-blocker')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('step3-floating-return-zone-btn')),
          findsOneWidget,
        );
        final submitBtn = tester.widget<FilledButton>(
          find.byKey(const Key('step3-submit-report-btn')),
        );
        expect(submitBtn.onPressed, isNull);

        // Verify blocked state meets labeled tap target & contrast guidelines
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // Tap Return to 150 m zone -> moves pin to Siem Reap live GPS & enables Submit
        final returnBtn = find.byKey(const Key('step3-return-to-zone-btn'));
        await tester.ensureVisible(returnBtn);
        await tester.tap(returnBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const Key('step3-out-of-zone-blocker')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('step3-location-verified-pill')),
          findsOneWidget,
        );
        final enabledSubmit = tester.widget<FilledButton>(
          find.byKey(const Key('step3-submit-report-btn')),
        );
        expect(enabledSubmit.onPressed, isNotNull);

        handle.dispose();
      },
    );

    testWidgets(
      'Allows delayed upload in Phnom Penh with matching Fresh Photo EXIF when live GPS is disabled (strictly blocks GPS-off without EXIF even when Home District is set)',
      (tester) async {
        const phnomPenhSpot = LatLng(11.5318, 104.9044);

        // 1. Fresh Photo EXIF at Phnom Penh pin verifies the 150 m zone when live GPS is unavailable
        final exifRepo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        await tester.pumpWidget(
          _wrapWithScope(
            exifRepo,
            ReportWizardPage(
              key: const ValueKey('wizard-exif-override'),
              initialCategory: IssueCategory.pothole,
              initialCoordinates: phnomPenhSpot,
              initialPhotoPaths: const [_testPhotoDataUri],
              initialPhotoExif: PhotoExifMetadata(
                coordinates: phnomPenhSpot,
                capturedAt: DateTime.now().subtract(const Duration(hours: 2)),
              ),
              locationService: const _FakeLocationService(
                LocationServiceDisabled(),
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
        await tester.pump(const Duration(milliseconds: 350));

        expect(
          find.byKey(const Key('step3-exif-verified-pill')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('step3-submit-report-btn')),
              )
              .onPressed,
          isNotNull,
        );

        // 2. Pure strictness (Option B): GPS disabled with NO EXIF is STRICTLY
        //    blocked even when Home District is configured (zero Home bypass!)
        final homeRepo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
          initialProfile: const UserProfile(
            homeProvinceCode: 'phnom_penh',
            khmerHomeArea: 'ផ្សារថ្មី, ខណ្ឌដូនពេញ',
            englishHomeArea: 'Phsar Thmei, Daun Penh',
          ),
        );
        await tester.pumpWidget(
          _wrapWithScope(
            homeRepo,
            ReportWizardPage(
              key: const ValueKey('wizard-strict-gps-off'),
              initialCategory: IssueCategory.trash,
              initialCoordinates: phnomPenhSpot,
              initialPhotoPaths: const [_testPhotoDataUri],
              locationService: const _FakeLocationService(
                LocationServiceDisabled(),
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
        await tester.pump(const Duration(milliseconds: 350));

        expect(
          find.byKey(const Key('step3-location-required-banner')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('step3-submit-report-btn')),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'Step 3 150 m Multi-Incident Picker lists multiple similar reports, supports in-place preview, joins chosen 2nd Master Incident, and supports 1-tap New Separate Report',
      (tester) async {
        final handle = tester.ensureSemantics();
        const origin = LatLng(11.5318, 104.9044);
        final base = ReportRepository().findById('#SC-20519')!;
        final match1 = base.copyWith(
          coordinates: const LatLng(11.5322, 104.9044), // ~45 m
          englishTitle: 'First Pothole Nearby',
        );
        final match2 = CivicReport.fromJson({
          ...base.toJson(),
          'id': '#SC-29950',
          'englishTitle': 'Second Pothole Across Block',
          'lat': 11.5318,
          'lng': 104.9055, // ~120 m
          'isMine': false,
          'createdByCurrentUser': false,
          'joinedByCurrentUser': false,
        });

        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
          initialReports: [match2, match1],
        );
        final beforeMatch2Count = repo.findById('#SC-29950')!.affectedCitizens;

        await tester.pumpWidget(
          _wrapWithScope(
            repo,
            ReportWizardPage(
              initialCategory: IssueCategory.pothole,
              initialCoordinates: origin,
              initialPhotoPaths: const [_testPhotoDataUri],
              locationService: const _FakeLocationService(
                LocationSuccess(
                  point: origin,
                  accuracyMeters: 10,
                  isOutsideCambodia: false,
                ),
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
        await tester.pump(const Duration(milliseconds: 350));

        // Both matches within 150 m AND "+ Submit as a new separate report" appear
        expect(find.byKey(const Key('step3-similar-picker')), findsOneWidget);
        expect(
          find.byKey(const Key('similar-match-#SC-20519')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('similar-match-#SC-29950')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('step3-option-create-new')),
          findsOneWidget,
        );
        // Step 3 candidate cards omit per-pin distance labels
        expect(find.textContaining('#SC-20519 · ×'), findsOneWidget);
        expect(find.textContaining('#SC-29950 · ×'), findsOneWidget);
        expect(find.textContaining('m away'), findsNothing);

        // Pass WCAG 2.1 AA on the new Step 3 picker
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // Open in-place quick preview of 2nd match & tap "Select #SC-29950"
        final previewBtn = find.byKey(const Key('preview-match-#SC-29950'));
        await tester.ensureVisible(previewBtn);
        await tester.tap(previewBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('similar-report-preview-sheet')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('preview-select-match-btn')));
        await tester.pumpAndSettle();

        // Primary CTA now targets #SC-29950 specifically -> Join merges into #SC-29950
        expect(find.textContaining('Join #SC-29950'), findsOneWidget);
        await tester.tap(find.byKey(const Key('step3-join-report-btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          repo.findById('#SC-29950')!.affectedCitizens,
          equals(beforeMatch2Count + 1),
        );

        // Fresh wizard at same origin -> pick "+ Submit as a new separate report here"
        final beforeTotal = repo.reports.length;
        await tester.pumpWidget(
          ReportScope(
            key: const ValueKey('wizard-create-new-in-150m'),
            repository: repo,
            child: MaterialApp(
              theme: buildSrolanhCityTheme(),
              home: ReportWizardPage(
                initialCategory: IssueCategory.pothole,
                initialCoordinates: origin,
                initialPhotoPaths: const [_testPhotoDataUri],
                locationService: const _FakeLocationService(
                  LocationSuccess(
                    point: origin,
                    accuracyMeters: 10,
                    isOutsideCambodia: false,
                  ),
                ),
                voiceInputService: _UnavailableTestVoiceService(),
                civicAiService: _UnconfiguredTestAiService(),
                ipGeolocationService: const _TestIpGeoService(null),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.textContaining('Confirm location'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        final newOpt = find.byKey(const Key('step3-option-create-new'));
        await tester.ensureVisible(newOpt);
        await tester.tap(newOpt);
        await tester.pump();
        await tester.tap(find.byKey(const Key('step3-submit-new-report-btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(repo.reports.length, equals(beforeTotal + 1));
        expect(repo.reports.first.category, equals(IssueCategory.pothole));
        handle.dispose();
      },
    );

    testWidgets(
      'Live camera anchor hard-blocks pins > 150 m away, passes WCAG 2.1 AA, and unblocks on Return to 150 m zone',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        const cameraSpot = LatLng(11.5318, 104.9044);
        const farPin = LatLng(11.5356, 104.9044); // ~420 m away

        await tester.pumpWidget(
          _wrapWithScope(
            repo,
            ReportWizardPage(
              initialCategory: IssueCategory.pothole,
              initialCoordinates: farPin,
              initialPhotoPaths: const [_testPhotoDataUri],
              initialPhotoAnchor: PhotoLocationAnchor(
                point: cameraSpot,
                source: PhotoAnchorSource.liveCameraCapture,
                capturedAt: DateTime.now(),
              ),
              locationService: const _FakeLocationService(
                LocationServiceDisabled(),
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
        await tester.pump(const Duration(milliseconds: 350));

        expect(
          find.byKey(const Key('step3-out-of-zone-blocker')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('step3-floating-return-zone-btn')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('step3-submit-report-btn')),
              )
              .onPressed,
          isNull,
        );

        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.tap(find.byKey(const Key('step3-return-to-zone-btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.textContaining('Live camera GPS verified'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('step3-submit-report-btn')),
              )
              .onPressed,
          isNotNull,
        );
        handle.dispose();
      },
    );

    testWidgets(
      'ReportWizard enforces mandatory >= 1 photo on Step 1 & Step 2 and passes WCAG 2.1 AA guidelines',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );

        // Step 1 without photo -> Next disabled
        await tester.pumpWidget(
          _wrapWithScope(
            repo,
            ReportWizardPage(
              initialCategory: IssueCategory.pothole,
              voiceInputService: _UnavailableTestVoiceService(),
              civicAiService: _UnconfiguredTestAiService(),
              ipGeolocationService: const _TestIpGeoService(null),
            ),
          ),
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('step1-next-btn')))
              .onPressed,
          isNull,
        );

        // With 1 photo -> advances to Step 2; deleting last photo blocks Step 2
        await tester.pumpWidget(
          _wrapWithScope(
            repo,
            ReportWizardPage(
              key: const ValueKey('wizard-mandatory-photo-step2'),
              initialCategory: IssueCategory.pothole,
              initialPhotoPaths: const [_testPhotoDataUri],
              voiceInputService: _UnavailableTestVoiceService(),
              civicAiService: _UnconfiguredTestAiService(),
              ipGeolocationService: const _TestIpGeoService(null),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('step1-next-btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('step2-confirm-location-btn')),
              )
              .onPressed,
          isNotNull,
        );

        // Remove the only attached photo -> red banner + Confirm location disabled
        await tester.tap(find.byTooltip('Remove photo'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const Key('step2-photo-required-banner')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('step2-confirm-location-btn')),
              )
              .onPressed,
          isNull,
        );

        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      },
    );

    testWidgets(
      'TrackingPage renders clean placeholder (never a fake stock image) for photo-less repository reports',
      (tester) async {
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        final res = repo.submitReport(
          category: IssueCategory.pothole,
          description: 'Legacy text-only report',
          severity: 3,
          coordinates: const LatLng(11.5395, 104.9095),
          isAnonymous: false,
        );

        expect(res.report.localPhotoPath, isNull);
        expect(res.report.photoAssetPath, isNull);
        expect(res.report.hasPhoto, isFalse);

        await tester.pumpWidget(
          ReportScope(
            key: const ValueKey('tracking-nophoto-scope'),
            repository: repo,
            child: MaterialApp(
              theme: buildSrolanhCityTheme(),
              home: TrackingPage(reportId: res.report.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('report-photo-placeholder')),
          findsOneWidget,
        );
        expect(find.byType(Image), findsNothing);
      },
    );
  });

  group('R1–R4 Feature & UX Widget Tests', () {
    testWidgets(
      'R1 & R2: Own-report comments skip GPS & show real name / Guest · You / Anonymous · Original reporter with delete preserved',
      (tester) async {
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );

        // 1. Default Guest profile on own report (#SC-20481) with GPS disabled -> still posts with no GPS tag
        await tester.pumpWidget(
          _wrapWithScope(
            repo,
            const TrackingPage(
              reportId: '#SC-20481',
              locationService: _FakeLocationService(LocationServiceDisabled()),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('report-description-card')),
          250,
        );
        expect(
          find.textContaining('Guest · You · Original reporter'),
          findsOneWidget,
        );

        await tester.scrollUntilVisible(
          find.byKey(const Key('add-comment-btn')),
          250,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-comment-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('add-comment-field')),
          'Own report note without GPS',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit-comment-btn')));
        await tester.pumpAndSettle();

        final note1 = repo.findById('#SC-20481')!.effectiveComments.last;
        expect(note1.supportTier, isNull);
        expect(note1.authorName, isNull);
        expect(
          find.byKey(Key('comment-location-tag-${note1.id}')),
          findsNothing,
        );
        expect(find.byKey(Key('delete-comment-${note1.id}')), findsOneWidget);

        // 2. Real profile name replaces Guest · You with <Name> · Original reporter
        repo.updateProfile(
          const UserProfile(englishName: 'Dara Sok', khmerName: 'តារា សុខ'),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Dara Sok · Original reporter'),
          findsWidgets,
        );

        // 3. Anonymous toggle on own report shows Anonymous · Original reporter & preserves delete button
        await tester.scrollUntilVisible(
          find.byKey(const Key('add-comment-btn')),
          250,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-comment-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('add-comment-field')),
          'Own anonymous follow-up',
        );
        await tester.tap(find.byKey(const Key('add-comment-anon-switch')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit-comment-btn')));
        await tester.pumpAndSettle();

        final anonNote = repo.findById('#SC-20481')!.effectiveComments.last;
        expect(anonNote.isAnonymous, isTrue);
        expect(anonNote.authorName, isNull);
        expect(
          find.textContaining('Anonymous · Original reporter'),
          findsOneWidget,
        );
        expect(
          find.byKey(Key('delete-comment-${anonNote.id}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'R1 & R2: Other-report comments block Mock/Off/Outside-Cambodia GPS and silently attach ✓ On-site or Remote · <Area> with real name',
      (tester) async {
        final seedRepo = ReportRepository();
        final target = seedRepo.findById('#SC-20524')!;

        // 1. Mock GPS -> navigates to FakeGpsPage and blocks comment
        final mockRepo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        await tester.pumpWidget(
          _wrapWithScope(
            mockRepo,
            TrackingPage(
              reportId: '#SC-20524',
              locationService: _FakeLocationService(
                LocationMockDetected(
                  point: target.coordinates,
                  detectedLabel: 'Fake GPS App',
                ),
              ),
            ),
          ),
        );
        final beforeCount = mockRepo
            .findById('#SC-20524')!
            .effectiveComments
            .length;
        await tester.scrollUntilVisible(
          find.byKey(const Key('add-comment-btn')),
          250,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-comment-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('add-comment-field')),
          'Spoofed note',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit-comment-btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(FakeGpsPage), findsOneWidget);
        expect(
          mockRepo.findById('#SC-20524')!.effectiveComments.length,
          equals(beforeCount),
        );

        // 2. GPS off -> SnackBar error and blocks comment
        await tester.pumpWidget(
          ReportScope(
            key: const ValueKey('other-comment-gps-off-scope'),
            repository: mockRepo,
            child: MaterialApp(
              theme: buildSrolanhCityTheme(),
              home: const TrackingPage(
                reportId: '#SC-20524',
                locationService: _FakeLocationService(
                  LocationServiceDisabled(),
                ),
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('add-comment-btn')),
          250,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-comment-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('add-comment-field')),
          'No GPS note',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit-comment-btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Turn on GPS'), findsOneWidget);
        expect(
          mockRepo.findById('#SC-20524')!.effectiveComments.length,
          equals(beforeCount),
        );

        // 3. Outside Cambodia -> SnackBar error and blocks comment
        await tester.pumpWidget(
          _wrapWithScope(
            mockRepo,
            const TrackingPage(
              key: ValueKey('other-comment-outside-kh'),
              reportId: '#SC-20524',
              locationService: _FakeLocationService(
                LocationSuccess(
                  point: LatLng(37.422, -122.084),
                  accuracyMeters: 15,
                  isOutsideCambodia: true,
                ),
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('add-comment-btn')),
          250,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-comment-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('add-comment-field')),
          'Abroad note',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit-comment-btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('outside Cambodia'), findsOneWidget);
        expect(
          mockRepo.findById('#SC-20524')!.effectiveComments.length,
          equals(beforeCount),
        );

        // 4. Live GPS <= 150 m -> silently posts with `✓ On-site` & real name (no reason sheet)
        final onsiteRepo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
          initialProfile: const UserProfile(
            englishName: 'Sokha Chan',
            khmerName: 'សុខា ចាន់',
          ),
        );
        await tester.pumpWidget(
          _wrapWithScope(
            onsiteRepo,
            TrackingPage(
              key: const ValueKey('other-comment-onsite'),
              reportId: '#SC-20524',
              locationService: _FakeLocationService(
                LocationSuccess(
                  point: LatLng(
                    target.coordinates.latitude + 0.0004,
                    target.coordinates.longitude,
                  ),
                  accuracyMeters: 8,
                  isOutsideCambodia: false,
                ),
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('add-comment-btn')),
          250,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-comment-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('add-comment-field')),
          'Standing right next to this drain',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit-comment-btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('remote-support-reason-sheet')),
          findsNothing,
        );
        final onsiteComment = onsiteRepo
            .findById('#SC-20524')!
            .effectiveComments
            .last;
        expect(
          onsiteComment.supportTier,
          equals(SupportVerificationTier.verifiedNearby),
        );
        expect(onsiteComment.authorName, equals('Sokha Chan'));
        expect(
          find.byKey(Key('comment-location-tag-${onsiteComment.id}')),
          findsOneWidget,
        );
        expect(find.text('✓ On-site'), findsOneWidget);
        expect(find.text('Sokha Chan'), findsOneWidget);

        // 5. Live GPS > 150 m -> silently posts with `Remote · <Village>` (geocoded)
        final remoteRepo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
          initialProfile: const UserProfile(
            englishName: 'Sokha Chan',
            khmerName: 'សុខា ចាន់',
          ),
        );
        await tester.pumpWidget(
          _wrapWithScope(
            remoteRepo,
            TrackingPage(
              key: const ValueKey('other-comment-remote-village'),
              reportId: '#SC-20524',
              locationService: _FakeLocationService(
                LocationSuccess(
                  point: LatLng(
                    target.coordinates.latitude + 0.004,
                    target.coordinates.longitude,
                  ),
                  accuracyMeters: 12,
                  isOutsideCambodia: false,
                ),
              ),
              geocodingService: _FakeGeocodingService(
                const GeocodedPlace(
                  roadName: 'Street 1986',
                  sangkat: 'Phnom Penh Thmei',
                  khan: 'Sen Sok',
                  village: 'Phum Bayab',
                  displayName: 'Phum Bayab, Sen Sok, Phnom Penh',
                  countryCode: 'kh',
                ),
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('add-comment-btn')),
          250,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-comment-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('add-comment-field')),
          'Traffic backing up from nearby village',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit-comment-btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('remote-support-reason-sheet')),
          findsNothing,
        );
        final remoteComment = remoteRepo
            .findById('#SC-20524')!
            .effectiveComments
            .last;
        expect(
          remoteComment.supportTier,
          equals(SupportVerificationTier.remoteVillage),
        );
        expect(find.text('Remote · Phum Bayab'), findsOneWidget);
      },
    );

    testWidgets(
      'R3: Normal MapPage hides resolved #SC-20290 while MapPage(focusedReportId: #SC-20290) isolates green ✓ pin & auto-opens bottom sheet',
      (tester) async {
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );

        // 1. Normal MapPage: All (17) instead of 18, #SC-20290 hidden, Phnom Penh province count = 12
        await tester.pumpWidget(_wrapWithScope(repo, const MapPage()));
        await tester.pump();
        expect(find.text('All (17)'), findsOneWidget);
        expect(find.text('#SC-20290'), findsNothing);
        expect(find.text('✓'), findsNothing);

        await tester.tap(find.byKey(const Key('map-province-filter-btn')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('map-jump-province-phnom_penh')),
            matching: find.text('12'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('map-jump-all-cambodia')));
        await tester.pumpAndSettle();

        // 2. Focused resolved MapPage(#SC-20290): ONLY green ✓ pin + auto-opened bottom sheet
        await tester.pumpWidget(
          _wrapWithScope(
            repo,
            const MapPage(
              key: ValueKey('focused-resolved-map'),
              focusedReportId: '#SC-20290',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('map-focused-resolved-pill')),
          findsOneWidget,
        );
        expect(find.text('All (17)'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(MarkerLayer),
            matching: find.text('✓'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(MarkerLayer),
            matching: find.text('P5'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(MarkerLayer),
            matching: find.text('P4'),
          ),
          findsNothing,
        );
        expect(
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
          equals(1),
        );
        expect(
          find.byKey(const Key('map-sheet-resolved-badge')),
          findsOneWidget,
        );
        expect(find.text('#SC-20290'), findsWidgets);
        expect(find.text('Track Repair'), findsOneWidget);
      },
    );

    testWidgets(
      'R3: AlertDetailPage (active & resolved) and TrackingPage._buildResolvedView display View location on map and open focused MapPage',
      (tester) async {
        tester.view.physicalSize = const Size(390 * 2, 844 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );

        // 1. AlertDetailPage for active report (#SC-20481)
        final activeAlert = repo.alerts.firstWhere(
          (a) => a.reportId == '#SC-20481',
        );
        await tester.pumpWidget(
          _wrapWithScope(repo, AlertDetailPage(alert: activeAlert)),
        );
        await tester.pumpAndSettle();
        final activeMapBtn = find.byKey(const Key('alert-detail-view-map-btn'));
        await tester.scrollUntilVisible(activeMapBtn, 150);
        await tester.pumpAndSettle();
        expect(find.text('View location on map'), findsOneWidget);

        // 2. AlertDetailPage for resolved report (#SC-20290) -> pushes focused MapPage
        final resolvedAlert = repo.alerts.firstWhere(
          (a) => a.reportId == '#SC-20290',
        );
        await tester.pumpWidget(
          _wrapWithScope(
            repo,
            AlertDetailPage(
              key: const ValueKey('resolved-alert-detail'),
              alert: resolvedAlert,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final resolvedAlertMapBtn = find.byKey(
          const Key('alert-detail-view-map-btn'),
        );
        await tester.scrollUntilVisible(resolvedAlertMapBtn, 150);
        await tester.pumpAndSettle();
        await tester.tap(resolvedAlertMapBtn);
        await tester.pumpAndSettle();

        expect(find.byType(MapPage), findsOneWidget);
        expect(
          find.byKey(const Key('map-focused-resolved-pill')),
          findsOneWidget,
        );
        expect(find.text('✓'), findsOneWidget);

        // 3. TrackingPage._buildResolvedView (#SC-20290) at 390px -> View location on map
        await tester.pumpWidget(
          ReportScope(
            key: const ValueKey('resolved-tracking-view-map-scope'),
            repository: repo,
            child: MaterialApp(
              theme: buildSrolanhCityTheme(),
              home: const TrackingPage(reportId: '#SC-20290'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final trackingMapBtn = find.byKey(const Key('resolved-view-map-btn'));
        expect(trackingMapBtn, findsOneWidget);
        expect(find.text('View location on map'), findsOneWidget);
        await tester.tap(trackingMapBtn);
        await tester.pumpAndSettle();
        expect(find.byType(MapPage), findsOneWidget);
        expect(
          find.byKey(const Key('map-focused-resolved-pill')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'R4: AlertsPage supports >= 48dp accessible delete button, Dismissible swipe, Undo, Clear read/all & WCAG 2.1 AA without deleting CivicReports',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        final initialReportCount = repo.reports.length;
        final initialAlerts = repo.alerts.toList();
        final firstAlert = initialAlerts.first;
        final secondAlert = initialAlerts[1];

        await tester.pumpWidget(
          _wrapWithScope(repo, const Scaffold(body: AlertsPage())),
        );
        await tester.pumpAndSettle();

        // Check >= 48dp accessible delete button & WCAG 2.1 AA guidelines
        final deleteBtn = find.byKey(Key('delete-alert-${firstAlert.id}'));
        expect(deleteBtn, findsOneWidget);
        final btnSize = tester.getSize(deleteBtn);
        expect(btnSize.width, greaterThanOrEqualTo(48));
        expect(btnSize.height, greaterThanOrEqualTo(48));

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // 1. Delete via icon button + Undo restores
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();
        expect(repo.alerts.length, equals(initialAlerts.length - 1));
        expect(repo.reports.length, equals(initialReportCount));
        expect(repo.findById(firstAlert.reportId), isNotNull);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(repo.alerts.length, equals(initialAlerts.length));

        // 2. Swipe-to-delete via Dismissible + Undo restores
        await tester.drag(
          find.byKey(ValueKey('alert-dismissible-${secondAlert.id}')),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();
        expect(repo.alerts.length, equals(initialAlerts.length - 1));
        expect(repo.reports.length, equals(initialReportCount));
        expect(repo.findById(secondAlert.reportId), isNotNull);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(repo.alerts.length, equals(initialAlerts.length));

        // 3. Clear read removes only read alerts
        repo.markAlertRead(firstAlert.id);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('alerts-clear-read-btn')));
        await tester.pumpAndSettle();
        expect(repo.alerts.any((a) => a.isRead), isFalse);
        expect(repo.reports.length, equals(initialReportCount));

        // 4. Clear all clears remaining alerts without touching reports
        await tester.tap(find.byKey(const Key('alerts-clear-all-btn')));
        await tester.pumpAndSettle();
        expect(repo.alerts, isEmpty);
        expect(repo.reports.length, equals(initialReportCount));
        handle.dispose();
      },
    );

    testWidgets(
      'R4: AlertDetailPage >= 48dp delete button deletes alert, pops to AlertsPage, preserves CivicReport, and supports Undo',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = ReportRepository(
          initialSettings: const AppSettings(englishFirst: true),
        );
        final initialReportCount = repo.reports.length;
        final initialAlerts = repo.alerts.length;
        final targetAlert = repo.alerts.first;

        await tester.pumpWidget(
          _wrapWithScope(repo, const Scaffold(body: AlertsPage())),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(targetAlert.englishTitle));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDetailPage), findsOneWidget);

        final detailDeleteBtn = find.byKey(
          const Key('alert-detail-delete-btn'),
        );
        final size = tester.getSize(detailDeleteBtn);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.tap(detailDeleteBtn);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDetailPage), findsNothing);
        expect(repo.alerts.length, equals(initialAlerts - 1));
        expect(repo.reports.length, equals(initialReportCount));
        expect(repo.findById(targetAlert.reportId), isNotNull);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(repo.alerts.length, equals(initialAlerts));
        handle.dispose();
      },
    );
  });

  group('AuthPage & Guest Sign-In', () {
    testWidgets(
      'WelcomePage opens AuthPage and Continue as Guest enters MainShell',
      (tester) async {
        final repo = ReportRepository();
        await tester.pumpWidget(SrolanhCityApp(repository: repo));
        await tester.pumpAndSettle();

        final signInBtn = find.byKey(const Key('welcome-sign-in-btn'));
        await tester.ensureVisible(signInBtn);
        await tester.tap(signInBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth-guest-btn')), findsOneWidget);
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
        await tester.ensureVisible(find.byKey(const Key('auth-guest-btn')));
        await tester.tap(find.byKey(const Key('auth-guest-btn')));
        await tester.pumpAndSettle();

        expect(find.byType(MainShell), findsOneWidget);
      },
    );

    testWidgets(
      'AuthPage phone + OTP flow updates UserProfile and enters MainShell',
      (tester) async {
        final repo = ReportRepository();
        await tester.pumpWidget(SrolanhCityApp(repository: repo));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('welcome-sign-in-btn')),
        );
        await tester.tap(find.byKey(const Key('welcome-sign-in-btn')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('auth-phone-field')),
          '012 888 999',
        );
        await tester.enterText(
          find.byKey(const Key('auth-name-field')),
          'Dara Sok',
        );
        await tester.tap(find.byKey(const Key('auth-submit-btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth-otp-field')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('auth-otp-field')),
          '123456',
        );
        await tester.tap(find.byKey(const Key('auth-submit-btn')));
        await tester.pumpAndSettle();

        expect(find.byType(MainShell), findsOneWidget);
        expect(repo.profile.phoneNumber, equals('012 888 999'));
        expect(repo.profile.englishName, equals('Dara Sok'));
      },
    );

    testWidgets(
      'OfflineSyncBanner shows AI-rejection banner, opens TrackingPage on Review, and deletes rejected report',
      (tester) async {
        final rejected = CivicReport(
          id: '#SC-REJ1',
          category: IssueCategory.trash,
          khmerTitle: 'សំរាមខុសច្បាប់',
          englishTitle: 'Illegal Waste',
          description: 'Backyard photo',
          khmerLocation: 'ភ្នំពេញ',
          englishLocation: 'Phnom Penh',
          coordinates: const LatLng(11.5564, 104.9282),
          roadClass: RoadClass.alley,
          severity: 2,
          affectedCitizens: 1,
          status: ReportStatus.submitted,
          khmerAgency: 'PPCH',
          englishAgency: 'PPCH',
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          timeline: const [],
          createdByCurrentUser: true,
          isMine: true,
          syncStatus: SyncStatus.rejectedByAi,
          aiRejectionReasonEnglish:
              'Private backyard photo, not a public issue.',
        );
        final repo = ReportRepository(
          initialReports: [rejected],
          initialSettings: const AppSettings(englishFirst: true),
        );

        await tester.pumpWidget(
          ReportScope(
            repository: repo,
            child: const MaterialApp(home: MainShell()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('banner-review-rejected-btn')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('banner-review-rejected-btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('tracking-rejected-by-ai-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('rejected-delete-and-rereport-btn')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('rejected-delete-btn')));
        await tester.pumpAndSettle();

        expect(repo.findById('#SC-REJ1'), isNull);
        expect(
          find.byKey(const Key('banner-review-rejected-btn')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'HomePage shows multi-drafts, OfflineSyncBanner shows Resume CTA online, and Step 3 renders saved draft pins',
      (tester) async {
        final d1 = ReportDraft(
          id: 'd-one',
          category: IssueCategory.pothole,
          severity: 3,
          description: 'Corner pothole',
          isAnonymous: false,
          localPhotoPaths: const [],
          pinLat: 11.5564,
          pinLng: 104.9282,
        );
        final d2 = ReportDraft(
          id: 'd-two',
          category: IssueCategory.drain,
          severity: 4,
          description: 'Flooded drain',
          isAnonymous: false,
          localPhotoPaths: const [],
          pinLat: 11.5570,
          pinLng: 104.9290,
        );
        final repo = ReportRepository(
          initialReports: const [],
          initialSettings: const AppSettings(englishFirst: true),
        );
        repo.saveDraft(d1);
        repo.saveDraft(d2);

        await tester.pumpWidget(
          ReportScope(
            repository: repo,
            child: const MaterialApp(home: MainShell()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('banner-resume-draft-btn')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('home-draft-card-d-one')), findsOneWidget);
        expect(find.byKey(const Key('home-draft-card-d-two')), findsOneWidget);

        // Discard d-two leaves d-one intact.
        await tester.tap(find.byKey(const Key('home-draft-discard-d-two')));
        await tester.pumpAndSettle();
        expect(repo.draftCount, equals(1));
        expect(find.byKey(const Key('home-draft-card-d-one')), findsOneWidget);
        expect(find.byKey(const Key('home-draft-card-d-two')), findsNothing);

        // Open another wizard with a photo draft -> advance Step 2 -> Step 3 and verify d-one pin renders.
        final activeDraft = ReportDraft(
          id: 'd-current',
          category: IssueCategory.pothole,
          severity: 3,
          description: 'Current offline spot',
          isAnonymous: false,
          localPhotoPaths: const ['sample-photo.jpg'],
          photoAnchorLat: 11.55645,
          photoAnchorLng: 104.92825,
          photoAnchorSource: 'liveCameraCapture',
          photoAnchorCapturedAt: DateTime.now(),
        );
        await tester.pumpWidget(
          ReportScope(
            repository: repo,
            child: MaterialApp(
              home: ReportWizardPage(
                initialDraft: activeDraft,
                locationService: const _FakeLocationService(
                  LocationSuccess(
                    point: LatLng(11.55645, 104.92825),
                    accuracyMeters: 10,
                    isOutsideCambodia: false,
                  ),
                ),
                civicAiService: _UnconfiguredTestAiService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('step2-confirm-location-btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('step3-draft-pins-legend')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('step3-draft-pin-d-one')), findsOneWidget);
        expect(
          find.byKey(const Key('step3-nearby-draft-warning')),
          findsOneWidget,
        );
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

class _FakeGeocodingService extends ReverseGeocodingService {
  _FakeGeocodingService(this.place);

  final GeocodedPlace? place;

  @override
  Future<GeocodedPlace?> reverseGeocode(LatLng point) async => place;
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
  Future<bool> startRecording() async => true;

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

class _WidgetFakeTranslator implements CommentTranslationService {
  @override
  Future<String?> translate({
    required String text,
    required String targetLang,
  }) async => targetLang == 'km' ? 'ការបកប្រែជាភាសាខ្មែរ' : 'Translated EN';
}
