import 'package:flutter_test/flutter_test.dart';
import 'package:fridgie_app/features/notifications/data/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  test('computes schedule time from expiry date and days-before', () {
    final tz.TZDateTime now = tz.TZDateTime(tz.local, 2026, 3, 12, 10, 0);

    final tz.TZDateTime? scheduled = NotificationService.computeScheduleTime(
      expiryDate: DateTime(2026, 3, 20),
      daysBefore: 3,
      hhmm: '09:30',
      now: now,
    );

    expect(scheduled, isNotNull);
    expect(scheduled!.year, 2026);
    expect(scheduled.month, 3);
    expect(scheduled.day, 17);
    expect(scheduled.hour, 9);
    expect(scheduled.minute, 30);
  });

  test('returns null when schedule time is in the past', () {
    final tz.TZDateTime now = tz.TZDateTime(tz.local, 2026, 3, 19, 10, 0);

    final tz.TZDateTime? scheduled = NotificationService.computeScheduleTime(
      expiryDate: DateTime(2026, 3, 20),
      daysBefore: 3,
      hhmm: '09:30',
      now: now,
    );

    expect(scheduled, isNull);
  });

  test('returns null for invalid time format', () {
    final tz.TZDateTime now = tz.TZDateTime(tz.local, 2026, 3, 12, 10, 0);

    final tz.TZDateTime? scheduled = NotificationService.computeScheduleTime(
      expiryDate: DateTime(2026, 3, 20),
      daysBefore: 3,
      hhmm: 'invalid',
      now: now,
    );

    expect(scheduled, isNull);
  });
}
