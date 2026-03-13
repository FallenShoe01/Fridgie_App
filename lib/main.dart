import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/app.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/features/backup/data/backup_service.dart';
import 'package:fridgie_app/features/notifications/data/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  // Request runtime permissions used by the app (notifications, camera, photos/storage).
  try {
    await <Permission>[
      Permission.notification,
      Permission.camera,
      Permission.photos,
      Permission.storage,
    ].request();
  } catch (_) {}

  await BackupService.applyPendingRestoreIfExists();
  runApp(
    EasyLocalization(
      supportedLocales: const <Locale>[Locale('en'), Locale('uk')],
      path: 'assets/l10n',
      fallbackLocale: const Locale('en'),
      child: const ProviderScope(child: FridgieApp()),
    ),
  );

  // Initialize notifications after the app is running so native plugins are
  // registered (prevents MissingPluginException on some devices).
  Future<void>.delayed(Duration.zero, () async {
    try {
      await NotificationService(notificationsPlugin).initialize();
    } catch (e) {
      // ignore: avoid_print
      print('Deferred notification init failed: $e');
    }
  });
}
