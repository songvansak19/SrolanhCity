import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/services/civic_ai_service.dart';
import '../../core/l10n.dart';
import '../../core/widgets/motion.dart';
import '../profile/edit_profile_page.dart';
import '../profile/my_reports_page.dart';
import '../report/views/report_wizard_page.dart';
import '../tracking/tracking_page.dart';

/// Shared navigation & hotline helpers used by both [HelpCenterPage] and the
/// floating AI Assistant chat panel.
class AssistantActions {
  const AssistantActions._();

  static String actionLabel(
    HelpSuggestedAction action,
    String? reportId,
    Bilingual tr,
  ) => switch (action) {
    HelpSuggestedAction.openReportWizard => tr.primary(
      'ចាប់ផ្តើមរាយការណ៍',
      'Start Report',
    ),
    HelpSuggestedAction.openMyReports => tr.primary(
      'បើករបាយការណ៍ខ្ញុំ',
      'Open My Reports',
    ),
    HelpSuggestedAction.openTicket => tr.primary(
      'មើលសំបុត្រ ${reportId ?? ''}',
      'Open ${reportId ?? 'Ticket'}',
    ),
    HelpSuggestedAction.callRoadHotline1190 => tr.primary(
      'ហៅ 1190 (ផ្លូវ)',
      'Call 1190 (MPWT)',
    ),
    HelpSuggestedAction.callPowerHotline1298 => tr.primary(
      'ហៅ 1298 (EDC)',
      'Call 1298 (EDC)',
    ),
    HelpSuggestedAction.openEditProfile => tr.primary(
      'កែប្រែគណនី',
      'Edit Profile',
    ),
  };

  static Future<void> callHotline({
    required String number,
    required String khmerName,
    required String englishName,
    required Bilingual tr,
    ScaffoldMessengerState? messenger,
  }) async {
    HapticFeedback.selectionClick();
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched = await launchUrl(uri);
      if (!launched) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              tr.primary(
                'សូមហៅទៅ $khmerName៖ $number ដោយផ្ទាល់ពីទូរស័ព្ទអ្នក',
                'Dial $englishName ($number) directly from your phone.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr.primary('$khmerName៖ $number', '$englishName: $number'),
          ),
        ),
      );
    }
  }

  /// Runs a suggested assistant action using [navigator]. If [closePopupFirst]
  /// is true (e.g. triggered from the floating chat panel), dismisses the
  /// current popup route before pushing the destination page.
  static void runSuggestedAction({
    required NavigatorState navigator,
    required HelpSuggestedAction action,
    required Bilingual tr,
    String? reportId,
    ScaffoldMessengerState? messenger,
    bool closePopupFirst = false,
  }) {
    HapticFeedback.selectionClick();
    if (closePopupFirst && navigator.canPop()) {
      navigator.pop();
    }

    switch (action) {
      case HelpSuggestedAction.openReportWizard:
        navigator.push<void>(
          SrolanhSlideUpRoute<void>(builder: (_) => const ReportWizardPage()),
        );
      case HelpSuggestedAction.openMyReports:
        navigator.push<void>(
          MaterialPageRoute<void>(builder: (_) => const MyReportsPage()),
        );
      case HelpSuggestedAction.openTicket:
        if (reportId != null && reportId.isNotEmpty) {
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => TrackingPage(reportId: reportId),
            ),
          );
        }
      case HelpSuggestedAction.callRoadHotline1190:
        unawaited(
          callHotline(
            number: '1190',
            khmerName: 'ខ្សែទូរស័ព្ទបន្ទាន់ផ្លូវ (MPWT)',
            englishName: 'MPWT Road Hotline',
            tr: tr,
            messenger: messenger,
          ),
        );
      case HelpSuggestedAction.callPowerHotline1298:
        unawaited(
          callHotline(
            number: '1298',
            khmerName: 'ខ្សែទូរស័ព្ទអគ្គិសនីកម្ពុជា (EDC)',
            englishName: 'EDC Power Hotline',
            tr: tr,
            messenger: messenger,
          ),
        );
      case HelpSuggestedAction.openEditProfile:
        navigator.push<void>(
          MaterialPageRoute<void>(builder: (_) => const EditProfilePage()),
        );
    }
  }
}
