import 'package:aupp/dinzo/pix-code.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera reading a Pix QR code or a boleto barcode; pops with the code
/// (the boleto as its digitable line). Phone only.
class CodeScannerPage extends StatefulWidget {
  const CodeScannerPage({super.key});

  /// Opens the camera and returns what it read, or null.
  static Future<String?> scan(BuildContext context) => Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => const CodeScannerPage()),
  );

  @override
  State<CodeScannerPage> createState() => _CodeScannerPageState();
}

class _CodeScannerPageState extends State<CodeScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.itf14],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      // A boleto barcode has 44 digits; other ITF reads are partial.
      if (barcode.format == BarcodeFormat.itf14 &&
          !RegExp(r'^\d{44}$').hasMatch(raw)) {
        continue;
      }
      _done = true;
      Navigator.pop(context, PixCode.boletoLine(raw));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear Pix ou boleto'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Aponte para o QR code do Pix ou para o código de barras do '
                'boleto. No boleto, deite o celular se precisar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
