import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image_cropper/image_cropper.dart';
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
    required String imageKey,
    required ImageSource source,
    CropAspectRatio? cropAspectRatio,
  }) async {
    final XFile? picked = await _picker.pickImage(source: source);
    if (picked == null) {
      return null;
    }

    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressQuality: 88,
      aspectRatio: cropAspectRatio ??
          const CropAspectRatio(
            ratioX: 1,
            ratioY: 1,
          ),
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: 'Crop image',
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
      ],
    );

    final String sourcePath = cropped?.path ?? picked.path;
    return _copyToManagedStorage(sourcePath: sourcePath, imageKey: imageKey);
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

  Future<String> _copyToManagedStorage({
    required String sourcePath,
    required String imageKey,
  }) async {
    final Directory imageDir = await _imageDirectoryForKey(imageKey);
    final String extension = _safeExtension(sourcePath);
    final String filename =
        'img_${DateTime.now().millisecondsSinceEpoch}.$extension';

    final File destination = File(p.join(imageDir.path, filename));
    await File(sourcePath).copy(destination.path);
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

  String _safeExtension(String sourcePath) {
    final String ext = p.extension(sourcePath).replaceFirst('.', '').trim();
    if (ext.isEmpty) {
      return 'jpg';
    }
    return ext;
  }

  String _extensionFromUrl(String url) {
    final String ext = p.extension(Uri.parse(url).path).replaceFirst('.', '');
    if (ext.isEmpty) {
      return 'jpg';
    }
    return ext;
  }
}
