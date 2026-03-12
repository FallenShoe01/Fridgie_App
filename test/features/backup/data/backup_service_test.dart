import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Backup ZIP validation logic', () {
    List<int> makeValidZip({String app = 'fridgie_app'}) {
      final Archive archive = Archive();

      final List<int> metaBytes = utf8.encode(jsonEncode(<String, Object>{
        'version': 1,
        'app': app,
        'created_at': DateTime.now().toIso8601String(),
      }));
      archive.addFile(
        ArchiveFile('metadata.json', metaBytes.length, metaBytes),
      );

      final List<int> dbBytes = List<int>.filled(64, 0);
      archive.addFile(
        ArchiveFile('fridgie_app.sqlite', dbBytes.length, dbBytes),
      );

      return ZipEncoder().encode(archive)!;
    }

    test('valid backup ZIP round-trips correctly', () {
      final List<int> zipBytes = makeValidZip();
      final Archive decoded = ZipDecoder().decodeBytes(zipBytes);

      expect(
        decoded.files.any((ArchiveFile f) => f.name == 'metadata.json'),
        isTrue,
      );
      expect(
        decoded.files.any((ArchiveFile f) => f.name == 'fridgie_app.sqlite'),
        isTrue,
      );
    });

    test('metadata is correctly encoded and decoded', () {
      final List<int> zipBytes = makeValidZip();
      final Archive decoded = ZipDecoder().decodeBytes(zipBytes);
      final ArchiveFile metaFile = decoded.files
          .firstWhere((ArchiveFile f) => f.name == 'metadata.json');

      final Map<String, dynamic> meta = jsonDecode(
        utf8.decode(metaFile.content as List<int>),
      ) as Map<String, dynamic>;
      expect(meta['app'], equals('fridgie_app'));
      expect(meta['version'], equals(1));
    });

    test('backup with wrong app name is detectable', () {
      final List<int> zipBytes = makeValidZip(app: 'other_app');
      final Archive decoded = ZipDecoder().decodeBytes(zipBytes);
      final ArchiveFile metaFile = decoded.files
          .firstWhere((ArchiveFile f) => f.name == 'metadata.json');

      final Map<String, dynamic> meta = jsonDecode(
        utf8.decode(metaFile.content as List<int>),
      ) as Map<String, dynamic>;
      expect(meta['app'], isNot(equals('fridgie_app')));
    });

    test('decoding invalid bytes throws', () {
      expect(
        () => ZipDecoder().decodeBytes(<int>[1, 2, 3, 4, 5]),
        throwsA(anything),
      );
    });

    test('backup without metadata.json is detectable', () {
      final Archive archive = Archive();
      final List<int> dbBytes = List<int>.filled(32, 0);
      archive.addFile(
        ArchiveFile('fridgie_app.sqlite', dbBytes.length, dbBytes),
      );
      final List<int> zipBytes = ZipEncoder().encode(archive)!;
      final Archive decoded = ZipDecoder().decodeBytes(zipBytes);

      final bool hasMeta =
          decoded.files.any((ArchiveFile f) => f.name == 'metadata.json');
      expect(hasMeta, isFalse);
    });
  });
}
