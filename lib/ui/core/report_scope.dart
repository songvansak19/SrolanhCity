import 'package:material_ui/material_ui.dart';

import '../../data/repositories/report_repository.dart';

/// Reactive dependency container that exposes [ReportRepository] across the
/// widget tree without external state-management packages.
class ReportScope extends InheritedNotifier<ReportRepository> {
  const ReportScope({
    super.key,
    required ReportRepository repository,
    required super.child,
  }) : super(notifier: repository);

  /// Subscribes [context] to changes in [ReportRepository].
  static ReportRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ReportScope>();
    assert(scope != null, 'No ReportScope found in widget tree');
    return scope!.notifier!;
  }

  /// Reads [ReportRepository] without registering a rebuild dependency.
  static ReportRepository read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ReportScope>();
    assert(scope != null, 'No ReportScope found in widget tree');
    return scope!.notifier!;
  }
}
