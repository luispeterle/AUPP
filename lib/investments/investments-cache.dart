import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/dinzo/dinzo-auto-sync.dart';
import 'package:aupp/dinzo/dinzo-api.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/dinzo/daily-money.dart';

/// Everything the Investments tab shows, as last fetched from Dinzo.
class InvestmentsSnapshot {
  final List<DinzoInvestment> investments;

  /// Daily totals: {date, total, by_type}.
  final List<Map<String, dynamic>> history;

  /// B3 dividends/JCP paid in the last 12 months (empty without stocks).
  final List<Map<String, dynamic>> income;
  final double bankBalance;
  final double cardDebt;

  /// False when an account came without a balance ([DinzoBalances.complete]):
  /// the totals above miss it.
  final bool balancesComplete;
  final DateTime fetchedAt;

  InvestmentsSnapshot({
    required this.investments,
    required this.history,
    required this.income,
    required this.bankBalance,
    required this.cardDebt,
    this.balancesComplete = true,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
    'investments': investments.map((i) => i.raw).toList(),
    'history': history,
    'income': income,
    'bankBalance': bankBalance,
    'cardDebt': cardDebt,
    'balancesComplete': balancesComplete,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory InvestmentsSnapshot.fromJson(Map<String, dynamic> json) =>
      InvestmentsSnapshot(
        investments: (json['investments'] as List)
            .map((i) => DinzoInvestment.fromJson(i as Map<String, dynamic>))
            .toList(),
        history: (json['history'] as List).cast<Map<String, dynamic>>(),
        income: ((json['income'] as List?) ?? const [])
            .cast<Map<String, dynamic>>(),
        bankBalance: (json['bankBalance'] as num).toDouble(),
        cardDebt: (json['cardDebt'] as num).toDouble(),
        balancesComplete: json['balancesComplete'] as bool? ?? true,
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      );
}

/// Local copy of the Dinzo investment data, so the tab opens instantly and
/// offline. Refreshed by every sync and by the tab's refresh button. Derived
/// data: not part of backups.
class InvestmentsCache {
  static final _logger = Logger.withClass(InvestmentsCache);
  static const _fileName = 'dinzo_investments.json';

  static Future<File> _file() async {
    final dir = await DemoMode.supportDirectory();
    return File(join(dir.path, _fileName));
  }

  static Future<InvestmentsSnapshot?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return InvestmentsSnapshot.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to read the investments cache');
      return null;
    }
  }

