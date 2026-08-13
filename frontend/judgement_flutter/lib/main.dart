import 'package:flutter/material.dart';

import 'app/app.dart';
import 'auth/auth_service.dart';
import 'screens/landing_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService();
  await auth.bootstrap();
  final home = initialHomeFromUri(Uri.base);
  runApp(JudgementApp(
    home: home is LandingScreen
        ? LandingScreen(
            initialJoinCode: home.initialJoinCode,
            invalidJoinLink: home.invalidJoinLink,
            auth: auth,
          )
        : home,
  ));
}
