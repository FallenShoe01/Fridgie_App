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
import 'package:package_info_plus/package_info_plus.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isLoading = true;
  final TextEditingController _daysCtrl = TextEditingController();
  final TextEditingController _timeCtrl = TextEditingController();
  bool _isCheckingUpdate = false;
  String? _updateMsg;
  ThemeMode _themeMode = ThemeMode.system;
  AppAccent _accent = AppAccent.teal;
  String _localeCode = 'en';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final AppDatabase db = ref.read(dbProvider);
    final List<AppSetting> rows = await db.select(db.appSettings).get();
    final Map<String, String> map = <String, String>{
      for (final AppSetting r in rows) r.key: r.value,
    };
    if (!mounted) return;
    setState(() {
      _daysCtrl.text = map['default_notification_days_before'] ?? '3';
      _timeCtrl.text = map['default_notification_time_local'] ?? '09:00';
      _themeMode = _themeModeFromString(map['ui_theme_mode']);
      _accent = accentFromString(map['ui_accent'] ?? 'teal');
      _localeCode = map['ui_locale'] == 'uk' ? 'uk' : 'en';
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final AppDatabase db = ref.read(dbProvider);
    final List<AppSettingsCompanion> updates = <AppSettingsCompanion>[
      AppSettingsCompanion(
        key: const drift.Value('default_notification_days_before'),
        value: drift.Value(_daysCtrl.text.trim()),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('settings_saved'.tr())),
    );
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
    setState(() {
      _isCheckingUpdate = true;
      _updateMsg = null;
    });

    try {
      final GithubUpdateService updateService =
          ref.read(githubUpdateServiceProvider);
        final GithubReleaseInfo? info = await updateService.fetchLatestRelease();
      if (!mounted) return;

      if (info == null) {
        setState(
          () => _updateMsg = 'settings_no_github_connection'.tr(),
        );
        return;
      }

      final PackageInfo pkgInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;

      final bool isNewer = updateService.isRemoteVersionNewer(
        currentVersion: pkgInfo.version,
        remoteTag: info.tag,
      );

      if (!isNewer) {
        setState(
          () => _updateMsg = 'settings_up_to_date'.tr(
            namedArgs: <String, String>{'version': pkgInfo.version},
          ),
        );
        return;
      }

      setState(() => _updateMsg = null);
      await _showUpdateDialog(info);
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
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
    return Scaffold(
      appBar: AppBar(
        title: Text('settings_title'.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: _isLoading ? null : _saveSettings,
            child: Text('settings_save'.tr()),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _sectionHeader('settings_appearance_header'.tr()),
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
                const SizedBox(height: 12),
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
                    ref.read(settingsControllerProvider.notifier).setAccent(value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _localeCode,
                  decoration: InputDecoration(
                    labelText: 'settings_language_label'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'en', child: Text('English')),
                    DropdownMenuItem<String>(value: 'uk', child: Text('Українська')),
                  ],
                  onChanged: (String? value) {
                    if (value == null) return;
                    setState(() {
                      _localeCode = value;
                    });
                    ref.read(settingsControllerProvider.notifier).setLocale(value);
                  },
                ),
                const SizedBox(height: 24),
                _sectionHeader('settings_notifications_header'.tr()),
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
                const SizedBox(height: 24),
                _sectionHeader('settings_ota_header'.tr()),
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
                const SizedBox(height: 24),
                _sectionHeader('settings_data_header'.tr()),
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
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      );

  ThemeMode _themeModeFromString(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
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
      final String path = await widget.service.downloadApk(
        apkUrl: widget.info.apkUrl,
        apkName: widget.info.apkName,
        onProgress: (double prog) {
          if (mounted) setState(() => _progress = prog);
        },
      );
      if (!mounted) return;
      setState(() => _installing = true);
      Navigator.pop(context);
      await widget.service.installApk(path);
    } catch (e) {
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
            Text('${(_progress! * 100).toStringAsFixed(0)} %'),
          const SizedBox(height: 4),
          Text('update_do_not_close'.tr()),
        ],
      ),
    );
  }
}
