import 'package:flutter/material.dart';

import 'app/dehla_app.dart';
import 'screens/home_screen.dart';
import 'util/deep_link.dart';

/// Run Dehla alone for debug: `flutter run -t lib/main_dev.dart`
void main() {
  final deeplink = parseDehlaDeepLink(Uri.base);
  final home = deeplink == null
      ? const DehlaHomeScreen()
      : DehlaHomeScreen(
          initialJoinCode: deeplink.joinCode,
          invalidJoinLink: deeplink.invalidJoinLink,
        );
  runApp(DehlaApp(home: home));
}
