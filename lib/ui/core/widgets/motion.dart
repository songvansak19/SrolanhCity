import 'package:material_ui/material_ui.dart';

/// App-wide subtle shared-axis slide + fade route transition respecting
/// OS reduced-motion preferences (`MediaQuery.disableAnimationsOf`).
class SrolanhPageTransitionsBuilder extends PageTransitionsBuilder {
  const SrolanhPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0.05, 0.0),
      end: Offset.zero,
    ).animate(curved);
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.72, curve: Curves.easeOut),
      ),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

/// Crisp modal-style slide-up + fade route for launching the Report Wizard.
class SrolanhSlideUpRoute<T> extends PageRouteBuilder<T> {
  SrolanhSlideUpRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 210),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) {
            return child;
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
              ),
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}

/// Tactile press-scale micro-interaction (`1.0 → 0.96`) for hero CTAs,
/// quick-report tiles, and the center `+` FAB.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 110),
  });

  final Widget child;
  final double pressedScale;
  final Duration duration;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool next) {
    if (_pressed == next) return;
    setState(() => _pressed = next);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: (!reduceMotion && _pressed) ? widget.pressedScale : 1.0,
        duration: reduceMotion ? Duration.zero : widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Finite one-shot fade + gentle upward entrance animation for cards & sections.
/// Instant when reduced-motion is active and always settles cleanly in tests.
class FadeSlideEntrance extends StatelessWidget {
  const FadeSlideEntrance({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 240),
    this.verticalOffset = 10.0,
  });

  final Widget child;
  final Duration duration;
  final double verticalOffset;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, content) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1.0 - value) * verticalOffset),
          child: content,
        ),
      ),
      child: child,
    );
  }
}
