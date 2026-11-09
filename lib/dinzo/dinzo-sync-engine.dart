import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/components/known-tags.dart';

import 'dart:convert';

import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';

import 'daily-money.dart';
import 'dinzo-config.dart';
import 'dinzo-models.dart';

/// The fields the sync owns on an imported record. Stored as JSON in
/// [Record.dinzoSnapshot] so the next sync can tell whether the record was
/// edited locally (local wins) or changed in Dinzo (update it).
class DinzoSnapshot {
  final String title;
  final double value;

  /// "YYYY-MM-DD".
  final String date;
  final String? categoryName;
  final int? walletId;

  /// Tags the sync owns on the record: bank and payment method
  /// (e.g. ["C6", "Crédito"]). Sorted.
  final List<String> tags;

  /// Dinzo account the transaction came from. Not a record field; kept so a
  /// pending purchase that comes back under a new id can be matched again.
  final String? accountId;

  const DinzoSnapshot({
    required this.title,
    required this.value,
    required this.date,
    this.categoryName,
    this.walletId,
    this.tags = const [],
    this.accountId,
  });

  DinzoSnapshot withTitle(String newTitle) => DinzoSnapshot(
    title: newTitle,
    value: value,
    date: date,
    categoryName: categoryName,
    walletId: walletId,
    tags: tags,
    accountId: accountId,
  );

  DinzoSnapshot withCategory(String? newCategory) => DinzoSnapshot(
    title: title,
    value: value,
    date: date,
    categoryName: newCategory,
    walletId: walletId,
    tags: tags,
    accountId: accountId,
  );

  bool sameFieldsAs(DinzoSnapshot other) =>
      title == other.title &&
      (value - other.value).abs() < 0.005 &&
      date == other.date &&
      categoryName == other.categoryName &&
      walletId == other.walletId &&
      sameTags(tags, other.tags);

  static bool sameTags(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);

  String toJsonString() => jsonEncode({
    't': title,
    'v': value,
    'd': date,
    'c': categoryName,
    'w': walletId,
    'g': tags,
    'a': accountId,
  });

  static DinzoSnapshot? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return DinzoSnapshot(
      title: json['t'] as String? ?? '',
      value: (json['v'] as num).toDouble(),
      date: json['d'] as String,
      categoryName: json['c'] as String?,
      walletId: json['w'] as int?,
      tags: json['g'] is List ? List<String>.from(json['g'] as List) : const [],
      accountId: json['a'] as String?,
    );
  }

  /// What [record] looks like right now, in snapshot terms. [syncedTags] are
  /// the tags the sync last wrote: each counts only while the record has it.
  static DinzoSnapshot ofRecord(
    Record record, {
    String? accountId,
    List<String> syncedTags = const [],
  }) {
    final d = record.date; // YYYYMMDD in the record's timezone
    return DinzoSnapshot(
      title: record.title ?? '',
      value: record.value ?? 0,
      date: '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}',
      categoryName: record.category?.name,
      walletId: record.walletId,
      tags: syncedTags.where(record.tags.contains).toList(),
      accountId: accountId,
    );
  }
}

/// What [Record.dinzoSnapshot] holds: the values derived from Dinzo the last
/// time the record was synced ([source]) and the values written to the record
/// at that moment ([applied], which includes the user's merge-screen choices).
/// Comparing Dinzo against [source] says what changed there; comparing the
/// record against [applied] says what the user edited here.
class DinzoLink {
  final DinzoSnapshot source;
  final DinzoSnapshot applied;

  const DinzoLink(this.source, this.applied);

  String toJsonString() => jsonEncode({
    'src': jsonDecode(source.toJsonString()),
    'app': jsonDecode(applied.toJsonString()),
  });

  static DinzoLink? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return DinzoLink(
      DinzoSnapshot.fromJsonString(jsonEncode(json['src']))!,
      DinzoSnapshot.fromJsonString(jsonEncode(json['app']))!,
    );
  }
}

enum DinzoPlanKind {
  /// New transaction → new record.
  create,

  /// Changed in Dinzo on fields the user did not touch → update the record.
  update,

  /// Changed in Dinzo on a field the user also edited. Local wins unless the
  /// user opts in.
  conflict,

  /// Linked record whose transaction disappeared from Dinzo (or became
  /// hidden/internal/ignored) → delete the record.
  remove,

  /// Linked and nothing changed in Dinzo.
  unchanged,

  /// Never becomes a record (see [DinzoSkipReason]).
  skipped,
}

enum DinzoSkipReason {
  /// Hidden in Dinzo (own-account transfers, investment moves).
  hidden,

  /// A card bill payment: the purchases are already records. Money between
  /// the user's own accounts is not skipped any more: it comes in with
  /// [MoneyAccounts.transferTag] and the Extrato decides when to show it.
  internalTransfer,

