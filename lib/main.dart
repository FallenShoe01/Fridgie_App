import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/app.dart';
import 'package:fridgie_app/features/backup/data/backup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await BackupService.applyPendingRestoreIfExists();
  runApp(
    EasyLocalization(
      supportedLocales: const <Locale>[Locale('en'), Locale('uk')],
      path: 'assets/l10n',
      fallbackLocale: const Locale('en'),
      child: const ProviderScope(child: FridgieApp()),
    ),
  );
}