  static Future<void> save(InvestmentsSnapshot snapshot) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(snapshot.toJson()));
    await DailyMoney.refreshFromCache();
  }

  static const _pendingName = 'dinzo_investments_pending.json';

  static Future<File> _pendingFile() async {
    final dir = await DemoMode.supportDirectory();
    return File(join(dir.path, _pendingName));
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// A refresh started today and not finished (closed app, no network,
  /// Dinzo limit): the next one continues from there.
  static Future<bool> hasPending() async {
    try {
      final file = await _pendingFile();
      if (!await file.exists()) return false;
      final json = jsonDecode(await file.readAsString());
      return json['day'] == _today();
    } catch (_) {
      return false;
    }
  }

  static Completer<List<DinzoInvestment>>? _fetching;

  /// Progress of the positions fetch, for the sync notification.
  static final ValueNotifier<DinzoAutoSyncStatus?> status = ValueNotifier(null);

  /// Every position with its movements, one request per position. Progress
  /// is saved after each one, so a fetch interrupted today continues where
  /// it stopped; [restart] (the refresh button) starts over.
  static Future<List<DinzoInvestment>> fetch(
    DinzoApi api, {
    bool restart = false,
  }) async {
    if (_fetching != null) return _fetching!.future;
    final fetching = _fetching = Completer<List<DinzoInvestment>>();
    fetching.future.ignore();
    try {
      final file = await _pendingFile();
      Map<String, dynamic>? pending;
      if (!restart && await hasPending()) {
        pending = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
      final ids =
          (pending?['ids'] as List?)?.cast<String>() ??
          await api.investmentIds();
      final details = <String, dynamic>{
        ...?(pending?['details'] as Map<String, dynamic>?),
      };
      if (pending != null) {
        _logger.info(
          'Resuming investments fetch: ${details.length}/${ids.length} done',
        );
      }
      void progress() => status.value = DinzoAutoSyncStatus(
        DinzoAutoSyncState.running,
        'Lendo posições: ${details.length}/${ids.length}',
        done: details.length,
        total: ids.length,
      );
      progress();
      for (final id in ids) {
        if (details.containsKey(id)) continue;
        details[id] = await api.investment(id);
        await file.writeAsString(
          jsonEncode({'day': _today(), 'ids': ids, 'details': details}),
        );
        progress();
      }
      if (await file.exists()) await file.delete();
      final result = await withBrokers(api, [
        for (final id in ids)
          DinzoInvestment.fromJson(details[id] as Map<String, dynamic>),
      ]);
      final total = result.fold<double>(0, (s, i) => s + i.balance);
      status.value = DinzoAutoSyncStatus(
        DinzoAutoSyncState.applied,
        '${result.length} posições atualizadas · R\$ '
        '${total.toStringAsFixed(2).replaceAll('.', ',')}',
      );
      fetching.complete(result);
      return result;
    } catch (e, st) {
      status.value = DinzoAutoSyncStatus(
        DinzoAutoSyncState.failed,
        e is DinzoApiException
            ? 'Parou: ${e.message}. Continua de onde parou na próxima vez.'
            : 'Parou ($e). Continua de onde parou na próxima vez.',
      );
      fetching.completeError(e, st);
      rethrow;
    } finally {
      _fetching = null;
    }
  }

  /// Dinzo's REST positions don't say where they're held: the bank comes
  /// from the MCP ([DinzoApi.investmentConnectors], one request). If that
  /// fails, the previous cache's banks are kept.
  static Future<List<DinzoInvestment>> withBrokers(
    DinzoApi api,
    List<DinzoInvestment> investments,
  ) async {
    Map<String, String> brokers;
    try {
      brokers = await api.investmentConnectors();
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to read where the investments are held');
      brokers = {
        for (final inv in (await load())?.investments ?? <DinzoInvestment>[])
          if (inv.broker != null) inv.assetKey: inv.broker!,
      };
    }
    return [
      for (final inv in investments)
        if (brokers['${inv.raw['id']}'] ?? brokers[inv.assetKey]
            case final broker?)
          DinzoInvestment.fromJson({...inv.raw, 'broker': broker})
        else
          inv,
    ];
  }

  /// On app open/resume: finishes a refresh left halfway today.
  static Future<void> resumePending() async {
    if (DemoMode.active) return;
    if (DinzoSyncService.apiKey == null || !await hasPending()) return;
    try {
      await refresh();
    } catch (e, st) {
      _logger.handle(e, st, 'Resuming the investments refresh failed');
    }
  }

  /// Fetches investments, history, income and balances from Dinzo.
  /// [restart] drops a refresh left halfway instead of continuing it.
  static Future<InvestmentsSnapshot> refresh({bool restart = false}) async {
    // The demo's data is made up once, at its start: nothing to fetch.
    if (DemoMode.active) {
      final cached = await load();
      if (cached != null) return cached;
    }
    final key = DinzoSyncService.apiKey;
    if (key == null) {
      throw DinzoApiException(
        null,
        'missing_key',
        'Chave da API não configurada',
      );
    }
    final api = DinzoApi(key);
    try {
      final accounts = await api.accounts();
      final investments = await fetch(api, restart: restart);
      final balances = DailyMoney.balances(accounts, investments);
      final now = DateTime.now();
      final snapshot = InvestmentsSnapshot(
        investments: investments,
        history: await api.investmentSnapshots(),
        income: await api.investmentIncome(
          DateTime(now.year - 1, now.month, now.day),
          now,
        ),
        bankBalance: balances.bank,
        cardDebt: balances.cardDebt,
        balancesComplete: balances.complete,
        fetchedAt: now,
      );
      await save(snapshot);
      return snapshot;
    } finally {
      api.close();
    }
  }
}
