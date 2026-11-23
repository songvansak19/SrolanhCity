import 'package:material_ui/material_ui.dart';

import '../../../core/l10n.dart';
import '../../../core/report_scope.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/bilingual_text.dart';

/// Screen 2.4 / Slide 06: Fake GPS & Mock Location Blocked Screen.
class FakeGpsPage extends StatefulWidget {
  const FakeGpsPage({
    super.key,
    required this.onOpenSettings,
    required this.onTryAgain,
    this.detectedAppLabel = 'Mock GPS / Spoofing Provider',
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onTryAgain;
  final String detectedAppLabel;

  @override
  State<FakeGpsPage> createState() => _FakeGpsPageState();
}

class _FakeGpsPageState extends State<FakeGpsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 26),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              final scale =
                                  1.0 + (_pulseController.value * 0.14);
                              return SizedBox(
                                width: 126,
                                height: 126,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Transform.scale(
                                      scale: scale,
                                      child: Container(
                                        width: 108,
                                        height: 108,
                                        decoration: BoxDecoration(
                                          color: AppColors.danger.withValues(
                                            alpha: 0.18,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    child!,
                                  ],
                                ),
                              );
                            },
                            child: Container(
                              width: 92,
                              height: 92,
                              decoration: const BoxDecoration(
                                color: AppColors.dangerSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.gpp_bad_outlined,
                                color: AppColors.danger,
                                size: 46,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          BilingualText(
                            bilingual: tr,
                            khmer: 'រកឃើញទីតាំងក្លែងក្លាយ',
                            english: 'Fake location detected',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            tr.primary(
                              'សូមបិទកម្មវិធីប្តូរទីតាំង (Mock location) មុនពេលរាយការណ៍ ដើម្បីធានាថាទិន្នន័យពិតប្រាកដ និងក្រុមជួសជុលទៅដល់ទីតាំងត្រឹមត្រូវ។',
                              'Please turn off mock-location or GPS spoofing apps before reporting. This keeps civic data honest and crews focused on real problems.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.mutedSurface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 18,
                                      color: AppColors.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${widget.detectedAppLabel} · ${tr.paired('កំពុងដំណើរការ', 'running')}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.my_location_outlined,
                                      size: 18,
                                      color: AppColors.muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        tr.paired(
                                          'ការអនុញ្ញាតទីតាំង',
                                          'Location permission',
                                        ),
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: widget.onOpenSettings,
                      child: Text(tr.paired('បើកការកំណត់', 'Open settings')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: widget.onTryAgain,
                      child: Text(tr.paired('ព្យាយាមម្តងទៀត', 'Try again')),
                    ),
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
