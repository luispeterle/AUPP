import 'dart:convert';
import 'dart:math';

import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/investments/diagram.dart';
import 'package:aupp/dashboard/dashboard-data.dart';
import 'package:aupp/dinzo/dinzo-default-categories.dart';
import 'package:aupp/dinzo/dinzo-sync-engine.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:aupp/dinzo/daily-money.dart';

/// What the demo starts with: a backup to restore plus the Dinzo caches of
/// the home screen and the investments tab.
class DemoSeed {
  final Map<String, dynamic> backup;
  final DashboardData dashboard;
  final InvestmentsSnapshot investments;

  DemoSeed(this.backup, this.dashboard, this.investments);
}

/// A made-up person shaped like the user's own data (2026-10 backup): same
/// banks, cards, tags, wallets and habits, smaller numbers. Salary 4.000,
/// food voucher, a few envelopes ("caixinhas"), some fixed income, an ETF,
/// a FII, a little BTC and XMR.
///
/// Dates are relative to [today]: the history covers the last
/// [historyMonths] months plus the current one. Each month draws from its own
/// seed, so past months look the same on every entry while the current month
/// grows day by day (what has not happened yet is left out).
class DemoData {
  static const personName = 'Alex Moraes';
  static const salary = 4000.0;
  static const valeMensal = 350.0;
  static const historyMonths = 12;

  /// CDI assumed for the made-up yields (a year).
  static const _cdi = 0.149;

  final DateTime today;
  final DateTime _now;
  final String timezone;

  DemoData(DateTime now, {this.timezone = 'America/Sao_Paulo'})
    : _now = now,
      today = DateTime(now.year, now.month, now.day);

  // Wallet ids in the backup (the restore maps them to the database's).
  static const _conta = 1,
      _investir = 2,
      _carro = 4,
      _viagem = 5,
      _saude = 6,
      _reserva = 7,
      _voucherWallet = 10;

  // Dinzo accounts (fixed made-up ids).
  static const _c6Card = '7b1e9c40-52d3-4f1a-9a7e-3c5d2e8f6a11';
  static const _nuCard = 'c2f4a8d1-6e3b-4b9c-8d2a-1f7e5c9b3a22';
  static const _c6Account = '5d8e2f71-9a4c-4e3b-b6d1-8c2a7f4e1b33';
  static const _nuAccount = 'e9a3c6b2-1d7f-4a8e-9c5b-2f6d8a1e4c44';
  static const _mpAccount = '3f6b9e2a-8c1d-4f7a-a2e9-6b4c1d8f5e55';

  static const _c6 = _Pay('C6', 'Crédito', _c6Card);
  static const _c6Debito = _Pay('C6', 'Débito', _c6Account);
  static const _nuCredito = _Pay('Nubank', 'Crédito', _nuCard);
  static const _nuPix = _Pay('Nubank', 'Pix', _nuAccount);
  static const _nuTransf = _Pay('Nubank', 'Transferência', _nuAccount);
  static const _mpPix = _Pay('Mercado Pago', 'Pix', _mpAccount);

  final _records = <Map<String, dynamic>>[];
  final _tags = <Map<String, dynamic>>[];
  final _categories = <String, Category>{};
  final _cardSpends = <String, List<MapEntry<DateTime, double>>>{};
  var _nextId = 1;

  DemoSeed build() {
    for (final c in dinzoDefaultCategories()) {
      _categories['${c.name}|${c.categoryType!.index}'] = c;
    }
    final first = DateTime(today.year, today.month - historyMonths);
    for (var m = first; !m.isAfter(today); m = DateTime(m.year, m.month + 1)) {
      _month(m);
    }
    final patterns = [..._caixinhaPatterns(first), ..._estimates()];

    final investments = _Investments(today, _cdi);
    _openingBalance();

    // The cofrinho holds whatever the wallets have beyond the other positions.
    final bankBalance = 180 + Random(_seed(today)).nextInt(420).toDouble();
    final bills = _bills();
    final cardDebt = bills.fold<double>(0, (s, b) => s + b.amount);
    final wallets = [
      _conta,
      _investir,
      _carro,
      _viagem,
      _saude,
      _reserva,
    ].fold<double>(0, (s, w) => s + _balance(w));
    investments.settleCofrinho(
      wallets + investments.outsideMoney - bankBalance + cardDebt,
    );

    final backup = {
      'records': _records,
      'categories': [for (final c in _categories.values) c.toMap()],
      'recurrent_record_patterns': patterns,
      'record_tag_associations': _tags,
      'wallets': _wallets(),
      'created_at': _now.millisecondsSinceEpoch,
      'package_name': 'demo',
      'version': '',
      'database_version': '${SqliteDatabase.version}',
      'preferences': {
        PreferencesKeys.assetLots: jsonEncode({
          'BTC': [
            {
              'day': _day(DateTime(today.year, today.month - 9, 4)),
              'qty': 0.002,
              'cost': 820.0,
            },
          ],
          'XMR': [
            {'day': _day(DateTime(today.year - 2, 6, 1)), 'qty': 0.5},
          ],
          for (final (ticker, monthsAgo, quantity, cost) in _abroad)
            ticker: [
              {
                'day': _day(DateTime(today.year, today.month - monthsAgo, 10)),
                'qty': quantity,
                'cost': cost,
              },
            ],
        }),
        PreferencesKeys.portfolioDiagram: _diagram(),
        PreferencesKeys.assetNotes: jsonEncode({
          'notes': {
            'PETR4': {
              'thesis': 'Pré-sal de baixo custo e geração de caixa forte. '
                  'Risco principal: interferência do governo.',
              'sellIf': 'Voltar a distribuir acima do que o caixa aguenta.',
            },
          },
        }),
        PreferencesKeys.allowManualRecords: true,
        PreferencesKeys.totalWallets: ['Conta corrente', 'Vale alimentação'],
        PreferencesKeys.budgetPlan: jsonEncode({
          'percents': {
            'liberdade': 20,
            'fixos': 40,
            'conforto': 10,
            'metas': 15,
            'prazeres': 10,
            'conhecimento': 5,
          },
          'categories': {'Ajuste de saldo': outOfBudget},
          'wallets': {},
        }),
      },
    };

    return DemoSeed(
      backup,
      _dashboard(bills, bankBalance, cardDebt),
      InvestmentsSnapshot(
        investments: [
          for (final raw in investments.raw()) DinzoInvestment.fromJson(raw),
        ],
        history: investments.history(first),
        income: investments.income(),
        bankBalance: bankBalance,
        cardDebt: cardDebt,
        fetchedAt: _now,
      ),
    );
  }

