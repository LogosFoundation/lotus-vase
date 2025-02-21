import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

final qrKey = GlobalKey(debugLabel: 'QR');

class QRView extends HookWidget {
  const QRView({Key? key, required this.onScanResult}) : super(key: key);

  final Function(String?) onScanResult;

  @override
  Widget build(BuildContext context) {
    final throttledOnScanResult = throttle(onScanResult, 1000);
    return MobileScanner(
      fit: BoxFit.cover,
      onDetect: (capture) {
        final barcodes = capture.barcodes;
        for (final barcode in barcodes) {
          final value = barcode.rawValue;
          if (value != null) {
            throttledOnScanResult(value);
          }
        }
      },
    );
  }
}

Function(String) throttle(Function fn, int time) {
  var previous = 0;
  return (String args) {
    var now = DateTime.now().millisecondsSinceEpoch;
    if (previous == 0 || now - previous >= time) {
      previous = now;
      fn(args);
    }
  };
}
