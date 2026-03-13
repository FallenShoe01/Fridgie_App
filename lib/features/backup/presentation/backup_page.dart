import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _isBusy = false;
  String? _message;
  bool _isError = false;

  Future<void> _createBackup() async {
    setState(() {
      _isBusy = true;
      _message = null;
      _isError = false;
    });
    try {
      final String zipPath =
          await ref.read(backupServiceProvider).createBackupZip();
      if (!mounted) return;

      if (Platform.isAndroid) {
        final File zipFile = File(zipPath);
        final String fileName = p.basename(zipPath);
        final String? savedPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: <String>['zip'],
          bytes: await zipFile.readAsBytes(),
        );

        if (savedPath == null) {
          if (!mounted) return;
          setState(() => _message = 'backup_cancel'.tr());
          return;
        }
      } else {
        await Share.shareXFiles(
          <XFile>[XFile(zipPath)],
          text: 'Fridgie backup',
        );
      }

      if (!mounted) return;
      setState(() => _message = 'backup_created'.tr());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Backup failed: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
    );
    if (!mounted || picked == null || picked.files.single.path == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('backup_confirm_title'.tr()),
        content: Text('backup_confirm_body'.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('backup_cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('backup_restore_confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isBusy = true;
      _message = null;
      _isError = false;
    });
    try {
      final String? error = await ref
          .read(backupServiceProvider)
          .stageRestoreFromZip(picked.files.single.path!);
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _message = error;
          _isError = true;
        });
      } else {
        setState(() => _message = 'backup_staged'.tr());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Restore failed: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('backup_title'.tr())),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('backup_description'.tr()),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isBusy ? null : _createBackup,
              icon: const Icon(Icons.backup_outlined),
              label: Text('backup_create'.tr()),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _restoreBackup,
              icon: const Icon(Icons.restore_outlined),
              label: Text('backup_restore'.tr()),
            ),
            if (_isBusy) ...<Widget>[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_message != null) ...<Widget>[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isError ? cs.errorContainer : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _isError
                        ? cs.onErrorContainer
                        : cs.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            const Spacer(),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'backup_format_title'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'backup_format_body'.tr(),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
