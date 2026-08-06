import 'package:dehla_flutter/dehla_flutter.dart';
import 'package:flutter/material.dart';

import 'game_picker_screen.dart';

Widget resolveShellHome(Uri uri) {
  final deeplink = parseDehlaDeepLink(uri);
  if (deeplink != null) {
    return DehlaHomeScreen(
      initialJoinCode: deeplink.joinCode,
      invalidJoinLink: deeplink.invalidJoinLink,
    );
  }
  return const GamePickerScreen();
}
