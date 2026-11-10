import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/fiscal/fiscal-engine.dart';
import 'package:aupp/fiscal/fiscal-page.dart';
import 'package:aupp/fiscal/fiscal-store.dart';
import 'dart:async';
import 'dart:math' show max;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:aupp/desktop/desktop-layout.dart';
import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/budget_plan/budget-plan-groups.dart';
import 'package:aupp/budget_plan/budget-plan-page.dart';
import 'package:aupp/budget_plan/budget-plan-service.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/components/missing-payment-code-icon.dart';
import 'package:aupp/components/due-date-badge.dart';
import 'package:aupp/dinzo/payment-launcher.dart';
import 'package:aupp/records/edit-record-page.dart';
import 'package:aupp/dinzo/dinzo-api.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/records/records-list-page.dart';
import 'package:aupp/statistics/statistics-page.dart';
import 'package:aupp/records/controllers/tab_records_controller.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/services/total-wallets.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/wallets/wallets-tab-page.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';

import 'package:aupp/services/home-widget-service.dart';

import 'dashboard-data.dart';
import 'due-bills.dart';
import 'due-today-alert.dart';

import 'package:aupp/dinzo/estimate-link.dart';

/// Home screen (pt-BR): what needs attention now. Shows the cached
/// Dinzo data at once and refreshes it in the background every time it is
/// shown; month totals and the budget split come from the local records.
class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  DashboardPageState createState() => DashboardPageState();
}

class _MonthTotals {
  double income = 0;

  /// What the month really paid; [expensesTotal] = everything spent, at
  /// full value (also what caixinhas paid), shown below it.
  double expenses = 0;
  double expensesTotal = 0;

  /// Money moved to other wallets (caixinhas) and taken back from them (a
  /// purchase partly paid with one too). Not income or expenses, but it
  /// moves the balance.
  /// [invested]: to wallets in Liberdade Financeira (budget plan).
  double invested = 0;
  double setAside = 0;
  double takenBack = 0;

  /// What the estimates and the other upcoming records of the month still
  /// expect, already inside [income] and [expensesTotal].
  double plannedIncome = 0;
  double plannedExpenses = 0;

  /// [takenBack] includes what caixinhas paid of purchases, so the full
  /// amount spent is what comes off.
  double get saved => income - expensesTotal - invested - setAside + takenBack;
}

class DashboardPageState extends State<DashboardPage> {
  DashboardData? _data;
  _MonthTotals _month = _MonthTotals();

  /// The records behind [_month] and the wallets, to open them on a tap.
  List<Record> _monthRecords = [];
  Map<int, Wallet> _walletMap = {};
  BudgetPlanSnapshot? _plan;
  double? _free;

  /// What the month still expects in the Conta corrente: the estimates not
  /// linked yet (the salary, the rent) and the upcoming recurrent records.
  double _freePending = 0;
  double _toInvest = 0;

  /// Boleto / Pix occurrences still to pay this month or in the next
  /// [_billsDays] days ([_inBillsWindow]; a [Record.billingTags]
  /// recurrence, or any with a code pasted).
  List<Record> _duePayments = [];

  /// Each company with its taxes due this month (last month's) and the
  /// current month's so far.
  List<(String, FiscalMonth, FiscalMonth)> _taxes = [];

  /// Of those (and the stored ones of today), what is due today or overdue
  /// up to [_billsDays] days and not marked "Já paguei": the red alert.
  List<Record> _dueNow = [];

  /// "Próximas faturas" only shows what is due this soon.
  static const _billsDays = 7;
  bool _refreshing = false;
  String? _error;

  final _dayMonth = DateFormat('dd/MM');

  static const _monthNames = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  @override
  void initState() {
    super.initState();
    SqliteDatabase.dataChangeNotifier.addListener(_onDataChanged);
    onTabChange();
  }

