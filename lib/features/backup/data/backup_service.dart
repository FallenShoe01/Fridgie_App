import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BackupService {
  const BackupService({required this.db});

  final AppDatabase db;

  static const String _pendingSqliteFilename = 'fridgie_restore_pending.sqlite';
  static const String _pendingFlagFilename = 'fridgie_restore_pending.flag';

  /// Creates a ZIP backup containing the database and all product images.
  /// Returns the path to the ZIP file, ready to share.
  Future<String> createBackupZip() async {
    final Directory docsDir = await getApplicationDocumentsDirectory();
    final Directory tempDir = await getTemporaryDirectory();

    // Flush WAL to the main file for a consistent snapshot.
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

    final Archive archive = Archive();

    // Include the SQLite database.
    final File sqliteFile = File(p.join(docsDir.path, 'fridgie_app.sqlite'));
    if (sqliteFile.existsSync()) {
      final List<int> bytes = await sqliteFile.readAsBytes();
      archive.addFile(ArchiveFile('fridgie_app.sqlite', bytes.length, bytes));
    }

    // Include the images directory recursively.
    final Directory imagesDir = Directory(p.join(docsDir.path, 'images'));
    if (imagesDir.existsSync()) {
      await for (final FileSystemEntity entity
          in imagesDir.list(recursive: true)) {
        if (entity is File) {
          final String rel = p
              .relative(entity.path, from: docsDir.path)
              .replaceAll(r'\', '/');
          final List<int> bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(rel, bytes.length, bytes));
        }
      }
    }

    // Include a metadata file for validation.
    final Map<String, Object> meta = <String, Object>{
      'version': 1,
      'app': 'fridgie_app',
      'created_at': DateTime.now().toIso8601String(),
    };
    final List<int> metaBytes = utf8.encode(jsonEncode(meta));
    archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));

    final List<int>? zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('Failed to encode backup archive.');
    }

    final String ts = _formatTimestamp(DateTime.now());
    final File zipFile =
        File(p.join(tempDir.path, 'fridgie_backup_$ts.zip'));
    await zipFile.writeAsBytes(zipBytes);
    return zipFile.path;
  }

  /// Validates and stages a restore from [zipPath].
  /// Returns `null` on success, or an error message string on failure.
  /// The database swap takes effect on the next app launch.
  Future<String?> stageRestoreFromZip(String zipPath) async {
    final File zipFile = File(zipPath);
    if (!zipFile.existsSync()) {
      return 'Backup file not found.';
    }

    late Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    } catch (_) {
      return 'Could not read the file. Is it a valid Fridgie backup?';
    }

    final bool hasMeta =
        archive.files.any((ArchiveFile f) => f.name == 'metadata.json');
    final bool hasSqlite =
        archive.files.any((ArchiveFile f) => f.name == 'fridgie_app.sqlite');
    if (!hasMeta || !hasSqlite) {
      return 'Invalid backup: missing required files.';
    }

    try {
      final ArchiveFile metaArch = archive.files
          .firstWhere((ArchiveFile f) => f.name == 'metadata.json');
      final Map<String, dynamic> meta = jsonDecode(
        utf8.decode(metaArch.content as List<int>),
      ) as Map<String, dynamic>;
      if (meta['app'] != 'fridgie_app') {
        return 'This backup is not from Fridgie.';
      }
    } catch (_) {
      return 'Could not parse backup metadata.';
    }

    final Directory docsDir = await getApplicationDocumentsDirectory();

    // Restore images immediately — safe since we only add/replace files.
    for (final ArchiveFile file in archive.files) {
      if (file.isFile && file.name.startsWith('images/')) {
        final File out = File(p.join(docsDir.path, file.name));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>);
      }
    }

    // Stage the SQLite file for hot-swap on the next app launch.
    final ArchiveFile sqliteArch = archive.files
        .firstWhere((ArchiveFile f) => f.name == 'fridgie_app.sqlite');
    await File(p.join(docsDir.path, _pendingSqliteFilename))
        .writeAsBytes(sqliteArch.content as List<int>);

    // Write the flag so main() knows to swap on next start.
    await File(p.join(docsDir.path, _pendingFlagFilename)).writeAsString('1');

    return null; // success — restart required
  }

  /// Call in `main()` BEFORE constructing [AppDatabase] to apply a staged
  /// restore. If no restore is pending this is a fast no-op.
  static Future<void> applyPendingRestoreIfExists() async {
    final Directory docsDir = await getApplicationDocumentsDirectory();
    final File flag = File(p.join(docsDir.path, _pendingFlagFilename));
    if (!flag.existsSync()) return;

    final File pending =
        File(p.join(docsDir.path, _pendingSqliteFilename));
    final File main = File(p.join(docsDir.path, 'fridgie_app.sqlite'));
    final File preRestore =
        File(p.join(docsDir.path, 'fridgie_app_pre_restore.sqlite'));

    if (pending.existsSync()) {
      if (main.existsSync()) await main.copy(preRestore.path);
      try {
        await pending.copy(main.path);
        await pending.delete();
        if (preRestore.existsSync()) await preRestore.delete();
      } catch (_) {
        // Rollback to the pre-restore snapshot on failure.
        if (preRestore.existsSync()) {
          await preRestore.copy(main.path);
          await preRestore.delete();
        }
      }
    }
    await flag.delete();
  }
}

String _formatTimestamp(DateTime dt) {
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}${p2(dt.month)}${p2(dt.day)}_'
      '${p2(dt.hour)}${p2(dt.minute)}${p2(dt.second)}';
}
