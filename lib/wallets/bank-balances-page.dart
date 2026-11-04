import 'package:flutter/material.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/dashboard/dashboard-data.dart';
import 'package:aupp/dinzo/daily-money.dart';
import 'package:aupp/dinzo/dinzo-api.dart';
import 'package:aupp/dinzo/dinzo-models.dart';
import 'package:aupp/dinzo/dinzo-taxes.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/investments/investments-page.dart' show InstitutionLogo;
import 'package:aupp/services/logger.dart';

String _dayText(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// One bank, with what Dinzo says is in it.
class BankHoldings {
  final Institution institution;
  final List<DinzoAccount> accounts = [];
  final List<DinzoAccount> cards = [];
  final List<DinzoInvestment> fixedIncome = [];
  final List<DinzoInvestment> otherInvestments = [];

  BankHoldings(this.institution);

  bool get isDaily => DailyBanks.isDaily(institution.name);

  static double _sum(Iterable<DinzoInvestment> list) =>
      list.fold(0.0, (sum, i) => sum + i.balance);

  double get accountsTotal => accounts.fold(
    0.0,
    (sum, a) => sum + (a.excludeFromTotals ? 0 : a.balance ?? 0),
  );
  double get fixedIncomeTotal => _sum(fixedIncome);
  double get otherTotal => _sum(otherInvestments);
  double get cardsTotal =>
      cards.fold(0.0, (sum, c) => sum + (c.excludeFromTotals ? 0 : c.balance ?? 0));

  /// What is there, cards left out (they are what is owed).
  double get total => accountsTotal + fixedIncomeTotal + otherTotal;

  /// By bank: accounts and cards by their connection, positions by the
  /// institution they are at ([Institution.of]). Archived ones are left out.
  static List<BankHoldings> group(
    List<DinzoAccount> accounts,
    List<DinzoInvestment> investments,
  ) {
    final byName = <String, BankHoldings>{};
    BankHoldings of(Institution institution) =>
        byName.putIfAbsent(institution.name, () => BankHoldings(institution));
    for (final account in accounts.where((a) => !a.archived)) {
      final connector = account.connectorName;
      final tag = connector == null ? null : KnownTag.bankIn(connector);
      final bank = of(
        tag != null
            ? Institution.fromTag(tag)
            : Institution(
                connector ?? 'Contas sem banco',
                null,
                Colors.blueGrey,
              ),
      );
      (account.isCreditCard ? bank.cards : bank.accounts).add(account);
    }
    for (final inv in investments.where((i) => !i.archived)) {
      final bank = of(Institution.of(inv));
      (inv.type == DailyMoney.fixedIncomeType
              ? bank.fixedIncome
              : bank.otherInvestments)
          .add(inv);
    }
    return byName.values.toList()..sort((a, b) {
      if (a.isDaily != b.isDaily) return a.isDaily ? -1 : 1;
      return b.total.compareTo(a.total);
    });
  }
}

/// Fork: the balance at each bank Dinzo syncs, as it last came, and how it
/// makes up the money the wallets divide.
class BankBalancesPage extends StatefulWidget {
  const BankBalancesPage({super.key});

  @override
  State<BankBalancesPage> createState() => _BankBalancesPageState();
}

class _BankBalancesPageState extends State<BankBalancesPage> {
  static final _logger = Logger.withClass(BankBalancesPage);

  DashboardData? _dashboard;
  InvestmentsSnapshot? _investments;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dashboard = await DashboardCache.load();
    final investments = await InvestmentsCache.load();
    if (!mounted) return;
    setState(() {
      _dashboard = dashboard;
      _investments = investments;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final dashboard = await DashboardCache.refresh();
      final investments = await InvestmentsCache.refresh();
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _investments = investments;
      });
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to refresh the bank balances');
      if (mounted) setState(() => _error = 'Não consegui buscar na Dinzo: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<DinzoAccount> get _accounts => [
    for (final raw in _dashboard?.accounts ?? const <Map<String, dynamic>>[])
      DinzoAccount.fromJson(raw),
  ];

  List<DinzoInvestment> get _positions =>
      _investments?.investments ?? const [];

  static String _when(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final fetched = [
      ?_dashboard?.fetchedAt,
      ?_investments?.fetchedAt,
    ]..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldo nos bancos'),
        actions: [
          IconButton(
            tooltip: 'Buscar na Dinzo',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dashboard == null && _investments == null
          ? _empty(context)
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (fetched.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Text(
                      'Como a Dinzo mandou em ${_when(fetched.first)}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                for (final bank in BankHoldings.group(_accounts, _positions))
                  _BankCard(bank, bills: _dashboard?.upcomingBills ?? const []),
                _MoneyCard(DailyMoney.balances(_accounts, _positions)),
              ],
            ),
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Nada da Dinzo ainda neste aparelho.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _refreshing ? null : _refresh,
            child: const Text('Buscar agora'),
          ),
        ],
      ),
    ),
  );
}