  @override
  void dispose() {
    SqliteDatabase.dataChangeNotifier.removeListener(_onDataChanged);
    _reloadTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Timer? _reloadTimer;

  /// A sync applied or a record changed: recompute the local numbers once
  /// the burst of writes is over.
  void _onDataChanged() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 600), _loadLocal);
  }

  /// Called when the tab is shown: local numbers right away, then Dinzo in
  /// the background.
  Future<void> onTabChange() async {
    await _loadLocal();
    final cached = await DashboardCache.load();
    if (mounted && cached != null && _data == null) {
      setState(() => _data = cached);
    }
    await _refresh(force: false);
  }

  Future<void> _refresh({bool force = true}) async {
    // The Dinzo is optional: without it the Início is the local numbers.
    if (_refreshing || DinzoSyncService.apiKey == null) return;
    final last = _data?.fetchedAt;
    if (!force && DashboardCache.fetchedToday(last)) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final data = await DashboardCache.refresh();
      if (mounted) setState(() => _data = data);
    } on DinzoApiException catch (e) {
      _error = e.code == 'missing_key'
          ? 'Configure a chave da Dinzo em Configurações → Integrações com API.'
          : 'Dinzo indisponível agora (${e.code}).';
    } catch (_) {
      _error = 'Sem conexão: mostrando os dados salvos.';
    }
    if (mounted) setState(() => _refreshing = false);
    await _loadLocal();
  }

  Future<void> _loadLocal() async {
    final db = ServiceConfig.database;
    final now = DateTime.now();
    final records = MoneyAccounts.withoutTransfers(await db.getAllRecords())
        .whereType<Record>();

    final defaultWallet = await db.getDefaultWallet();

    // Same numbers as the Extrato's totals (TotalWallets): transfers to/from
    // other wallets count as expense/income (see Record.countsAsExpense);
    // records in other wallets stay out.
    final wallets = await db.getAllWallets();
    final spendingIds = TotalWallets.idsIn(wallets, defaultWallet?.id);
    // The whole month, as in the Extrato: the estimates not linked yet and
    // the upcoming recurrent records count too.
    // Far enough for the next days' boletos too, when the month ends sooner.
    final monthEnd = DateTime(now.year, now.month + 1);
    final billsEnd = DateTime(now.year, now.month, now.day + _billsDays + 1);
    var upcoming = <Record>[];
    try {
      upcoming = await RecurrentRecordService()
          .updateRecurrentRecords(
            (billsEnd.isAfter(monthEnd) ? billsEnd : monthEnd).toUtc(),
          );
    } catch (_) {}
    bool inMonth(Record r) =>
        r.dateTime.year == now.year && r.dateTime.month == now.month;
    // The last days too: an overdue estimate already paid is not due.
    final recentFrom = DateTime(now.year, now.month, now.day - _billsDays);
    bool recent(Record r) => !r.dateTime.isBefore(recentFrom);
    EstimateLink.markMatches([
      ...records.where((r) => inMonth(r) || recent(r)),
      ...upcoming,
    ]);
    final monthRecords = TabRecordsController.withoutHidden([
      ...records.where(inMonth),
      ...upcoming.where(inMonth),
    ]).whereType<Record>().toList();
    final month = _MonthTotals();
    final counted = spendingIds.isEmpty
        ? monthRecords
        : TabRecordsController.applyTransferAwareWalletFilter(
            monthRecords,
            spendingIds,
          ).whereType<Record>().toList();
    final budget = BudgetPlan.saved;
    final walletsById = {for (final w in wallets) w.id: w};
    for (final r in realExpenses(counted)) {
      month.expenses += -(r.value ?? 0);
    }
    for (final r in counted) {
      if (r.value == null) continue;
      if (r.countsAsIncome) {
        month.income += r.value!;
        if (r.isFutureRecord) month.plannedIncome += r.value!;
      } else if (r.countsAsExpense) {
        month.expensesTotal += -r.value!;
        if (r.isFutureRecord) month.plannedExpenses += -r.value!;
      } else if (r.isInvestmentFlow) {
        month.invested += -r.value!;
      } else if (r.countsAsSetAside) {
        final to = walletsById[r.transferWalletId];
        if (r.value! < 0 && to != null && budget.isInvestmentWallet(to.name)) {
          month.invested += -r.value!;
        } else if (r.value! < 0) {
          month.setAside += -r.value!;
        } else {
          month.takenBack += r.value!;
        }
      }
    }

    BudgetPlanSnapshot? plan;
    try {
      plan = await BudgetPlanService.load(now: now);
    } catch (_) {
      plan = null;
    }

    double? free;
    double toInvest = 0;
    if (defaultWallet != null) {
      for (final w in await db.getWalletsBalanceAsOf(
        now)) {
        final balance = w.balance ?? w.initialAmount;
        if (w.id == defaultWallet.id) {
          free = balance;
        } else if (!w.isArchived && w.isInvestmentReserve) {
          toInvest += balance;
        }
      }
    }

    var freePending = 0.0;
    for (final r in upcoming.where(inMonth)) {
      if (r.value == null || r.estimateMatch != null) continue;
      if (r.walletId == defaultWallet?.id) freePending += r.value!;
      if (r.transferWalletId == defaultWallet?.id) {
        freePending -= r.value!;
      }
    }

    final bills = await DueBills.find(records, upcoming);
    HomeWidgetService.saveDueDays(bills);
    // What is paid already leaves the list.
    final duePayments = bills
        .where((r) => !r.markedPaid && _daysUntil(r.dateTime) >= 0)
        .where((r) => _inBillsWindow(r.dateTime))
        .toList();
    final dueNow = bills.where((r) {
      final days = _daysUntil(r.dateTime);
      return !r.markedPaid && days <= 0 && days >= -_billsDays;
    }).toList();

    final taxes = <(String, FiscalMonth, FiscalMonth)>[];
    for (final company in MoneyAccounts.companies()) {
      if (!company.fiscal.isSetUp) continue;
      final loaded = await FiscalStore.load(company);
      final now = FiscalStore.currentMonth;
      taxes.add((
        company.name,
        loaded.engine.month(now.add(-1)),
        loaded.engine.month(now),
      ));
    }

    if (!mounted) return;
    setState(() {
      _taxes = taxes;
      _duePayments = duePayments;
      _dueNow = dueNow;
      _month = month;
      _monthRecords = counted;
      _walletMap = {
        for (final w in wallets)
          if (w.id != null) w.id!: w,
      };
      _freePending = freePending;
      _plan = plan;
      _free = free;
      _toInvest = toInvest;
    });
  }

  String _money(double v) => getCurrencyValueString(v);

  final ScrollController _scroll = ScrollController();
  double _offset = 0;

  /// Lower on the computer: the picture is much wider there.
  double get _heroHeight => isWideLayout(context) ? 240 : 300;

  static const _weekdays = [
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
    'domingo',
  ];

  String get _greeting {
    final h = DateTime.now().hour;
    final hello = h < 5
        ? 'Boa noite'
        : h < 12
        ? 'Bom dia'
        : h < 18
        ? 'Boa tarde'
        : 'Boa noite';
    final name = _data?.firstName;
    return name == null ? hello : '$hello, $name';
  }

  String get _todayLabel {
    final now = DateTime.now();
    return '${_weekdays[now.weekday - 1]}, ${now.day} de '
        '${_monthNames[now.month - 1]}';
  }

  /// The month's landscape takes the light of the hour: warm in the
  /// morning, neutral at midday, golden at sunset, deep blue at night.
  Color get _hourTint {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 10) return const Color(0x33FFB74D);
    if (h >= 10 && h < 16) return const Color(0x1A000000);
    if (h >= 16 && h < 19) return const Color(0x4DFF7043);
    return const Color(0x99101A3A);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overImage = _offset < _heroHeight - kToolbarHeight - 40;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: AnimatedOpacity(
          opacity: overImage ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          child: const Text('Início'),
        ),
        backgroundColor: overImage
            ? Colors.transparent
            : theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: overImage ? Colors.white : null,
        systemOverlayStyle: overImage
            ? SystemUiOverlayStyle.light
            : (theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _refreshing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: overImage ? Colors.white : null,
                      ),
                    )
                  : _data == null
                  ? const SizedBox.shrink()
                  : Text(
                      DateFormat('HH:mm').format(_data!.fetchedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: overImage ? Colors.white70 : null,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        onRefresh: () => _refresh(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical &&
                (n.metrics.pixels - _offset).abs() > 2) {
              setState(() => _offset = n.metrics.pixels);
            }
            return false;
          },
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.zero,
            children: [
              _buildHero(),
              Transform.translate(
                offset: const Offset(0, -28),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      _buildDueNow(),
                      AdaptiveColumns(
                        left: [
                          _buildMonth(),
                          _buildBills(),
                          _buildTaxes(),
                          _buildSubscriptions(),
                        ],
                        right: [if (_plan != null) _buildBudgetPlan(_plan!)],
                        narrow: [
                          _buildMonth(),
                          if (_plan != null) _buildBudgetPlan(_plan!),
                          _buildBills(),
                          _buildTaxes(),
                          _buildSubscriptions(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    const shadow = [Shadow(blurRadius: 8, color: Colors.black54)];
    // Only the money waiting to be invested:
    // caixinhas, crypto and yield have their own screens.
    // The month's estimates count: the big number is how the month ends.
    final pending = _freePending.abs() >= 0.005;
    final details = [
      if (_free != null && pending) 'hoje ${_money(_free!)}',
      if (_toInvest > 0) '${_money(_toInvest)} para investir',
    ];
    return SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Parallax: the picture scrolls at half speed.
          ClipRect(
            child: Transform.translate(
              offset: Offset(0, _offset.clamp(0, _heroHeight) * 0.5),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(_hourTint, BlendMode.srcATop),
                child: Image(
                  image: getBackgroundImage(DateTime.now().month),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // Keeps the white text readable on bright pictures.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x55000000),
                  Color(0x00000000),
                  Color(0x88000000),
                ],
                stops: [0, 0.4, 1],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 16,
            bottom: 48,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _greeting,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          shadows: shadow,
                        ),
                      ),
                      Text(
                        _todayLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          shadows: shadow,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        pending
                            ? 'Conta corrente no fim do mês'
                            : 'Conta corrente',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          shadows: shadow,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _free == null ? '—' : _money(_free! + _freePending),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            shadows: shadow,
                          ),
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details.join(' · '),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            shadows: shadow,
                          ),
                        ),
                    ],
                  ),
                ),
                _walletsButton(shadow),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The wallets live here instead of the bottom bar: a frosted round button
  /// over the picture.
  Widget _walletsButton(List<Shadow> shadow) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Material(
                color: Colors.white.withValues(alpha: 0.18),
                shape: CircleBorder(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openWallets,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.white,
                      size: 26,
                      shadows: shadow,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Carteiras',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              shadows: shadow,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWallets() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WalletsTabPage()),
    );
    _loadLocal();
  }

  Widget _section(String title, Widget child, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- bills

  static int _daysUntil(DateTime due) => DueBills.daysUntil(due);

  String _dueLabel(DateTime due) {
    final days = _daysUntil(due);
    if (days < 0) return 'venceu ${_dayMonth.format(due)}';
    if (days == 0) return 'vence hoje';
    if (days == 1) return 'vence amanhã';
    return 'vence em $days dias · ${_dayMonth.format(due)}';
  }

  Widget _buildBills() {
    // Card bills come from the Dinzo (optional); boletos and Pix from the
    // recurrent records.
    final dinzo = DinzoSyncService.apiKey != null;
    if (!dinzo && _duePayments.isEmpty) return const SizedBox.shrink();
    final bills = (_data?.upcomingBills ?? const <UpcomingBill>[])
        .where((b) => _inBillsWindow(b.dueDate))
        .toList();
    final theme = Theme.of(context);
    // Boletos, Pix and cards together, by due date.
    final rows = <(DateTime, Widget)>[
      for (final r in _duePayments) (r.dateTime, _buildDuePayment(r)),
      for (final b in bills) (b.dueDate, _buildCardBill(b)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return _section(
      'Próximas faturas',
      Card(
        margin: EdgeInsets.zero,
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  dinzo && _data == null
                      ? 'Carregando faturas da Dinzo…'
                      : 'Nada vencendo neste mês nem nos próximos '
                            '$_billsDays dias.',
                ),
              )
            : Column(children: [for (final (_, row) in rows) row]),
      ),
      action: _data == null
          ? null
          : Text(
              'aberto ${_money(_data!.openBillsTotal)}',
              style: theme.textTheme.bodySmall,
            ),
    );
  }

  /// "Próximas faturas" shows the rest of the month, or the next
  /// [_billsDays] days when they go into the next month (on the 29th, what
  /// is due on the 3rd).
  static bool _inBillsWindow(DateTime due) {
    final now = DateTime.now();
    return _daysUntil(due) <= _billsDays ||
        (due.year == now.year && due.month == now.month);
  }

  Widget _buildCardBill(UpcomingBill b) {
    final theme = Theme.of(context);
    return ListTile(
      leading: _bankLogo(b.connector),
      title: Text(b.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _dueLabel(b.dueDate) + (b.isEstimate ? ' · estimada' : ''),
      ),
      trailing: Text(
        _money(b.amount),
        style: theme.textTheme.titleMedium?.copyWith(
          color: b.dueDate.difference(DateTime.now()).inDays <= 3
              ? theme.colorScheme.error
              : null,
        ),
      ),
    );
  }

  /// A boleto / Pix occurrence: tap to copy or paste its code; blinks red
  /// while it has none.
  Widget _buildDuePayment(Record r) {
    final theme = Theme.of(context);
    final code = r.paymentCode;
    final kind = code != null
        ? Record.paymentCodeKind(code)
        : Record.billingKindOf(r.tags)!;
    final title = r.title == null || r.title!.trim().isEmpty
        ? r.category?.name ?? kind
        : r.title!;
    return ListTile(
      leading: r.needsPaymentCode
          ? MissingPaymentCodeIcon(kind, size: 32)
          : DueDateBadge(
              show: r.dueDateUnknown,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: KnownTag.of(kind)?.color,
                child: Icon(
                  KnownTag.of(kind)?.icon ?? Icons.qr_code_2,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_dueLabel(r.dateTime)} · '
        '${code == null ? '$kind sem código' : kind}',
      ),
      trailing: Text(
        _money(-(r.value ?? 0)),
        style: theme.textTheme.titleMedium?.copyWith(
          color: _daysUntil(r.dateTime) <= 3
              ? theme.colorScheme.error
              : null,
        ),
      ),
      onTap: () async {
        if (code != null) {
          await PaymentLauncher.open(context, code);
          return;
        }
        await _openOccurrence(r);
      },
    );
  }

  Future<void> _openOccurrence(Record r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditRecordPage(passedRecord: r, readOnly: true),
      ),
    );
    await _loadLocal();
  }

  /// "Já paguei": out of the alert until the real record comes and is linked.
  Future<void> _markPaid(Record r, bool paid) async {
    await RecurrentRecordService.setMarkedPaid(r, paid);
    await _loadLocal();
    if (!mounted || !paid) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Marcado como pago. Quando chegar da Dinzo, é só vincular.',
        ),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () => _markPaid(r, false),
        ),
      ),
    );
  }

  Widget _buildDueNow() {
    if (_dueNow.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: DueTodayAlert(
        due: _dueNow,
        onPay: (r) => PaymentLauncher.open(context, r.paymentCode!),
        onMarkPaid: (r) => _markPaid(r, true),
        onOpen: _openOccurrence,
      ),
    );
  }

  Widget _bankLogo(String? connector) {
    final bank = connector == null ? null : KnownTag.bankIn(connector);
    if (bank != null) return BankMark(bank, size: 32);
    return const CircleAvatar(
      radius: 16,
      child: Icon(Icons.credit_card, size: 18),
    );
  }

  // ----------------------------------------------------------------- month

  /// Receitas, Despesas, Saldo: the chart of the month on that tab.
  void _openMonthChart(StatisticsTab tab) {
    final now = DateTime.now();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatisticsPage(
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59),
          _monthRecords,
          walletMap: _walletMap,
          initialTab: tab,
        ),
      ),
    ).then((_) => _loadLocal());
  }

  /// Investido, Guardado, Retirado: just the records of the month.
  void _openMonthList(String label, List<Record> Function(SetAsideSplit) pick) {
    final budget = BudgetPlan.saved;
    final split = SetAsideSplit(_monthRecords, (id) {
      final to = _walletMap[id];
      return to != null && budget.isInvestmentWallet(to.name);
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordsListPage(
          title: '$label · ${_monthNames[DateTime.now().month - 1]}',
          records: pick(split),
        ),
      ),
    ).then((_) => _loadLocal());
  }

  Widget _buildMonth() {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final m = _month;
    final dim = theme.colorScheme.onSurfaceVariant;
    final incomeColor = incomeAmountColor(brightness);
    final expenseColor = expenseAmountColor(brightness);
    final investedColor = budgetGroupById('liberdade')!.color;
    final savedColor = budgetGroupById('metas')!.color;

    // Fixed slots (label, amount, footnote), the same three columns in both
    // rows, so nothing moves when a footnote or a value shows up.
    Widget cell(
      String label,
      double value, {
      Color? color,
      Color? dot,
      String? note,
      bool big = true,
      VoidCallback? onTap,
    }) => Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (dot != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: dim),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _money(value),
                style:
                    (big
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.bodyLarge)
                        ?.copyWith(
                          color: value.abs() < 0.005 && !big ? dim : color,
                          fontWeight: big ? FontWeight.w700 : FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
            ),
            if (big)
              SizedBox(
                height: 16,
                child: note == null
                    ? null
                    : Text(
                        note,
                        style: theme.textTheme.labelSmall?.copyWith(color: dim),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
          ],
        ),
      ),
    );

    // Where the money that came in went: spent, invested, set aside, left.
    final cameIn = m.income + m.takenBack;
    final left = max(0.0, m.saved);
    final segments = [
      (m.expensesTotal, expenseColor),
      (m.invested, investedColor),
      (m.setAside, savedColor),
      (left, incomeColor),
    ].where((s) => s.$1 > 0.005).toList();
    final segmentsTotal = segments.fold(0.0, (t, s) => t + s.$1);
    // Wider than what came in only when more went out than came in.
    final barTotal = max(cameIn, segmentsTotal);

    return _section(
      'O mês · ${_monthNames[DateTime.now().month - 1]}',
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cell(
                    'Receitas',
                    m.income,
                    color: incomeColor,
                    onTap: () => _openMonthChart(StatisticsTab.income),
                    note: m.plannedIncome > 0.005
                        ? '${_money(m.plannedIncome)} previsto'
                        : null,
                  ),
                  const SizedBox(width: 12),
                  cell(
                    'Despesas',
                    m.expenses,
                    color: expenseColor,
                    dot: expenseColor,
                    onTap: () => _openMonthChart(StatisticsTab.expenses),
                    // Everything spent, at full value (also what caixinhas
                    // paid); only when it differs.
                    note: m.plannedExpenses > 0.005
                        ? '${_money(m.plannedExpenses)} previsto'
                        : m.expensesTotal > m.expenses + 0.005
                        ? 'total ${_money(m.expensesTotal)}'
                        : null,
                  ),
                  const SizedBox(width: 12),
                  cell(
                    'Saldo',
                    m.saved,
                    color: m.saved >= 0 ? incomeColor : expenseColor,
                    dot: incomeColor,
                    onTap: () => _openMonthChart(StatisticsTab.balance),
                  ),
                ],
              ),
              if (barTotal > 0.005) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        for (final (value, color) in segments)
                          Expanded(
                            flex: max(1, (value / barTotal * 1000).round()),
                            child: Container(color: color),
                          ),
                        if (segmentsTotal < barTotal - 0.005)
                          Expanded(
                            flex: max(
                              1,
                              ((barTotal - segmentsTotal) / barTotal * 1000)
                                  .round(),
                            ),
                            child: Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cell(
                    'Investido',
                    m.invested,
                    dot: investedColor,
                    big: false,
                    onTap: () => _openMonthList('Investido', (s) => s.invested),
                  ),
                  const SizedBox(width: 12),
                  cell(
                    'Guardado',
                    m.setAside,
                    dot: savedColor,
                    big: false,
                    onTap: () => _openMonthList('Guardado', (s) => s.saved),
                  ),
                  const SizedBox(width: 12),
                  cell(
                    'Retirado',
                    m.takenBack,
                    big: false,
                    onTap: () => _openMonthList('Retirado', (s) => s.taken),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- budgets

  Future<void> _openBudgetPlan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BudgetPlanPage()),
    );
    _loadLocal();
  }

  /// The month's records behind one group, in the statistics screen,
  /// grouped by subcategory (records match their own category, never the
  /// parent's, so a parent never drags in another group's subcategory).
  Widget _buildBudgetPlan(BudgetPlanSnapshot snap) {
    final now = DateTime.now();
    return _section(
      'Orçamento · ${_monthNames[now.month - 1]}',
      Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openBudgetPlan,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: BudgetPlanGroups(
              snap: snap,
              from: DateTime(now.year, now.month, 1),
              to: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
              onReturn: _loadLocal,
            ),
          ),
        ),
      ),
      action: TextButton(
        onPressed: _openBudgetPlan,
        child: const Text('Ajustar'),
      ),
    );
  }

  // ------------------------------------------------------------------ free

  // --------------------------------------------------------- subscriptions

  /// The company's taxes due this month, and a preview of the next ones.
  Widget _buildTaxes() {
    if (_taxes.isEmpty) return const SizedBox.shrink();
    return _section(
      'Impostos do mês',
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (name, due, current) in _taxes)
              ListTile(
                dense: true,
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(name),
                subtitle: Text(
                  '${due.month.label}: ${_dueLabel(due.due)}\n'
                  'Prévia de ${current.month.label}: ${_money(current.taxes)}',
                ),
                isThreeLine: true,
                trailing: Text(
                  _money(due.taxes),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FiscalPage(companyName: name),
                    ),
                  );
                  _loadLocal();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptions() {
    final subs = _data?.activeSubscriptions ?? const <ActiveSubscription>[];
    if (subs.isEmpty) return const SizedBox.shrink();
    final today = DateTime.now();
    subs.sort(
      (a, b) => (a.nextCharge(today) ?? DateTime(9999)).compareTo(
        b.nextCharge(today) ?? DateTime(9999),
      ),
    );
    final total = subs.fold<double>(0, (s, x) => s + x.amount);
    return _section(
      'Assinaturas',
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (final s in subs)
              ListTile(
                dense: true,
                leading: const Icon(Icons.autorenew),
                title: Text(s.name),
                subtitle: Text(
                  s.nextCharge(today) == null
                      ? 'cobrança recorrente'
                      : 'próxima ${_dayMonth.format(s.nextCharge(today)!)}',
                ),
                trailing: Text(_money(s.amount)),
              ),
          ],
        ),
      ),
      action: Text(
        '${_money(total)}/mês',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
