import 'package:material_ui/material_ui.dart';

/// Tracks active [PopupRoute] overlays (dialogs, bottom sheets, menus, and the
/// floating assistant chat panel itself) so [AssistantBubbleHost] hides cleanly
/// whenever a modal or popup sits on top of the current page.
class AssistantRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  AssistantRouteObserver({required this.onPopupDepthChanged});

  final ValueChanged<int> onPopupDepthChanged;
  final Set<Route<dynamic>> _activePopups = <Route<dynamic>>{};

  int get popupDepth => _activePopups.length;

  void _sync() {
    onPopupDepthChanged(_activePopups.length);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PopupRoute) {
      _activePopups.add(route);
      _sync();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_activePopups.remove(route)) {
      _sync();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_activePopups.remove(route)) {
      _sync();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    var changed = false;
    if (oldRoute != null && _activePopups.remove(oldRoute)) {
      changed = true;
    }
    if (newRoute is PopupRoute && _activePopups.add(newRoute)) {
      changed = true;
    }
    if (changed) {
      _sync();
    }
  }
}
