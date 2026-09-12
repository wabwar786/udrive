import 'package:flutter/material.dart';
import 'app.dart';
import 'core/theme/accent_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read before the first frame, so the app never paints in the default colour
  // and then flips to the chosen one a moment later.
  await AccentStore.instance.restore();

  runApp(const UDriveApp());
}
