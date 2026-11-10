import 'dart:convert';
import 'dart:io';

import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/services/logger.dart';

import 'dinzo-models.dart';
import 'dinzo-rate-limit.dart';
import 'dinzo-taxes.dart';

class DinzoApiException implements Exception {
  final int? status;
  final String code;
  final String message;

  DinzoApiException(this.status, this.code, this.message);

  @override
  String toString() => 'DinzoApiException($status, $code): $message';
}

/// Totals that make up the user's real money, read on every sync.
class DinzoBalances {
  /// Sum of the accounts in the everyday banks (cards excluded).
  final double bank;

  /// Card used limit: open bills plus future installments.
  final double cardDebt;

  /// What the everyday banks hold beyond the accounts and is chosen as
  /// everyday money ([DailyBanks]): CDB, cofrinho, whatever the user chose.
  final double parked;

  /// Accounts that count in the totals but came without a balance (a bank
  /// still refreshing). The totals then miss them: a card left out would show
  /// its whole bill as money.
  final List<String> unknown;

  DinzoBalances({
    required this.bank,
    required this.cardDebt,
    required this.parked,
    this.unknown = const [],
  });

  bool get complete => unknown.isEmpty;

  /// What the wallets divide, see [DailyMoney].
  double get money => bank + parked - cardDebt;

  /// What the default wallet starts at on the first sync.
  double get spendable => bank - cardDebt;
}

/// Client for https://api.dinzo.com.br/v1. Reads, asks the banks to refresh,
/// and renames a transaction when the user renames its record. Nothing else
/// is ever written to Dinzo.
class DinzoApi {
  static final _logger = Logger.withClass(DinzoApi);
  static const String baseUrl = 'https://api.dinzo.com.br';

  final String apiKey;
  final HttpClient _client;

