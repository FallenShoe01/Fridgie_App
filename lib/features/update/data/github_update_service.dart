import 'dart:io';
import 'dart:developer' as developer;

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
  static const String _githubToken = String.fromEnvironment(
    'GITHUB_TOKEN',
    defaultValue: '',
  );

  void _log(String message) {
    developer.log(message, name: 'FridgieUpdateService');
  }

  Map<String, String> _githubHeaders({bool api = true}) {
    final Map<String, String> headers = <String, String>{
      'User-Agent': 'Fridgie-App',
      if (api) ...<String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    };
    final String token = _githubToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<GithubReleaseInfo?> fetchLatestRelease() async {
    final String endpoint =
        'https://api.github.com/repos/$fixedOwner/$fixedRepo/releases/latest';
    _log(
      'fetchLatestRelease started; owner=$fixedOwner repo=$fixedRepo tokenConfigured=${_githubToken.trim().isNotEmpty}',
    );

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        endpoint,
        options: Options(
          headers: _githubHeaders(),
        ),
      );
      _log('API response status=${response.statusCode}');
      if (response.statusCode == 200 && response.data != null) {
        final GithubReleaseInfo? parsed = _parseApiRelease(response.data);
        if (parsed != null) {
          _log('API parse success; tag=${parsed.tag} apk=${parsed.apkName}');
          return parsed;
        }
        _log('API parse failed: no APK asset found');
      }
    } on DioException catch (e) {
      final int? code = e.response?.statusCode;
      _log('API request failed; status=$code message=${e.message}');
      if (code != 403) {
        return null;
      }
      // 403 on GitHub API is often public quota exhaustion; fallback to web.
      _log('API rate limited; using web fallback');
    } catch (_) {
      _log('API request failed with unexpected exception');
      return null;
    }

    return _fetchLatestReleaseFromWeb();
  }

  GithubReleaseInfo? _parseApiRelease(dynamic rawData) {
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(rawData as Map<dynamic, dynamic>);

    final List<dynamic> assets =
        (data['assets'] as List<dynamic>? ?? <dynamic>[]);
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
  }

  Future<GithubReleaseInfo?> _fetchLatestReleaseFromWeb() async {
    final String latestUrl =
        'https://github.com/$fixedOwner/$fixedRepo/releases/latest';

    try {
      _log('Web fallback started; url=$latestUrl');
      final Response<String> latestRes = await _dio.get<String>(
        latestUrl,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (int? status) =>
              status != null && status >= 200 && status < 400,
          headers: _githubHeaders(api: false),
        ),
      );

      final String? location =
          latestRes.headers.value('location')?.trim();
        _log('Web fallback latest redirect location=$location');
      final String tag = _extractTagFromLocation(location);
      final String releaseUrl = location == null || location.isEmpty
          ? latestUrl
          : (location.startsWith('http')
              ? location
              : 'https://github.com$location');

      final Response<String> pageRes = await _dio.get<String>(
        releaseUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: _githubHeaders(api: false),
        ),
      );
      final String html = pageRes.data ?? '';
      _log('Web fallback release page loaded; htmlLength=${html.length}');

      final RegExp apkLinkRegex = RegExp(
        r'href="([^"]*/releases/download/[^"]*\.apk)"',
        caseSensitive: false,
      );
      final RegExpMatch? linkMatch = apkLinkRegex.firstMatch(html);
      if (linkMatch == null) {
        _log('Web fallback parse failed: no .apk link in release page');
        return null;
      }

      final String href = linkMatch.group(1) ?? '';
      if (href.isEmpty) {
        _log('Web fallback parse failed: empty href');
        return null;
      }

      final String apkUrl = href.startsWith('http')
          ? href
          : 'https://github.com$href';
      final String apkName = Uri.parse(apkUrl).pathSegments.last;
      final String normalizedTag = tag.isEmpty ? 'unknown' : tag;
      _log('Web fallback success; tag=$normalizedTag apk=$apkName');

      return GithubReleaseInfo(
        tag: normalizedTag,
        name: normalizedTag,
        body: '',
        apkUrl: apkUrl,
        apkName: apkName,
      );
    } catch (_) {
      _log('Web fallback failed with exception');
      return null;
    }
  }

  String _extractTagFromLocation(String? location) {
    if (location == null || location.isEmpty) {
      return '';
    }
    final RegExp tagRegex = RegExp(r'/releases/tag/([^/?#]+)');
    final RegExpMatch? match = tagRegex.firstMatch(location);
    if (match == null) {
      return '';
    }
    return Uri.decodeComponent(match.group(1) ?? '');
  }

  bool isRemoteVersionNewer({
    required String currentVersion,
    required String remoteTag,
  }) {
    final List<int> current = _parseSemver(currentVersion);
    final List<int> remote = _parseSemver(remoteTag);

    for (int i = 0; i < 3; i++) {
      if (remote[i] > current[i]) {
        _log(
          'Version compare: remote=$remoteTag current=$currentVersion => newer=true',
        );
        return true;
      }
      if (remote[i] < current[i]) {
        _log(
          'Version compare: remote=$remoteTag current=$currentVersion => newer=false',
        );
        return false;
      }
    }

    _log(
      'Version compare: remote=$remoteTag current=$currentVersion => equal/newer=false',
    );

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
    _log('downloadApk started; apkName=$apkName url=$apkUrl');
    final Directory? externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      _log('downloadApk failed: external storage unavailable');
      throw StateError('External storage is not available.');
    }
    final String savePath = p.join(externalDir.path, apkName);
    await _dio.download(
      apkUrl,
      savePath,
      options: Options(headers: _githubHeaders(api: false)),
      onReceiveProgress: (int count, int total) {
        if (total > 0 && onProgress != null) {
          onProgress(count / total);
        }
      },
    );
    _log('downloadApk completed; savePath=$savePath');
    return savePath;
  }

  /// Launches the system APK installer for the file at [apkPath].
  /// Uses FileProvider content URI for Android 7+ compatibility.
  Future<void> installApk(String apkPath) async {
    _log('installApk called; apkPath=$apkPath');
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
    _log('installApk intent launched');
  }
}
