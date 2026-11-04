import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:aupp/services/logger.dart';

/// A bank's capital ratios from the Banco Central's IF.data (Olinda API),
/// for its prudential conglomerate: the Basel ratio (own capital over the
/// risk it carries; the minimum is 11%) and the fixed-asset ratio (equity
/// tied up in buildings and the like; the maximum is 50%).
class BankCapital {
  final double basel;
  final double? fixedAssets;

  /// The quarter the figures are from.
  final DateTime at;

  const BankCapital(this.basel, this.fixedAssets, this.at);

  static const _base =
      'https://olinda.bcb.gov.br/olinda/servico/IFDATA/versao/v1/odata';
  static final _logger = Logger.withClass(BankCapital);
  static final _cache = <String, BankCapital?>{};

  @visibleForTesting
  static void resetForTests() => _cache.clear();

  /// The conglomerate led by a CNPJ root, from IF.data's register.
  @visibleForTesting
  static String? prudentialCode(Map<String, dynamic> json) {
    for (final item in json['value'] as List? ?? const []) {
      final code = (item as Map)['CodConglomeradoPrudencial'] as String?;
      if (code != null && code.isNotEmpty) return code;
    }
    return null;
  }

  /// The ratios in IF.data's summary report; null when the quarter is not out.
  @visibleForTesting
  static BankCapital? fromValues(Map<String, dynamic> json, DateTime at) {
    double? basel;
    double? fixed;
    for (final item in json['value'] as List? ?? const []) {
      final name = ((item as Map)['NomeColuna'] as String? ?? '').trim();
      final value = (item['Saldo'] as num?)?.toDouble();
      if (name == 'Índice de Basileia') basel = value;
      if (name == 'Índice de Imobilização') fixed = value;
    }
    return basel == null ? null : BankCapital(basel, fixed, at);
  }

  /// Quarter ends from the last one before [now], newest first.
  @visibleForTesting
  static List<DateTime> quartersBefore(DateTime now, int count) {
    var month = ((now.month - 1) ~/ 3) * 3;
    var year = now.year;
    final out = <DateTime>[];
    while (out.length < count) {
      if (month == 0) {
        month = 12;
        year--;
      }
      out.add(DateTime(year, month));
      month -= 3;
    }
    return out;
  }

  /// Null for what is not a bank, or without network. Looked up once a run.
  static Future<BankCapital?> fetch(
    String cnpj, {
    http.Client? client,
    DateTime? now,
  }) async {
    final root = cnpj.replaceAll(RegExp(r'\D'), '');
    if (root.length < 8) return null;
    final key = root.substring(0, 8);
    if (_cache.containsKey(key)) return _cache[key];
    final http_ = client ?? http.Client();
    try {
      Future<Map<String, dynamic>?> get(String path) async {
        final response = await http_
            .get(Uri.parse('$_base/$path'))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return null;
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      }

      // Each quarter comes out about three months after it ends.
      for (final quarter in quartersBefore(now ?? DateTime.now(), 4)) {
        final month = '${quarter.year}${quarter.month.toString().padLeft(2, '0')}';
        final register = await get(
          'IfDataCadastro(AnoMes=@AnoMes)?@AnoMes=$month'
          '&\$filter=CnpjInstituicaoLider%20eq%20%27$key%27'
          '&\$select=CodInst,CodConglomeradoPrudencial&\$format=json',
        );
        final code = register == null ? null : prudentialCode(register);
        if (code == null) continue;
        final values = await get(
          'IfDataValores(AnoMes=@AnoMes,TipoInstituicao=@TipoInstituicao,'
          'Relatorio=@Relatorio)?@AnoMes=$month&@TipoInstituicao=1'
          '&@Relatorio=%271%27&\$filter=CodInst%20eq%20%27$code%27'
          '&\$format=json',
        );
        final found = values == null ? null : fromValues(values, quarter);
        if (found != null) return _cache[key] = found;
      }
      return _cache[key] = null;
    } catch (e, st) {
      _logger.handle(e, st, 'IF.data of $key failed');
      return null;
    } finally {
      if (client == null) http_.close();
    }
  }
}
