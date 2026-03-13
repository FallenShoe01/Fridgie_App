import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fridgie_app/features/images/presentation/image_cropper_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageService {
  ImageService({
    ImagePicker? picker,
    Dio? dio,
    Future<Directory> Function()? documentsDirectoryProvider,
  })  : _picker = picker ?? ImagePicker(),
        _dio = dio ?? Dio(),
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final ImagePicker _picker;
  final Dio _dio;
  final Future<Directory> Function() _documentsDirectoryProvider;

  Future<String?> pickCropAndStoreImage({
    required BuildContext context,
    required String imageKey,
    required ImageSource source,
  }) async {
    final XFile? picked = await _picker.pickImage(source: source);
    if (picked == null) {
      return null;
    }

    final Uint8List bytes = await picked.readAsBytes();
    if (!context.mounted) {
      return null;
    }

    final Uint8List? croppedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => ImageCropperPage(imageBytes: bytes),
      ),
    );
    if (croppedBytes == null) {
      return null;
    }

    return _storeBytesToManagedStorage(bytes: croppedBytes, imageKey: imageKey);
  }

  Future<String?> downloadAndStoreImage({
    required String imageUrl,
    required String imageKey,
  }) async {
    try {
      final Response<List<int>> response = await _dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final List<int>? bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      final Directory imageDir = await _imageDirectoryForKey(imageKey);
      final String extension = _extensionFromUrl(imageUrl);
      final String filename =
          'remote_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final File file = File(p.join(imageDir.path, filename));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _storeBytesToManagedStorage({
    required Uint8List bytes,
    required String imageKey,
  }) async {
    final Directory imageDir = await _imageDirectoryForKey(imageKey);
    final String filename = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final File destination = File(p.join(imageDir.path, filename));
    await destination.writeAsBytes(bytes, flush: true);
    return destination.path;
  }

  Future<Directory> _imageDirectoryForKey(String imageKey) async {
    final Directory docsDir = await _documentsDirectoryProvider();
    final String safeKey = _safeSegment(imageKey);

    final Directory dir = Directory(
      p.join(docsDir.path, 'images', 'products', safeKey),
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  String _safeSegment(String raw) {
    final String trimmed = raw.trim();
    final RegExp invalid = RegExp(r'[^a-zA-Z0-9_-]');
    final String sanitized = trimmed.replaceAll(invalid, '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  String _extensionFromUrl(String url) {
    final String ext = p.extension(Uri.parse(url).path).replaceFirst('.', '');
    if (ext.isEmpty) {
      return 'jpg';
    }
    return ext;
  }
}
