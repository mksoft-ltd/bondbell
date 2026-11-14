import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/debug_flags.dart';
import 'app/router.dart';
import 'app/screenshot_seed.dart';
import 'core/storage/local_store.dart';
import 'features/draws/data/draw_source.dart';
import 'features/purchases/data/store_gateway.dart';
import 'features/purchases/presentation/purchase_controller.dart';
import 'features/reminders/reminder_service.dart';
import 'core/utils/app_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Orientation is decided after the first frame (AppHooks) and by
  // Info.plist on iOS, never here: the view size can still be zero.

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  // Bond numbers and holder names live in a file whose folder iOS excludes
  // from backups (security audit L-2); older installs are migrated out of
  // SharedPreferences. The flag is set before anything is written there.
  final Directory privateDir = Directory(
    '${(await getApplicationSupportDirectory()).path}/bondbell_private',
  );
  if (!privateDir.existsSync()) privateDir.createSync(recursive: true);
  final bool excluded = await excludeFromBackup(privateDir);
  final DataVault vault = await DataVault.open(privateDir);
  await vault.migrateFrom(prefs);
  final LocalStore store = LocalStore.withVault(prefs, vault);
  if (screenshotMode) await seedScreenshotData(store);

  // A check interrupted by the app being killed may have left a download.
  unawaited(clearScratch());

  final ReminderService reminders = LocalReminderService();
  if (store.getBool('settings.reminders') ?? false) {
    // Keep six months of reminders queued; permission was granted earlier.
    unawaited(
      reminders.scheduleUpcoming().catchError(
        (Object e) => appLog('reminder top-up: $e'),
      ),
    );
  }

  final ProviderContainer container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      vaultStatusProvider.overrideWithValue(vault.status),
      storeGatewayProvider.overrideWithValue(NativeStoreGateway()),
      reminderServiceProvider.overrideWithValue(reminders),
      if (screenshotMode) forceProProvider.overrideWithValue(true),
    ],
  );
  runApp(
    UncontrolledProviderScope(container: container, child: const BondbellApp()),
  );
  if (!excluded) {
    // The native channel registers with the engine; if Dart got here first,
    // try again once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(excludeFromBackup(privateDir)),
    );
  }
  if (screenshotTour) unawaited(_runTour(container));
}

Future<void> _runTour(ProviderContainer container) async {
  await Future<void>.delayed(const Duration(seconds: 4));
  for (final (String route, int secs) in tourStops) {
    container.read(routerProvider).go(route);
    await Future<void>.delayed(Duration(seconds: secs));
  }
}