  // ------------------------------------------------------------ portfolio

  /// Bought abroad: ticker, months ago, quantity and what it cost in reais.
  static const _abroad = [
    ('VOO', 14, 0.8, 2100.0),
    ('AAPL', 11, 2.0, 2300.0),
    ('MSFT', 8, 1.0, 2500.0),
    ('O', 6, 6.0, 1900.0),
  ];

  /// The grades and what is held abroad, on Carteira e aporte. Every "no" is a
  /// question the asset fails; all the rest it passes.
  String _diagram() {
    Map<String, bool> answered(List<String> questions, List<int> no) => {
      for (final (i, question) in questions.indexed)
        question: !no.contains(i),
    };
    final stock = DiagramState.defaultStockQuestions;
    final fii = DiagramState.defaultFiiQuestions;
    final etf = DiagramState.defaultEtfQuestions;
    return jsonEncode({
      'watched': {
        'VOO': DiagramClass.intlStock.name,
        'AAPL': DiagramClass.intlStock.name,
        'MSFT': DiagramClass.intlStock.name,
        'O': DiagramClass.reit.name,
      },
      'watchedEtfs': ['VOO'],
      'abroad': {for (final a in _abroad) a.$1: a.$3},
      'answers': {
        'PETR4': answered(stock, [3, 9, 10]),
        'WEGE3': answered(stock, [6, 13]),
        'ITUB4': answered(stock, [3, 14]),
        'IVVB11': answered(etf, [5]),
        'MXRF11': answered(fii, [0, 1, 7]),
        'VOO': answered(etf, []),
        'AAPL': answered(stock, [6, 13, 14]),
        'MSFT': answered(stock, [6, 13]),
        'O': answered(fii, [1]),
      },
      'monthlyContribution': 1500.0,
    });
  }

  // ------------------------------------------------------------- months

  static int _seed(DateTime month) => month.year * 12 + month.month + 7919;

  int _monthsAgo(DateTime month) =>
      (today.year * 12 + today.month) - (month.year * 12 + month.month);

