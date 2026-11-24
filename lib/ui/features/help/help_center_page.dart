import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/services/help_assistant_service.dart';
import '../../core/assistant/assistant_bubble_suppressor.dart';
import '../../core/assistant/assistant_scope.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/motion.dart';
import 'assistant_actions.dart';
import 'assistant_chat_view.dart';
import 'help_chat_controller.dart';

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
  HelpChatController? _localController;
  HelpChatController? _activeController;
  final Set<String> _expandedFaqIds = <String>{'faq-how-to-report'};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = widget.assistantService == null
        ? AssistantScope.maybeRead(context)?.chatController
        : null;
    if (shared != null) {
      _activeController = shared;
    } else {
      _localController ??= HelpChatController(
        assistant: widget.assistantService,
      );
      _activeController = _localController;
    }
    _activeController?.markRead();
  }

  @override
  void dispose() {
    _localController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final settings = repo.settings;
    final tr = Bilingual(settings.englishFirst);
    final chatController = _activeController!;
    final isAiBackendLive =
        repo.isOnline && chatController.isBackendAiConfigured;

    return AssistantBubbleSuppressor(
      child: Scaffold(
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
          actions: [
            if (!settings.assistantBubbleEnabled)
              TextButton.icon(
                key: const Key('help-show-bubble-action'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  repo.updateSettings(
                    settings.copyWith(assistantBubbleEnabled: true),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        tr.primary(
                          'បានបើកប៊ូតុងជំនួយការ AI ឡើងវិញ',
                          'Floating AI assistant bubble enabled',
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.support_agent_rounded, size: 18),
                label: Text(
                  tr.primary('បង្ហាញប៊ូតុង AI', 'Show bubble'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
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
                          onTap: () => AssistantActions.callHotline(
                            number: '1190',
                            khmerName: 'ខ្សែទូរស័ព្ទផ្លូវ (MPWT)',
                            englishName: 'MPWT Road Hotline',
                            tr: tr,
                            messenger: ScaffoldMessenger.maybeOf(context),
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
                          onTap: () => AssistantActions.callHotline(
                            number: '1298',
                            khmerName: 'អគ្គិសនីកម្ពុជា (EDC)',
                            englishName: 'EDC Power Hotline',
                            tr: tr,
                            messenger: ScaffoldMessenger.maybeOf(context),
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
                          onTap: () => AssistantActions.callHotline(
                            number: '117',
                            khmerName: 'ប៉ូលិស និងជំនួយបន្ទាន់',
                            englishName: 'National Emergency',
                            tr: tr,
                            messenger: ScaffoldMessenger.maybeOf(context),
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
                        AssistantChatView(controller: chatController),
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
