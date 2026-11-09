import 'package:flutter/foundation.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/cvm-funds.dart';
import 'package:aupp/investments/cvm-store.dart';
import 'package:aupp/investments/fii-store.dart';
import 'package:aupp/investments/sec-fund.dart';
import 'package:aupp/services/logger.dart';

/// Everything the Ficha, Análise and Comparar read from the CVM, the SEC and
/// brapi's lists, downloaded when the app opens (so a screen has it when it
/// opens), one after the other: a phone's connection shared by all of them at
/// once leaves each one waiting. Each store fetches only what changed, unless
/// [preload] is forced (Integrações com API → Dados de investimentos).
class InvestmentData {
  static final _logger = Logger.withClass(InvestmentData);

  /// What is being downloaded now; null when done.
  static final status = ValueNotifier<String?>(null);

  /// When the last [preload] ended, and whether something failed then.
  static DateTime? doneAt;
  static bool failed = false;

  static Future<void>? _running;

  static Future<void> preload({bool force = false}) =>
      _running ??= _preload(force).whenComplete(() {
        _running = null;
        status.value = null;
      });

  static Future<void> _preload(bool force) async {
    failed = false;
    Future<void> step(
      String label,
      Future<void> Function() run, {
      String? Function()? error,
    }) async {
      status.value = label;
      try {
        await run();
        if (error?.call() != null) failed = true;
      } catch (e, st) {
        // One that fails leaves the others to download.
        _logger.handle(e, st, '$label failed');
        failed = true;
      }
    }

    await step('Lista de cotações da B3', () async {
      await B3Market.instance.ensure(force: force);
      await B3Market.funds.ensure(force: force);
    });
    await step(
      'Lista de ETFs e fundos dos EUA (SEC)',
      () => SecFundStore.instance.ensureFundTickers(force: force),
    );
    await step(
      'Balanços das empresas (CVM)',
      () => CvmStore.instance.ensure(force: force),
      error: () => CvmStore.instance.error,
    );
    await step(
      'Informes dos FIIs (CVM)',
      () => FiiStore.instance.ensure(force: force),
      error: () => FiiStore.instance.error,
    );
    for (final part in FundReports.values) {
      await step(
        switch (part) {
          FundReports.register => 'Cadastro dos fundos (CVM)',
          FundReports.daily => 'Informes diários dos fundos (CVM)',
          FundReports.fiagro => 'Informes dos Fiagros (CVM)',
        },
        () => CvmFundStore.instance.ensure(part, force: force),
        error: () => CvmFundStore.instance.errorOf(part),
      );
    }
    doneAt = DateTime.now();
  }
}