  /// One month of statements: fixed bills, everyday spending, the food
  /// voucher and a few one-offs. Days after today are left out.
  void _month(DateTime month) {
    final r = Random(_seed(month));
    final y = month.year, m = month.month;
    final ago = _monthsAgo(month);
    final lastDay = DateTime(y, m + 1, 0).day;
    DateTime day(int d) => DateTime(y, m, min(d, lastDay));
    DateTime anyDay() => day(1 + r.nextInt(lastDay));
    double around(double base, double spread) =>
        _round(base + (r.nextDouble() * 2 - 1) * spread);

    // Income.
    _dinzo(_businessDay(y, m, 5), 'Salário', salary, 'Trabalho', _nuTransf,
        income: true);
    if (m == 11) {
      _dinzo(day(28), '13º Salário · 1ª parcela', 2000, '13° Salário',
          _nuTransf, income: true);
    }
    if (m == 12) {
      _dinzo(day(18), '13º Salário · 2ª parcela', 1652.37, '13° Salário',
          _nuTransf, income: true);
    }
    if (m == 7) {
      _dinzo(day(31), 'Restituição Imposto', 312.4, 'Impostos/Taxas', _nuPix,
          income: true);
    }

    // Fixed bills (the house ones are paid together around the 8th).
    _dinzo(day(8), 'Aluguel', -850, 'Aluguel/Prestação', _nuPix);
    final summer = m == 12 || m <= 3;
    _dinzo(day(8), 'Energia', -around(summer ? 178 : 132, 22), 'Luz', _nuPix);
    _dinzo(day(8), 'Água', -around(58, 8), 'Água', _nuPix);
    _dinzo(day(9), 'Internet', -99.9, 'Internet', _c6);
    _dinzo(day(9), 'Seguro Carro', -119.4, 'Seguro do Carro', _nuCredito);
    _dinzo(day(12), 'Claro', -44.99, 'Telefone/Celular', _c6);
    _dinzo(day(10), 'Unimed', -189.9, 'Plano de Saúde', _nuPix);
    _dinzo(day(3), 'Smart Fit', -109.9, 'Academia', _c6);
    _dinzo(day(15), 'Youtube Premium', -16.9, 'Streamings', _nuCredito);
    _dinzo(day(23), 'Meli+', -9.9, 'Aplicativos', _c6);
    if (m == 1) _dinzo(day(20), 'IPVA', -784.12, 'IPVA', _nuPix);
    if (m == 4) _dinzo(day(12), 'Licenciamento', -165.88, 'Licenciamento', _nuPix);

    // Everyday spending.
    for (var i = 0, n = 8 + r.nextInt(4); i < n; i++) {
      final where = _pick(r, const [
        "Supermercado Bom Preço",
        "Supermercado Bom Preço",
        "Supermercado Bom Preço",
        'Carrefour',
        'Pão de Açúcar',
        'Mercado da Esquina',
        'Assaí Atacadista',
      ]);
      final big = where == 'Assaí Atacadista' || r.nextDouble() < 0.1;
      _dinzo(anyDay(), where, -_spend(r, big ? 120 : 22, big ? 240 : 90),
          'Supermercado', r.nextDouble() < 0.85 ? _c6 : _nuCredito);
    }
    for (var i = 0, n = 1 + r.nextInt(3); i < n; i++) {
      _dinzo(anyDay(), _pick(r, const [
        'Sushi da Praça',
        'Milky Moo',
        'Sorveteria Central',
        'Cantina Italiana',
        'Restaurante da Tia',
        'Outback',
        'Burger King',
      ]), -_spend(r, 28, 135), 'Restaurante', _c6);
    }
    for (var i = 0, n = r.nextInt(3); i < n; i++) {
      _dinzo(anyDay(), 'iFood', -_spend(r, 34, 82), 'Delivery', _nuCredito);
    }
    for (var i = 0, n = 1 + r.nextInt(4); i < n; i++) {
      _dinzo(anyDay(), 'Padaria Pão Quente', -_spend(r, 7, 26), 'Padaria', _c6);
    }
    for (var i = 0, n = 1 + r.nextInt(3); i < n; i++) {
      _dinzo(anyDay(), _pick(r, const [
        'Posto Ipiranga',
        'Petrobras Premmia',
        'Podium',
      ]), -_spend(r, 80, 190), 'Combustível', _c6);
    }
    for (var i = 0, n = r.nextInt(4); i < n; i++) {
      _dinzo(anyDay(), 'Pedágio Via Costeira', -5.5, 'Pedágio', _c6Debito);
    }
    if (r.nextDouble() < 0.5) {
      _dinzo(anyDay(), 'Estacionamento', -_spend(r, 8, 25), 'Estacionamento',
          _c6);
    }
    final blackFriday = m == 11 ? 2 : 0;
    for (var i = 0, n = 1 + r.nextInt(2) + blackFriday; i < n; i++) {
      _dinzo(blackFriday > 0 && i < 2 ? day(27 + i) : anyDay(), _pick(r, const [
        'Mercado Livre',
        'Shopee',
        'Amazon',
        'AliExpress',
        'Shopee - Casa e Cia',
      ]), -_spend(r, 25, 240), 'Compras', r.nextDouble() < 0.8 ? _c6 : _mpPix);
    }
    for (var i = 0, n = r.nextInt(3); i < n; i++) {
      _dinzo(anyDay(), _pick(r, const [
        'Drogasil',
        'Droga Raia',
        'Pague Menos',
      ]), -_spend(r, 14, 88), 'Farmácia', r.nextBool() ? _c6 : _nuPix);
    }
    if (r.nextDouble() < 0.6) {
      _dinzo(anyDay(), 'Barbearia do Zé', -45, 'Cabeleireiro/Barbeiro', _nuPix);
    }
    if (r.nextDouble() < 0.35) {
      _dinzo(anyDay(), _pick(r, const ['Hering', 'Renner', 'Riachuelo']),
          -_spend(r, 79, 260), 'Roupas', _c6);
    }
    if (r.nextDouble() < 0.3) {
      _dinzo(anyDay(), 'Cinema', -_spend(r, 32, 78), 'Cinema', _c6);
    }
    for (var i = 0, n = (m == 2 ? 2 : 0) + (r.nextDouble() < 0.4 ? 1 : 0);
        i < n; i++) {
      _dinzo(anyDay(), 'Bar do Alemão', -_spend(r, 45, 130), 'Bares', _c6);
    }
    if (r.nextDouble() < 0.2) {
      _dinzo(anyDay(), _pick(r, const ['Troca de óleo', 'Pneus', 'Mecânica']),
          -_spend(r, 120, 480), 'Manutenção', _c6);
    }
    if (r.nextDouble() < 0.15) {
      _dinzo(anyDay(), 'Udemy', -_spend(r, 27.9, 79.9), 'Cursos', _c6);
    }
    if (r.nextDouble() < 0.15) {
      _dinzo(anyDay(), 'Steam', -_spend(r, 19.9, 89.9), 'Jogos', _c6);
    }
    if (m == 12) {
      for (var i = 0; i < 3; i++) {
        _dinzo(day(10 + 4 * i), 'Presente', -_spend(r, 50, 160),
            'Presentes/Doações', _c6);
      }
    }

    // Pix with friends, refunds and cashback.
    for (var i = 0, n = r.nextInt(3); i < n; i++) {
      final friend = _pick(r, const [
        'Bruno Lima Carvalho',
        'Camila Reis Duarte',
        'Diego Nunes Prado',
      ]);
      if (r.nextBool()) {
        _dinzo(anyDay(), friend, -_spend(r, 20, 150), 'Transferência', _nuPix);
      } else {
        _dinzo(anyDay(), friend, _spend(r, 20, 120), 'Transferência', _nuPix,
            income: true);
      }
    }
    if (r.nextDouble() < 0.3) {
      _dinzo(anyDay(), 'Estorno', _spend(r, 12, 70), 'Outros', _c6,
          income: true);
    }
    if (r.nextDouble() < 0.2) {
      _dinzo(anyDay(), 'Resgate de Cashback', _spend(r, 4, 18), 'Outros',
          _c6, income: true);
    }

    // Purchases partly paid with an envelope (the split payment).
    if (ago == 3) {
      _withEnvelope(day(17), 'Revisão do carro', 780, 'Manutenção', _carro,
          'Caixinha Carro', 400);
    }
    if (ago == 7) {
      _withEnvelope(day(22), 'Pousada Serra Gaúcha', 1180, 'Hotel', _viagem,
          'Caixinha Viagem', 650);
    }

    // A few records typed by hand.
    if (ago == 5) {
      _manual(day(11), 'Venda da bike antiga', 650, 'Outros', income: true);
    }
    if (ago == 1) _manual(day(6), 'Feira do bairro', -38, 'Supermercado');

    _voucher(month, r);
  }

  /// Vale alimentação: the monthly credit, purchases at the store and some
  /// cashback, never spending more than is there.
  void _voucher(DateTime month, Random r) {
    final y = month.year, m = month.month;
    final lastDay = DateTime(y, m + 1, 0).day;
    _voucherRecord(DateTime(y, m, 1, 9, 12), 'Vale - Vale Mensal', valeMensal,
        'Vale alimentação', income: true, kind: 'F');
    var left = valeMensal;
    final uses = 4 + r.nextInt(3);
    for (var i = 0; i < uses && left > 15; i++) {
      final value = min(left, _spend(r, 35, 115));
      left -= value;
      final d = 2 + ((lastDay - 2) * (i + r.nextDouble()) / uses).floor();
      _voucherRecord(
        DateTime(y, m, min(d, lastDay), 10 + r.nextInt(9), r.nextInt(60)),
        'Vale - Uso Vale',
        -_round(value),
        'Supermercado',
        kind: 'U',
        pdv: 1 + r.nextInt(6),
      );
    }
    if (r.nextDouble() < 0.5) {
      _voucherRecord(DateTime(y, m, min(5 + r.nextInt(20), lastDay), 18, 40),
          'Vale - Cashback de compra', _spend(r, 1, 6), 'Outros',
          income: true, kind: 'V');
    }
  }

  // ------------------------------------------------------------ records

