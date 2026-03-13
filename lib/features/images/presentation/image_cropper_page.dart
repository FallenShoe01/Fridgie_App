import 'package:crop_your_image/crop_your_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ImageCropperPage extends StatefulWidget {
  const ImageCropperPage({
    super.key,
    required this.imageBytes,
  });

  final Uint8List imageBytes;

  @override
  State<ImageCropperPage> createState() => _ImageCropperPageState();
}

class _ImageCropperPageState extends State<ImageCropperPage> {
  final CropController _controller = CropController();
  bool _isCropping = false;
  bool _isTransforming = false;
  late Uint8List _currentImageBytes;
  late Uint8List _originalImageBytes;

  @override
  void initState() {
    super.initState();
    _currentImageBytes = widget.imageBytes;
    _originalImageBytes = widget.imageBytes;
  }

  void _crop() {
    if (_isCropping || _isTransforming) {
      return;
    }
    setState(() {
      _isCropping = true;
    });
    _controller.crop();
  }

  Future<void> _rotate(double angle) async {
    if (_isCropping || _isTransforming) {
      return;
    }
    setState(() {
      _isTransforming = true;
    });

    try {
      final Uint8List sourceBytes = _currentImageBytes;
      Uint8List nextBytes;
      try {
        nextBytes = await compute<Map<String, Object>, Uint8List>(
          _rotateImageBytesCompute,
          <String, Object>{
            'bytes': sourceBytes,
            'angle': angle,
          },
        );
      } catch (_) {
        // Fallback keeps rotation working even if background spawning fails.
        nextBytes = _rotateImageBytes(sourceBytes, angle);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _currentImageBytes = nextBytes;
      });
      _controller.image = nextBytes;
    } finally {
      if (mounted) {
        setState(() {
          _isTransforming = false;
        });
      }
    }
  }

  void _reset() {
    if (_isCropping || _isTransforming) {
      return;
    }
    setState(() {
      _currentImageBytes = _originalImageBytes;
    });
    _controller.image = _originalImageBytes;
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle toolButtonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('image_cropper_title'.tr()),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Crop(
                    image: _currentImageBytes,
                    controller: _controller,
                    aspectRatio: 1,
                    interactive: true,
                    fixCropRect: true,
                    willUpdateScale: (double value) => value <= 5,
                    baseColor: Theme.of(context).colorScheme.surface,
                    maskColor: Theme.of(context)
                        .colorScheme
                        .scrim
                        .withValues(alpha: 0.45),
                    radius: 12,
                    onCropped: (CropResult result) {
                      if (!mounted) {
                        return;
                      }

                      switch (result) {
                        case CropSuccess(:final croppedImage):
                          Navigator.of(context).pop(croppedImage);
                        case CropFailure():
                          setState(() {
                            _isCropping = false;
                          });
                      }
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'image_cropper_pinch_hint'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      style: toolButtonStyle,
                      onPressed: _isCropping || _isTransforming
                          ? null
                          : () => _rotate(-90),
                      icon: const Icon(Icons.rotate_left),
                      label: Text(
                        'image_cropper_rotate_left'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: toolButtonStyle,
                      onPressed: _isCropping || _isTransforming
                          ? null
                          : _reset,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        'image_cropper_reset'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: toolButtonStyle,
                      onPressed: _isCropping || _isTransforming
                          ? null
                          : () => _rotate(90),
                      icon: const Icon(Icons.rotate_right),
                      label: Text(
                        'image_cropper_rotate_right'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isCropping || _isTransforming
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text('image_cropper_cancel'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isCropping ? null : _crop,
                      child: _isCropping
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text('image_cropper_done'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Uint8List _rotateImageBytes(Uint8List sourceBytes, double angle) {
  final img.Image? decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    return sourceBytes;
  }

  final img.Image rotated = img.copyRotate(
    decoded,
    angle: angle,
    interpolation: img.Interpolation.nearest,
  );

  // Slightly lower quality speeds up repeated preview rotations.
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 86));
}

Uint8List _rotateImageBytesCompute(Map<String, Object> payload) {
  final Uint8List bytes = payload['bytes']! as Uint8List;
  final double angle = payload['angle']! as double;
  return _rotateImageBytes(bytes, angle);
}
