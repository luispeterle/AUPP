import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../components/known-tags.dart';
import '../desktop/desktop-layout.dart';
import '../models/record.dart';

/// Fork: pays an estimate's Pix copia-e-cola / boleto digitable line.
///
/// There is no standard link to hand a Pix or boleto to a bank app: the
/// Central Bank only defines `pix://<host>?qr=<copia e cola>` for Pix by
/// proximity (NFC), and no bank app on the user's phone opens it. Bank apps
/// read documents instead: the C6 does not understand shared text nor a QR
/// image, but reads a boleto PDF. So both go to bank apps as a PDF (Pix: QR
/// code + copia-e-cola; boleto: digitable line + barcode); apps that take no
/// PDF are just opened. The code is always copied too (bank apps detect a
/// copied Pix/boleto when opened).
///
/// Apps in the Samsung Secure Folder (an Android private profile) are hidden
/// from every app but the launcher: they can't be listed nor opened from
/// here. The Secure Folder itself can, so the sheet offers it.
class PaymentLauncher {
  static const _channel = MethodChannel('aupp/app');
  static const _secureFolder = 'com.samsung.knox.securefolder';

  static Future<List<_App>> _apps(String method, [Map? args]) async {
    try {
      final list = await _channel.invokeListMethod<Map>(method, args) ?? [];
      return [
        for (final m in list)
          _App(m['package'] as String, m['label'] as String? ?? ''),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The 44-digit barcode of a boleto from its digitable line (47 digits for
  /// a bank boleto, 48 for a utility/tax one), or null when it is neither.
  static String? boletoBarcode(String code) {
    final d = code.replaceAll(RegExp(r'\D'), '');
    if (d.length == 44) return d;
    if (d.length == 47) {
      return d.substring(0, 4) +
          d[32] +
          d.substring(33, 47) +
          d.substring(4, 9) +
          d.substring(10, 20) +
          d.substring(21, 31);
    }
    if (d.length == 48 && d.startsWith('8')) {
      return [for (var i = 0; i < 4; i++) d.substring(i * 12, i * 12 + 11)]
          .join();
    }
    return null;
  }

  /// Writes the file handed to bank apps under cache/share_plus (served by
  /// share_plus's FileProvider). Null for a code that is neither Pix nor
  /// boleto.
  static Future<String?> _pdf(String code) async {
    final kind = Record.paymentCodeKind(code);
    if (kind != 'Pix' && kind != 'Boleto') return null;
    final file = File('${await _shareDir()}/${kind.toLowerCase()}.pdf');
    await file.writeAsBytes(await _paymentPdf(code.trim(), pix: kind == 'Pix'));
    return file.path;
  }

  /// The QR code image of a Pix, for the share sheet.
  static Future<String> _pixPng(String code) async {
    final file = File('${await _shareDir()}/pix.png');
    await file.writeAsBytes(await _qrPng(code.trim()));
    return file.path;
  }

  static Future<String> _shareDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/share_plus');
    await dir.create(recursive: true);
    return dir.path;
  }

  static Future<Uint8List> _qrPng(String data) async {
    const size = 720.0, margin = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, size + 2 * margin, size + 2 * margin),
        Paint()..color = Colors.white);
    final black = Paint()..color = Colors.black;
    final elements = pw.Barcode.qrCode(
            errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium)
        .make(data, width: size, height: size);
    for (final e in elements) {
      if (e is pw.BarcodeBar && e.black) {
        canvas.drawRect(
            Rect.fromLTWH(margin + e.left, margin + e.top, e.width, e.height),
            black);
      }
    }
    final image = await recorder
        .endRecording()
        .toImage((size + 2 * margin).toInt(), (size + 2 * margin).toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  static Future<Uint8List> _paymentPdf(String code, {required bool pix}) async {
    final barcode = pix ? null : boletoBarcode(code);
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(pix ? 'Pix' : 'Boleto', style: pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 12),
          if (pix) ...[
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: code,
              width: 60 * PdfPageFormat.mm,
              height: 60 * PdfPageFormat.mm,
            ),
            pw.SizedBox(height: 12),
            pw.Text('Pix copia e cola', style: pw.TextStyle(fontSize: 11)),
          ],
          pw.Text(code, style: pw.TextStyle(fontSize: pix ? 10 : 13)),
          if (barcode != null) ...[
            pw.SizedBox(height: 16),
            pw.BarcodeWidget(
              barcode: pw.Barcode.itf(),
              data: barcode,
              width: 103 * PdfPageFormat.mm,
              height: 13 * PdfPageFormat.mm,
              drawText: false,
            ),
          ],
        ],
      ),
    ));
    return doc.save();
  }

  static Future<void> open(BuildContext context, String code) async {
    final kind = Record.paymentCodeKind(code);
    await Clipboard.setData(ClipboardData(text: code.trim()));
    // No bank apps nor file sharing on the computer: the code to paste, and
    // the Pix QR code to scan with the bank app on the phone.
    if (isComputer) {
      final qr = kind == 'Pix' ? await _qrPng(code.trim()) : null;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Pagar $kind'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (qr != null) ...[
                  Image.memory(qr, width: 280, height: 280),
                  const SizedBox(height: 12),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text('Código copiado'),
                  subtitle: Text(
                    qr != null
                        ? 'Escaneie com o app do banco no celular, ou cole o '
                              'código no banco.'
                        : 'Cole no app ou no site do banco.',
                  ),
                ),
                SelectableText(
                  code.trim(),
                  maxLines: 3,
                  style: Theme.of(dialog).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      return;
    }
    final pdf = await _pdf(code);
    final takers = pdf == null
        ? <String>{}
        : (await _apps('shareFileApps', {'mime': 'application/pdf'}))
            .map((a) => a.package)
            .toSet();
    final banks = <(_App, KnownTag)>[];
    _App? secureFolder;
    for (final app in await _apps('launcherApps')) {
      if (app.package == _secureFolder) secureFolder = app;
      final bank = KnownTag.bankIn(app.label);
      if (bank != null) banks.add((app, bank));
    }
    banks.sort((a, b) => a.$1.label.compareTo(b.$1.label));
    if (!context.mounted) return;
    final what = kind == 'Pix' ? 'o Pix em PDF' : 'o boleto em PDF';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Pagar $kind',
                    style: Theme.of(sheet).textTheme.titleLarge),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Código copiado'),
                subtitle: Text(code.trim(),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Divider(height: 1),
              for (final (app, bank) in banks)
                _bankTile(context, sheet, app, bank,
                    pdf: takers.contains(app.package) ? pdf : null,
                    what: what),
              if (secureFolder != null)
                ListTile(
                  leading: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(child: Icon(Icons.lock_outline)),
                  ),
                  title: Text(secureFolder.label),
                  subtitle:
                      const Text('Abra o app do banco lá e cole o código'),
                  onTap: () {
                    Navigator.pop(sheet);
                    _channel.invokeMethod<bool>(
                        'launchApp', {'package': _secureFolder});
                  },
                ),
              if (banks.isEmpty && secureFolder == null)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Nenhum app de banco encontrado'),
                  subtitle: Text('Abra o app do banco e cole o código.'),
                ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Compartilhar…'),
                subtitle: kind == 'Pix'
                    ? const Text('Envia o QR code')
                    : pdf == null
                        ? null
                        : Text('Envia $what'),
                onTap: () async {
                  Navigator.pop(sheet);
                  final params = kind == 'Pix'
                      ? ShareParams(files: [
                          XFile(await _pixPng(code), mimeType: 'image/png')
                        ])
                      : pdf == null
                          ? ShareParams(text: code.trim())
                          : ShareParams(files: [
                              XFile(pdf, mimeType: 'application/pdf')
                            ]);
                  await SharePlus.instance.share(params);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _bankTile(
    BuildContext context,
    BuildContext sheet,
    _App app,
    KnownTag bank, {
    required String? pdf,
    required String what,
  }) {
    return ListTile(
      leading: SizedBox(
        width: 32,
        height: 32,
        child: Center(child: BankMark(bank, size: 32)),
      ),
      title: Text(app.label),
      subtitle: Text(pdf != null
          ? 'Envia $what para o app'
          : 'Abra o pagamento e cole o código'),
      onTap: () async {
        Navigator.pop(sheet);
        final ok = await _channel.invokeMethod<bool>(
                pdf != null ? 'shareFileTo' : 'launchApp', {
              'package': app.package,
              if (pdf != null) 'path': pdf,
              if (pdf != null) 'mime': 'application/pdf',
            }) ??
            false;
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Não deu para abrir ${app.label}. O código está copiado.')));
        }
      },
    );
  }
}

class _App {
  final String package;
  final String label;
  const _App(this.package, this.label);
}