  int _add({
    required double value,
    required DateTime local,
    String? title,
    Category? category,
    int wallet = _conta,
    int? to,
    String? description,
    String? recurrenceId,
    String? dinzoId,
    String? snapshot,
    Iterable<String> tags = const [],
  }) {
    final id = _nextId++;
    _records.add({
      'id': id,
      'title': title,
      'value': _round(value),
      'datetime': local.toUtc().millisecondsSinceEpoch,
      'timezone': timezone,
      'category_name': category?.name,
      'category_type': category?.categoryType?.index,
      'description': description,
      'recurrence_id': recurrenceId,
      'wallet_id': wallet,
      'transfer_wallet_id': to,
      'dinzo_id': dinzoId,
      'dinzo_snapshot': snapshot,
    });
    for (final tag in tags) {
      _tags.add({'record_id': id, 'tag_name': tag});
    }
    return id;
  }

  /// A statement line as the Dinzo sync imports it (linked, with snapshot).
  String? _dinzo(
    DateTime day,
    String title,
    double value,
    String category,
    _Pay pay, {
    bool income = false,
  }) {
    if (day.isAfter(today)) return null;
    final dinzoId = _uuid(Random(Object.hash(title, day, value)));
    final tags = [pay.bank, pay.form]..sort();
    final snapshot = DinzoSnapshot(
      title: title,
      value: _round(value),
      date: _day(day),
      categoryName: category,
      walletId: _conta,
      tags: tags,
      accountId: pay.account,
    );
    _add(
      value: value,
      local: DateTime(day.year, day.month, day.day, 12),
      title: title,
      category: _cat(category, income: income),
      dinzoId: dinzoId,
      snapshot: DinzoLink(snapshot, snapshot).toJsonString(),
      tags: tags,
    );
    if (pay.form == 'Crédito') {
      _cardSpends.putIfAbsent(pay.account, () => []).add(
        MapEntry(day, -value),
      );
    }
    return dinzoId;
  }

  void _withEnvelope(
    DateTime day,
    String title,
    double total,
    String category,
    int envelope,
    String envelopeName,
    double part,
  ) {
    final dinzoId = _dinzo(day, title, -total, category, _c6);
    if (dinzoId == null) return;
    _add(
      value: -part,
      local: DateTime(day.year, day.month, day.day, 12),
      title: '$title · $envelopeName',
      wallet: envelope,
      to: _conta,
      description: 'Parte paga com a caixinha',
      dinzoId: '${DinzoSyncService.syntheticPrefix}split:$dinzoId',
      tags: const [DinzoSyncService.virtualTag],
    );
  }

  void _manual(DateTime day, String title, double value, String category,
      {bool income = false}) {
    if (day.isAfter(today)) return;
    _add(
      value: value,
      local: DateTime(day.year, day.month, day.day, 19, 30),
      title: title,
      category: _cat(category, income: income),
      tags: const [DinzoSyncService.manualTag],
    );
  }

  void _voucherRecord(
    DateTime at,
    String title,
    double value,
    String category, {
    bool income = false,
    required String kind,
    int pdv = 1,
  }) {
    if (at.isAfter(_now)) return;
    final r = Random(Object.hash(title, at));
    final hash = List.generate(26, (_) => r.nextInt(10)).join();
    _add(
      value: value,
      local: at,
      title: title,
      category: _cat(category, income: income),
      wallet: _voucherWallet,
      description: kind == 'U'
          ? 'Uso: Consumido no PDV $pdv - F22\nFilial 22 · tipo U'
          : 'Filial 22 · tipo $kind',
      dinzoId: '${DinzoSyncService.syntheticPrefix}vale:h:$hash',
      tags: const ['Vale alimentação'],
    );
  }

  Category _cat(String name, {bool income = false}) {
    final type = income ? CategoryType.income : CategoryType.expense;
    return _categories.putIfAbsent(
      '$name|${type.index}',
      () => DinzoSyncService.categoryFromDinzo(name, type),
    );
  }

  /// Wallet balance from the records so far (plus [extra] ones).
  double _balance(int wallet, {List<Map<String, dynamic>> extra = const []}) {
    var sum = _initial[wallet] ?? 0;
    for (final r in [..._records, ...extra]) {
      final value = (r['value'] as num).toDouble();
      if (r['wallet_id'] == wallet) sum += value;
      if (r['transfer_wallet_id'] == wallet) {
        sum -= value;
      }
    }
    return sum;
  }

  // ----------------------------------------------------------- wallets

  final _initial = <int, double>{
    _investir: 900,
    _carro: 250,
    _viagem: 300,
    _reserva: 1500,
  };

  List<Map<String, dynamic>> _wallets() {
    Map<String, dynamic> wallet(
      int id,
      String name,
      int icon, {
      String? color,
      String kind = 'normal',
    }) => {
      'id': id,
      'name': name,
      'color': color,
      'icon': icon,
      'icon_emoji': null,
      'initial_amount': _initial[id] ?? 0.0,
      'is_archived': 0,
      'is_default': id == _conta ? 1 : 0,
      'is_predefined': id == _conta ? 1 : 0,
      'sort_order': id - 1,
      'kind': kind,
    };
    // Icons and colours as in the user's own backup.
    return [
      wallet(_conta, 'Conta corrente', 62805,
          color: '255:129:199:132'),
      wallet(_investir, 'Investir', 62675,
          color: '255:0:200:83', kind: 'toInvest'),
      wallet(_carro, 'Caixinha Carro', 61881, color: '255:239:108:0'),
      wallet(_viagem, 'Caixinha Viagem', 62896, color: '255:3:169:244'),
      wallet(_saude, 'Caixinha Saude', 61681, color: '255:79:195:247'),
      wallet(_reserva, 'Reserva de Emergencia', 62675,
          color: '255:183:28:28', kind: 'emergency'),
      wallet(_voucherWallet, 'Vale alimentação', 62097),
    ];
  }

  // ------------------------------------------------------- recurrences

