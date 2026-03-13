import 'package:drift/drift.dart' as drift;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/settings_controller.dart';
import 'package:fridgie_app/app/theme/app_theme.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/update/data/github_update_service.dart';
import 'package:fridgie_app/features/update/data/models/github_release_info.dart';
import 'package:go_router/go_router.dart';
import 'package:fridgie_app/shared/top_snackbar.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final TextEditingController _daysCtrl = TextEditingController();
  final TextEditingController _expiringDaysCtrl = TextEditingController();
  final TextEditingController _timeCtrl = TextEditingController();
  bool _isCheckingUpdate = false;
  String? _updateMsg;
  ThemeMode _themeMode = ThemeMode.system;
  AppAccent _accent = AppAccent.teal;
  String _localeCode = 'en';
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _hydrateThemeAndLocaleFromController();
    _daysCtrl.text = '3';
    _expiringDaysCtrl.text = '3';
    _timeCtrl.text = '09:00';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.microtask(() async {
        if (!mounted) return;
        await _loadSettings();
      });
    });
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    _expiringDaysCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final AppDatabase db = ref.read(dbProvider);
      final Future<List<AppSetting>> settingsFuture = db.select(db.appSettings).get();
      final Future<PackageInfo?> packageFuture = _loadPackageInfo();

      final List<AppSetting> rows = await settingsFuture;
      final PackageInfo? pkg = await packageFuture;
      final Map<String, String> map = <String, String>{
        for (final AppSetting r in rows) r.key: r.value,
      };

      if (!mounted) return;

      setState(() {
        _daysCtrl.text = map['default_notification_days_before'] ?? '3';
        _expiringDaysCtrl.text = map['main_expiring_soon_days'] ?? '3';
        _timeCtrl.text = map['default_notification_time_local'] ?? '09:00';
        if (pkg != null) {
          _appVersion = 'v${pkg.version}+${pkg.buildNumber}';
        }
      });
    } catch (_) {
      // Keep defaults if hydration fails.
    }
  }

  Future<PackageInfo?> _loadPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  void _hydrateThemeAndLocaleFromController() {
    final SettingsState? initialState =
        ref.read(settingsControllerProvider).valueOrNull;
    if (initialState == null) return;

    _themeMode = initialState.themeMode;
    _accent = initialState.accent;
    _localeCode = initialState.localeCode;
  }

  Future<void> _saveSettings() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final AppDatabase db = ref.read(dbProvider);
    final List<AppSettingsCompanion> updates = <AppSettingsCompanion>[
      AppSettingsCompanion(
        key: const drift.Value('default_notification_days_before'),
        value: drift.Value(_daysCtrl.text.trim()),
      ),
      AppSettingsCompanion(
        key: const drift.Value('main_expiring_soon_days'),
        value: drift.Value(_expiringDaysCtrl.text.trim()),
      ),
      AppSettingsCompanion(
        key: const drift.Value('default_notification_time_local'),
        value: drift.Value(_timeCtrl.text.trim()),
      ),
      AppSettingsCompanion(
        key: const drift.Value('ui_theme_mode'),
        value: drift.Value(_themeMode.name),
      ),
      AppSettingsCompanion(
        key: const drift.Value('ui_accent'),
        value: drift.Value(_accent.name),
      ),
      AppSettingsCompanion(
        key: const drift.Value('ui_locale'),
        value: drift.Value(_localeCode),
      ),
    ];
    for (final AppSettingsCompanion u in updates) {
      await db.into(db.appSettings).insertOnConflictUpdate(u);
    }

    final SettingsController controller =
        ref.read(settingsControllerProvider.notifier);
    await controller.setThemeMode(_themeMode);
    await controller.setAccent(_accent);
    await controller.setLocale(_localeCode);

    if (!mounted) return;
    showTopSnackBar(context, 'settings_saved'.tr());
  }

  Future<void> _pickTime() async {
    final List<String> parts = _timeCtrl.text.split(':');
    final int h = int.tryParse(parts.isNotEmpty ? parts[0] : '9') ?? 9;
    final int m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
    );
    if (picked != null) {
      _timeCtrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _checkForUpdate() async {
    debugPrint('[Update] User tapped Check for updates');
    setState(() {
      _isCheckingUpdate = true;
      _updateMsg = null;
    });

    try {
      final GithubUpdateService updateService =
          ref.read(githubUpdateServiceProvider);
      final GithubReleaseInfo? info = await updateService.fetchLatestRelease();
      debugPrint(
        '[Update] fetchLatestRelease completed; found=${info != null}',
      );
      if (!mounted) return;

      if (info == null) {
        debugPrint('[Update] No release info available from GitHub');
        setState(
          () => _updateMsg = 'settings_no_github_connection'.tr(),
        );
        return;
      }

      final PackageInfo pkgInfo = await PackageInfo.fromPlatform();
      debugPrint(
        '[Update] Version check local=${pkgInfo.version} remote=${info.tag}',
      );
      if (!mounted) return;

      final bool isNewer = updateService.isRemoteVersionNewer(
        currentVersion: pkgInfo.version,
        remoteTag: info.tag,
      );

      if (!isNewer) {
        debugPrint('[Update] App is up to date');
        setState(
          () => _updateMsg = 'settings_up_to_date'.tr(
            namedArgs: <String, String>{'version': pkgInfo.version},
          ),
        );
        return;
      }

      debugPrint('[Update] New version available; opening update dialog');
      setState(() => _updateMsg = null);
      await _showUpdateDialog(info);
    } catch (e) {
      debugPrint('[Update] Update check exception: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
      debugPrint('[Update] Update check finished');
    }
  }

  Future<void> _showUpdateDialog(GithubReleaseInfo info) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('update_available_title'.tr(
          namedArgs: <String, String>{'tag': info.tag},
        )),
        content: SingleChildScrollView(
          child: Text(
            info.body.isEmpty ? 'update_available_body'.tr() : info.body,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('update_later'.tr()),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startDownloadInstall(info);
            },
            child: Text('update_download_install'.tr()),
          ),
        ],
      ),
    );
  }

  void _startDownloadInstall(GithubReleaseInfo info) {
    debugPrint('[Update] Start download/install for tag=${info.tag}');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _DownloadProgressDialog(
        info: info,
        service: ref.read(githubUpdateServiceProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('settings_title'.tr()),
      ),
      body: Stack(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: ListView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: <Widget>[
                      _block(
                        title: 'settings_appearance_header'.tr(),
                        children: <Widget>[
                          SegmentedButton<ThemeMode>(
                            segments: <ButtonSegment<ThemeMode>>[
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.system,
                                label: Text('settings_theme_system'.tr()),
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.light,
                                label: Text('settings_theme_light'.tr()),
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.dark,
                                label: Text('settings_theme_dark'.tr()),
                              ),
                            ],
                            selected: <ThemeMode>{_themeMode},
                            onSelectionChanged: (Set<ThemeMode> selection) {
                              final ThemeMode selected = selection.first;
                              setState(() {
                                _themeMode = selected;
                              });
                              ref
                                  .read(settingsControllerProvider.notifier)
                                  .setThemeMode(selected);
                            },
                          ),
                        ],
                      ),
                      _block(
                        title: '',
                        children: <Widget>[
                          DropdownButtonFormField<AppAccent>(
                            initialValue: _accent,
                            decoration: InputDecoration(
                              labelText: 'settings_accent_label'.tr(),
                              border: const OutlineInputBorder(),
                            ),
                            items: AppAccent.values
                                .map(
                                  (AppAccent value) => DropdownMenuItem<AppAccent>(
                                    value: value,
                                    child: Text('settings_accent_${value.name}'.tr()),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (AppAccent? value) {
                              if (value == null) return;
                              setState(() {
                                _accent = value;
                              });
                              ref
                                  .read(settingsControllerProvider.notifier)
                                  .setAccent(value);
                            },
                          ),
                        ],
                      ),
                      _block(
                        title: '',
                        children: <Widget>[
                          DropdownButtonFormField<String>(
                            initialValue: _localeCode,
                            decoration: InputDecoration(
                              labelText: 'settings_language_label'.tr(),
                              border: const OutlineInputBorder(),
                            ),
                            items: <DropdownMenuItem<String>>[
                              DropdownMenuItem<String>(
                                value: 'en',
                                child: Text('language_en'.tr()),
                              ),
                              DropdownMenuItem<String>(
                                value: 'uk',
                                child: Text('language_uk'.tr()),
                              ),
                              DropdownMenuItem<String>(
                                value: 'ru',
                                child: Text('language_ru'.tr()),
                              ),
                            ],
                            onChanged: (String? value) async {
                              if (value == null) return;
                              setState(() {
                                _localeCode = value;
                              });
                              await context.setLocale(Locale(value));
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .setLocale(value);
                            },
                          ),
                        ],
                      ),
                      _block(
                        title: 'settings_notifications_header'.tr(),
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: _daysCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'settings_days_before_label'.tr(),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _timeCtrl,
                                  readOnly: true,
                                  onTap: _pickTime,
                                  decoration: InputDecoration(
                                    labelText: 'settings_time_label'.tr(),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: const Icon(Icons.access_time),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _expiringDaysCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: 'settings_expiring_days_label'.tr(),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                      _block(
                        title: 'settings_ota_header'.tr(),
                        children: <Widget>[
                          Text(
                            'settings_ota_description'.tr(),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _isCheckingUpdate ? null : _checkForUpdate,
                            icon: _isCheckingUpdate
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.system_update_outlined),
                            label: Text('settings_check_updates'.tr()),
                          ),
                          if (_updateMsg != null) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              _updateMsg!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.info_outline),
                            title: Text(
                              _appVersion == null
                                  ? '...'
                                  : 'app_version'.tr(
                                      namedArgs: <String, String>{
                                        'version': _appVersion!,
                                      },
                                    ),
                            ),
                          ),
                        ],
                      ),
                      _block(
                        title: 'settings_data_header'.tr(),
                        children: <Widget>[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.backup_outlined),
                            title: Text('nav_backup'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/backup'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.battery_saver_outlined),
                            title: Text('nav_background_reliability'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/background-reliability'),
                          ),
                        ],
                      ),
                      
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, keyboardInset + 16),
              child: Align(
                alignment: Alignment.bottomRight,
                child: FloatingActionButton.extended(
                  heroTag: 'settings-save-fab',
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: Text('settings_save'.tr()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _block({required String title, required List<Widget> children}) => Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title.isNotEmpty) _sectionHeader(title),
              ...children,
            ],
          ),
        ),
      );

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
        ),
      );

}

