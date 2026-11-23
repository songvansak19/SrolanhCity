import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../l10n.dart';
import '../theme.dart';
import 'platform_image.dart';

/// Renders a report photo from a user-captured file, a bundled asset, or a
/// clean vector placeholder when no photo asset exists for a category.
class ReportPhoto extends StatelessWidget {
  const ReportPhoto({
    super.key,
    required this.category,
    this.localPhotoPath,
    this.assetPath,
    this.width,
    this.height,
    this.borderRadius = 14,
    this.showExifBadge = false,
    this.bilingual,
  });

  final IssueCategory category;
  final String? localPhotoPath;
  final String? assetPath;
  final double? width;
  final double? height;
  final double borderRadius;
  final bool showExifBadge;
  final Bilingual? bilingual;

  @override
  Widget build(BuildContext context) {
    final effectiveAsset = (assetPath != null && assetPath!.isNotEmpty)
        ? assetPath
        : category.defaultAssetPath;
    Widget imageWidget;
    if (localPhotoPath != null && localPhotoPath!.isNotEmpty) {
      imageWidget = buildLocalImageWidget(
        path: localPhotoPath!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => effectiveAsset != null
            ? Image.asset(
                effectiveAsset,
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(),
              )
            : _placeholder(),
      );
    } else if (effectiveAsset != null && effectiveAsset.isNotEmpty) {
      imageWidget = Image.asset(
        effectiveAsset,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else {
      imageWidget = _placeholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          imageWidget,
          if (showExifBadge)
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 13,
                      color: Color(0xFF7BE4D8),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      bilingual?.primary(
                            'លុប EXIF ស្វ័យប្រវត្តិ',
                            'EXIF Stripped',
                          ) ??
                          'EXIF Stripped',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE7F2F0), Color(0xFFD5EAE6)],
        ),
      ),
      child: Center(
        child: Icon(
          Bilingual.categoryIcon(category),
          size: (height != null && height! < 90) ? 28 : 48,
          color: AppColors.teal,
        ),
      ),
    );
  }
}
