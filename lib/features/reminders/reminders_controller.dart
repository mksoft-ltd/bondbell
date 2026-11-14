import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/common.dart';
import '../settings/presentation/app_settings.dart';
import 'reminder_service.dart';
import '../../core/utils/app_log.dart';

final Provider<bool> remindersEnabledProvider = Provider<bool>(
  (Ref ref) => ref.watch(
    appSettingsProvider.select((AppSettings s) => s.remindersEnabled),
  ),
);

/// Asks for notification permission at the moment the user turns reminders
/// on — the only place Bondbell ever asks.
Future<void> enableReminders(BuildContext context, WidgetRef ref) async {
  final ReminderService service = ref.read(reminderServiceProvider);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String device = deviceNoun(context);
  bool granted = false;
  try {
    granted = await service.requestPermission();
    if (granted) await service.scheduleUpcoming();
  } on Object catch (e) {
    appLog('enableReminders: $e');
  }
  await ref.read(appSettingsProvider.notifier).setRemindersEnabled(granted);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        granted
            ? 'Reminders are on. You\'ll hear from Bondbell at 9am on results '
                  'day.'
            : 'Notifications are turned off for Bondbell. You can allow them '
                  'in your $device\'s Settings, then try again.',
      ),
    ),
  );
}

Future<void> disableReminders(WidgetRef ref) async {
  try {
    await ref.read(reminderServiceProvider).cancelAll();
  } on Object catch (e) {
    appLog('disableReminders: $e');
  }
  await ref.read(appSettingsProvider.notifier).setRemindersEnabled(false);
}