  /// Monthly transfers into the envelopes, with every past occurrence.
  List<Map<String, dynamic>> _caixinhaPatterns(DateTime first) {
    const plans = [
      ('Investir', 300.0, _investir, 12, null),
      ('Reserva de Emergencia', 150.0, _reserva, 12, null),
      ('Caixinha Viagem', 150.0, _viagem, 10, 'Viagem de fim de ano'),
      ('Caixinha Carro', 150.0, _carro, 8, null),
      ('Caixinha Saude', 100.0, _saude, 5, null),
    ];
    final current = DateTime(today.year, today.month);
    return [
      for (final (title, value, to, months, description) in plans)
        () {
          final id = _uuid(Random(Object.hash('pattern', title)));
          final start = DateTime(today.year, today.month - months);
          for (var m = start; !m.isAfter(current);
              m = DateTime(m.year, m.month + 1)) {
            _add(
              value: -value,
              local: m,
              title: title,
              to: to,
              description: description,
              recurrenceId: id,
              tags: const [DinzoSyncService.virtualTag],
            );
          }
          return _pattern(id, title, -value, start,
              to: to,
              description: description,
              lastUpdate: current,
              tag: DinzoSyncService.virtualTag);
        }(),
    ];
  }

  /// Bills and salary expected ahead ("Estimativa" recurrences).
  List<Map<String, dynamic>> _estimates() {
    const plans = [
      ('Salário', 4000.0, 7, 'Trabalho', true),
      ('Aluguel', -850.0, 8, 'Aluguel/Prestação', false),
      ('Unimed', -189.9, 10, 'Plano de Saúde', false),
      ('Energia', -150.0, 8, 'Luz', false),
      ('Água', -60.0, 8, 'Água', false),
      ('Internet', -99.9, 9, 'Internet', false),
      ('Seguro Carro', -119.4, 9, 'Seguro do Carro', false),
      ('Claro', -44.99, 12, 'Telefone/Celular', false),
      ('Smart Fit', -109.9, 3, 'Academia', false),
      ('Youtube Premium', -16.9, 15, 'Streamings', false),
      ('Meli+', -9.9, 23, 'Aplicativos', false),
    ];
    return [
      for (final (title, value, dayOfMonth, category, income) in plans)
        () {
          var next = DateTime(today.year, today.month, dayOfMonth);
          if (!next.isAfter(today)) {
            next = DateTime(today.year, today.month + 1, dayOfMonth);
          }
          return _pattern(
            _uuid(Random(Object.hash('estimate', title))),
            title,
            value,
            next,
            category: _cat(category, income: income),
            tag: DinzoSyncService.estimateTag,
          );
        }(),
    ];
  }

  Map<String, dynamic> _pattern(
    String id,
    String title,
    double value,
    DateTime start, {
    int? to,
    Category? category,
    String? description,
    DateTime? lastUpdate,
    required String tag,
  }) => {
    'id': id,
    'title': title,
    'value': value,
    'datetime': start.toUtc().millisecondsSinceEpoch,
    'timezone': timezone,
    'category_name': category?.name,
    'category_type': category?.categoryType?.index,
    'description': description,
    'recurrent_period': 2, // every month
    'last_update': lastUpdate?.toUtc().millisecondsSinceEpoch,
    'tags': tag,
    'end_date': null,
    'wallet_id': _conta,
    'transfer_wallet_id': to,
    'custom_interval_value': null,
    'custom_interval_unit': null,
  };

  // -------------------------------------------------------- investments

  /// The Conta corrente ends somewhere between 1.100 and 1.700 today.
  void _openingBalance() {
    final target = 1100 + Random(_seed(today) + 2).nextInt(600).toDouble();
    _initial[_conta] = _round(target - _balance(_conta));
  }

  // ---------------------------------------------------------- dashboard

  static const _cards = [
    (_c6Card, 'C6 Carbon', 'C6 Bank', 2, 10, 7500.0),
    (_nuCard, 'Nubank', 'Nubank', 6, 13, 4200.0),
  ];

  /// Card bills: the one closed and still unpaid (if any) and the open one.
  List<_Bill> _bills() {
    final bills = <_Bill>[];
    for (final (id, title, _, closeDay, dueDay, _) in _cards) {
      final spends = _cardSpends[id] ?? const [];
      double sum(DateTime from, DateTime until) => _round(
        spends
            .where((e) => !e.key.isBefore(from) && e.key.isBefore(until))
            .fold<double>(0, (s, e) => s + e.value),
      );
      // The cycle open today closes on [nextClose].
      var nextClose = DateTime(today.year, today.month, closeDay);
      if (!today.isBefore(nextClose)) {
        nextClose = DateTime(today.year, today.month + 1, closeDay);
      }
      final lastClose =
          DateTime(nextClose.year, nextClose.month - 1, closeDay);
      final lastDue = DateTime(lastClose.year, lastClose.month, dueDay);
      if (!today.isAfter(lastDue)) {
        final before =
            DateTime(lastClose.year, lastClose.month - 1, closeDay);
        bills.add(_Bill(id, title, sum(before, lastClose), lastDue, false));
      }
      bills.add(
        _Bill(
          id,
          title,
          sum(lastClose, today.add(const Duration(days: 1))),
          DateTime(nextClose.year, nextClose.month, dueDay),
          true,
        ),
      );
    }
    return bills..sort((a, b) => a.due.compareTo(b.due));
  }

