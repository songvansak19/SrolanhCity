import 'package:material_ui/material_ui.dart';

import '../l10n.dart';
import '../theme.dart';

/// Signature SrolanhCity stacked bilingual typography:
/// Primary language on top, secondary language underneath at 72% size and
/// WCAG-AA-safe 80% opacity (honoring the user's Khmer-First / English-First
/// setting).
class BilingualText extends StatelessWidget {
  const BilingualText({
    super.key,
    required this.bilingual,
    required this.khmer,
    required this.english,
    this.fontSize = 15,
    this.fontWeight = FontWeight.w700,
    this.color = AppColors.ink,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.textAlign = TextAlign.start,
    this.maxLines = 2,
    this.useDisplayFont = false,
    this.isHeader = false,
  });

  final Bilingual bilingual;
  final String khmer;
  final String english;
  final double fontSize;
  final FontWeight fontWeight;
  final Color color;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign textAlign;
  final int maxLines;
  final bool useDisplayFont;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final primaryText = bilingual.primary(khmer, english);
    final secondaryText = bilingual.secondary(khmer, english);

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          primaryText,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: useDisplayFont ? AppFonts.display : AppFonts.body,
            fontFamilyFallback: const [AppFonts.body],
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          secondaryText,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: (fontSize * 0.72).clamp(10.0, 16.0),
            fontWeight: FontWeight.w400,
            color: color.withValues(alpha: 0.80),
            height: 1.25,
          ),
        ),
      ],
    );

    if (!isHeader) return column;
    return Semantics(header: true, child: column);
  }
}
