import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/dinzo/dinzo-api.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/services/logger.dart';

/// A credit card bill due soon (Dinzo `/v1/overview` `next_bills`).
class UpcomingBill {
  final String cardAccountId;
  final String cardTitle;

  /// Bank connector of the card (e.g. "C6 Bank"), for its logo.
  final String? connector;
  final double amount;
  final DateTime dueDate;
  final bool isEstimate;

  UpcomingBill({
    required this.cardAccountId,
    required this.cardTitle,
    required this.connector,
    required this.amount,
    required this.dueDate,
    required this.isEstimate,
  });
}

class ActiveSubscription {
  final String name;
  final double amount;
  final int? chargeDay;
  final String cadence;

  ActiveSubscription(this.name, this.amount, this.chargeDay, this.cadence);

  /// Next charge from the day of the month (monthly cadence assumed).
  DateTime? nextCharge(DateTime today) {
    if (chargeDay == null) return null;
    final day = DateTime(today.year, today.month, today.day);
    var next = DateTime(today.year, today.month, chargeDay!);
    if (next.isBefore(day))
      next = DateTime(today.year, today.month + 1, chargeDay!);
    return next;
  }
}

/// Dinzo data for the home screen, as raw API payloads so the cache can be
/// re-parsed by newer app versions.
class DashboardData {
  final Map<String, dynamic> overview;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> subscriptions;

  /// Dinzo user profile (`/v1/me`), for the greeting.
  final Map<String, dynamic> me;
  final DateTime fetchedAt;

  DashboardData({
    required this.overview,
    required this.accounts,
    required this.subscriptions,
    this.me = const {},
    required this.fetchedAt,
  });

  /// First name from the Dinzo profile, if any.
  String? get firstName {
    final profile = me['profile'] as Map<String, dynamic>? ?? me;
    final name = (profile['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }

  double get openBillsTotal =>
      (overview['open_bills_total'] as num?)?.toDouble() ?? 0;

  List<UpcomingBill> get upcomingBills {
    final byId = {for (final a in accounts) a['id'] as String: a};
    return ((overview['next_bills'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((b) {
          final account = byId[b['card_account_id']];
          final openFinance = account?['open_finance'] as Map<String, dynamic>?;
          return UpcomingBill(
            cardAccountId: b['card_account_id'] as String,
            cardTitle: ((account?['title'] ?? b['description']) as String)
                .trim(),
            connector: openFinance?['connector_name'] as String?,
            amount: (b['amount'] as num).toDouble(),
            dueDate: DateTime.parse(b['due_date'] as String),
            isEstimate: b['amount_is_estimate'] as bool? ?? false,
          );
        })
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  /// Subscriptions still running (not cancelled or rejected).
  List<ActiveSubscription> get activeSubscriptions => subscriptions
      .where((s) => !const {'CANCELLED', 'REJECTED'}.contains(s['status']))
      .map(
        (s) => ActiveSubscription(
          (s['merchant_name'] as String? ?? '').trim(),
          (s['amount'] as num).toDouble(),
          s['charge_day'] as int?,
          s['cadence'] as String? ?? '',
        ),
      )
      .toList();

  Map<String, dynamic> toJson() => {
    'overview': overview,
    'accounts': accounts,
    'subscriptions': subscriptions,
    'me': me,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
    overview: json['overview'] as Map<String, dynamic>,
    accounts: (json['accounts'] as List).cast<Map<String, dynamic>>(),
    subscriptions: (json['subscriptions'] as List).cast<Map<String, dynamic>>(),
    me: (json['me'] as Map<String, dynamic>?) ?? const {},
    fetchedAt: DateTime.parse(json['fetchedAt'] as String),
  );
}

/// Local copy of the home-screen data; refreshed in the background whenever
/// the home screen is shown (read-only: nothing is imported).
class DashboardCache {
  static final _logger = Logger.withClass(DashboardCache);
  static const _fileName = 'dinzo_dashboard.json';

  /// Automatic refreshes happen once a day (Dinzo allows 5,000 requests a
  /// day); the refresh button always fetches.
  static bool fetchedToday(DateTime? last) {
    if (last == null) return false;
    final now = DateTime.now();
    return last.year == now.year &&
        last.month == now.month &&
        last.day == now.day;
  }

  static Future<File> _file() async {
    final dir = await DemoMode.supportDirectory();
    return File(join(dir.path, _fileName));
  }

  static Future<DashboardData?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return DashboardData.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to read the dashboard cache');
      return null;
    }
  }

  static Future<void> store(DashboardData data) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  static Future<DashboardData> refresh() async {
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
      final data = DashboardData(
        overview: await api.overview(),
        accounts: await api.accountsRaw(),
        subscriptions: await api.subscriptions(),
        me: await api.me(),
        fetchedAt: DateTime.now(),
      );
      await store(data);
      return data;
    } finally {
      api.close();
    }
  }
}