class _BankCard extends StatelessWidget {
  const _BankCard(this.bank, {required this.bills});

  final BankHoldings bank;
  final List<UpcomingBill> bills;

  static String _rateOf(DinzoInvestment inv) {
    if (inv.rate != null && inv.rateType != null) {
      return '${_number(inv.rate!)}% ${inv.rateType}';
    }
    if (inv.fixedAnnualRate != null) {
      return '${_number(inv.fixedAnnualRate!)}% a.a.';
    }
    return '';
  }

  static String _number(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: InstitutionLogo(institution: bank.institution, size: 36),
            title: Text(
              bank.institution.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            subtitle: Text(
              bank.isDaily ? 'Dia a dia' : 'Investimento',
              style: TextStyle(color: muted),
            ),
            trailing: Text(
              formatMoney(bank.total),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          for (final account in bank.accounts)
            _line(
              context,
              bank.accounts.length > 1 ? 'Conta · ${account.title}' : 'Conta',
              account.balance,
              note: account.excludeFromTotals ? 'fora dos totais' : null,
            ),
          if (bank.fixedIncome.isNotEmpty)
            _positions(
              context,
              'Renda fixa',
              bank.fixedIncome,
              bank.fixedIncomeTotal,
            ),
          if (bank.otherInvestments.isNotEmpty)
            _positions(
              context,
              'Ações e fundos',
              bank.otherInvestments,
              bank.otherTotal,
            ),
          for (final card in bank.cards) _card(context, card),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    double? value, {
    String? note,
    Color? color,
  }) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 15)),
      subtitle: note == null
          ? null
          : Text(note, style: TextStyle(color: muted)),
      trailing: Text(
        value == null ? 'sem saldo' : formatMoney(value),
        style: TextStyle(fontSize: 15, color: color),
      ),
    );
  }

  Widget _positions(
    BuildContext context,
    String label,
    List<DinzoInvestment> list,
    double total,
  ) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final sorted = [...list]..sort((a, b) => b.balance.compareTo(a.balance));
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        title: Text(
          '$label · ${list.length} ${list.length == 1 ? 'item' : 'itens'}',
          style: const TextStyle(fontSize: 15),
        ),
        trailing: Text(formatMoney(total), style: const TextStyle(fontSize: 15)),
        childrenPadding: const EdgeInsets.only(left: 16),
        children: [
          for (final inv in sorted)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                [productOf(inv), _rateOf(inv)]
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
              ),
              subtitle: Text(
                [
                  // "CDB - NU FINANCEIRA..." says nothing the line above
                  // does not.
                  if (!inv.name.startsWith('${productOf(inv)} - ')) inv.name,
                  if (inv.dueDate != null) 'vence ${_dayText(inv.dueDate!)}',
                ].join(' · '),
                style: TextStyle(color: muted),
              ),
              trailing: Text(formatMoney(inv.balance)),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, DinzoAccount card) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final bill = bills.where((b) => b.cardAccountId == card.id).firstOrNull;
    final limit = card.creditLimit;
    return ListTile(
      dense: true,
      title: Text(
        'Cartão · ${card.title}',
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: Text(
        [
          if (bill != null)
            'Fatura aberta ${formatMoney(bill.amount)}'
                '${bill.isEstimate ? ' (estimada)' : ''}'
                ', vence ${_dayText(bill.dueDate.toIso8601String())}',
          if (limit != null) 'Limite ${formatMoney(limit)}',
          if (card.excludeFromTotals) 'fora dos totais',
        ].join('\n'),
        style: TextStyle(color: muted),
      ),
      isThreeLine: bill != null && limit != null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            card.balance == null ? 'sem saldo' : '− ${formatMoney(card.balance!)}',
            style: TextStyle(fontSize: 15, color: theme.colorScheme.error),
          ),
          Text('limite usado', style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );
  }
}

/// How the banks make up the money the wallets divide (and the wallet to
/// invest takes what the others leave): see [DailyMoney].
class _MoneyCard extends StatelessWidget {
  const _MoneyCard(this.balances);

  final DinzoBalances balances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, double value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          Text(
            formatMoney(value),
            style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ],
      ),
    );
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Dinheiro que as carteiras repartem',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            row('Contas dos bancos do dia a dia', balances.bank),
            row('Renda fixa dos bancos do dia a dia', balances.fixedIncome),
            row('Cartões (limite usado)', -balances.cardDebt),
            const Divider(),
            row('Dinheiro', balances.money, bold: true),
            if (!balances.complete) ...[
              const SizedBox(height: 8),
              Text(
                'Sem saldo de ${balances.unknown.join(', ')}: o Investir não é '
                'recalculado até a Dinzo mandar.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'O que sobra depois das outras carteiras fica no Investir. Ações e '
              'fundos, e o que está nos bancos de investimento, não entram.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
