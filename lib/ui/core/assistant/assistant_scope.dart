import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/services/help_assistant_service.dart';
import '../../features/help/help_chat_controller.dart';
import 'assistant_route_observer.dart';

/// App-wide coordinator for the floating AI Civic Assistant bubble, route
/// suppression state, popup tracking, and shared chat conversation.
class AssistantController extends ChangeNotifier {
  AssistantController({HelpAssistantService? assistant})
    : chatController = HelpChatController(assistant: assistant) {
    routeObserver = AssistantRouteObserver(onPopupDepthChanged: _setPopupDepth);
    chatController.addListener(_onChatChanged);
  }

  final HelpChatController chatController;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final AssistantRouteObserver routeObserver;

  int _suppressCount = 0;
  int _popupDepth = 0;
  bool _isPanelOpen = false;
  bool _disposed = false;
  bool _notificationScheduled = false;

  int get suppressCount => _suppressCount;
  int get popupDepth => _popupDepth;
  bool get isPanelOpen => _isPanelOpen;

  void _onChatChanged() {
    _safeNotify();
  }

  void _setPopupDepth(int depth) {
    if (_popupDepth == depth) return;
    _popupDepth = depth;
    _safeNotify();
  }

  void incrementSuppress() {
    _suppressCount++;
    _safeNotify();
  }

  void decrementSuppress() {
    if (_suppressCount <= 0) return;
    _suppressCount--;
    _safeNotify();
  }

  void setPanelOpen(bool open) {
    if (_isPanelOpen == open) return;
    _isPanelOpen = open;
    chatController.setPanelVisible(open);
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    chatController.removeListener(_onChatChanged);
    chatController.dispose();
    super.dispose();
  }
}

/// Exposes [AssistantController] to every route and the global bubble overlay.
class AssistantScope extends InheritedNotifier<AssistantController> {
  const AssistantScope({
    super.key,
    required AssistantController controller,
    required super.child,
  }) : super(notifier: controller);

  static AssistantController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AssistantScope>()
        ?.notifier;
  }

  static AssistantController? maybeRead(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AssistantScope>();
    return (element?.widget as AssistantScope?)?.notifier;
  }

  static AssistantController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No AssistantScope found in widget tree.');
    return controller!;
  }
}
