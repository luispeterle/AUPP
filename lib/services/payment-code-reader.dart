import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aupp/dinzo/pix-code.dart';
import 'package:aupp/helpers/itf-reader.dart';
import 'package:aupp/services/logger.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:zxing2/qrcode.dart' as zx;

/// Finds the Pix QR codes and boleto barcodes in a PDF or an image (a bill
/// shared from another app or picked from the files). Each code comes as the
/// app keeps it: the Pix copia-e-cola, the boleto as its digitable line.
class PaymentCodeReader {
  static final _logger = Logger.withClass(PaymentCodeReader);

  /// What the file picker offers.
  static const extensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp'];

  /// A bill rarely has the code past its first pages.
  static const _maxPages = 3;

  /// The phone's barcode reader (ML Kit) exists on the phone only.
  static bool get _phoneReader => Platform.isAndroid || Platform.isIOS;

  /// Sharp enough for a boleto's narrow bars (0.25 mm, 3 pixels).
  static const _dpi = 300.0;

  /// The codes in the file at [path], without repeats; empty when none.
  static Future<List<String>> readFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final found = <String>{};
    if (_isPdf(bytes)) {
      for (var page = 0; page < _maxPages; page++) {
        final raster = await _page(bytes, page);
        if (raster == null) break;
        found.addAll(await _readPixels(raster.$1, raster.$2, raster.$3));
      }
    } else {
      if (_phoneReader) found.addAll(await _readWithPhone(path));
      if (found.isEmpty) {
        final image = await _decodeImage(bytes);
        if (image != null) {
          found.addAll(await _readPure(image.$1, image.$2, image.$3));
        }
      }
    }
    return found.toList();
  }

  static bool _isPdf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 && // %PDF
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;

  /// Page [index] drawn on white (RGBA, width, height); null past the end.
  static Future<(Uint8List, int, int)?> _page(Uint8List pdf, int index) async {
    try {
      await for (final raster in Printing.raster(
        pdf,
        pages: [index],
        dpi: _dpi,
      )) {
        final pixels = raster.pixels;
        // The phone draws the page on a transparent background.
        for (var i = 0; i < pixels.length; i += 4) {
          final a = pixels[i + 3];
          if (a == 255) continue;
          final paper = 255 - a;
          pixels[i] = (pixels[i] + paper).clamp(0, 255);
          pixels[i + 1] = (pixels[i + 1] + paper).clamp(0, 255);
          pixels[i + 2] = (pixels[i + 2] + paper).clamp(0, 255);
          pixels[i + 3] = 255;
        }
        return (pixels, raster.width, raster.height);
      }
    } catch (e) {
      // Past the last page, or not a PDF the system can draw.
      if (index == 0) _logger.warning('Could not draw the PDF: $e');
    }
    return null;
  }

  /// A page: the phone's reader first (it reads photos better), then ours.
  static Future<List<String>> _readPixels(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    if (_phoneReader) {
      final png = await _png(rgba, width, height);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'aupp-code-page.png'));
      await file.writeAsBytes(png, flush: true);
      try {
        final found = await _readWithPhone(file.path);
        if (found.isNotEmpty) return found;
      } finally {
        await file.delete().catchError((_) => file);
      }
    }
    return _readPure(rgba, width, height);
  }

  static Future<Uint8List> _png(Uint8List rgba, int width, int height) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return data!.buffer.asUint8List();
  }

  /// The phone's barcode reader (the camera's, on a file).
  static Future<List<String>> _readWithPhone(String path) async {
    final controller = ms.MobileScannerController(autoStart: false);
    try {
      final capture = await controller.analyzeImage(
        path,
        formats: const [ms.BarcodeFormat.qrCode, ms.BarcodeFormat.itf14],
      );
      return [
        for (final barcode in capture?.barcodes ?? const <ms.Barcode>[])
          if (_accept(barcode.rawValue) case final code?) code,
      ];
    } catch (e) {
      _logger.warning('The phone reader failed: $e');
      return const [];
    } finally {
      await controller.dispose();
    }
  }

  /// A read the app can keep: a Pix copia-e-cola whose checksum matches, or
  /// a whole boleto barcode (as its digitable line). Anything else (a link,
  /// part of the bars) is null.
  static String? _accept(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    if (isPixPayload(text)) return text;
    if (PixCode.isBoletoBarcode(text)) return PixCode.boletoLine(text);
    return null;
  }

  /// A Pix copia-e-cola with its checksum (the last field, 6304 + CRC).
  static bool isPixPayload(String text) {
    if (!text.startsWith('000201') || text.length < 8) return false;
    final body = text.substring(0, text.length - 4);
    if (!body.endsWith('6304')) return false;
    return PixCode.crc16(body) == text.substring(text.length - 4).toUpperCase();
  }

  /// A picture file as RGBA, no wider than a page drawn at [_dpi].
  static Future<(Uint8List, int, int)?> _decodeImage(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final big = descriptor.width > 3000 || descriptor.height > 3000;
      final codec = await descriptor.instantiateCodec(
        targetWidth: big && descriptor.width >= descriptor.height ? 3000 : null,
        targetHeight: big && descriptor.height > descriptor.width ? 3000 : null,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = (data!.buffer.asUint8List(), image.width, image.height);
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return result;
    } catch (e) {
      _logger.warning('Could not open the image: $e');
      return null;
    }
  }

  /// Our own readers, away from the screen's thread.
  static Future<List<String>> _readPure(
    Uint8List rgba,
    int width,
    int height,
  ) => Isolate.run(() => readRgba(rgba, width, height));

  /// The boleto barcodes and the Pix QR code in an RGBA image (opaque).
  static List<String> readRgba(Uint8List rgba, int width, int height) {
    final size = width * height;
    final gray = Uint8List(size);
    final argb = Int32List(size);
    for (var i = 0; i < size; i++) {
      final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
      gray[i] = (r + 2 * g + b) >> 2;
      argb[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
    }
    final found = <String>[
      for (final barcode in ItfReader.read(gray, width, height))
        PixCode.boletoLine(barcode),
    ];
    final source = zx.RGBLuminanceSource(width, height, argb);
    final hints = zx.DecodeHints()..put(zx.DecodeHintType.tryHarder);
    for (final binarizer in [
      zx.HybridBinarizer(source),
      zx.GlobalHistogramBinarizer(source),
    ]) {
      try {
        final result = zx.QRCodeReader().decode(
          zx.BinaryBitmap(binarizer),
          hints: hints,
        );
        final code = _accept(result.text);
        if (code != null) {
          found.add(code);
          break;
        }
      } catch (_) {
        // No QR code here.
      }
    }
    return found;
  }
}
