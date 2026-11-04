import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../navigation.dart';
import '../widgets/app_scaffold.dart';

/// Lee un código QR con la cámara y lo devuelve (null si se vuelve atrás).
Future<String?> scanQrCode(BuildContext context, {String title = 'Escanear código QR', String? hint, MainTab tab = MainTab.trips}) =>
    Navigator.push<String>(context, MaterialPageRoute(builder: (_) => QrScannerScreen(title: title, hint: hint, tab: tab)));

class QrScannerScreen extends StatefulWidget {
  final String title;
  final String? hint;
  final MainTab tab;

  const QrScannerScreen({super.key, this.title = 'Escanear código QR', this.hint, this.tab = MainTab.trips});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.title,
      tab: widget.tab,
      appBarActions: [
        IconButton(tooltip: 'Linterna', icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _controller.toggleTorch()),
      ],
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
            if (value != null && !_done) {
              _done = true;
              Navigator.pop(context, value);
            }
          },
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(widget.hint ?? 'Apunte al código QR de la persona (el del teléfono o el impreso).', textAlign: TextAlign.center),
            ),
          ),
        ),
      ]),
    );
  }
}
