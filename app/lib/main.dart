import 'package:flutter/material.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(BillApp(state: state));
}
