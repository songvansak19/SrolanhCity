import 'package:material_ui/material_ui.dart';

import '../../core/assistant/assistant_bubble_suppressor.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../shell/main_shell.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);

    return AssistantBubbleSuppressor(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxHeight < 650;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 44,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.language,
                                size: 16,
                                color: AppColors.teal,
                              ),
                              label: Text(
                                repo.settings.englishFirst
                                    ? 'EN · ខ្មែរ'
                                    : 'ខ្មែរ · EN',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              onPressed: () {
                                repo.updateSettings(
                                  repo.settings.copyWith(
                                    englishFirst: !repo.settings.englishFirst,
                                  ),
                                );
                              },
                            ),
                          ),
                          Column(
                            children: [
                              SizedBox(height: isCompact ? 4 : 12),
                              Image.asset(
                                'assets/srolanhcity-logo.png',
                                width: isCompact ? 132 : 240,
                                height: isCompact ? 132 : 240,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const CircleAvatar(
                                  radius: 52,
                                  backgroundColor: AppColors.tealSoft,
                                  child: Icon(
                                    Icons.location_city_rounded,
                                    size: 48,
                                    color: AppColors.teal,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                tr.primary(
                                  'ថតរូប · រាយការណ៍ · តាមដានការជួសជុល',
                                  'Snap · Report · Track Repairs',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                tr.primary(
                                  'AI ជួយកំណត់ប្រភេទបញ្ហា រាយការណ៍ទៅអាជ្ញាធរត្រឹមត្រូវ និងតាមដានការជួសជុលប្រកបដោយតម្លាភាព',
                                  'AI classifies road issues, routes directly to the right Phnom Penh authority, and tracks every repair with photo proof.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 14,
                                  height: 1.55,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  _FeaturePill(
                                    icon: Icons.auto_awesome,
                                    label: tr.primary(
                                      'AI បែងចែកអាជ្ញាធរ',
                                      'AI Auto-Routing',
                                    ),
                                  ),
                                  _FeaturePill(
                                    icon: Icons.mic_none_rounded,
                                    label: tr.primary(
                                      'រាយការណ៍ជាសំឡេងខ្មែរ',
                                      'Khmer Voice Note',
                                    ),
                                  ),
                                  _FeaturePill(
                                    icon: Icons.shield_outlined,
                                    label: tr.primary(
                                      'ឯកជនភាពជាអាទិភាព',
                                      'Privacy-by-Design',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              SizedBox(height: isCompact ? 14 : 28),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: FilledButton(
                                  onPressed: () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => const MainShell(),
                                    ),
                                  ),
                                  child: Text(
                                    tr.primary('ចាប់ផ្តើម', 'Get started'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                tr.primary(
                                  'រៀបចំសម្រាប់ប្រជាពលរដ្ឋកម្ពុជា',
                                  'Built for Cambodian Citizens · SrolanhCity',
                                ),
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.teal),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.tealDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
