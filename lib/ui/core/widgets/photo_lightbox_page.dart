import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../assistant/assistant_bubble_suppressor.dart';
import '../l10n.dart';
import 'report_photo.dart';

/// Full-screen pinch-to-zoom photo lightbox (`InteractiveViewer`) with
/// optional Hero transition and EXIF-stripped privacy indicator.
class PhotoLightboxPage extends StatelessWidget {
  const PhotoLightboxPage({
    super.key,
    required this.category,
    required this.bilingual,
    this.localPhotoPath,
    this.assetPath,
    this.title,
    this.subtitle,
    this.heroTag,
    this.showExifBadge = true,
  });

  final IssueCategory category;
  final Bilingual bilingual;
  final String? localPhotoPath;
  final String? assetPath;
  final String? title;
  final String? subtitle;
  final Object? heroTag;
  final bool showExifBadge;

  static Future<void> open(
    BuildContext context, {
    required IssueCategory category,
    required Bilingual bilingual,
    String? localPhotoPath,
    String? assetPath,
    String? title,
    String? subtitle,
    Object? heroTag,
    bool showExifBadge = true,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoLightboxPage(
          category: category,
          bilingual: bilingual,
          localPhotoPath: localPhotoPath,
          assetPath: assetPath,
          title: title,
          subtitle: subtitle,
          heroTag: heroTag,
          showExifBadge: showExifBadge,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget photo = ReportPhoto(
      category: category,
      localPhotoPath: localPhotoPath,
      assetPath: assetPath,
      borderRadius: 16,
      showExifBadge: showExifBadge,
      bilingual: bilingual,
    );

    if (heroTag != null) {
      photo = Hero(tag: heroTag!, child: photo);
    }

    return AssistantBubbleSuppressor(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: title == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
          ),
          body: SafeArea(
            child: Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AspectRatio(aspectRatio: 4 / 3, child: photo),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
