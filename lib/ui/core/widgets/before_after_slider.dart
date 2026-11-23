import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../theme.dart';
import 'report_photo.dart';

/// Interactive draggable Before & After split-screen photo comparison widget.
class BeforeAfterSlider extends StatefulWidget {
  const BeforeAfterSlider({
    super.key,
    required this.category,
    required this.beforeLabel,
    required this.afterLabel,
    required this.beforeDate,
    required this.afterDate,
    this.beforeLocalPath,
    this.beforeAssetPath,
    this.afterAssetPath,
    this.height = 240,
  });

  final IssueCategory category;
  final String beforeLabel;
  final String afterLabel;
  final String beforeDate;
  final String afterDate;
  final String? beforeLocalPath;
  final String? beforeAssetPath;
  final String? afterAssetPath;
  final double height;

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _position = 0.5;

  void _updateFromLocalX(double localX, double width) {
    if (width <= 0) return;
    final next = (localX / width).clamp(0.08, 0.92);
    if ((next - _position).abs() > 0.002) {
      setState(() => _position = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.beforeLabel} / ${widget.afterLabel} comparison slider',
      slider: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final dividerX = width * _position;

          return GestureDetector(
            key: const Key('before-after-slider'),
            onHorizontalDragStart: (_) => HapticFeedback.selectionClick(),
            onHorizontalDragUpdate: (details) =>
                _updateFromLocalX(details.localPosition.dx, width),
            onTapDown: (details) {
              HapticFeedback.selectionClick();
              _updateFromLocalX(details.localPosition.dx, width);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: widget.height,
                width: width,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Right / Underlying: AFTER photo
                    ReportPhoto(
                      category: widget.category,
                      assetPath:
                          widget.afterAssetPath ?? 'assets/pothole-after.jpg',
                      width: width,
                      height: widget.height,
                      borderRadius: 0,
                    ),

                    // Left / Clipped: BEFORE photo
                    ClipRect(
                      clipper: _LeftSplitClipper(_position),
                      child: ReportPhoto(
                        category: widget.category,
                        localPhotoPath: widget.beforeLocalPath,
                        assetPath: widget.beforeAssetPath,
                        width: width,
                        height: widget.height,
                        borderRadius: 0,
                      ),
                    ),

                    // Top Left Before pill
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _PillBadge(label: widget.beforeLabel),
                    ),
                    // Top Right After pill
                    Positioned(
                      right: 12,
                      top: 12,
                      child: _PillBadge(label: widget.afterLabel),
                    ),
                    // Bottom Dates
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: _DarkPill(label: widget.beforeDate),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _DarkPill(label: widget.afterDate),
                    ),

                    // Vertical Divider Line
                    Positioned(
                      left: dividerX - 1.5,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 3, color: Colors.white),
                    ),

                    // Draggable Center Handle
                    Positioned(
                      left: dividerX - 20,
                      top: (widget.height / 2) - 20,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.teal, width: 2.2),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: const Icon(
                          Icons.compare_arrows_rounded,
                          color: AppColors.teal,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LeftSplitClipper extends CustomClipper<Rect> {
  const _LeftSplitClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftSplitClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppColors.cardShadow,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.device.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