// ---------------------------------------------------------------------------
// Download + install dialog
// ---------------------------------------------------------------------------

class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({
    required this.info,
    required this.service,
  });

  final GithubReleaseInfo info;
  final GithubUpdateService service;

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double? _progress;
  String? _error;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      debugPrint('[Update] Download dialog started');
      final String path = await widget.service.downloadApk(
        apkUrl: widget.info.apkUrl,
        apkName: widget.info.apkName,
        onProgress: (double prog) {
          if (mounted) setState(() => _progress = prog);
        },
      );
      if (!mounted) return;
      debugPrint('[Update] Download complete path=$path');
      setState(() => _installing = true);
      Navigator.pop(context);
      await widget.service.installApk(path);
      debugPrint('[Update] Install intent sent');
    } catch (e) {
      debugPrint('[Update] Download/install exception: $e');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AlertDialog(
        title: Text('update_failed_title'.tr()),
        content: Text(_error!),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('update_ok'.tr()),
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(
        _installing ? 'update_installing'.tr() : 'update_downloading'.tr(),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 8),
          if (_progress != null)
            Text(
              'percent_value'.tr(namedArgs: <String, String>{
                'pct': (_progress! * 100).toStringAsFixed(0),
              }),
            ),
          const SizedBox(height: 4),
          Text('update_do_not_close'.tr()),
        ],
      ),
    );
  }
}
