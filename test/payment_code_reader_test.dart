import 'dart:typed_data';

import 'package:aupp/dinzo/pix-code.dart';
import 'package:aupp/helpers/itf-reader.dart';
import 'package:aupp/services/payment-code-reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zxing2/qrcode.dart';

/// A made-up bank boleto: the check digit (position 5) found by trying.
String bankBarcode() {
  const before = '0019';
  const after = '1234000015075' '00000023456789000123456178';
  for (var dv = 0; dv < 10; dv++) {
    final code = '$before$dv$after';
    if (PixCode.isBoletoBarcode(code)) return code;
  }
  throw StateError('no check digit');
}

const _patterns = [
  'NNWWN', 'WNNNW', 'NWNNW', 'WWNNN', 'NNWNW', //
  'WNWNN', 'NWWNN', 'NNNWW', 'WNNWN', 'NWNWN',
];

/// The widths of the bars and spaces of [digits] in ITF, with margins.
List<(bool, int)> itfRuns(String digits, {int narrow = 3, int wide = 9}) {
  int w(String c) => c == 'W' ? wide : narrow;
  final runs = <(bool, int)>[(false, 40)];
  for (var k = 0; k < 4; k++) {
    runs.add((k.isEven, narrow));
  }
  for (var i = 0; i < digits.length; i += 2) {
    final a = _patterns[int.parse(digits[i])];
    final b = _patterns[int.parse(digits[i + 1])];
    for (var k = 0; k < 5; k++) {
      runs.add((true, w(a[k])));
      runs.add((false, w(b[k])));
    }
  }
  runs
    ..add((true, wide))
    ..add((false, narrow))
    ..add((true, narrow))
    ..add((false, 40));
  return runs;
}

/// A gray image of the barcode, [height] pixels tall.
(Uint8List, int, int) barcodeImage(String digits, {int height = 30}) {
  final row = <int>[
    for (final (dark, width) in itfRuns(digits))
      for (var i = 0; i < width; i++) dark ? 0 : 255,
  ];
  final gray = Uint8List(row.length * height);
  for (var y = 0; y < height; y++) {
    gray.setRange(y * row.length, (y + 1) * row.length, row);
  }
  return (gray, row.length, height);
}

void main() {
  test('boleto check digit: bank and utility', () {
    final bank = bankBarcode();
    expect(PixCode.isBoletoBarcode(bank), isTrue);
    // One digit off fails it.
    final wrong = '${bank.substring(0, 20)}'
        '${(int.parse(bank[20]) + 1) % 10}${bank.substring(21)}';
    expect(PixCode.isBoletoBarcode(wrong), isFalse);
    expect(PixCode.isBoletoBarcode('1234'), isFalse);
    // A utility barcode (type 6: check digit in mod 10).
    for (var dv = 0; dv < 10; dv++) {
      final code = '846${dv}0000001087500912345678901234123456789012';
      if (PixCode.isBoletoBarcode(code)) {
        expect(code.length, 44);
        return;
      }
    }
    fail('no utility check digit');
  });

  test('reads a boleto barcode across, backwards and on its side', () {
    final code = bankBarcode();
    final (gray, width, height) = barcodeImage(code);
    expect(ItfReader.read(gray, width, height), [code]);

    // Mirrored: read right to left.
    final mirrored = Uint8List(gray.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        mirrored[y * width + x] = gray[y * width + width - 1 - x];
      }
    }
    expect(ItfReader.read(mirrored, width, height), [code]);

    // Turned: the bars run across, the code down the page.
    final turned = Uint8List(gray.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        turned[x * height + y] = gray[y * width + x];
      }
    }
    expect(ItfReader.read(turned, height, width), [code]);
  });

  test('a barcode with a wrong check digit is not read', () {
    final code = bankBarcode();
    final wrong = '${code.substring(0, 4)}${(int.parse(code[4]) + 1) % 10}'
        '${code.substring(5)}';
    final (gray, width, height) = barcodeImage(wrong);
    expect(ItfReader.read(gray, width, height), isEmpty);
  });

  test('finds the Pix QR code and the boleto in one image', () {
    final pix = PixCode.build(key: 'teste@exemplo.com', amount: 87.4);
    final matrix = Encoder.encode(pix, ErrorCorrectionLevel.m).matrix!;
    const scale = 6, margin = 24;
    final code = bankBarcode();
    final (bars, barsWidth, barsHeight) = barcodeImage(code, height: 60);
    final qrSize = matrix.width * scale + 2 * margin;
    final width = barsWidth > qrSize ? barsWidth : qrSize;
    final height = qrSize + barsHeight;
    final rgba = Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255);
    void set(int x, int y, int v) {
      final i = (y * width + x) * 4;
      rgba[i] = rgba[i + 1] = rgba[i + 2] = v;
    }

    for (var y = 0; y < matrix.height * scale; y++) {
      for (var x = 0; x < matrix.width * scale; x++) {
        if (matrix.get(x ~/ scale, y ~/ scale) == 1) {
          set(x + margin, y + margin, 0);
        }
      }
    }
    for (var y = 0; y < barsHeight; y++) {
      for (var x = 0; x < barsWidth; x++) {
        set(x, qrSize + y, bars[y * barsWidth + x]);
      }
    }
    final found = PaymentCodeReader.readRgba(rgba, width, height);
    expect(found, containsAll([pix, PixCode.boletoLine(code)]));
    expect(found, hasLength(2));
  });

  test('only a whole Pix copia-e-cola is taken', () {
    final pix = PixCode.build(key: 'teste@exemplo.com');
    expect(PaymentCodeReader.isPixPayload(pix), isTrue);
    expect(PaymentCodeReader.isPixPayload('${pix.substring(0, 20)}0000'),
        isFalse);
    expect(PaymentCodeReader.isPixPayload('https://exemplo.com'), isFalse);
  });
}
