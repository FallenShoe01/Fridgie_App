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
    final release = await service.fetchLatestRelease();

    expect(release, isNotNull);
    expect(release!.tag, 'v0.3.0');
    expect(release.apkUrl, 'https://example.com/app.apk');
  });

  test('falls back to web release page on API rate limit', () async {
    final Dio dio = Dio()
      ..httpClientAdapter = _FallbackAdapter(
        apiUrl:
            'https://api.github.com/repos/FallenShoe01/Fridgie_App/releases/latest',
        latestUrl:
            'https://github.com/FallenShoe01/Fridgie_App/releases/latest',
        tagUrl:
            'https://github.com/FallenShoe01/Fridgie_App/releases/tag/0.1.1%2B1',
      );

    final GithubUpdateService service = GithubUpdateService(dio: dio);
    final release = await service.fetchLatestRelease();

    expect(release, isNotNull);
    expect(release!.tag, '0.1.1+1');
    expect(
      release.apkUrl,
      'https://github.com/FallenShoe01/Fridgie_App/releases/download/0.1.1%2B1/app-release.apk',
    );
    expect(release.apkName, 'app-release.apk');
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

class _FallbackAdapter implements HttpClientAdapter {
  _FallbackAdapter({
    required this.apiUrl,
    required this.latestUrl,
    required this.tagUrl,
  });

  final String apiUrl;
  final String latestUrl;
  final String tagUrl;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String url = options.uri.toString();

    if (url == apiUrl) {
      final List<int> bytes = utf8.encode(
        jsonEncode(<String, String>{'message': 'API rate limit exceeded'}),
      );
      return ResponseBody.fromBytes(
        bytes,
        403,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }

    if (url == latestUrl) {
      return ResponseBody.fromBytes(
        const <int>[],
        302,
        headers: <String, List<String>>{
          'location': <String>['/FallenShoe01/Fridgie_App/releases/tag/0.1.1%2B1'],
          Headers.contentTypeHeader: <String>['text/html'],
        },
      );
    }

    if (url == tagUrl) {
      const String html =
          '<a href="/FallenShoe01/Fridgie_App/releases/download/0.1.1%2B1/app-release.apk">APK</a>';
      final List<int> bytes = utf8.encode(html);
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['text/html'],
        },
      );
    }

    return ResponseBody.fromBytes(
      const <int>[],
      404,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.textPlainContentType],
      },
    );
  }
}