  DashboardData _dashboard(
    List<_Bill> bills,
    double bankBalance,
    double cardDebt,
  ) {
    final debtByCard = <String, double>{};
    for (final b in bills) {
      debtByCard[b.card] = (debtByCard[b.card] ?? 0) + b.amount;
    }
    final c6Share = _round(bankBalance * 0.55);
    final nuShare = _round(bankBalance * 0.35);
    Map<String, dynamic> bank(String id, String title, String connector,
            double balance) =>
        {
          'id': id,
          'type': 'BANK',
          'sub_type': 'CHECKING_ACCOUNT',
          'title': title,
          'archived': false,
          'exclude_from_totals': false,
          'currency': 'BRL',
          'balance': balance,
          'credit': null,
          'open_finance': {'connected': true, 'connector_name': connector},
        };
    final monthStart = DateTime(today.year, today.month);
    double monthSum(bool income) => _round(
      _records
          .where(
            (r) =>
                r['wallet_id'] == _conta &&
                r['transfer_wallet_id'] == null &&
                (r['dinzo_id'] as String?)?.startsWith('livre:') != true &&
                DateTime.fromMillisecondsSinceEpoch(
                  r['datetime'] as int,
                ).isAfter(monthStart) &&
                ((r['value'] as num) > 0) == income,
          )
          .fold<double>(0, (s, r) => s + (r['value'] as num).abs()),
    );
    final receitas = monthSum(true), despesas = monthSum(false);
    Map<String, dynamic> subscription(
      String name,
      double amount,
      int day,
      String account,
    ) => {
      'id': _uuid(Random(Object.hash('subscription', name))),
      'merchant_name': name,
      'amount': amount,
      'currency': 'BRL',
      'cadence': 'MONTHLY',
      'charge_day': day,
      'status': 'CONFIRMED',
      'source': 'AUTO',
      'account_id': account,
    };
    return DashboardData(
      overview: {
        'bank_balance': bankBalance,
        'card_debt': cardDebt,
        'open_bills_total': cardDebt,
        'net_worth': _round(bankBalance - cardDebt),
        'next_bills': [
          for (final b in bills)
            {
              'projected_bill_id':
                  'mocked-bill:${b.card}:${b.due.millisecondsSinceEpoch}',
              'card_account_id': b.card,
              'description': 'Fatura ${b.title}',
              'amount': b.amount,
              'due_date': _day(b.due),
              'amount_is_estimate': b.estimate,
            },
        ],
        'month': {
          'receitas': receitas,
          'despesas': despesas,
          'resultado': _round(receitas - despesas),
        },
      },
      accounts: [
        for (final (id, title, connector, closeDay, dueDay, limit) in _cards)
          {
            'id': id,
            'type': 'CREDIT',
            'sub_type': 'CREDIT_CARD',
            'title': title,
            'archived': false,
            'exclude_from_totals': false,
            'currency': 'BRL',
            'balance': _round(debtByCard[id] ?? 0),
            'credit': {
              'close_day': closeDay,
              'due_day': dueDay,
              'due_day_of_month': dueDay,
              'limit': limit,
            },
            'open_finance': {'connected': true, 'connector_name': connector},
          },
        bank(_c6Account, 'C6 BANK', 'C6 Bank', c6Share),
        bank(_nuAccount, 'Nubank', 'Nubank', nuShare),
        bank(_mpAccount, 'Mercado Pago', 'Mercado Pago',
            _round(bankBalance - c6Share - nuShare)),
      ],
      subscriptions: [
        subscription('Smart Fit', 109.9, 3, _c6Card),
        subscription('Internet', 99.9, 9, _c6Card),
        subscription('Claro', 44.99, 12, _c6Card),
        subscription('Youtube Premium', 16.9, 15, _nuCard),
        subscription('Meli+', 9.9, 23, _c6Card),
      ],
      me: {
        'id': '0d3c5e7a-2b4f-4c6d-8e1a-9f3b5d7c1e66',
        'name': personName,
        'wage': salary,
      },
      fetchedAt: _now,
    );
  }

  // ------------------------------------------------------------ helpers

  /// The [n]th weekday of the month (salary day).
  static DateTime _businessDay(int year, int month, int n) {
    var d = DateTime(year, month, 1);
    var count = 0;
    while (true) {
      if (d.weekday <= DateTime.friday && ++count == n) return d;
      d = d.add(const Duration(days: 1));
    }
  }

  static T _pick<T>(Random r, List<T> options) =>
      options[r.nextInt(options.length)];

  /// A price between [low] and [high], leaning to the low end like real
  /// receipts.
  static double _spend(Random r, double low, double high) =>
      _round(low + (high - low) * pow(r.nextDouble(), 1.6));

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _uuid(Random r) {
    String hex(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }
}

class _Pay {
  final String bank;
  final String form;
  final String account;

  const _Pay(this.bank, this.form, this.account);
}

class _Bill {
  final String card;
  final String title;
  final double amount;
  final DateTime due;
  final bool estimate;

  _Bill(this.card, this.title, this.amount, this.due, this.estimate);
}

// ------------------------------------------------------------ investments

class _Move {
  final String type; // BUY, SELL, TAX
  final DateTime date;

  /// Gross amount.
  final double amount;

  /// What reached the account (sells).
  final double net;

  _Move(this.type, this.date, this.amount, [double? net])
    : net = net ?? amount;
}

class _Position {
  final String assetKey;
  final String name;
  final String type;
  final String? subType;
  final String? issuer;
  final String? code;
  final double? rate;
  final bool taxExempt;
  final double? lastTwelveMonths;
  final DateTime? due;
  final List<_Move> moves;

  /// Price of one unit on a day (gross).
  final double Function(DateTime) price;

  /// Fixed income taxed on redemption: the balance shown is net of it.
  final bool netOfTax;

  /// The cofrinho's balance today (it has no movements).
  double? fixedBalance;

  /// At a broker: investment, not part of the money in the wallets.
  final bool atBroker;

  _Position({
    required this.assetKey,
    required this.name,
    required this.type,
    required this.price,
    this.subType,
    this.issuer,
    this.code,
    this.rate,
    this.taxExempt = false,
    this.lastTwelveMonths,
    this.due,
    this.moves = const [],
    this.netOfTax = false,
    this.atBroker = false,
  });

  String get shortName {
    // Tickers read better than names; a fund's code is its CNPJ.
    if (code != null && RegExp(r'^[A-Z]{4}\d{1,2}$').hasMatch(code!)) {
      return code!;
    }
    return name.length > 40 ? '${name.substring(0, 40)}…' : name;
  }

  DateTime? get firstBuy => moves.isEmpty ? null : moves.first.date;

  /// Shares and ETF units are bought whole; what is left of the amount stays
  /// at the broker.
  bool get _wholeUnits => type == 'EQUITY' || type == 'ETF';

  /// Units held at the end of [day], and what they cost.
  (double, double) _holdingOn(DateTime day) {
    var units = 0.0, cost = 0.0;
    for (final m in moves) {
      if (m.date.isAfter(day)) break;
      var moved = m.amount / price(m.date);
      if (_wholeUnits) moved = moved.floorToDouble();
      if (m.type == 'BUY') {
        units += moved;
        cost += m.amount;
      } else if (m.type == 'SELL') {
        cost -= cost * moved / units;
        units -= moved;
      }
    }
    return (units, cost);
  }

  /// Units held today, as the Dinzo sends them for shares and ETFs.
  double? unitsOn(DateTime day) => _wholeUnits ? _holdingOn(day).$1 : null;

