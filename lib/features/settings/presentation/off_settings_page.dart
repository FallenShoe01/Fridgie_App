import 'package:drift/drift.dart' as drift;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/shared/top_snackbar.dart';
import 'package:fridgie_app/core/off_environment.dart';
import 'package:openfoodfacts/openfoodfacts.dart';

class OffSettingsPage extends ConsumerStatefulWidget {
  const OffSettingsPage({super.key});

  @override
  ConsumerState<OffSettingsPage> createState() => _OffSettingsPageState();
}

class _OffSettingsPageState extends ConsumerState<OffSettingsPage> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  bool _internetSearchEnabled = true;
  bool _useAccount = false;
  bool _loggedIn = false;
  bool _busy = false;
  String? _loginStatus;
  String? _registerStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.microtask(() async {
        if (!mounted) return;
        await _loadSettings();
      });
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final AppDatabase db = ref.read(dbProvider);
      final List<AppSetting> rows = await db.select(db.appSettings).get();
      final Map<String, String> map = <String, String>{
        for (final AppSetting r in rows) r.key: r.value,
      };
      if (!mounted) return;
      setState(() {
        _internetSearchEnabled =
            (map['lookup_open_food_facts_enabled'] ?? 'true').trim().toLowerCase() == 'true';
        _useAccount =
            (map['lookup_off_account_enabled'] ?? 'false').trim().toLowerCase() == 'true';
        _loggedIn =
            (map['lookup_off_logged_in'] ?? 'false').trim().toLowerCase() == 'true';
        _usernameCtrl.text = map['lookup_off_username'] ?? '';
        _passwordCtrl.text = map['lookup_off_password'] ?? '';
        _nameCtrl.text = map['lookup_off_register_name'] ?? '';
        _emailCtrl.text = map['lookup_off_register_email'] ?? '';
      });
    } catch (_) {
      // Keep defaults if hydration fails.
    }
  }

  Future<void> _persist() async {
    final AppDatabase db = ref.read(dbProvider);
    final List<AppSettingsCompanion> updates = <AppSettingsCompanion>[
      AppSettingsCompanion(
        key: const drift.Value('lookup_open_food_facts_enabled'),
        value: drift.Value(_internetSearchEnabled.toString()),
      ),
      AppSettingsCompanion(
        key: const drift.Value('lookup_off_account_enabled'),
        value: drift.Value(_useAccount.toString()),
      ),
      AppSettingsCompanion(
        key: const drift.Value('lookup_off_logged_in'),
        value: drift.Value(_loggedIn.toString()),
      ),
      AppSettingsCompanion(
        key: const drift.Value('lookup_off_username'),
        value: drift.Value(_usernameCtrl.text.trim()),
      ),
      AppSettingsCompanion(
        key: const drift.Value('lookup_off_password'),
        value: drift.Value(_passwordCtrl.text),
      ),
      AppSettingsCompanion(
        key: const drift.Value('lookup_off_register_name'),
        value: drift.Value(_nameCtrl.text.trim()),
      ),
      AppSettingsCompanion(
        key: const drift.Value('lookup_off_register_email'),
        value: drift.Value(_emailCtrl.text.trim()),
      ),
    ];
    for (final AppSettingsCompanion u in updates) {
      await db.into(db.appSettings).insertOnConflictUpdate(u);
    }
  }

  User? _buildUser() {
    final String username = _usernameCtrl.text.trim();
    final String password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) return null;
    return User(userId: username, password: password);
  }

  Future<void> _login() async {
    final User? user = _buildUser();
    debugPrint(
      '[OFFAuth] Login tapped: usernameLen=${_usernameCtrl.text.trim().length}, passwordLen=${_passwordCtrl.text.length}',
    );
    if (user == null) {
      setState(() => _loginStatus = 'settings_off_fill_credentials'.tr());
      return;
    }

    setState(() {
      _busy = true;
      _loginStatus = null;
    });
    debugPrint('[OFFAuth] Login request started for user=${user.userId}');

    try {
      final LoginStatus? status = await OpenFoodAPIClient.login2(
        user,
        uriHelper: kOffAuthUriHelper,
      );
      final bool success = status?.successful ?? false;
      debugPrint(
        '[OFFAuth] Login response: success=$success, status=${status?.status}, verbose=${status?.statusVerbose}, userId=${status?.userId}',
      );
      if (success) {
        OpenFoodAPIConfiguration.globalUser = user;
        setState(() => _loggedIn = true);
        await _persist();
        debugPrint('[OFFAuth] Login success: globalUser configured and settings persisted');
      }

      if (!mounted) return;
      setState(() {
        if (status == null) {
          _loginStatus = 'settings_off_server_unreachable'.tr();
        } else if (success) {
          _loginStatus = 'settings_off_login_success'
              .tr(namedArgs: <String, String>{'user': user.userId});
        } else {
          _loginStatus = status.statusVerbose.isNotEmpty
              ? status.statusVerbose
              : 'settings_off_login_failed'.tr();
        }
      });
    } catch (e, st) {
      debugPrint('[OFFAuth] Login exception: $e\n$st');
      if (!mounted) return;
      setState(() => _loginStatus = 'settings_off_login_failed'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
      debugPrint('[OFFAuth] Login flow finished');
    }
  }

  Future<void> _register() async {
    final User? user = _buildUser();
    final String name = _nameCtrl.text.trim();
    final String email = _emailCtrl.text.trim();
    debugPrint(
      '[OFFAuth] Register tapped: usernameLen=${_usernameCtrl.text.trim().length}, passwordLen=${_passwordCtrl.text.length}, nameLen=${name.length}, emailLen=${email.length}',
    );

    if (user == null || name.isEmpty || email.isEmpty) {
      setState(() => _registerStatus = 'settings_off_fill_registration'.tr());
      return;
    }

    setState(() {
      _busy = true;
      _registerStatus = null;
    });
    debugPrint('[OFFAuth] Register request started for user=${user.userId}');

    try {
      final SignUpStatus status = await OpenFoodAPIClient.register(
        user: user,
        name: name,
        email: email,
        uriHelper: kOffAuthUriHelper,
      );
      final bool success = status.status == 201 || status.status == 1;
      debugPrint(
        '[OFFAuth] Register response: success=$success, status=${status.status}, verbose=${status.statusVerbose}, error=${status.error}',
      );
      if (success) {
        OpenFoodAPIConfiguration.globalUser = user;
        setState(() => _loggedIn = true);
        await _persist();
        debugPrint('[OFFAuth] Register success: globalUser configured and settings persisted');
      }

      if (!mounted) return;
      setState(() {
        _registerStatus = success
            ? 'settings_off_register_success'
                .tr(namedArgs: <String, String>{'user': user.userId})
            : (status.statusVerbose ?? 'settings_off_register_failed'.tr());
      });
    } catch (e, st) {
      debugPrint('[OFFAuth] Register exception: $e\n$st');
      if (!mounted) return;
      setState(() => _registerStatus = 'settings_off_register_failed'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
      debugPrint('[OFFAuth] Register flow finished');
    }
  }

  Future<void> _logout() async {
    OpenFoodAPIConfiguration.globalUser = null;
    _passwordCtrl.clear();
    setState(() {
      _loggedIn = false;
      _useAccount = false;
      _loginStatus = null;
      _registerStatus = null;
    });
    await _persist();
    debugPrint('[OFFAuth] Logged out');
    if (mounted) showTopSnackBar(context, 'settings_off_logged_out'.tr());
  }

  void _onInternetSearchChanged(bool value) {
    setState(() => _internetSearchEnabled = value);
    _persistInternetSearch(value);
  }

  Future<void> _persistInternetSearch(bool value) async {
    final AppDatabase db = ref.read(dbProvider);
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            key: const drift.Value('lookup_open_food_facts_enabled'),
            value: drift.Value(value.toString()),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings_off_page_title'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ── Online search toggle ────────────────────────────────────────
          _block(
            title: 'settings_off_online_search_header'.tr(),
            children: <Widget>[
              Text(
                'settings_internet_search_description'.tr(),
                style: const TextStyle(fontSize: 12),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _internetSearchEnabled,
                onChanged: _busy ? null : _onInternetSearchChanged,
                title: Text('settings_internet_search_label'.tr()),
              ),
              if (_internetSearchEnabled && !_loggedIn)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'settings_off_login_to_use_hint'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),

          // ── Account / Login ─────────────────────────────────────────────
          _block(
            title: 'settings_off_account_header'.tr(),
            children: <Widget>[
              Text(
                'settings_off_account_description'.tr(),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _useAccount,
                onChanged: _loggedIn && !_busy
                    ? (bool v) {
                        setState(() => _useAccount = v);
                        _persist();
                      }
                    : null,
                title: Text('settings_off_use_account_label'.tr()),
              ),
              if (_loggedIn) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'settings_off_logged_in_as'.tr(
                          namedArgs: <String, String>{'user': _usernameCtrl.text},
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _logout,
                  icon: const Icon(Icons.logout),
                  label: Text('settings_off_logout_button'.tr()),
                ),
              ] else ...<Widget>[
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'settings_off_username_label'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'settings_off_password_label'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text('settings_off_login_button'.tr()),
                ),
                if (_loginStatus != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _loginStatus!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ],
            ],
          ),

          // ── Registration (only when not logged in) ──────────────────────
          if (!_loggedIn)
            _block(
              title: 'settings_off_register_section_header'.tr(),
              children: <Widget>[
                Text(
                  'settings_off_register_description'.tr(),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'settings_off_name_label'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'settings_off_email_label'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _register,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text('settings_off_register_button'.tr()),
                ),
                if (_registerStatus != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _registerStatus!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ],
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
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                  ),
                ),
              ...children,
            ],
          ),
        ),
      );
}