  /// Investment moves and yield: they change net worth, which the free
  /// wallet already tracks, so they never become records.
  investment,

  /// Installment 2..N: the purchase is recorded in full on installment 1.
  laterInstallment,

  /// The user chose "não integrar".
  ignoredByUser,

  /// Moves inside the banks outside the everyday ones (BTG Banking → BTG
  /// Investimentos, a broker's own entries): the money stayed invested.
  /// Dinzo sometimes hides only one side of them.
  outsideDailyBanks,
}

class DinzoPlanItem {
  final DinzoPlanKind kind;
  final DinzoTransaction? transaction;

  /// Values derived from Dinzo alone (stored as [DinzoLink.source]).
  final DinzoSnapshot? source;

  /// What the record will look like after applying. The merge screen may
  /// change it (category, wallet, title...) before applying.
  DinzoSnapshot? desired;

  /// Text for [Record.description] on create (e.g. installment details).
  final String? description;

  /// Expense or income, from the transaction direction.
  final CategoryType? categoryType;

  /// The linked local record (update/conflict/remove/unchanged).
  final Record? existing;
  final DinzoSkipReason? skipReason;

  /// Whether applying the plan will act on this item. Conflicts and removals
  /// of locally edited records start unselected (local wins).
  bool selected;

  DinzoPlanItem({
    required this.kind,
    this.transaction,
    this.source,
    this.desired,
    this.description,
    this.categoryType,
    this.existing,
    this.skipReason,
    bool? selected,
  }) : selected =
           selected ??
           (kind == DinzoPlanKind.create ||
               kind == DinzoPlanKind.update ||
               kind == DinzoPlanKind.remove);

  bool get needsCategory =>
      (kind == DinzoPlanKind.create ||
          kind == DinzoPlanKind.update ||
          kind == DinzoPlanKind.conflict) &&
      desired?.categoryName == null;
}

class DinzoSyncPlan {
  final List<DinzoPlanItem> items;

  DinzoSyncPlan(this.items);

  Iterable<DinzoPlanItem> ofKind(DinzoPlanKind kind) =>
      items.where((i) => i.kind == kind);
}

/// Pure decision logic for a Dinzo pull: no network, no database.
class DinzoSyncEngine {
  final DinzoConfig config;
  final Map<String, DinzoAccount> accounts;
  final Map<String, DinzoCategory> categories;

  /// Wallet that receives imports with no merchant rule ("Livre").
  final int? defaultWalletId;

  /// The wallet to invest: money sent to a bank outside the everyday ones
  /// leaves it ([brokerOf]). Null before it exists: such transfers are
  /// skipped like any other investment move.
  final int? toInvestWalletId;

  /// Whether an account is in an everyday bank ([DailyBanks]).
  final bool Function(DinzoAccount account) isDailyAccount;

  DinzoSyncEngine({
    required this.config,
    required List<DinzoAccount> accounts,
    required List<DinzoCategory> categories,
    required this.defaultWalletId,
    this.toInvestWalletId,
    this.isDailyAccount = DailyBanks.holdsAccount,
  }) : accounts = {for (final a in accounts) a.id: a},
       categories = {for (final c in categories) c.id: c};

  static final RegExp _billPayment = RegExp(
    r'^pagamento efetuado\||pagamento de fatura|pagto\.? fatura|pagamento recebido|inclus[aã]o de pagamento',
    caseSensitive: false,
  );

  /// Nubank debits "Compra de Renda Variável" when a stock order is placed
  /// and refunds what was not executed as "Valor recebido de Investimentos";
  /// Dinzo files the debit under Compras, so it is matched by name.
  static final RegExp _investmentMove = RegExp(
    r'valor (recebido|transferido) (de|para) investimentos|aplica[cç][aã]o (rdb|cdb)|resgate (rdb|cdb|fundo)|dinheiro (reservado|retirado)|(compra|venda) de renda vari[aá]vel',
    caseSensitive: false,
  );

  /// Ids of card bill payments found by pairing: a credit on a card and a
  /// debit of the same amount on a bank account within 3 days. Filled by
  /// [plan].
  final Set<String> _billPaymentPairs = {};

  /// Money between an everyday bank and another one (a broker), by the id
  /// of the everyday side → the other bank's account. Filled by [plan].
  final Map<String, DinzoAccount> _brokerTransfers = {};

  /// Ids of transactions on a bank outside the everyday ones whose other
  /// side is on another own account (Dinzo hid one side only). Filled by
  /// [plan].
  final Set<String> _movesOutside = {};