  DinzoApi(this.apiKey, {HttpClient? client})
    : _client = client ?? HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);

  void close() => _client.close();

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
    int attempt = 0,
  }) async {
    if (DemoMode.active) {
      throw DinzoApiException(
        null,
        'demo',
        'Modo demonstração: sem conexão com a Dinzo',
      );
    }
    final blocked = DinzoRateLimiter.blockedUntil;
    if (blocked != null && blocked.isAfter(DateTime.now())) {
      // Daily quota spent: don't waste requests until Dinzo frees it.
      throw DinzoApiException(
        429,
        'rate_limited',
        'Limite diário da Dinzo atingido; libera às '
            '${blocked.hour.toString().padLeft(2, '0')}:'
            '${blocked.minute.toString().padLeft(2, '0')}',
      );
    }
    await DinzoRateLimiter.acquire();
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = await _client.openUrl(method, uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    // The MCP endpoint answers JSON-RPC as a server-sent event.
    request.headers.set(
      HttpHeaders.acceptHeader,
      path == '/mcp'
          ? 'application/json, text/event-stream'
          : 'application/json',
    );
    if (payload != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
    }
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response.transform(utf8.decoder).join();
    await DinzoRateLimiter.recordServer(response.headers.value('ratelimit'));
    final retryAfter = int.tryParse(
      response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
    );
    // A refresh refused with 429 is Pluggy's limit for that one connection
    // (its retry_after can be hours), not our API quota: the caller skips the
    // connection; blocking here locked the whole app out of Dinzo.
    final quota429 = response.statusCode == 429 && !path.endsWith('/refresh');
    if (quota429 && (retryAfter ?? 0) > 60) {
      // Daily quota, not the per-minute one: stop until it frees.
      await DinzoRateLimiter.block(Duration(seconds: retryAfter!));
    } else if (quota429 && attempt < 3) {
      final wait = retryAfter ?? 5;
      _logger.warning('Dinzo rate limit on $path, retrying in ${wait}s');
      await Future.delayed(Duration(seconds: wait));
      return _request(
        method,
        path,
        query: query,
        payload: payload,
        attempt: attempt + 1,
      );
    }
    if (response.statusCode >= 400) {
      String code = 'http_${response.statusCode}';
      String message = body;
      try {
        final problem = jsonDecode(body) as Map<String, dynamic>;
        code = problem['code'] as String? ?? code;
        message =
            problem['detail'] as String? ??
            problem['title'] as String? ??
            message;
      } catch (_) {}
      throw DinzoApiException(response.statusCode, code, message);
    }
    if (body.startsWith('event:') || body.startsWith('data:')) {
      final data = body
          .split('\n')
          .where((l) => l.startsWith('data:'))
          .map((l) => l.substring(5).trim())
          .join();
      return jsonDecode(data);
    }
    return body.isEmpty ? null : jsonDecode(body);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) =>
      _request('GET', path, query: query);

  Future<List<DinzoAccount>> accounts() async {
    final json = await _get('/v1/accounts') as Map<String, dynamic>;
    return (json['data'] as List)
        .map((a) => DinzoAccount.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<List<DinzoCategory>> categories() async {
    final json = await _get('/v1/categories') as Map<String, dynamic>;
    return (json['data'] as List)
        .map((c) => DinzoCategory.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// All transactions between [from] and [to] (inclusive), one row per card
  /// purchase (`view=ledger`). Windows longer than the API's 366-day limit
  /// are split.
  Future<List<DinzoTransaction>> transactions(
    DateTime from,
    DateTime to,
  ) async {
    final result = <DinzoTransaction>[];
    var windowStart = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!windowStart.isAfter(end)) {
      var windowEnd = windowStart.add(const Duration(days: 365));
      if (windowEnd.isAfter(end)) windowEnd = end;
      String? cursor;
      do {
        final json = await _get('/v1/transactions', {
          'from': _day(windowStart),
          'to': _day(windowEnd),
          'view': 'ledger',
          'limit': '100',
          if (cursor != null) 'cursor': cursor,
        }) as Map<String, dynamic>;
        result.addAll(
          (json['data'] as List).map(
            (t) => DinzoTransaction.fromJson(t as Map<String, dynamic>),
          ),
        );
        cursor = json['has_more'] == true
            ? json['next_cursor'] as String?
            : null;
      } while (cursor != null);
      windowStart = windowEnd.add(const Duration(days: 1));
    }
    return result;
  }

  /// Every position now, without its movements (one request).
  Future<List<DinzoInvestment>> investmentsNow() async {
    final json = await _get('/v1/investments') as Map<String, dynamic>;
    return [
      for (final row in (json['data'] as List).cast<Map<String, dynamic>>())
        if (row['archived'] != true) DinzoInvestment.fromJson(row),
    ];
  }

  /// Ids of the investment positions (archived ones aside). Each one's
  /// movements need its own request ([investment]); InvestmentsCache.fetch
  /// reads them resumably.
  Future<List<String>> investmentIds() async {
    final json = await _get('/v1/investments') as Map<String, dynamic>;
    return [
      for (final row in (json['data'] as List).cast<Map<String, dynamic>>())
        if (row['archived'] != true) '${row['id']}',
    ];
  }

  /// Bank connector of each position ("Nubank"), keyed by both the row `id`
  /// and the `asset_key` (several CDBs share one asset_key). REST
  /// `/v1/investments` doesn't say where a position is held (stocks come with
  /// no issuer); the MCP tool `listar_investimentos` adds its connection.
  Future<Map<String, String>> investmentConnectors() async {
    final json = await _request(
      'POST',
      '/mcp',
      payload: {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'listar_investimentos',
          'arguments': {'incluir_arquivados': true},
        },
      },
    ) as Map<String, dynamic>;
    final result = json['result'] as Map<String, dynamic>?;
    if (result == null || result['isError'] == true) {
      throw DinzoApiException(
        null,
        'mcp_error',
        '${json['error'] ?? result?['content'] ?? 'MCP sem resultado'}',
      );
    }
    final content =
        result['structuredContent'] as Map<String, dynamic>? ??
        jsonDecode((result['content'] as List).first['text'] as String)
            as Map<String, dynamic>;
    final connectors = <String, String>{};
    for (final row
        in (content['investments'] as List).cast<Map<String, dynamic>>()) {
      final connector = row['connection']?['connector_name'];
      if (connector is! String) continue;
      connectors['${row['id']}'] = connector;
      connectors.putIfAbsent(row['asset_key'] as String, () => connector);
    }
    return connectors;
  }

  /// One position with its movements, as the raw API object.
  Future<Map<String, dynamic>> investment(String id) async =>
      await _get('/v1/investments/$id') as Map<String, dynamic>;

  /// The user's profile, plan and token scopes.
  Future<Map<String, dynamic>> me() async =>
      await _get('/v1/me') as Map<String, dynamic>;

  /// Net worth, open card bills and bills due in the next 30 days.
  Future<Map<String, dynamic>> overview() async =>
      await _get('/v1/overview') as Map<String, dynamic>;

  /// Accounts as raw API rows (titles and bank connectors).
  Future<List<Map<String, dynamic>>> accountsRaw() async {
    final json = await _get('/v1/accounts') as Map<String, dynamic>;
    return (json['data'] as List).cast<Map<String, dynamic>>();
  }

  /// Recurring charges Dinzo detected or the user confirmed.
  Future<List<Map<String, dynamic>>> subscriptions() async {
    final json = await _get('/v1/subscriptions') as Map<String, dynamic>;
    return (json['data'] as List).cast<Map<String, dynamic>>();
  }

  /// Daily snapshots of the total invested and its split by asset type,
  /// oldest first, as raw API rows.
  Future<List<Map<String, dynamic>>> investmentSnapshots() async {
    final json =
        await _get('/v1/investments/snapshots') as Map<String, dynamic>;
    return (json['data'] as List).cast<Map<String, dynamic>>();
  }

  /// Dividends/JCP of B3 assets paid in the window, as raw API rows; empty
  /// when the market data source is unavailable.
  Future<List<Map<String, dynamic>>> investmentIncome(
    DateTime from,
    DateTime to,
  ) async {
    final json = await _get('/v1/investments/income', {
      'from': _day(from),
      'to': _day(to),
    }) as Map<String, dynamic>;
    if (json['available'] == false) return const [];
    return ((json['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// Renames a transaction in Dinzo (its display description).
  Future<void> renameTransaction(String id, String description) => _request(
    'PATCH',
    '/v1/transactions/$id',
    payload: {'description': description},
  );

  /// Moves a transaction to another category in Dinzo (null = none).
  Future<void> setTransactionCategory(String id, String? categoryId) =>
      _request(
        'PATCH',
        '/v1/transactions/$id',
        payload: {'category_id': categoryId},
      );

  /// Asks every Open Finance connection to sync with its bank. Best effort:
  /// a connection that is busy, rate limited or waiting for the user is
  /// skipped. Returns the names of the connections that need attention.
  Future<List<String>> refreshConnections() async {
    final json =
        await _get('/v1/open-finance/connections') as Map<String, dynamic>;
    final needsAttention = <String>[];
    for (final c in (json['data'] as List).cast<Map<String, dynamic>>()) {
      // Leftovers of abandoned connection attempts back no account: nothing
      // to refresh and nothing the user needs to fix for the sync.
      if ((c['accounts'] as List?)?.isEmpty ?? true) continue;
      final name = c['connector_name'] as String? ?? 'Conexão sem nome';
      final status = c['status'] as String?;
      if (status == 'WAITING_USER_INPUT' || status == 'LOGIN_ERROR') {
        needsAttention.add(name);
        continue;
      }
      try {
        await _request(
          'POST',
          '/v1/open-finance/connections/${c['id']}/refresh',
        );
      } on DinzoApiException catch (e) {
        _logger.info('Refresh of "$name" skipped: ${e.code} ${e.message}');
      }
    }
    return needsAttention;
  }

  /// Polls until no connection is mid-sync, or [timeout] passes.
  Future<void> waitForConnections({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final json =
          await _get('/v1/open-finance/connections') as Map<String, dynamic>;
      const busyStates = {
        'UPDATING',
        'CREATING',
        'LOGIN_IN_PROGRESS',
        'MERGING',
        'TRANSACTIONS_IN_PROGRESS',
        'ACCOUNTS_IN_PROGRESS',
      };
      final busy = (json['data'] as List).cast<Map<String, dynamic>>().any(
        (c) =>
            busyStates.contains(c['status']) ||
            busyStates.contains(c['execution_status']),
      );
      if (!busy) return;
      await Future.delayed(const Duration(seconds: 5));
    }
    _logger.warning('Dinzo connections still syncing after $timeout');
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
