/// Detects a newer Firebase Hosting deploy via `/version.json`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'web_reload.dart';

/// Baked in at `flutter build` via `--dart-define` (see stamp / deploy scripts).
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0',
);
const String kAppBuildId = String.fromEnvironment(
  'APP_BUILD_ID',
  defaultValue: 'local',
);

class AppUpdateController extends ChangeNotifier {
  AppUpdateController();

  static final AppUpdateController instance = AppUpdateController();

  String? latestVersion;
  String? latestBuildId;
  bool checking = false;
  bool initialCheckComplete = false;
  bool _reloading = false;
  Timer? _timer;

  String get runningLabel {
    if (kAppBuildId == 'local' || kAppBuildId.isEmpty) {
      return kAppVersion;
    }
    return '$kAppVersion ($kAppBuildId)';
  }

  String? get latestLabel {
    final id = latestBuildId;
    final ver = latestVersion;
    if (id == null && ver == null) return null;
    if (id == null || id.isEmpty) return ver;
    if (ver == null || ver.isEmpty) return id;
    return '$ver ($id)';
  }

  bool get updateAvailable {
    final remote = latestBuildId;
    if (remote == null || remote.isEmpty) return false;
    if (kAppBuildId == 'local') return false;
    return remote != kAppBuildId;
  }

  /// True while the first version check is in flight (web only).
  bool get awaitingInitialCheck =>
      kIsWeb && kAppBuildId != 'local' && !initialCheckComplete;

  void start({Duration interval = const Duration(seconds: 60)}) {
    unawaited(check());
    // Catch a deploy that lands just after the first poll.
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (_timer != null) unawaited(check());
    });
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    notifyListeners();
    try {
      final uri = Uri.base.resolve('version.json').replace(
        queryParameters: {
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final data = jsonDecode(res.body);
      if (data is! Map) return;
      latestVersion = data['version']?.toString();
      latestBuildId = data['build_id']?.toString();
    } catch (_) {
      // Offline / blocked — keep last known state.
    } finally {
      checking = false;
      if (!initialCheckComplete) {
        initialCheckComplete = true;
      }
      notifyListeners();
    }
  }

  Future<void> switchToLatest() async {
    if (_reloading) return;
    _reloading = true;
    notifyListeners();
    final target = latestBuildId;
    await clearWebCachesAndReload(
      buildId: (target != null && target.isNotEmpty) ? target : kAppBuildId,
    );
  }

  /// Returns `true` if the running build is current and entry may proceed.
  /// If a newer deploy exists, starts a cache-busting navigation and returns
  /// `false` (caller must not continue Create/Join).
  Future<bool> ensureFreshOrReload() async {
    if (!kIsWeb || kAppBuildId == 'local') return true;
    if (!initialCheckComplete) {
      await check();
    } else if (!updateAvailable) {
      await check();
    }
    if (updateAvailable) {
      await switchToLatest();
      return false;
    }
    return true;
  }
}

/// Watches app resume to re-check hosting version.
class AppUpdateLifecycle extends StatefulWidget {
  final Widget child;

  const AppUpdateLifecycle({super.key, required this.child});

  @override
  State<AppUpdateLifecycle> createState() => _AppUpdateLifecycleState();
}

class _AppUpdateLifecycleState extends State<AppUpdateLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      AppUpdateController.instance.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppUpdateController.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && kIsWeb) {
      unawaited(AppUpdateController.instance.check());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