  /// Net balance at the end of [day].
  double valueOn(DateTime day, DateTime today) {
    if (fixedBalance != null) {
      return fixedBalance! * price(day) / price(today);
    }
    final (units, cost) = _holdingOn(day);
    final gross = units * price(day);
    if (!netOfTax || taxExempt || gross <= cost) return gross;
    final days = day.difference(firstBuy!).inDays;
    final rate = days <= 180
        ? 0.225
        : days <= 360
        ? 0.20
        : days <= 720
        ? 0.175
        : 0.15;
    return gross - (gross - cost) * rate;
  }
}

/// The made-up portfolio: CDBs, an LCI, a fund, an ETF, a FII and a
/// "cofrinho" whose balance is set last (see DemoData.build).
class _Investments {
  final DateTime today;
  final double cdi;
  late final List<_Position> positions;
  late final DateTime _base;

  _Investments(this.today, this.cdi) {
    _base = DateTime(today.year - 2, today.month);
    DateTime at(int monthsAgo, int day) =>
        DateTime(today.year, today.month - monthsAgo, day);
    double Function(DateTime) ofCdi(double percent) =>
        (d) => pow(1 + cdi, percent / 100 * d.difference(_base).inDays / 365)
            .toDouble();
    const nu = 'NU FINANCEIRA S.A. - SOCIEDADE DE CREDITO, FINANCIAMENTO E '
        'INVESTIMENTO';
    final fund = at(9, 12);
    positions = [
      _Position(
        assetKey: 'FIXED_INCOME|demo:cdb-nu-120',
        name: 'CDB - $nu',
        type: 'FIXED_INCOME',
        subType: 'CDB',
        issuer: nu,
        rate: 120,
        price: ofCdi(120),
        netOfTax: true,
        due: DateTime(at(10, 14).year + 2, at(10, 14).month, 14),
        moves: [_Move('BUY', at(10, 14), 2000)],
      ),
      _Position(
        assetKey: 'FIXED_INCOME|demo:cdb-nu-100-a',
        name: 'CDB - $nu',
        type: 'FIXED_INCOME',
        subType: 'CDB',
        issuer: nu,
        rate: 100,
        price: ofCdi(100),
        netOfTax: true,
        due: DateTime(at(6, 6).year + 2, at(6, 6).month, 6),
        moves: [_Move('BUY', at(6, 6), 1000)],
      ),
      _Position(
        assetKey: 'FIXED_INCOME|demo:cdb-nu-100-b',
        name: 'CDB - $nu',
        type: 'FIXED_INCOME',
        subType: 'CDB',
        issuer: nu,
        rate: 100,
        price: ofCdi(100),
        netOfTax: true,
        due: DateTime(at(2, 10).year + 2, at(2, 10).month, 10),
        moves: [_Move('BUY', at(2, 10), 600)],
      ),
      _Position(
        assetKey: 'FIXED_INCOME|demo:cdb-c6-102',
        name: 'CDB - BANCO C6 S.A.',
        type: 'FIXED_INCOME',
        subType: 'CDB',
        issuer: 'BANCO C6 S.A.',
        rate: 102,
        price: ofCdi(102),
        netOfTax: true,
        due: DateTime(at(4, 21).year + 1, at(4, 21).month, 21),
        moves: [_Move('BUY', at(4, 21), 1000)],
      ),
      _Position(
        assetKey: 'FIXED_INCOME|demo:lci-inter-92',
        name: 'LCI - BANCO INTER S.A.',
        type: 'FIXED_INCOME',
        subType: 'LCI',
        issuer: 'BANCO INTER S.A.',
        rate: 92,
        taxExempt: true,
        price: ofCdi(92),
        due: DateTime(at(8, 3).year + 3, at(8, 3).month, 3),
        moves: [_Move('BUY', at(8, 3), 1500)],
      ),
      _Position(
        assetKey: 'MUTUAL_FUND|code:42.699.466/0001-77',
        name: 'NU RESERVA IMEDIATA FUNDO DE INVESTIMENTO RENDA FIXA',
        type: 'MUTUAL_FUND',
        subType: 'FIXED_INCOME_FUND',
        code: '42.699.466/0001-77',
        lastTwelveMonths: 13.4,
        price: ofCdi(99),
        moves: _fundMoves(fund, at(5, 2), at(3, 18), ofCdi(99)),
      ),
      _Position(
        assetKey: 'ETF|code:IVVB11',
        name: 'IVVB11',
        type: 'ETF',
        code: 'IVVB11',
        price: _walk(17, 372, 0.0005, 0.011),
        moves: [_Move('BUY', at(7, 15), 700)],
      ),
      _Position(
        assetKey: 'FIXED_INCOME|demo:cdb-btg',
        name: 'CDB - BANCO BTG PACTUAL S.A.',
        type: 'FIXED_INCOME',
        subType: 'CDB',
        issuer: 'BANCO BTG PACTUAL S.A.',
        atBroker: true,
        rate: 112,
        price: ofCdi(112),
        netOfTax: true,
        due: DateTime(at(12, 5).year + 3, at(12, 5).month, 5),
        moves: [_Move('BUY', at(12, 5), 2500)],
      ),
      _Position(
        assetKey: 'EQUITY|code:PETR4',
        name: 'PETR4',
        type: 'EQUITY',
        code: 'PETR4',
        taxExempt: true,
        price: _walk(41, 34, 0.0004, 0.014),
        moves: [_Move('BUY', at(10, 12), 1800)],
      ),
      _Position(
        assetKey: 'EQUITY|code:WEGE3',
        name: 'WEGE3',
        type: 'EQUITY',
        code: 'WEGE3',
        taxExempt: true,
        price: _walk(53, 44, 0.0006, 0.013),
        moves: [_Move('BUY', at(9, 8), 1500)],
      ),
      _Position(
        assetKey: 'EQUITY|code:ITUB4',
        name: 'ITUB4',
        type: 'EQUITY',
        code: 'ITUB4',
        taxExempt: true,
        price: _walk(67, 32, 0.0004, 0.01),
        moves: [_Move('BUY', at(6, 20), 1200)],
      ),
      _Position(
        assetKey: 'EQUITY|code:MXRF11',
        name: 'MXRF11',
        type: 'EQUITY',
        subType: 'REAL_ESTATE_FUND',
        code: 'MXRF11',
        price: _walk(29, 9.6, 0.0001, 0.004),
        moves: [_Move('BUY', at(3, 7), 500)],
      ),
      _Position(
        assetKey: 'FIXED_INCOME|code:DEMO-COFRINHO',
        name: 'Cofrinho',
        type: 'FIXED_INCOME',
        code: 'demo-cofrinho',
        rate: 120,
        price: ofCdi(120),
      )..fixedBalance = 6000,
    ];
  }

