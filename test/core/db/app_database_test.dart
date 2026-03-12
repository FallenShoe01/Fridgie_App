import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridgie_app/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('opens database and seeds default settings', () async {
    final List<AppSetting> settings = await db.select(db.appSettings).get();

    expect(settings, isNotEmpty);
    expect(
      settings.any((AppSetting e) => e.key == 'default_notification_days_before'),
      isTrue,
    );
    expect(
      settings.any((AppSetting e) => e.key == 'default_notification_time_local'),
      isTrue,
    );
    expect(settings.any((AppSetting e) => e.key == 'default_sort'), isTrue);
  });
}
