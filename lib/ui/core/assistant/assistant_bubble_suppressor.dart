import 'package:material_ui/material_ui.dart';

import 'assistant_scope.dart';

/// Suppresses the floating AI Assistant bubble **only while the enclosing
/// [ModalRoute] is the topmost route**.
///
/// For example, wrapping [ReportWizardPage] hides the bubble on Steps 1–3, but
/// if the wizard pushes [ReportSubmittedPage] on top, the bubble automatically
/// reappears on the confirmation screen.
class AssistantBubbleSuppressor extends StatefulWidget {
  const AssistantBubbleSuppressor({super.key, required this.child});

  final Widget child;

  @override
  State<AssistantBubbleSuppressor> createState() =>
      _AssistantBubbleSuppressorState();
}

class _AssistantBubbleSuppressorState extends State<AssistantBubbleSuppressor>
    with RouteAware {
  AssistantController? _controller;
  ModalRoute<dynamic>? _subscribedRoute;
  bool _isSuppressing = false;

  void _setSuppressed(bool active) {
    if (_isSuppressing == active) return;
    final controller = _controller;
    if (controller == null) return;
    _isSuppressing = active;
    if (active) {
      controller.incrementSuppress();
    } else {
      controller.decrementSuppress();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AssistantScope.maybeRead(context);
    final route = ModalRoute.of(context);
    if (controller == null || route == null) return;

    if (_controller != controller || _subscribedRoute != route) {
      _setSuppressed(false);
      _controller?.routeObserver.unsubscribe(this);
      _controller = controller;
      _subscribedRoute = route;
      controller.routeObserver.subscribe(this, route);
    }

    // RouteObserver.subscribe does not replay didPush for already-mounted
    // routes (such as the initial WelcomePage), so sync current state here.
    _setSuppressed(route.isCurrent);
  }

  @override
  void didPush() {
    _setSuppressed(true);
  }

  @override
  void didPopNext() {
    _setSuppressed(true);
  }

  @override
  void didPushNext() {
    _setSuppressed(false);
  }

  @override
  void didPop() {
    _setSuppressed(false);
  }

  @override
  void dispose() {
    _setSuppressed(false);
    _controller?.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
