import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Animated 5-bar waveform visualizer displayed while recording Khmer/English
/// voice notes, optionally boosted by real microphone [soundLevel] (`0.0..1.0`).
/// Respects OS reduced-motion preferences and excludes decorative bars from
/// assistive technologies.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    this.color = AppColors.danger,
    this.height = 24,
    this.soundLevel,
  });

  final Color color;
  final double height;
  final double? soundLevel;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 0.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = reduceMotion ? 0.0 : _controller.value * 2 * math.pi;
          final boost = widget.soundLevel != null
              ? (0.55 + widget.soundLevel!.clamp(0.0, 1.0) * 0.45)
              : 1.0;
          return SizedBox(
            height: widget.height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(5, (index) {
                final phase = index * 0.9;
                final wave = reduceMotion
                    ? const [0.35, 0.75, 1.0, 0.75, 0.35][index]
                    : (math.sin(t + phase) + 1) / 2;
                final barHeight = (6 + wave * (widget.height - 6) * boost)
                    .clamp(5.0, widget.height);
                return Container(
                  width: 3.5,
                  height: barHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 1.8),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
