import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';

class BarcodeScannerSheet extends StatefulWidget {
  const BarcodeScannerSheet({super.key});

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  static const int _requiredConfirmations = 2;
  static const Duration _confirmationWindow = Duration(milliseconds: 1400);

  bool _didReturnCode = false;
  late final MobileScannerController _scannerController;
  late final Stopwatch _scanSessionTimer;
  String? _lastCandidate;
  DateTime? _lastCandidateAt;
  int _lastCandidateHits = 0;

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
      // We confirm a candidate across multiple detections ourselves to reduce
      // one-frame misreads.
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 180,
      returnImage: false,
      autoStart: true,
    );
  }

  String? _normalizeBarcodeCandidate(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final String compact = trimmed.replaceAll(RegExp(r'[\s\-\.]'), '');
    if (compact.isEmpty) {
      return null;
    }

    return compact;
  }

  bool _isLikelyValidBarcode(String code, BarcodeFormat format) {
    final String digits = code.replaceAll(RegExp(r'[^0-9]'), '');

    // Strong validation for retail numeric barcodes.
    switch (format) {
      case BarcodeFormat.ean8:
        return digits.length == 8 && _isValidEan8(digits);
      case BarcodeFormat.ean13:
        return digits.length == 13 && _isValidEan13(digits);
      case BarcodeFormat.upcA:
        return digits.length == 12 && _isValidUpcA(digits);
      case BarcodeFormat.upcE:
        return digits.length == 8;
      case BarcodeFormat.code128:
        // Code128 is often alphanumeric; enforce a practical minimum length
        // to reduce short noisy decodes.
        return code.length >= 6;
      default:
        return code.length >= 6;
    }
  }

  int _candidateScore(String normalized, BarcodeFormat format) {
    final String digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');

    if (format == BarcodeFormat.ean13 && digits.length == 13) {
      return _isValidEan13(digits) ? 100 : 40;
    }
    if (format == BarcodeFormat.upcA && digits.length == 12) {
      return _isValidUpcA(digits) ? 95 : 35;
    }
    if (format == BarcodeFormat.ean8 && digits.length == 8) {
      return _isValidEan8(digits) ? 90 : 30;
    }
    if (format == BarcodeFormat.upcE && digits.length == 8) {
      return 80;
    }
    if (format == BarcodeFormat.code128) {
      return normalized.length >= 8 ? 75 : 60;
    }
    return normalized.length >= 8 ? 50 : 20;
  }

  bool _isValidEan13(String digits) {
    if (digits.length != 13) {
      return false;
    }
    final int check = int.parse(digits[12]);
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final int n = int.parse(digits[i]);
      sum += (i % 2 == 0) ? n : (n * 3);
    }
    final int computed = (10 - (sum % 10)) % 10;
    return computed == check;
  }

  bool _isValidEan8(String digits) {
    if (digits.length != 8) {
      return false;
    }
    final int check = int.parse(digits[7]);
    int sum = 0;
    for (int i = 0; i < 7; i++) {
      final int n = int.parse(digits[i]);
      sum += (i % 2 == 0) ? (n * 3) : n;
    }
    final int computed = (10 - (sum % 10)) % 10;
    return computed == check;
  }

  bool _isValidUpcA(String digits) {
    if (digits.length != 12) {
      return false;
    }
    final int check = int.parse(digits[11]);
    int sumOdd = 0;
    int sumEven = 0;
    for (int i = 0; i < 11; i++) {
      final int n = int.parse(digits[i]);
      if (i % 2 == 0) {
        sumOdd += n;
      } else {
        sumEven += n;
      }
    }
    final int total = (sumOdd * 3) + sumEven;
    final int computed = (10 - (total % 10)) % 10;
    return computed == check;
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

                    Barcode? best;
                    String? bestCode;
                    int bestScore = -1;

                    for (final Barcode barcode in capture.barcodes) {
                      final String raw = barcode.rawValue ?? '';
                      final String? normalized =
                          _normalizeBarcodeCandidate(raw);
                      if (normalized == null) {
                        continue;
                      }

                      if (!_isLikelyValidBarcode(normalized, barcode.format)) {
                        debugPrint(
                          '[ScannerPerf] Reject candidate raw="$raw" format=${barcode.format.name}',
                        );
                        continue;
                      }

                      final int score = _candidateScore(normalized, barcode.format);
                      if (score > bestScore) {
                        best = barcode;
                        bestCode = normalized;
                        bestScore = score;
                      }
                    }

                    if (bestCode == null || best == null) {
                      return;
                    }

                    final DateTime now = DateTime.now();
                    final bool withinWindow = _lastCandidateAt != null &&
                        now.difference(_lastCandidateAt!) <= _confirmationWindow;
                    if (_lastCandidate == bestCode && withinWindow) {
                      _lastCandidateHits += 1;
                    } else {
                      _lastCandidate = bestCode;
                      _lastCandidateHits = 1;
                    }
                    _lastCandidateAt = now;

                    debugPrint(
                      '[ScannerPerf] Candidate "$bestCode" format=${best.format.name} score=$bestScore hits=$_lastCandidateHits/$_requiredConfirmations',
                    );

                    if (_lastCandidateHits >= _requiredConfirmations) {
                      debugPrint(
                        '[ScannerPerf] Confirmed code "$bestCode" at ${_scanSessionTimer.elapsedMilliseconds}ms',
                      );
                      await _closeWithCode(bestCode);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Align barcode in center and hold steady for a moment',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
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
