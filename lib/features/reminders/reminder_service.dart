import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/calendar/results_calendar.dart';

/// Schedules "new results are due" reminders at 9am UK time on each results
/// day. Several months are queued ahead so the reminder keeps coming even
/// if the app isn't opened every month; the queue is topped up at launch.
abstract class ReminderService {
  Future<void> init();

  /// Asks the OS for permission. Called only when the user turns reminders
  /// on, never at launch.
  Future<bool> requestPermission();
  Future<void> scheduleUpcoming();
  Future<void> cancelAll();
}

class LocalReminderService implements ReminderService {
  LocalReminderService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const int monthsAhead = 6;
  static const String channelId = 'results_due';

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/London'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        // Never prompt at launch; permission is asked in context.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final IOSFlutterLocalNotificationsPlugin? ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> scheduleUpcoming() async {
    await init();
    await _plugin.cancelAll();
    final List<tz.TZDateTime> times = reminderTimes(
      tz.TZDateTime.now(tz.local),
      tz.getLocation('Europe/London'),
    );
    for (int i = 0; i < times.length; i++) {
      final tz.TZDateTime at = times[i];
      final String month = DateFormat('MMMM').format(at);
      await _plugin.zonedSchedule(
        id: 1000 + i,
        title: 'New prize results are due',
        body: 'The $month draw results should now be on NS&I\'s site. '
            'Open Bondbell to check your bonds.',
        scheduledDate: at,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Results reminders',
            channelDescription: 'A reminder on the day new monthly prize '
                'results are expected.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact is fine for a morning reminder and needs no exact-alarm
        // permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// When each reminder fires: 09:00 UK time (GMT or BST) on each of the
  /// next [count] results days, whatever time zone the device is in.
  @visibleForTesting
  static List<tz.TZDateTime> reminderTimes(
    tz.TZDateTime now,
    tz.Location london, {
    int count = monthsAhead,
  }) {
    final tz.TZDateTime uk = tz.TZDateTime.from(now, london);
    return <tz.TZDateTime>[
      for (final DateTime d in ResultsCalendar.upcomingResultsDays(
        DateTime(uk.year, uk.month, uk.day, uk.hour, uk.minute),
        count,
      ))
        tz.TZDateTime(london, d.year, d.month, d.day, d.hour),
    ];
  }

  @override
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}

/// Overridable in tests.
final Provider<ReminderService> reminderServiceProvider =
    Provider<ReminderService>((Ref ref) => LocalReminderService());
