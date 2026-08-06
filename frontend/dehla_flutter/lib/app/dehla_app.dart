import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../theme/dehla_theme.dart';

class DehlaApp extends StatelessWidget {
  const DehlaApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dehla Pakad',
      debugShowCheckedModeBanner: false,
      theme: buildDehlaTheme(),
      home: home ?? const DehlaHomeScreen(),
    );
  }
}
