import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../l10n.dart';
import '../theme.dart';

/// Solid-fill Ministry 1–5 Priority Pill matching the Lovable Style Guide.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({
    super.key,
    required this.breakdown,
    required this.bilingual,
    this.compact = false,
    this.showLabelBeside = false,
  });

  final PriorityBreakdown breakdown;
  final Bilingual bilingual;
  final bool compact;
  final bool showLabelBeside;

  @override
  Widget build(BuildContext context) {
    final fill = AppColors.priorityColor(breakdown.level);
    final fg = AppColors.priorityForeground(breakdown.level);

    final pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'P${breakdown.level}',
        style: AppFonts.displayStyle(
          color: fg,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final content = (compact && !showLabelBeside)
        ? pill
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              pill,
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  bilingual.paired(
                    breakdown.khmerLevelName,
                    breakdown.englishLevelName,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      excludeSemantics: true,
      label: bilingual.primary(
        'កម្រិតអាទិភាព P${breakdown.level} ${breakdown.khmerLevelName}',
        'Priority P${breakdown.level}, ${breakdown.englishLevelName}',
      ),
      child: content,
    );
  }
}
