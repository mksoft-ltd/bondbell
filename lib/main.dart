import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/screenshot_seed.dart';
import 'core/storage/local_store.dart';
import 'features/draws/data/draw_source.dart';
import 'features/purchases/data/store_gateway.dart';
import 'features/purchases/presentation/purchase_controller.dart';
import 'features/reminders/reminder_service.dart';

/// `--dart-define=SCREENSHOT_MODE=true` seeds sample data and unlocks Pro
/// for store screenshots. Ignored in release builds.
const bool _screenshotDefine = bool.fromEnvironment('SCREENSHOT_MODE');
const bool screenshotMode = _screenshotDefine && !kReleaseMode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Phones stay portrait; tablets rotate freely.
  final FlutterView view = PlatformDispatcher.instance.views.first;
  final double shortest =
      view.physicalSize.shortestSide / view.devicePixelRatio;
  if (shortest < 600) {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
  }

  final LocalStore store = LocalStore(await SharedPreferences.getInstance());
  if (screenshotMode) await seedScreenshotData(store);

  // A check interrupted by the app being killed may have left a download.
  unawaited(clearScratch());

  final ReminderService reminders = LocalReminderService();
  if (store.getBool('settings.reminders') ?? false) {
    // Keep six months of reminders queued; permission was granted earlier.
    unawaited(
      reminders.scheduleUpcoming().catchError(
        (Object e) => debugPrint('reminder top-up: $e'),
      ),
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        storeGatewayProvider.overrideWithValue(NativeStoreGateway()),
        reminderServiceProvider.overrideWithValue(reminders),
        if (screenshotMode) forceProProvider.overrideWithValue(true),
      ],
      child: const BondbellApp(),
    ),
  );
}