  /// Two buys, a partial redemption (with tax withheld) and the come-cotas
  /// of May and November.
  List<_Move> _fundMoves(
    DateTime first,
    DateTime second,
    DateTime sell,
    double Function(DateTime) price,
  ) {
    final moves = [
      _Move('BUY', first, 800),
      _Move('BUY', second, 400),
    ];
    final gain = 300 * (1 - price(first) / price(sell));
    moves.add(
      _Move('SELL', sell, 300, DemoData._round(300 - gain * 0.2)),
    );
    for (var y = first.year; y <= today.year; y++) {
      for (final month in [5, 11]) {
        final day = DateTime(y, month + 1, 0);
        if (day.isBefore(first)) continue;
        moves.add(_Move('TAX', day, DemoData._round(4 + (y + month) % 5)));
      }
    }
    return moves..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Daily random walk of a quoted asset's price.
  double Function(DateTime) _walk(
    int seed,
    double start,
    double drift,
    double volatility,
  ) {
    final r = Random(seed);
    final prices = <double>[];
    var p = start;
    final days = today.difference(_base).inDays + 1;
    for (var i = 0; i < days; i++) {
      prices.add(p);
      // Box–Muller.
      final z =
          sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());
      p *= exp(drift + volatility * z);
    }
    return (d) =>
        prices[d.difference(_base).inDays.clamp(0, prices.length - 1)];
  }

  /// What is outside the money the wallets divide: stocks, funds and the like.
  double get outsideMoney => positions
      .where((p) => p.type != DailyMoney.fixedIncomeType || p.atBroker)
      .fold<double>(0, (s, p) => s + p.valueOn(today, today));

  void settleCofrinho(double investmentsTotal) {
    final cofrinho = positions.last;
    final others = positions
        .where((p) => p != cofrinho)
        .fold<double>(0, (s, p) => s + p.valueOn(today, today));
    cofrinho.fixedBalance = max(300, investmentsTotal - others);
  }

  double total(DateTime day) =>
      positions.fold(0, (s, p) => s + p.valueOn(day, today));

  Iterable<(_Position, _Move)> taxes() sync* {
    for (final p in positions) {
      for (final m in p.moves) {
        if (m.type == 'TAX' || (m.type == 'SELL' && m.net < m.amount)) {
          yield (p, m);
        }
      }
    }
  }

  /// Money put in (buys − what sells paid out) and tax withheld, in
  /// (from, until].
  ({double net, double taxes}) flowsBetween(DateTime from, DateTime until) {
    var net = 0.0, taxes = 0.0;
    for (final p in positions) {
      for (final m in p.moves) {
        if (!m.date.isAfter(from) || m.date.isAfter(until)) continue;
        if (m.type == 'BUY') net += m.amount;
        if (m.type == 'SELL') {
          net -= m.net;
          taxes += m.amount - m.net;
        }
        if (m.type == 'TAX') taxes += m.amount;
      }
    }
    return (net: net, taxes: taxes);
  }

  /// Daily totals since [first], by asset type (the evolution chart).
  List<Map<String, dynamic>> history(DateTime first) => [
    for (var d = first; !d.isAfter(today); d = d.add(const Duration(days: 1)))
      {
        'date': DemoData._day(d),
        'total': DemoData._round(total(d)),
        'by_type': () {
          final byType = <String, double>{};
          for (final p in positions) {
            final v = p.valueOn(d, today);
            if (v > 0) byType[p.type] = DemoData._round((byType[p.type] ?? 0) + v);
          }
          return byType;
        }(),
      },
  ];

  /// FII monthly income paid since it was bought.
  List<Map<String, dynamic>> income() {
    final fii = positions.firstWhere((p) => p.code == 'MXRF11');
    final buy = fii.moves.first;
    final units = (buy.amount / fii.price(buy.date)).floorToDouble();
    return [
      for (var m = DateTime(buy.date.year, buy.date.month + 1, 15);
          !m.isAfter(today);
          m = DateTime(m.year, m.month + 1, 15))
        {
          'ticker': 'MXRF11',
          'type': 'Rendimento',
          'amount': DemoData._round(units * 0.09),
          'payment_date': DemoData._day(m),
        },
    ];
  }

  /// Positions as Dinzo's `/v1/investments/{id}` objects.
  List<Map<String, dynamic>> raw() => [
    for (final (i, p) in positions.indexed)
      {
        'id': DemoData._uuid(Random(i + 101)),
        'asset_key': p.assetKey,
        'name': p.name,
        'type': p.type,
        'sub_type': p.subType,
        'balance': DemoData._round(p.valueOn(today, today)),
        'quantity': p.unitsOn(today),
        'value': p.unitsOn(today) == null
            ? null
            : DemoData._round(p.price(today)),
        'code': p.code,
        'isin': null,
        'issuer': p.issuer,
        'currency': 'BRL',
        'due_date': p.due == null ? null : DemoData._day(p.due!),
        'purchase_date':
            p.firstBuy == null ? null : DemoData._day(p.firstBuy!),
        'rate': p.rate,
        'rate_type': p.rate == null ? null : 'CDI',
        'fixed_annual_rate': null,
        'last_twelve_months_rate': p.lastTwelveMonths,
        'tax_exempt': p.taxExempt ? true : null,
        'status': 'ACTIVE',
        'archived': false,
        'transactions': [
          for (final (j, m) in p.moves.indexed)
            if (!m.date.isAfter(today))
              {
                'id': DemoData._uuid(Random(i * 100 + j + 7)),
                'type': m.type,
                'movement_type': m.type == 'BUY' ? 'CREDIT' : 'DEBIT',
                'date': DemoData._day(m.date),
                'amount': m.amount,
                'net_amount': m.net,
                'description': null,
              },
        ],
      },
  ];
}
