import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  void _setFallbackLocationByOffset() {
    final Duration systemOffset = DateTime.now().timeZoneOffset;
    String? matched;
    for (final MapEntry<String, tz.Location> entry
        in tz.timeZoneDatabase.locations.entries) {
      try {
        final tz.TZDateTime nowInLoc = tz.TZDateTime.now(entry.value);
        if (nowInLoc.timeZoneOffset == systemOffset) {
          tz.setLocalLocation(entry.value);
          matched = entry.key;
          break;
        }
      } catch (_) {
        continue;
      }
    }
    // ignore: avoid_print
    print('NotificationService: fallback matched timezone: $matched (offset=$systemOffset)');
  }

  Future<void> initialize() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    tz_data.initializeTimeZones();

    // Determine local timezone via system offset to avoid runtime/plugin
    // compatibility issues while still using local wall-clock scheduling.
    _setFallbackLocationByOffset();

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
      // Log when scheduling is skipped for easier debugging.
      // ignore: avoid_print
      print('NotificationService: not scheduling id=$notificationId, expiry=$expiryDate, daysBefore=$daysBefore, hhmm=$hhmm -> scheduleAt=null or in past');
      return;
    }

    // ignore: avoid_print
    print('NotificationService: scheduling id=$notificationId at $scheduleAt (expiry=$expiryDate, daysBefore=$daysBefore, hhmm=$hhmm)');

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

    try {
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
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationService: zonedSchedule failed: ${e.code} ${e.message}');
      if (e.code.contains('exact_alarms_not_permitted')) {
        try {
          final AndroidScheduleMode fallback = AndroidScheduleMode.values.firstWhere(
            (AndroidScheduleMode m) => m.toString().toLowerCase().contains('inexact'),
            orElse: () => AndroidScheduleMode.values.first,
          );
          // ignore: avoid_print
          print('NotificationService: retrying zonedSchedule with fallback mode $fallback');
          await _plugin.zonedSchedule(
            notificationId,
            title,
            body,
            scheduleAt,
            notificationDetails,
            androidScheduleMode: fallback,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: null,
          );
          // ignore: avoid_print
          print('NotificationService: fallback schedule succeeded');
        } catch (e2) {
          // ignore: avoid_print
          print('NotificationService: fallback zonedSchedule also failed: $e2');
        }
      }
    }
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

    final DateTime localExpiry = expiryDate.toLocal();
    final DateTime triggerDate = DateTime(
      localExpiry.year,
      localExpiry.month,
      localExpiry.day,
    ).subtract(Duration(days: daysBefore));

    // ignore: avoid_print
    print('NotificationService.computeScheduleTime: expiry(local)=$localExpiry, daysBefore=$daysBefore, hhmm=$hhmm, now=$now, triggerDate=$triggerDate');

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
