import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/record.dart';

/// Fork: pays an estimate's Pix copia-e-cola / boleto digitable line by
/// copying it: bank apps detect a copied Pix/boleto when opened.
class PaymentLauncher {
  static Future<void> open(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code.trim()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('${Record.paymentCodeKind(code)} copiado'),
      ));
  }
}
