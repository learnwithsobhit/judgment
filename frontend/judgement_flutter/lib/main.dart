import 'package:flutter/material.dart';

import 'app/app.dart';
import 'util/native_kv_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NativeKvStore.init();
  runApp(JudgementApp(home: initialHomeFromUri(Uri.base)));
}
