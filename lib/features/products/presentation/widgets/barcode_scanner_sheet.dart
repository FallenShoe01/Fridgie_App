import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';

class BarcodeScannerSheet extends StatefulWidget {
  const BarcodeScannerSheet({super.key});

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  bool _didReturnCode = false;
  late final MobileScannerController _scannerController;
  late final Stopwatch _scanSessionTimer;

  Future<void> _closeWithCode(String code) async {
    if (_didReturnCode) {
      return;
    }

    debugPrint('[ScannerPerf] Closing with code=$code at ${_scanSessionTimer.elapsedMilliseconds}ms');
    _didReturnCode = true;
    try {
      final Stopwatch stopTimer = Stopwatch()..start();
      await _scannerController.stop();
      debugPrint('[ScannerPerf] Controller.stop() completed in ${stopTimer.elapsedMilliseconds}ms');
    } catch (_) {
      // Ignore vendor-specific stop errors during camera teardown.
      debugPrint('[ScannerPerf] Controller.stop() threw during closeWithCode');
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(code);
  }

  Future<void> _closeWithoutCode() async {
    if (_didReturnCode) {
      return;
    }

    debugPrint('[ScannerPerf] Closing without code at ${_scanSessionTimer.elapsedMilliseconds}ms');
    _didReturnCode = true;
    try {
      final Stopwatch stopTimer = Stopwatch()..start();
      await _scannerController.stop();
      debugPrint('[ScannerPerf] Controller.stop() completed in ${stopTimer.elapsedMilliseconds}ms');
    } catch (_) {
      // Ignore vendor-specific stop errors during camera teardown.
      debugPrint('[ScannerPerf] Controller.stop() threw during closeWithoutCode');
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    _scanSessionTimer = Stopwatch()..start();
    debugPrint('[ScannerPerf] Scanner sheet init');
    _scannerController = MobileScannerController(
      // Retail-focused formats: reduces decode work vs scanning all formats.
      formats: <BarcodeFormat>[
        BarcodeFormat.ean8,
        BarcodeFormat.ean13,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
      detectionSpeed: DetectionSpeed.noDuplicates,
      detectionTimeoutMs: 250,
      returnImage: false,
      autoStart: true,
    );
  }

  @override
  void dispose() {
    debugPrint('[ScannerPerf] Scanner sheet dispose at ${_scanSessionTimer.elapsedMilliseconds}ms');
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 420,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'add_product_scan'.tr(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: (BarcodeCapture capture) async {
                    if (_didReturnCode) {
                      return;
                    }

                    debugPrint(
                      '[ScannerPerf] onDetect fired at ${_scanSessionTimer.elapsedMilliseconds}ms, barcodes=${capture.barcodes.length}',
                    );

                    for (final Barcode barcode in capture.barcodes) {
                      final String? code = barcode.rawValue?.trim();
                      if (code != null && code.isNotEmpty) {
                        debugPrint(
                          '[ScannerPerf] Valid code detected at ${_scanSessionTimer.elapsedMilliseconds}ms',
                        );
                        await _closeWithCode(code);
                        return;
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _closeWithoutCode,
              child: Text('confirm_cancel'.tr()),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
