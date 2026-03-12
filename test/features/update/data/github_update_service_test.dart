import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridgie_app/features/update/data/github_update_service.dart';

void main() {
  test('detects newer remote version', () {
    final service = GithubUpdateService(dio: Dio());

    expect(
      service.isRemoteVersionNewer(currentVersion: '0.1.0', remoteTag: 'v0.2.0'),
      isTrue,
    );
    expect(
      service.isRemoteVersionNewer(currentVersion: '1.2.3', remoteTag: '1.2.3'),
      isFalse,
    );
    expect(
      service.isRemoteVersionNewer(currentVersion: '1.3.0', remoteTag: '1.2.9'),
      isFalse,
    );
  });

  test('parses latest release and picks apk asset', () async {
    final Dio dio = Dio()..httpClientAdapter = _FakeAdapter(
      statusCode: 200,
      body: <String, dynamic>{
        'tag_name': 'v0.3.0',
        'name': '0.3.0',
        'body': 'Release notes',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'fridgie-app-release.apk',
            'browser_download_url': 'https://example.com/app.apk',
          },
        ],
      },
    );

    final service = GithubUpdateService(dio: dio);
    final release = await service.fetchLatestRelease(
      owner: 'example',
      repo: 'fridgie_app',
    );

    expect(release, isNotNull);
    expect(release!.tag, 'v0.3.0');
    expect(release.apkUrl, 'https://example.com/app.apk');
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final List<int> bytes = utf8.encode(jsonEncode(body));
    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}
