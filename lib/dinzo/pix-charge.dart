import 'dart:convert';

import 'package:aupp/services/logger.dart';
import 'package:http/http.dart' as http;

/// A Pix charge (cobrança: an electricity bill's QR) whose copia-e-cola has
/// no amount, only the address where the receiver's bank keeps it. Read from
/// that address, as the payer's bank app does, by the Pix API of the Banco
/// Central (`GET /{pixUrlAccessToken}` and `GET /cobv/{pixUrlAccessToken}`,
/// a signed JWS). Only when a code is pasted or scanned, never by itself.
class PixCharge {
  static final _logger = Logger.withClass(PixCharge);

  final double amount;
  final DateTime? dueDate;
  final String? receiver;

  /// "ATIVA" while it can be paid; "CONCLUIDA" once paid.
  final String? status;

  const PixCharge({
    required this.amount,
    this.dueDate,
    this.receiver,
    this.status,
  });

  bool get isOpen => status == null || status == 'ATIVA';

  static final _cache = <String, PixCharge?>{};

  /// The charge's address inside a copia-e-cola (field 26, subfield 25), or
  /// null for a Pix with the key in it.
  static String? urlOf(String payload) {
    final account = _field(payload.trim(), '26');
    if (account == null) return null;
    final url = _field(account, '25');
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http') ? url : 'https://$url';
  }

  /// Fetches the charge of [payload]; null when it is not one, or the bank
  /// does not answer. The signature is not checked: the amount is only shown
  /// and saved on the occurrence, and the bank app checks it when paying.
  static Future<PixCharge?> fetch(String payload) async {
    final url = urlOf(payload);
    if (url == null) return null;
    if (_cache.containsKey(url)) return _cache[url];
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        _logger.warning('Pix charge: HTTP ${response.statusCode}');
        return null;
      }
      final charge = parse(response.body);
      _cache[url] = charge;
      return charge;
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to fetch the Pix charge');
      return null;
    }
  }

  /// Reads the JWS the bank answers with.
  static PixCharge? parse(String jws) {
    final parts = jws.trim().split('.');
    if (parts.length != 3) return null;
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final value = body['valor'] as Map<String, dynamic>?;
    final amount = double.tryParse(
      '${value?['final'] ?? value?['original'] ?? ''}',
    );
    if (amount == null || amount <= 0) return null;
    final calendar = body['calendario'] as Map<String, dynamic>?;
    final receiver = body['recebedor'] as Map<String, dynamic>?;
    return PixCharge(
      amount: amount,
      dueDate: DateTime.tryParse('${calendar?['dataDeVencimento'] ?? ''}'),
      receiver: (receiver?['nomeFantasia'] ?? receiver?['nome']) as String?,
      status: body['status'] as String?,
    );
  }

  /// The value of the top-level field [id] of an EMV payload.
  static String? _field(String payload, String id) {
    var i = 0;
    while (i + 4 <= payload.length) {
      final len = int.tryParse(payload.substring(i + 2, i + 4));
      if (len == null || i + 4 + len > payload.length) return null;
      if (payload.substring(i, i + 2) == id) {
        return payload.substring(i + 4, i + 4 + len);
      }
      i += 4 + len;
    }
    return null;
  }
}
