import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'data/repositories/report_repository.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/local_storage_service.dart';
import 'ui/core/report_scope.dart';
import 'ui/core/theme.dart';
import 'ui/features/welcome/welcome_page.dart';

void main() => runApp(const SrolanhCityApp());

class SrolanhCityApp extends StatefulWidget {
  const SrolanhCityApp({
    super.key,
    ReportRepository? repository,
    this.connectivityService,
  }) : _providedRepository = repository;

  final ReportRepository? _providedRepository;
  final ConnectivityService? connectivityService;

  @override
  State<SrolanhCityApp> createState() => _SrolanhCityAppState();
}

class _SrolanhCityAppState extends State<SrolanhCityApp> {
  late final ReportRepository _repository;
  late final bool _ownsRepository;
  ConnectivityService? _connectivity;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    if (widget._providedRepository != null) {
      _repository = widget._providedRepository!;
      _ownsRepository = false;
      _connectivity = widget.connectivityService;
    } else {
      _repository = ReportRepository(storage: const LocalStorageService());
      _ownsRepository = true;
      _connectivity = widget.connectivityService ?? PlusConnectivityService();
      unawaited(_repository.hydrate());
    }

    final connectivity = _connectivity;
    if (connectivity != null) {
      unawaited(_initConnectivity(connectivity));
    }
  }

  Future<void> _initConnectivity(ConnectivityService connectivity) async {
    final online = await connectivity.checkOnline();
    if (!mounted) return;
    _repository.setOnlineStatus(online);
    _connectivitySub = connectivity.onOnlineChanged.listen((isOnline) {
      if (mounted) {
        _repository.setOnlineStatus(isOnline);
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    if (_ownsRepository) {
      _repository.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReportScope(
      repository: _repository,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SrolanhCity',
        scrollBehavior: const _SrolanhScrollBehavior(),
        theme: buildSrolanhCityTheme(),
        home: const WelcomePage(),
      ),
    );
  }
}

class _SrolanhScrollBehavior extends MaterialScrollBehavior {
  const _SrolanhScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}
