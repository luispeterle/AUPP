import 'dart:typed_data';

import 'package:aupp/dinzo/pix-code.dart';

/// Reads a boleto barcode (Interleaved 2 of 5, 44 digits) from a grayscale
/// image, in pure Dart: where the phone's barcode reader is missing (the
/// computer) or did not find it. Made for a PDF page drawn as an image, where
/// the bars are sharp; a photo is the phone reader's job.
class ItfReader {
  /// Narrow (N) and wide (W) widths of each digit, 0 to 9.
  static const _patterns = [
    'NNWWN', 'WNNNW', 'NWNNW', 'WWNNN', 'NNWNW', //
    'WNWNN', 'NWWNN', 'NNNWW', 'WNNWN', 'NWNWN',
  ];

  /// Bars and spaces of a 44-digit code: start (4), 22 pairs of digits
  /// (10 each), end (3).
  static const _elements = 4 + 22 * 10 + 3;

  /// The 44-digit barcodes found in [gray] (one byte per pixel, rows of
  /// [width]), only the ones whose check digit matches. Looks across rows
  /// and down columns, both ways, so a page on its side reads too.
  static List<String> read(Uint8List gray, int width, int height) {
    final found = <String>{};
    void scan(Uint8List line) {
      final runs = _runs(line);
      if (runs == null) return;
      for (final code in _decodeRuns(runs.$1, runs.$2)) {
        found.add(code);
      }
    }

    // A boleto's bars are about 13 mm tall: lines every few pixels cross
    // them several times, and one clean line is enough.
    final rowStep = (height / 300).ceil().clamp(1, 12);
    for (var y = 0; y < height; y += rowStep) {
      scan(Uint8List.sublistView(gray, y * width, (y + 1) * width));
    }
    if (found.isNotEmpty) return found.toList();
    final colStep = (width / 300).ceil().clamp(1, 12);
    final column = Uint8List(height);
    for (var x = 0; x < width; x += colStep) {
      for (var y = 0; y < height; y++) {
        column[y] = gray[y * width + x];
      }
      scan(column);
    }
    return found.toList();
  }

  /// Lengths of the dark and light stretches of [line], and whether the
  /// first one is dark. Null when the line is all one shade.
  static (List<int>, bool)? _runs(Uint8List line) {
    var min = 255, max = 0;
    for (final v in line) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    if (max - min < 60) return null;
    final threshold = (min + max) ~/ 2;
    final runs = <int>[];
    final firstDark = line[0] < threshold;
    var dark = firstDark;
    var length = 0;
    for (final v in line) {
      final d = v < threshold;
      if (d == dark) {
        length++;
      } else {
        runs.add(length);
        dark = d;
        length = 1;
      }
    }
    runs.add(length);
    // Too few stretches to hold a boleto's bars.
    if (runs.length < _elements) return null;
    return (runs, firstDark);
  }

  /// Every valid code in a line given as [runs] (stretch lengths) starting
  /// dark or light ([firstDark]); read forwards and backwards.
  static Iterable<String> _decodeRuns(List<int> runs, bool firstDark) sync* {
    for (final reversed in [false, true]) {
      final r = reversed ? runs.reversed.toList() : runs;
      // Whether the stretch at i is dark.
      final lastDark = firstDark == runs.length.isOdd;
      final startDark = reversed ? lastDark : firstDark;
      for (var i = 0; i + _elements <= r.length; i++) {
        if ((i.isEven) != startDark) continue; // a code starts on a bar
        final code = _decodeAt(r, i);
        if (code != null) yield code;
      }
    }
  }

  /// The code whose start pattern begins at [runs][i], or null.
  static String? _decodeAt(List<int> runs, int i) {
    // Start: four narrow stretches, alike.
    final start = runs.sublist(i, i + 4);
    final narrow = start.reduce((a, b) => a + b) / 4;
    for (final s in start) {
      if (s > narrow * 1.8 || s * 1.8 < narrow) return null;
    }
    // Light margin before it (or the edge of the image).
    if (i > 0 && runs[i - 1] < narrow * 4) return null;
    final digits = StringBuffer();
    var at = i + 4;
    for (var pair = 0; pair < 22; pair++) {
      final bars = [for (var k = 0; k < 5; k++) runs[at + 2 * k]];
      final spaces = [for (var k = 0; k < 5; k++) runs[at + 2 * k + 1]];
      final a = _digit(bars);
      final b = _digit(spaces);
      if (a == null || b == null) return null;
      digits
        ..write(a)
        ..write(b);
      at += 10;
    }
    // End: wide bar, narrow space, narrow bar.
    final endBar = runs[at];
    if (endBar < runs[at + 1] * 1.5 || endBar < runs[at + 2] * 1.5) {
      return null;
    }
    final code = digits.toString();
    return PixCode.isBoletoBarcode(code) ? code : null;
  }

  /// The digit five widths stand for: the two widest are the wide ones,
  /// clearly wider than the other three.
  static int? _digit(List<int> widths) {
    final sorted = [...widths]..sort();
    if (sorted[3] < sorted[2] * 1.5) return null;
    final cut = (sorted[2] + sorted[3]) / 2;
    final pattern = widths.map((w) => w > cut ? 'W' : 'N').join();
    final d = _patterns.indexOf(pattern);
    return d < 0 ? null : d;
  }
}
