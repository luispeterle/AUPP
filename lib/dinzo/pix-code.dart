/// Pix copia-e-cola (BR Code, the Banco Central's static Pix payload) made
/// from a Pix key, and the boleto barcode turned into its digitable line.
/// Everything here is local: no API is called.
class PixCode {
  /// Static Pix payload for [key], with [amount] already set when given.
  /// The bank app shows the real name of the key's owner; [name] and [city]
  /// only fill the fields the format requires.
  static String build({
    required String key,
    String? name,
    String? city,
    double? amount,
  }) {
    String field(String id, String value) =>
        '$id${value.length.toString().padLeft(2, '0')}$value';

    final payload = StringBuffer()
      ..write(field('00', '01'))
      ..write(
        field(
          '26',
          field('00', 'br.gov.bcb.pix') + field('01', normalizeKey(key)),
        ),
      )
      ..write(field('52', '0000'))
      ..write(field('53', '986'));
    if (amount != null && amount > 0) {
      payload.write(field('54', amount.toStringAsFixed(2)));
    }
    payload
      ..write(field('58', 'BR'))
      ..write(field('59', _plain(name, 'PIX', 25)))
      ..write(field('60', _plain(city, 'BRASIL', 15)))
      ..write(field('62', field('05', '***')))
      ..write('6304');
    final text = payload.toString();
    return text + crc16(text);
  }

  /// The key the way the Pix directory stores it: CPF/CNPJ digits only,
  /// e-mail and random key in lowercase, phone as +55 and digits.
  static String normalizeKey(String key) {
    final k = key.trim();
    if (k.contains('@')) return k.toLowerCase();
    if (RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(k)) {
      return k.toLowerCase();
    }
    final digits = k.replaceAll(RegExp(r'\D'), '');
    if (k.startsWith('+')) return '+$digits';
    if (!RegExp(r'^[\d.\-/() ]+$').hasMatch(k)) return k;
    // CPF or CNPJ, with or without dots, dash or slash.
    if (digits.length == 14) return digits;
    if (digits.length == 11 && !k.contains('(') && _isCpf(digits)) {
      return digits;
    }
    // A phone with area code, typed without +55: 48999999999 (11 digits
    // that are not a CPF), (11) 99999-9999 or a landline's 10 digits.
    if (digits.length == 10 || digits.length == 11) return '+55$digits';
    // With the country code but no +: 5548999999999.
    if (digits.length >= 12 && digits.startsWith('55')) return '+$digits';
    return k;
  }

  /// Whether 11 digits make a CPF: its two check digits match. A phone
  /// with area code has 11 digits too.
  static bool _isCpf(String digits) {
    final d = digits.split('').map(int.parse).toList();
    if (d.toSet().length == 1) return false;
    for (final n in [9, 10]) {
      var sum = 0;
      for (var i = 0; i < n; i++) {
        sum += d[i] * (n + 1 - i);
      }
      if (sum * 10 % 11 % 10 != d[n]) return false;
    }
    return true;
  }

  /// "Telefone", "CPF", "CNPJ", "E-mail" or "Chave aleatória".
  static String keyKind(String key) {
    final k = normalizeKey(key);
    if (k.contains('@')) return 'E-mail';
    if (k.startsWith('+')) return 'Telefone';
    if (RegExp(r'^\d{11}$').hasMatch(k)) return 'CPF';
    if (RegExp(r'^\d{14}$').hasMatch(k)) return 'CNPJ';
    return 'Chave aleatória';
  }

  /// Whether [text] is a whole Pix copia-e-cola rather than a key.
  static bool isPayload(String text) => text.trim().startsWith('000201');

  /// The amount a code asks for: a Pix with a set value, or a boleto with
  /// one (utility boletos may only carry a reference). Null when it has none.
  static double? amountOf(String code) {
    final c = code.trim();
    if (isPayload(c)) {
      // Top-level fields: id (2), length (2), value.
      var i = 0;
      while (i + 4 <= c.length) {
        final id = c.substring(i, i + 2);
        final len = int.tryParse(c.substring(i + 2, i + 4));
        if (len == null || i + 4 + len > c.length) return null;
        if (id == '54') {
          final v = double.tryParse(c.substring(i + 4, i + 4 + len));
          return v != null && v > 0 ? v : null;
        }
        i += 4 + len;
      }
      return null;
    }
    final barcode = _barcodeOf(c.replaceAll(RegExp(r'[\s.\-]'), ''));
    if (barcode == null) return null;
    final String cents;
    if (barcode.startsWith('8')) {
      // The third digit says whether it is a real amount (6, 8) or not.
      if (barcode[2] != '6' && barcode[2] != '8') return null;
      cents = barcode.substring(4, 15);
    } else {
      cents = barcode.substring(9, 19);
    }
    final v = int.parse(cents) / 100;
    return v > 0 ? v : null;
  }

