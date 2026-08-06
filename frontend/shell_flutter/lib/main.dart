import 'package:dehla_flutter/dehla_flutter.dart';
import 'package:flutter/material.dart';

import 'game_picker_screen.dart';
import 'uri_home.dart';

void main() {
  runApp(ShellApp(home: resolveShellHome(Uri.base)));
}

class ShellApp extends StatelessWidget {
  const ShellApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Table games',
      debugShowCheckedModeBanner: false,
      theme: buildDehlaTheme(),
      home: home ?? const GamePickerScreen(),
    );
  }
}
