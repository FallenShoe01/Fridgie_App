import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:dio/dio.dart';
import 'package:fridgie_app/features/update/data/models/github_release_info.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class GithubUpdateService {
  GithubUpdateService({required Dio dio}) : _dio = dio;

  final Dio _dio;
  static const String fixedOwner = 'FallenShoe01';
  static const String fixedRepo = 'Fridgie_App';

  Future<GithubReleaseInfo?> fetchLatestRelease() async {
    final String endpoint =
        'https://api.github.com/repos/$fixedOwner/$fixedRepo/releases/latest';

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(endpoint);
      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(response.data as Map<dynamic, dynamic>);

      final List<dynamic> assets = (data['assets'] as List<dynamic>? ?? <dynamic>[]);
      final Map<String, dynamic>? apkAsset = assets
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> e) => Map<String, dynamic>.from(e))
          .where(
            (Map<String, dynamic> e) =>
                (e['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
          )
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (Map<String, dynamic>? e) => e != null,
            orElse: () => null,
          );

      if (apkAsset == null) {
        return null;
      }

      return GithubReleaseInfo(
        tag: (data['tag_name'] as String? ?? '').trim(),
        name: (data['name'] as String? ?? '').trim(),
        body: (data['body'] as String? ?? '').trim(),
        apkUrl: (apkAsset['browser_download_url'] as String? ?? '').trim(),
        apkName: (apkAsset['name'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null;
    }
  }

  bool isRemoteVersionNewer({
    required String currentVersion,
    required String remoteTag,
  }) {
    final List<int> current = _parseSemver(currentVersion);
    final List<int> remote = _parseSemver(remoteTag);

    for (int i = 0; i < 3; i++) {
      if (remote[i] > current[i]) {
        return true;
      }
      if (remote[i] < current[i]) {
        return false;
      }
    }

    return false;
  }

  List<int> _parseSemver(String raw) {
    final String cleaned = raw.trim().toLowerCase().replaceFirst('v', '');
    final List<String> parts = cleaned.split('.');
    final List<int> values = <int>[0, 0, 0];

    for (int i = 0; i < values.length && i < parts.length; i++) {
      final String token = parts[i].split('-').first;
      values[i] = int.tryParse(token) ?? 0;
    }

    return values;
  }

  /// Downloads the APK from [apkUrl] to external storage and returns the
  /// local file path. [onProgress] receives values from 0.0 to 1.0.
  Future<String> downloadApk({
    required String apkUrl,
    required String apkName,
    void Function(double progress)? onProgress,
  }) async {
    final Directory? externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      throw StateError('External storage is not available.');
    }
    final String savePath = p.join(externalDir.path, apkName);
    await _dio.download(
      apkUrl,
      savePath,
      onReceiveProgress: (int count, int total) {
        if (total > 0 && onProgress != null) {
          onProgress(count / total);
        }
      },
    );
    return savePath;
  }

  /// Launches the system APK installer for the file at [apkPath].
  /// Uses FileProvider content URI for Android 7+ compatibility.
  Future<void> installApk(String apkPath) async {
    if (!Platform.isAndroid) return;
    const String authority = 'com.example.fridgie_app.fileprovider';
    final String filename = p.basename(apkPath);
    final String contentUri =
        'content://$authority/external_files/$filename';
    final AndroidIntent intent = AndroidIntent(
      action: 'android.intent.action.VIEW',
      data: contentUri,
      type: 'application/vnd.android.package-archive',
      // FLAG_GRANT_READ_URI_PERMISSION = 0x00000001
      flags: <int>[0x00000001],
    );
    await intent.launch();
  }
}