  /// The due date of a bank boleto (its due factor: days counted from
  /// 2025-02-22 = 1000, since the factor restarted). Utility boletos have no
  /// standard one, and a Pix charge's comes from the bank ([PixCharge]).
  static DateTime? dueDateOf(String code) {
    final barcode = _barcodeOf(code.trim().replaceAll(RegExp(r'[\s.\-]'), ''));
    if (barcode == null || barcode.startsWith('8')) return null;
    final factor = int.parse(barcode.substring(5, 9));
    if (factor < 1000) return null;
    final base = DateTime(2025, 2, 22);
    return DateTime(base.year, base.month, base.day + factor - 1000);
  }

  /// The 44-digit barcode of a boleto, from the barcode or its line.
  static String? _barcodeOf(String digits) {
    if (RegExp(r'^\d{44}$').hasMatch(digits)) return digits;
    if (RegExp(r'^\d{48}$').hasMatch(digits)) {
      return [for (var i = 0; i < 48; i += 12) digits.substring(i, i + 11)]
          .join();
    }
    if (RegExp(r'^\d{47}$').hasMatch(digits)) {
      return digits.substring(0, 4) +
          digits[32] +
          digits.substring(33) +
          digits.substring(4, 9) +
          digits.substring(10, 20) +
          digits.substring(21, 31);
    }
    return null;
  }

  /// Whether [digits] is a whole boleto barcode: 44 digits whose check digit
  /// matches (a bank boleto's in position 5, a utility's in position 4). A
  /// misread or a partial read of the bars fails it.
  static bool isBoletoBarcode(String digits) {
    if (!RegExp(r'^\d{44}$').hasMatch(digits)) return false;
    if (digits.startsWith('8')) {
      final rest = digits.substring(0, 3) + digits.substring(4);
      final type = digits[2];
      final String dv;
      if (type == '6' || type == '7') {
        dv = _mod10(rest);
      } else if (type == '8' || type == '9') {
        dv = _mod11(rest);
      } else {
        return false;
      }
      return digits[3] == dv;
    }
    final rest = digits.substring(0, 4) + digits.substring(5);
    var sum = 0;
    var weight = 2;
    for (var i = rest.length - 1; i >= 0; i--) {
      sum += int.parse(rest[i]) * weight;
      weight = weight == 9 ? 2 : weight + 1;
    }
    final r = sum % 11;
    final dv = r == 0 || r == 1 ? 1 : 11 - r;
    return digits[4] == '$dv';
  }

  /// The 44-digit boleto barcode (what the camera reads) as the digitable
  /// line bank apps show; anything else is returned as it came.
  static String boletoLine(String scanned) {
    final b = scanned.trim();
    if (!RegExp(r'^\d{44}$').hasMatch(b)) return b;
    if (b.startsWith('8')) {
      // Utilities and taxes: four blocks of 11, each with its check digit.
      final mod10 = b[2] == '6' || b[2] == '7';
      return [
        for (var i = 0; i < 44; i += 11)
          b.substring(i, i + 11) +
              (mod10
                  ? _mod10(b.substring(i, i + 11))
                  : _mod11(b.substring(i, i + 11))),
      ].join();
    }
    final free = b.substring(19);
    final f1 = b.substring(0, 4) + free.substring(0, 5);
    final f2 = free.substring(5, 15);
    final f3 = free.substring(15, 25);
    return f1 +
        _mod10(f1) +
        f2 +
        _mod10(f2) +
        f3 +
        _mod10(f3) +
        b[4] +
        b.substring(5, 19);
  }

  static String _mod10(String digits) {
    var sum = 0;
    var weight = 2;
    for (var i = digits.length - 1; i >= 0; i--) {
      final p = int.parse(digits[i]) * weight;
      sum += p > 9 ? p - 9 : p;
      weight = weight == 2 ? 1 : 2;
    }
    return ((10 - sum % 10) % 10).toString();
  }

  static String _mod11(String digits) {
    var sum = 0;
    var weight = 2;
    for (var i = digits.length - 1; i >= 0; i--) {
      sum += int.parse(digits[i]) * weight;
      weight = weight == 9 ? 2 : weight + 1;
    }
    final rest = sum % 11;
    return (rest == 0 || rest == 1 ? 0 : 11 - rest).toString();
  }

  /// Uppercase ASCII without accents, cut to [max] characters.
  static String _plain(String? text, String fallback, int max) {
    const from = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
    const to = 'AAAAAEEEEIIIIOOOOOUUUUCN';
    final upper = (text ?? '').trim().toUpperCase();
    final out = StringBuffer();
    for (final ch in upper.split('')) {
      final i = from.indexOf(ch);
      final c = i >= 0 ? to[i] : ch;
      if (RegExp(r'[A-Z0-9 ]').hasMatch(c)) out.write(c);
    }
    final s = out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return fallback;
    return s.length > max ? s.substring(0, max).trim() : s;
  }

  /// CRC16-CCITT (polynomial 0x1021, start 0xFFFF), as the format asks.
  static String crc16(String text) {
    var crc = 0xFFFF;
    for (final byte in text.codeUnits) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
        crc &= 0xFFFF;
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
