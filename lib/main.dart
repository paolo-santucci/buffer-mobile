// Entry point — Buffer mobile (TASK-16)
//
// Spec refs: FR-05, NFR-04, NFR-05, MC-01
//
// Composition root:
//   1. Ensure the Flutter engine is initialised before any platform calls.
//   2. Obtain a real SharedPreferences instance (async; requires an
//      initialised engine).
//   3. Mount a single ProviderScope above everything, injecting the real
//      SharedPreferences via sharedPreferencesProvider.overrideWithValue().
//      This satisfies the override seam required by tests (TASK-15 / TASK-16).
//   4. BufferApp is const — it never rebuilds when the root widget is recreated.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/presentation/app.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BufferApp(),
    ),
  );
}
