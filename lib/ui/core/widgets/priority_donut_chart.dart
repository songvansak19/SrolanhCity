import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../theme.dart';

/// Donut ring visualizing the weighted Priority Score model from Slide 07:
/// Traffic Volume (40%), Severity & Accident Risk (30%), Report Volume (30%).
class PriorityDonutChart extends StatelessWidget {
  const PriorityDonutChart({
    super.key,
    required this.breakdown,
    this.size = 92,
  });

  final PriorityBreakdown breakdown;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'P${breakdown.level} ${breakdown.rawScore.toStringAsFixed(1)}/5.0',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DonutPainter(
            trafficFraction: 0.40 * (breakdown.trafficScore / 5),
            severityFraction: 0.30 * (breakdown.severityScore / 5),
            reportsFraction: 0.30 * (breakdown.reportCountScore / 5),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(size * 0.2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      breakdown.rawScore.toStringAsFixed(1),
                      style: AppFonts.displayStyle(
                        fontSize: size * 0.22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      '/5.0',
                      style: AppFonts.displayStyle(
                        fontSize: size * 0.12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.trafficFraction,
    required this.severityFraction,
    required this.reportsFraction,
  });

  final double trafficFraction;
  final double severityFraction;
  final double reportsFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.16;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.width - strokeWidth) / 2,
    );

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = AppColors.mutedSurface;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    // Draw proportional 40% / 30% / 30% segments with clean white gap.
    const startOffset = -math.pi / 2;
    const gap = 0.06;

    final segments = [
      (0.40, AppColors.teal, trafficFraction / 0.40),
      (0.30, AppColors.saffron, severityFraction / 0.30),
      (0.30, const Color(0xFF499D90), reportsFraction / 0.30),
    ];

    var cursor = startOffset;
    for (final (weight, color, fillRatio) in segments) {
      final slotSweep = (math.pi * 2 * weight) - gap;
      final activeSweep = (slotSweep * fillRatio.clamp(0.1, 1.0));

      // Background faint track for slot
      final slotPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = color.withValues(alpha: 0.18);
      canvas.drawArc(rect, cursor, slotSweep, false, slotPaint);

      // Filled portion
      final activePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = color;
      canvas.drawArc(rect, cursor, activeSweep, false, activePaint);

      cursor += slotSweep + gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.trafficFraction != trafficFraction ||
      oldDelegate.severityFraction != severityFraction ||
      oldDelegate.reportsFraction != reportsFraction;
}