  /// A broker's own entries, when Dinzo neither hides them nor files them
  /// under Investimentos.
  static final RegExp _brokerEntry = RegExp(
    r'liq\.? bolsa|tesouro direto|conta remunerada|dividendo|juros s(obre|/) ?capital|\bjcp\b|rendimento|amortiza[cç][aã]o|corretagem|cust[oó]dia|emolumento',
    caseSensitive: false,
  );

  /// A refund's credit by its id → the debit it undoes. Filled by [plan].
  final Map<String, DinzoTransaction> _refunded = {};

  /// "Reembolso de transferência enviada Fulano": the rest is the
  /// description of the debit being undone.
  static final RegExp _refund = RegExp(
    r'^(reembolso|estorno|devolu[cç][aã]o) (de |do |da )?',
    caseSensitive: false,
  );

  /// Real total of installment purchases, by the id of their first
  /// installment, when a later installment is known. Banks put the leftover
  /// cents in the first one (12x of 323,92 = 27,03 + 11 × 26,99), so the
  /// first installment times N overstates it. Filled by [plan].
  final Map<String, double> _installmentTotals = {};

  /// Display title: Nubank-style "Kind|Counterparty" keeps the counterparty;
  /// whitespace runs are collapsed.
  static String cleanTitle(String description) {
    final parts = description.split('|');
    final title = parts.length > 1 && parts.last.trim().isNotEmpty
        ? parts.last
        : description;
    return title.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Key used to remember per-merchant choices: lowercase, no digits.
  static String merchantKey(String description) =>
      cleanTitle(description)
          .toLowerCase()
          .replaceAll(RegExp(r'[0-9]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// A card bill paid from a bank account (both sides).
  bool isBillPayment(DinzoTransaction tx) =>
      _billPaymentPairs.contains(tx.id) ||
      _billPayment.hasMatch(tx.description);

  /// Money between the user's own accounts (PJ to PF...): the counterparty
  /// is one of [DinzoConfig.selfIdentifiers].
  bool isOwnTransfer(DinzoTransaction tx) {
    if (isBillPayment(tx)) return false;
    final text = '${tx.description} ${tx.originalDescription ?? ''}'
        .toLowerCase();
    final parties = {
      counterparty(tx.description),
      if (tx.originalDescription != null) counterparty(tx.originalDescription!),
    };
    for (final id in config.selfIdentifiers) {
      final needle = id.trim().toLowerCase();
      if (needle.isEmpty) continue;
      // Documents (CPF/CNPJ) can sit anywhere; names must open the
      // counterparty, so "Maria Souza" never matches "Jose Maria Souza".
      if (_document.hasMatch(needle)) {
        if (text.contains(needle)) return true;
      } else if (parties.any((p) => p.startsWith(needle))) {
        return true;
      }
    }
    return false;
  }

  static final _document = RegExp(r'^[\d.\-/ ]+$');
  static final _transferWords = RegExp(
    r'^((reembolso|estorno|devolu[cç][aã]o) (de |do |da )?)?(pix (enviado|recebido)( para| de)?|transfer[eê]ncia (enviada|recebida)( pelo pix)?|pagamento com (qr )?pix|ted (enviada|recebida)|doc (enviado|recebido))\s*',
  );
  static final _leadingDocument = RegExp(r'^[\d.\-/ ]+');

  /// Who sent or received the money, lowercase: "Transferência enviada pelo
  /// Pix|Maria Souza" and "Pix recebido de 12.345.678 MARIA LIMA" become
  /// "maria souza" and "maria lima".
  static String counterparty(String description) {
    var p = cleanTitle(description).toLowerCase();
    p = p.replaceFirst(_transferWords, '');
    p = p.replaceFirst(_leadingDocument, '');
    return p.trim();
  }

  DinzoSkipReason? skipReason(DinzoTransaction tx) {
    if (config.ignoredIds.contains(tx.id)) return DinzoSkipReason.ignoredByUser;
    // Dinzo hides it as a transfer between own accounts, but the money left
    // (or came back to) the everyday banks.
    if (brokerOf(tx) != null) return null;
    if (tx.hidden) return DinzoSkipReason.hidden;
    if (isBillPayment(tx)) return DinzoSkipReason.internalTransfer;
    if (isInvestment(tx)) return DinzoSkipReason.investment;
    if (isOutsideDailyBanks(tx) &&
        (isOwnTransfer(tx) ||
            _movesOutside.contains(tx.id) ||
            _brokerEntry.hasMatch(tx.description))) {
      return DinzoSkipReason.outsideDailyBanks;
    }
    if (tx.isInstallment && tx.installmentCurrent! > 1) {
      return DinzoSkipReason.laterInstallment;
    }
    // Dinzo hides an own-account transfer but not its refund: alone, the
    // refund would look like income. Only hiding is passed on: a refund of
    // a later installment still offsets the purchase recorded in full.
    if (_refunded[tx.id]?.hidden ?? false) return DinzoSkipReason.hidden;
    return null;
  }

  bool isInvestment(DinzoTransaction tx) {
    // A card holds no investments: "Juros" there is interest charged.
    if (accounts[tx.accountId]?.isCreditCard ?? false) return false;
    if (_investmentMove.hasMatch(tx.description)) return true;
    String? id = tx.categoryId;
    while (id != null) {
      final category = categories[id];
      if (category == null) return false;
      if (category.parentId == null) {
        return category.title.toLowerCase() == 'investimentos';
      }
      id = category.parentId;
    }
    return false;
  }

  /// The account outside the everyday banks that [tx] sent money to or got
  /// it from, when [tx] is one: then it is an aporte (or a withdrawal) of the
  /// wallet to invest.
  DinzoAccount? brokerOf(DinzoTransaction tx) => _brokerTransfers[tx.id];

  bool _isBankAccount(DinzoAccount? account) =>
      account != null && !account.isCreditCard;

  /// A bank account outside the everyday banks (a broker's): its money is
  /// invested, not money of the wallets.
  bool isOutsideAccount(String? accountId) {
    final account = accounts[accountId];
    return _isBankAccount(account) && !isDailyAccount(account!);
  }

  /// Whatever is left of it after [skipReason] was paid to someone else, or
  /// came from someone else (a Pix from the BTG Banking): a record like any
  /// other, plus the withdrawal (or aporte) that keeps the wallets as the
  /// everyday banks are ([BrokerPayment]).
  bool isOutsideDailyBanks(DinzoTransaction tx) =>
      isOutsideAccount(tx.accountId);

  /// The bank's short name ("BTG") when [accountId] is outside the everyday
  /// banks, else null.
  String? outsideBankOf(String? accountId) =>
      isOutsideAccount(accountId) ? _bankName(accounts[accountId]!) : null;

  /// Finds the transactions on a bank outside the everyday ones that Dinzo
  /// left visible but whose other side is on another own account: opposite
  /// direction, same amount, up to 3 days apart, the other side hidden or
  /// also outside the everyday banks.
  void _findMovesOutside(List<DinzoTransaction> transactions) {
    _movesOutside.clear();
    final real = transactions.where((t) => !t.projected).toList();
    for (final tx in real) {
      if (tx.hidden || !isOutsideDailyBanks(tx)) continue;
      final other = real.any(
        (t) =>
            t.accountId != tx.accountId &&
            _isBankAccount(accounts[t.accountId]) &&
            t.isDebit != tx.isDebit &&
            (t.amount - tx.amount).abs() < 0.005 &&
            DateTime.parse(t.date)
                    .difference(DateTime.parse(tx.date))
                    .inDays
                    .abs() <=
                3 &&
            !isBillPayment(t) &&
            !isInvestment(t) &&
            (t.hidden || isOwnTransfer(t) || isOutsideDailyBanks(t)),
      );
      if (other) _movesOutside.add(tx.id);
    }
  }

  /// Pairs each transfer between own accounts on an everyday bank with the
  /// other side on a bank outside them: opposite direction, same amount, up
  /// to 3 days apart (the closest), one to one. Only the everyday side
  /// becomes a record; the other one stays hidden like everything that
  /// happens inside a broker.
  void _findBrokerTransfers(List<DinzoTransaction> transactions) {
    _brokerTransfers.clear();
    if (toInvestWalletId == null) return;
    final real = transactions.where((t) => !t.projected).toList();
    final elsewhere = [
      for (final t in real)
        if (_isBankAccount(accounts[t.accountId]) &&
            !isDailyAccount(accounts[t.accountId]!))
          t,
    ];
    if (elsewhere.isEmpty) return;
    bool daily(DinzoTransaction t) =>
        _isBankAccount(accounts[t.accountId]) &&
        isDailyAccount(accounts[t.accountId]!);
    bool sameMoney(DinzoTransaction a, DinzoTransaction b) =>
        a.isDebit != b.isDebit &&
        (a.amount - b.amount).abs() < 0.005 &&
        DateTime.parse(a.date)
                .difference(DateTime.parse(b.date))
                .inDays
                .abs() <=
            3;
    final used = <String>{};
    for (final tx in real) {
      if (!daily(tx)) continue;
      if (!tx.hidden && !isOwnTransfer(tx)) continue;
      if (isBillPayment(tx) || isInvestment(tx)) continue;
      // Its other side is in another everyday bank: the money stayed.
      if (real.any(
        (t) => t.accountId != tx.accountId && daily(t) && sameMoney(t, tx),
      )) {
        continue;
      }
      DinzoTransaction? best;
      var bestGap = 4;
      for (final other in elsewhere) {
        if (used.contains(other.id) || other.isDebit == tx.isDebit) continue;
        if ((other.amount - tx.amount).abs() >= 0.005) continue;
        final gap = DateTime.parse(other.date)
            .difference(DateTime.parse(tx.date))
            .inDays
            .abs();
        if (gap >= bestGap) continue;
        best = other;
        bestGap = gap;
      }
      if (best == null) continue;
      used.add(best.id);
      _brokerTransfers[tx.id] = accounts[best.accountId]!;
    }
  }

  void _findInstallmentTotals(List<DinzoTransaction> transactions) {
    _installmentTotals.clear();
    final real = transactions.where((t) => !t.projected && t.isInstallment);
    final later = real.where((t) => t.installmentCurrent! > 1).toList();
    for (final first in real) {
      if (first.installmentCurrent != 1 || first.installmentTotal! < 2) {
        continue;
      }
      final known = <int, double>{};
      var ambiguous = false;
      for (final tx in later) {
        if (!isLaterInstallmentOf(first, tx)) continue;
        if (known.containsKey(tx.installmentCurrent)) ambiguous = true;
        known[tx.installmentCurrent!] = tx.amount;
      }
      if (known.isEmpty || ambiguous) continue;
      _installmentTotals[first.id] = installmentTotal(first, known);
    }
  }

  /// Same purchase: same card, same number of installments, same bank
  /// description, a few cents apart and about a month per installment later.
  static bool isLaterInstallmentOf(
    DinzoTransaction first,
    DinzoTransaction tx,
  ) {
    final n = first.installmentTotal!;
    if (tx.accountId != first.accountId ||
        tx.installmentTotal != n ||
        _purchaseKey(tx) != _purchaseKey(first) ||
        (tx.amount - first.amount).abs() > 0.01 * (n - 1) + 0.001) {
      return false;
    }
    final steps = tx.installmentCurrent! - 1;
    final days = DateTime.parse(tx.date)
        .difference(DateTime.parse(first.date))
        .inDays;
    return days > 0 && days >= 28 * steps - 28 && days <= 31 * steps + 20;
  }

  static String _purchaseKey(DinzoTransaction tx) =>
      (tx.originalDescription ?? tx.description)
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  /// First installment plus each later one; an installment not seen yet
  /// is taken as the closest known one before it (or the first known after).
  static double installmentTotal(
    DinzoTransaction first,
    Map<int, double> known,
  ) {
    final ks = known.keys.toList()..sort();
    var total = first.amount;
    for (var k = 2; k <= first.installmentTotal!; k++) {
      final before = ks.where((x) => x <= k);
      total += known[before.isEmpty ? ks.first : before.last]!;
    }
    return _round2(total);
  }

  void _findBillPaymentPairs(List<DinzoTransaction> transactions) {
    _billPaymentPairs.clear();
    final bankDebits = transactions
        .where(
          (t) => t.isDebit && !(accounts[t.accountId]?.isCreditCard ?? false),
        )
        .toList();
    for (final credit in transactions) {
      if (credit.isDebit ||
          !(accounts[credit.accountId]?.isCreditCard ?? false)) {
        continue;
      }
      final creditDay = DateTime.parse(credit.date);
      for (final debit in bankDebits) {
        if (_billPaymentPairs.contains(debit.id)) continue;
        if ((debit.amount - credit.amount).abs() >= 0.005) continue;
        if (DateTime.parse(debit.date).difference(creditDay).inDays.abs() > 3) {
          continue;
        }
        _billPaymentPairs
          ..add(credit.id)
          ..add(debit.id);
        break;
      }
    }
  }

  /// Pairs each refund credit with a debit on the same account, of the same
  /// amount and description, up to 7 days before it.
  void _findRefunds(List<DinzoTransaction> transactions) {
    _refunded.clear();
    final paired = <String>{};
    for (final credit in transactions) {
      if (credit.isDebit || credit.projected) continue;
      final prefix = _refund.firstMatch(credit.description);
      if (prefix == null) continue;
      final undone = _normalized(credit.description.substring(prefix.end));
      final creditDay = DateTime.parse(credit.date);
      for (final debit in transactions) {
        if (!debit.isDebit || debit.projected || paired.contains(debit.id)) {
          continue;
        }
        if (debit.accountId != credit.accountId) continue;
        if ((debit.amount - credit.amount).abs() >= 0.005) continue;
        final days = creditDay.difference(DateTime.parse(debit.date)).inDays;
        if (days < 0 || days > 7) continue;
        if (_normalized(debit.description) != undone) continue;
        paired.add(debit.id);
        _refunded[credit.id] = debit;
        break;
      }
    }
  }

  static String _normalized(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  CategoryType categoryTypeOf(DinzoTransaction tx) => brokerOf(tx) != null
      ? CategoryType.investment
      : tx.isDebit
      ? CategoryType.expense
      : CategoryType.income;

  /// Category of transactions Dinzo has not categorised yet. Categorising
  /// them in Dinzo updates the record on the next sync.
  static const String uncategorized = Category.uncategorizedName;

  /// Dinzo is the source of truth: the record gets the Dinzo category as is
  /// (a subcategory such as "Luz"; AUPP knows its parent). A merchant rule or a category mapping, when present, is an
  /// explicit override.
  String resolveCategory(DinzoTransaction tx) {
    if (brokerOf(tx) != null) {
      return tx.isDebit ? Category.investmentName : Category.withdrawalName;
    }
    final rule = config.merchantRules[merchantKey(tx.description)];
    if (rule?.categoryName != null) return rule!.categoryName!;
    final type = categoryTypeOf(tx);
    String? id = tx.categoryId;
    // Walk up the Dinzo tree so mapping a parent covers its subcategories.
    while (id != null) {
      final mapped = config.categoryMap[DinzoConfig.categoryKey(id, type)];
      if (mapped != null) return mapped;
      id = categories[id]?.parentId;
    }
    return categories[tx.categoryId]?.title ?? uncategorized;
  }

  /// Short bank name for the account's tag.
  String? bankTag(DinzoTransaction tx) {
    final account = accounts[tx.accountId];
    if (account == null) return null;
    return _bankName(account);
  }

  static String _bankName(DinzoAccount account) {
    final connector = account.connectorName;
    if (connector == null) return account.title;
    // The bank catalogue knows the connectors' spellings ("C6 Bank" → "C6",
    // "Nubank Empresas" → "Nubank PJ", "BTG Pactual" → "BTG"...).
    return KnownTag.bankIn(connector)?.name ?? connector;
  }

  static final _boleto = RegExp(
    r'boleto|pagamento de conta|pagto\.? conta|pagamento de t[ií]tulo',
  );
  static final _transfer = RegExp(r'transfer[eê]ncia|\bted\b|\bdoc\b');

  /// A card purchase as the card network writes it: merchant and city padded
  /// to fixed width, then the country ("LOJA EXEMPL*LOJA EXE  CAMPINAS   BRA").
  static final _cardDescriptor = RegExp(r'\s{2,}[a-z]{3}$');

  /// C6 Tag (tolls, parking), debited from the account: "C6TAG PEDAGIO" or
  /// the car's plate first ("ABC1D23-VIA SUL BR101...").
  static final _c6Tag = RegExp(r'^(c6tag\b|[a-z]{3}\d[a-z\d]\d{2}-)');
  static final _c6Investment = RegExp(r'\bcdb\b');

  /// How the money moved: card purchases are "Crédito"; on a bank account the
  /// description tells Pix, boleto or transfer apart, and an expense with a
  /// plain merchant name means a debit card purchase.
  String? methodTag(DinzoTransaction tx) {
    final account = accounts[tx.accountId];
    if (account == null) return null;
    if (account.isCreditCard) return 'Crédito';
    final text = '${tx.description} ${tx.originalDescription ?? ''}'
        .toLowerCase();
    if (text.contains('pix')) return 'Pix';
    if (_boleto.hasMatch(text)) return 'Boleto';
    if (_transfer.hasMatch(text)) return 'Transferência';
    final connector = account.connectorName;
    if (connector == null) return null; // manual account
    if (KnownTag.bankIn(connector)?.name == 'C6') return _c6Method(tx);
    return tx.isDebit ? 'Débito' : null;
  }

  /// C6 often sends a Pix as the other side's name alone ("CLINICA
  /// EXEMPLO", "12.345.678 MARIA SOUZA"), with no "Pix" in it. Its debit
  /// card purchases carry the card descriptor instead.
  String? _c6Method(DinzoTransaction tx) {
    final bank = (tx.originalDescription ?? tx.description)
        .trim()
        .toLowerCase();
    if (_c6Investment.hasMatch(bank)) return null;
    if (_cardDescriptor.hasMatch(bank) || _c6Tag.hasMatch(bank)) {
      return tx.isDebit ? 'Débito' : null;
    }
    return 'Pix';
  }

  List<String> syncedTagsFor(DinzoTransaction tx) => [
    bankTag(tx),
    methodTag(tx),
    // An aporte has one side only: nothing to cancel it out.
    if (isOwnTransfer(tx) && brokerOf(tx) == null) MoneyAccounts.transferTag,
  ].whereType<String>().toList()..sort();

  /// Dinzo subcategory title → its top-level category title.
  Map<String, String> get parentTitles => {
    for (final c in categories.values)
      if (c.parentId != null && categories[c.parentId] != null)
        c.title: categories[c.parentId]!.title,
  };

  int? resolveWallet(DinzoTransaction tx) => brokerOf(tx) != null
      ? toInvestWalletId
      : config.merchantRules[merchantKey(tx.description)]?.walletId ??
            defaultWalletId;

  /// "Aporte do Nubank para o BTG", "Resgate do BTG para o Nubank": the
  /// banks say more than "Pix to myself". A bank that sends only how the
  /// money moved ("Pix", "Tef") gets which way: "Pix enviado" (the bank is
  /// in the tag).
  String titleFor(DinzoTransaction tx) {
    final own = accounts[tx.accountId];
    final broker = brokerOf(tx);
    if (broker != null && own != null) {
      final here = _bankName(own);
      final there = _bankName(broker);
      return tx.isDebit
          ? 'Aporte do $here para o $there'
          : 'Resgate do $there para o $here';
    }
    final title = cleanTitle(tx.description);
    final bare = _bareMethods[title.toLowerCase()];
    if (bare == null) return title;
    final (name, feminine) = bare;
    return tx.isDebit
        ? '$name ${feminine ? 'enviada' : 'enviado'}'
        : '$name ${feminine ? 'recebida' : 'recebido'}';
  }

  /// Descriptions that say only how the money moved (the BTG sends "Pix",
  /// "Tef"), with how to name it and whether the name is feminine.
  static const _bareMethods = {
    'pix': ('Pix', false),
    'tef': ('Transferência', true),
    'ted': ('TED', true),
    'doc': ('DOC', false),
    'transferência': ('Transferência', true),
    'transferencia': ('Transferência', true),
  };

  /// The record as Dinzo alone would have it.
  DinzoSnapshot sourceFor(DinzoTransaction tx) {
    final multiplier = tx.isInstallment ? tx.installmentTotal! : 1;
    final amount = _installmentTotals[tx.id] ?? _round2(tx.amount * multiplier);
    return DinzoSnapshot(
      title: titleFor(tx),
      value: tx.isDebit ? -amount : amount,
      date: tx.date,
      categoryName: resolveCategory(tx),
      walletId: resolveWallet(tx),
      tags: syncedTagsFor(tx),
      accountId: tx.accountId,
    );
  }

  String? descriptionFor(DinzoTransaction tx) {
    final parts = <String>[];
    if (tx.isInstallment) {
      parts.add(
        'Parcelado em ${tx.installmentTotal}x de '
        '${tx.amount.toStringAsFixed(2).replaceAll('.', ',')}',
      );
    }
    if (tx.notes != null && tx.notes!.trim().isNotEmpty) {
      parts.add(tx.notes!.trim());
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// [transactions] must cover the whole [from]..[to] window: a linked
  /// record dated inside it whose transaction is missing is proposed for
  /// removal.
  DinzoSyncPlan plan({
    required List<DinzoTransaction> transactions,
    required List<Record> linkedRecords,
    required DateTime from,
    required DateTime to,
  }) {
    final startDay = day(config.startDate);
    final fromDay = day(from);
    final toDay = day(to);
    final byDinzoId = {
      for (final r in linkedRecords)
        if (r.dinzoId != null) r.dinzoId!: r,
    };
    final seen = <String>{};
    final items = <DinzoPlanItem>[];
    _findBillPaymentPairs(transactions);
    _findRefunds(transactions);
    _findInstallmentTotals(transactions);
    _findBrokerTransfers(transactions);
    _findMovesOutside(transactions);

    for (final tx in transactions) {
      if (tx.projected || tx.date.compareTo(startDay) < 0) continue;
      seen.add(tx.id);
      final existing = byDinzoId[tx.id];
      final reason = skipReason(tx);
      if (reason != null) {
        items.add(
          existing != null
              ? DinzoPlanItem(
                  kind: DinzoPlanKind.remove,
                  transaction: tx,
                  existing: existing,
                  skipReason: reason,
                  selected: !_editedLocally(existing),
                )
              : DinzoPlanItem(
                  kind: DinzoPlanKind.skipped,
                  transaction: tx,
                  skipReason: reason,
                ),
        );
        continue;
      }

      final source = sourceFor(tx);
      if (existing == null) {
        items.add(
          DinzoPlanItem(
            kind: DinzoPlanKind.create,
            transaction: tx,
            source: source,
            desired: source,
            description: descriptionFor(tx),
            categoryType: categoryTypeOf(tx),
          ),
        );
        continue;
      }
      items.add(_compare(tx, source, existing));
    }

    // Linked records whose transaction vanished from the fetched window.
    for (final record in linkedRecords) {
      if (record.dinzoId == null || seen.contains(record.dinzoId)) continue;
      final link = DinzoLink.fromJsonString(record.dinzoSnapshot);
      final date = link?.source.date ?? DinzoSnapshot.ofRecord(record).date;
      if (date.compareTo(fromDay) < 0 || date.compareTo(toDay) > 0) continue;
      items.add(
        DinzoPlanItem(
          kind: DinzoPlanKind.remove,
          existing: record,
          selected: !_editedLocally(record),
        ),
      );
    }

    _pairReissuedTransactions(items);
    return DinzoSyncPlan(items);
  }

  /// Three-way, field by field: a field changed in Dinzo (source vs stored
  /// source) takes the new Dinzo value; any other field keeps the record's
  /// current value. A field changed on both sides is a conflict.
  DinzoPlanItem _compare(
    DinzoTransaction tx,
    DinzoSnapshot source,
    Record existing,
  ) {
    final link = DinzoLink.fromJsonString(existing.dinzoSnapshot);
    final current = DinzoSnapshot.ofRecord(
      existing,
      syncedTags: link?.applied.tags ?? const [],
    );
    if (link == null) {
      // Linked without history (should not happen): adopt the record as is.
      return DinzoPlanItem(
        kind: DinzoPlanKind.update,
        transaction: tx,
        source: source,
        desired: current,
        existing: existing,
        categoryType: categoryTypeOf(tx),
      );
    }
    final old = link.source;
    final applied = link.applied;
    if (old.sameFieldsAs(source)) {
      return DinzoPlanItem(
        kind: DinzoPlanKind.unchanged,
        transaction: tx,
        source: source,
        existing: existing,
      );
    }

    var conflict = false;
    T pick<T>(
      T dinzoOld,
      T dinzoNew,
      T appliedValue,
      T currentValue,
      bool Function(T, T) same,
    ) {
      final dinzoChanged = !same(dinzoOld, dinzoNew);
      if (!dinzoChanged) return currentValue;
      final localChanged = !same(appliedValue, currentValue);
      if (localChanged && !same(currentValue, dinzoNew)) conflict = true;
      return dinzoNew;
    }

    bool eq<T>(T a, T b) => a == b;
    bool eqMoney(double a, double b) => (a - b).abs() < 0.005;

    final newCategory = source.categoryName ?? old.categoryName;
    final desired = DinzoSnapshot(
      title: pick(old.title, source.title, applied.title, current.title, eq),
      value: pick(
        old.value,
        source.value,
        applied.value,
        current.value,
        eqMoney,
      ),
      date: pick(old.date, source.date, applied.date, current.date, eq),
      categoryName: pick(
        old.categoryName,
        newCategory,
        applied.categoryName,
        current.categoryName,
        eq,
      ),
      walletId: pick(
        old.walletId,
        source.walletId,
        applied.walletId,
        current.walletId,
        eq,
      ),
      tags: pick(
        old.tags,
        source.tags,
        applied.tags,
        current.tags,
        DinzoSnapshot.sameTags,
      ),
      accountId: source.accountId,
    );
    return DinzoPlanItem(
      kind: conflict ? DinzoPlanKind.conflict : DinzoPlanKind.update,
      transaction: tx,
      source: source,
      desired: desired,
      existing: existing,
      categoryType: categoryTypeOf(tx),
      selected: !conflict,
    );
  }

  bool _editedLocally(Record record) {
    final link = DinzoLink.fromJsonString(record.dinzoSnapshot);
    if (link == null) return false;
    return !DinzoSnapshot.ofRecord(
      record,
      syncedTags: link.applied.tags,
    ).sameFieldsAs(link.applied);
  }

  /// Banks re-issue a pending card purchase under a new id once it posts.
  /// A removal plus a creation on the same account, same direction, close
  /// amount (±2%) and date (±7 days) becomes one update that rebinds the
  /// record to the new id, instead of delete + create.
  void _pairReissuedTransactions(List<DinzoPlanItem> items) {
    final removals = items
        .where((i) => i.kind == DinzoPlanKind.remove && i.transaction == null)
        .toList();
    final creations = items
        .where((i) => i.kind == DinzoPlanKind.create)
        .toList();
    for (final removal in removals) {
      final link = DinzoLink.fromJsonString(removal.existing!.dinzoSnapshot);
      final old = link?.source;
      if (old == null || old.accountId == null) continue;
      DinzoPlanItem? match;
      for (final creation in creations) {
        final s = creation.source!;
        if (s.accountId != old.accountId) continue;
        if (s.value.sign != old.value.sign) continue;
        if ((s.value - old.value).abs() > old.value.abs() * 0.02 + 0.01) {
          continue;
        }
        final days = DateTime.parse(s.date)
            .difference(DateTime.parse(old.date))
            .inDays
            .abs();
        if (days > 7) continue;
        match = creation;
        break;
      }
      if (match == null) continue;
      creations.remove(match);
      items[items.indexOf(match)] = _compare(
        match.transaction!,
        match.source!,
        removal.existing!,
      );
      items.remove(removal);
    }
  }
}
