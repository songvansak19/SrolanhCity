import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/services/civic_ai_service.dart';
import '../../../domain/services/help_assistant_service.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/motion.dart';
import '../profile/edit_profile_page.dart';
import '../profile/my_reports_page.dart';
import '../report/views/report_wizard_page.dart';
import '../tracking/tracking_page.dart';

class _HelpMessage {
  const _HelpMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.fromBackendAi = false,
    this.suggestedAction,
    this.referencedReportId,
  });

  final String id;
  final bool isUser;
  final String text;
  final bool fromBackendAi;
  final HelpSuggestedAction? suggestedAction;
  final String? referencedReportId;
}

/// Full bilingual SrolanhCity Help Center with Cambodian ministry hotlines,
/// Hybrid AI Civic Assistant (live ticket lookup + backend LLM ready), and
/// expandable FAQs.
class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key, this.assistantService});

  final HelpAssistantService? assistantService;

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  late final HelpAssistantService _assistant =
      widget.assistantService ?? HelpAssistantService();
  late final TextEditingController _inputController;
  final List<_HelpMessage> _messages = <_HelpMessage>[];
  final Set<String> _expandedFaqIds = <String>{'faq-how-to-report'};
  bool _isThinking = false;
  bool _seededGreeting = false;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_seededGreeting) {
      final repo = ReportScope.read(context);
      final tr = Bilingual(repo.settings.englishFirst);
      _messages.add(
        _HelpMessage(
          id: 'welcome',
          isUser: false,
          text: tr.primary(
            'សួស្តី! ខ្ញុំជាជំនួយការ SrolanhCity។ អ្នកអាចសួរអំពីការរាយការណ៍ ពិន្ទុអាទិភាព P1–P5 ការប្រើប្រាស់ក្រៅបណ្តាញ ឬវាយលេខសំបុត្រដូចជា #SC-20481។',
            'Hello! I am the SrolanhCity Civic Assistant. Ask about reporting issues, Priority P1–P5, offline sync, ministries, or type a ticket ID like #SC-20481.',
          ),
        ),
      );
      _seededGreeting = true;
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _callHotline(
    String number,
    String khmerName,
    String englishName,
    Bilingual tr,
  ) async {
    HapticFeedback.selectionClick();
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary('$khmerName៖ $number', '$englishName: $number'),
          ),
        ),
      );
    }
  }

  Future<void> _sendQuestion(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _isThinking) return;
    HapticFeedback.selectionClick();
    _inputController.clear();

    final repo = ReportScope.read(context);
    final history = _messages
        .map(
          (m) =>
              HelpChatTurn(role: m.isUser ? 'user' : 'assistant', text: m.text),
        )
        .toList(growable: false);

    setState(() {
      _messages.add(
        _HelpMessage(
          id: 'u-${DateTime.now().microsecondsSinceEpoch}',
          isUser: true,
          text: text,
        ),
      );
      _isThinking = true;
    });

    final reply = await _assistant.respond(
      message: text,
      history: history,
      repository: repo,
      englishFirst: repo.settings.englishFirst,
    );

    if (!mounted) return;
    setState(() {
      _isThinking = false;
      _messages.add(
        _HelpMessage(
          id: 'a-${DateTime.now().microsecondsSinceEpoch}',
          isUser: false,
          text: reply.text,
          fromBackendAi: reply.fromBackendAi,
          suggestedAction: reply.suggestedAction,
          referencedReportId: reply.referencedReportId,
        ),
      );
    });
  }

  void _runSuggestedAction(
    HelpSuggestedAction action,
    String? reportId,
    Bilingual tr,
  ) {
    HapticFeedback.selectionClick();
    switch (action) {
      case HelpSuggestedAction.openReportWizard:
        Navigator.push<void>(
          context,
          SrolanhSlideUpRoute<void>(builder: (_) => const ReportWizardPage()),
        );
      case HelpSuggestedAction.openMyReports:
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const MyReportsPage()),
        );
      case HelpSuggestedAction.openTicket:
        if (reportId != null && reportId.isNotEmpty) {
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => TrackingPage(reportId: reportId),
            ),
          );
        }
      case HelpSuggestedAction.callRoadHotline1190:
        unawaited(
          _callHotline(
            '1190',
            'ខ្សែទូរស័ព្ទបន្ទាន់ផ្លូវ (MPWT)',
            'MPWT Road Hotline',
            tr,
          ),
        );
      case HelpSuggestedAction.callPowerHotline1298:
        unawaited(
          _callHotline(
            '1298',
            'ខ្សែទូរស័ព្ទអគ្គិសនីកម្ពុជា (EDC)',
            'EDC Power Hotline',
            tr,
          ),
        );
      case HelpSuggestedAction.openEditProfile:
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const EditProfilePage()),
        );
    }
  }

  String _actionLabel(
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

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final isAiBackendLive = repo.isOnline && _assistant.isBackendAiConfigured;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr.primary('ត្រឡប់', 'Back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: BilingualText(
          bilingual: tr,
          khmer: 'មជ្ឈមណ្ឌលជំនួយ',
          english: 'Help Center',
          fontSize: 17,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                // 1. Emergency & Ministry Hotlines Strip
                BilingualText(
                  bilingual: tr,
                  khmer: 'ខ្សែទូរស័ព្ទបន្ទាន់ និងក្រសួង',
                  english: 'Emergency & Ministry Hotlines',
                  fontSize: 14.5,
                  isHeader: true,
                ),
                const SizedBox(height: 10),
                Row(
                  key: const Key('help-hotlines-strip'),
                  children: [
                    Expanded(
                      child: _HotlineCard(
                        key: const Key('hotline-1190'),
                        number: '1190',
                        khmerLabel: 'ផ្លូវ (MPWT)',
                        englishLabel: 'Roads (MPWT)',
                        icon: Icons.add_road_rounded,
                        color: AppColors.teal,
                        tr: tr,
                        onTap: () => _callHotline(
                          '1190',
                          'ខ្សែទូរស័ព្ទផ្លូវ (MPWT)',
                          'MPWT Road Hotline',
                          tr,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HotlineCard(
                        key: const Key('hotline-1298'),
                        number: '1298',
                        khmerLabel: 'ភ្លើង (EDC)',
                        englishLabel: 'Power (EDC)',
                        icon: Icons.bolt_rounded,
                        color: const Color(0xFFB54F00), // 4.86:1 on white
                        tr: tr,
                        onTap: () => _callHotline(
                          '1298',
                          'អគ្គិសនីកម្ពុជា (EDC)',
                          'EDC Power Hotline',
                          tr,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HotlineCard(
                        key: const Key('hotline-117'),
                        number: '117',
                        khmerLabel: 'បន្ទាន់ ២៤/៧',
                        englishLabel: 'Emergency',
                        icon: Icons.emergency_outlined,
                        color: AppColors.danger,
                        tr: tr,
                        onTap: () => _callHotline(
                          '117',
                          'ប៉ូលិស និងជំនួយបន្ទាន់',
                          'National Emergency',
                          tr,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 2. Interactive Hybrid AI Civic Assistant Card
                Container(
                  key: const Key('help-ai-chat'),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: AppColors.heroGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr.primary(
                                    'ជំនួយការឆ្លាតវៃ SrolanhCity',
                                    'SrolanhCity Smart Assistant',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  key: const Key('help-ai-mode-badge'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isAiBackendLive
                                        ? AppColors.tealSoft
                                        : AppColors.mutedSurface,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    isAiBackendLive
                                        ? tr.primary(
                                            'SrolanhCity AI · ផ្ទាល់',
                                            'SrolanhCity AI · Live',
                                          )
                                        : tr.primary(
                                            'ជំនួយការលើឧបករណ៍ · ប្រើក្រៅបណ្តាញបាន',
                                            'On-device Assistant · Offline-ready',
                                          ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isAiBackendLive
                                          ? AppColors.tealDark
                                          : AppColors.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Starter prompt chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final prompt
                                in HelpAssistantService.quickPrompts) ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  key: Key('help-prompt-${prompt.id}'),
                                  label: Text(
                                    tr.primary(
                                      prompt.khmerLabel,
                                      prompt.englishLabel,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () => _sendQuestion(
                                    tr.primary(
                                      prompt.khmerLabel,
                                      prompt.englishLabel,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Chat history
                      AnimatedSize(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final msg in _messages) ...[
                              _ChatBubble(
                                message: msg,
                                tr: tr,
                                actionLabel: msg.suggestedAction == null
                                    ? null
                                    : _actionLabel(
                                        msg.suggestedAction!,
                                        msg.referencedReportId,
                                        tr,
                                      ),
                                onAction: msg.suggestedAction == null
                                    ? null
                                    : () => _runSuggestedAction(
                                        msg.suggestedAction!,
                                        msg.referencedReportId,
                                        tr,
                                      ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_isThinking)
                              Semantics(
                                container: true,
                                liveRegion: true,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
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
                                      Text(
                                        tr.primary(
                                          'កំពុងរៀបចំចម្លើយ...',
                                          'Preparing answer...',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Chat composer
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('help-chat-input'),
                              controller: _inputController,
                              textInputAction: TextInputAction.send,
                              onSubmitted: _sendQuestion,
                              decoration: InputDecoration(
                                labelText: tr.primary(
                                  'សួរជំនួយការ',
                                  'Ask assistant',
                                ),
                                hintText: tr.primary(
                                  'សួរសំណួរ ឬវាយ #SC-20481...',
                                  'Ask a question or type #SC-20481...',
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: FilledButton(
                              key: const Key('help-chat-send-btn'),
                              onPressed: _isThinking
                                  ? null
                                  : () => _sendQuestion(_inputController.text),
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Tooltip(
                                message: tr.primary(
                                  'ផ្ញើសំណួរ',
                                  'Send question',
                                ),
                                child: const Icon(Icons.send_rounded, size: 19),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Bilingual FAQ Accordion
                BilingualText(
                  bilingual: tr,
                  khmer: 'សំណួរដែលសួរញឹកញាប់ (FAQ)',
                  english: 'Frequently Asked Questions',
                  fontSize: 15,
                  isHeader: true,
                ),
                const SizedBox(height: 10),
                Column(
                  key: const Key('help-faq-section'),
                  children: [
                    for (final faq in HelpAssistantService.faqs) ...[
                      _FaqTile(
                        faq: faq,
                        tr: tr,
                        expanded: _expandedFaqIds.contains(faq.id),
                        onToggle: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (_expandedFaqIds.contains(faq.id)) {
                              _expandedFaqIds.remove(faq.id);
                            } else {
                              _expandedFaqIds.add(faq.id);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HotlineCard extends StatelessWidget {
  const _HotlineCard({
    super.key,
    required this.number,
    required this.khmerLabel,
    required this.englishLabel,
    required this.icon,
    required this.color,
    required this.tr,
    required this.onTap,
  });

  final String number;
  final String khmerLabel;
  final String englishLabel;
  final IconData icon;
  final Color color;
  final Bilingual tr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${tr.primary(khmerLabel, englishLabel)} $number',
      child: PressableScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(
                  number,
                  style: AppFonts.displayStyle(fontSize: 17, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  tr.primary(khmerLabel, englishLabel),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.tr,
    this.actionLabel,
    this.onAction,
  });

  final _HelpMessage message;
  final Bilingual tr;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.teal : AppColors.paper,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && message.fromBackendAi) ...[
              Text(
                'SrolanhCity AI',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.teal.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              message.text.replaceAll('**', ''),
              style: TextStyle(
                fontSize: 12.8,
                height: 1.45,
                color: isUser ? Colors.white : AppColors.ink,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: const Size(48, 44),
                  side: BorderSide(
                    color: AppColors.teal.withValues(alpha: 0.5),
                  ),
                ),
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: AppColors.teal,
                ),
                label: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.tealDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (isUser) return bubble;
    return Semantics(container: true, liveRegion: true, child: bubble);
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.faq,
    required this.tr,
    required this.expanded,
    required this.onToggle,
  });

  final HelpFaqItem faq;
  final Bilingual tr;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      expanded: expanded,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: expanded
                ? AppColors.teal.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: InkWell(
          key: Key(faq.id),
          onTap: onToggle,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr.primary(faq.khmerQuestion, faq.englishQuestion),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0.0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.teal,
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            tr.primary(faq.khmerAnswer, faq.englishAnswer),
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: AppColors.muted,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
