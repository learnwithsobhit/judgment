import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'theme/festival_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FestivalController.instance.restoreCache();
  runApp(JudgementApp(home: initialHomeFromUri(Uri.base)));
  unawaited(FestivalController.instance.refresh());
}
