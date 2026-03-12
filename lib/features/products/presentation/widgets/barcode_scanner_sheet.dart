import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerSheet extends StatefulWidget {
  const BarcodeScannerSheet({super.key});

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  bool _didReturnCode = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 420,
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Scan barcode',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  onDetect: (BarcodeCapture capture) {
                    if (_didReturnCode) {
                      return;
                    }

                    final String? code =
                        capture.barcodes.firstOrNull?.rawValue?.trim();
                    if (code == null || code.isEmpty) {
                      return;
                    }

                    _didReturnCode = true;
                    Navigator.of(context).pop(code);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
