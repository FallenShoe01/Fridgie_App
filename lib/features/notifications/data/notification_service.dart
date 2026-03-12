import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    tz_data.initializeTimeZones();
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> scheduleExpiryNotification({
    required int notificationId,
    required String title,
    required String body,
    required DateTime expiryDate,
    required int daysBefore,
    required String hhmm,
  }) async {
    await initialize();

    final tz.TZDateTime? scheduleAt = computeScheduleTime(
      expiryDate: expiryDate,
      daysBefore: daysBefore,
      hhmm: hhmm,
      now: tz.TZDateTime.now(tz.local),
    );

    if (scheduleAt == null) {
      return;
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'expiry_alerts',
      'Expiry alerts',
      channelDescription: 'Notifies users before product expiry dates',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.zonedSchedule(
      notificationId,
      title,
      body,
      scheduleAt,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }

  Future<void> cancelNotification(int id) => _plugin.cancel(id);

  Future<void> cancelAll() => _plugin.cancelAll();

  static tz.TZDateTime? computeScheduleTime({
    required DateTime expiryDate,
    required int daysBefore,
    required String hhmm,
    required tz.TZDateTime now,
  }) {
    final List<String> parts = hhmm.split(':');
    if (parts.length != 2) {
      return null;
    }

    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }

    final DateTime triggerDate = DateTime(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
    ).subtract(Duration(days: daysBefore));

    final tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      triggerDate.year,
      triggerDate.month,
      triggerDate.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      return null;
    }

    return scheduled;
  }
}
