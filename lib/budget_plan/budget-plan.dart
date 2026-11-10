import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/total-wallets.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// One slice of the month's income (fork-only, replaces the upstream
/// budgets since 2026-10-13). Goals (Liberdade Financeira, Custos Fixos,
/// Metas, Conhecimento) are amounts to reach each month; Conforto and
/// Prazeres are limits that must not be passed (user's choice).
class BudgetGroup {
  final String id;
  final String name;
  final Color color;
  final IconData icon;
  final int defaultPercent;
  final bool isGoal;

  const BudgetGroup(
    this.id,
    this.name,
    this.color,
    this.icon,
    this.defaultPercent, {
    this.isGoal = false,
  });
}

const budgetGroups = <BudgetGroup>[
  BudgetGroup(
    'liberdade',
    'Liberdade Financeira',
    Color(0xFF7B6CF6),
    Icons.rocket_launch,
    25,
    isGoal: true,
  ),
  BudgetGroup(
    'fixos',
    'Custos Fixos',
    Color(0xFF1E88FF),
    Icons.home,
    30,
    isGoal: true,
  ),
  BudgetGroup('conforto', 'Conforto', Color(0xFFFF7EB3), Icons.weekend, 15),
  BudgetGroup(
    'metas',
    'Metas',
    Color(0xFF9C27B0),
    Icons.flag,
    15,
    isGoal: true,
  ),
  BudgetGroup('prazeres', 'Prazeres', Color(0xFFFF7A00), Icons.celebration, 10),
  BudgetGroup(
    'conhecimento',
    'Conhecimento',
    Color(0xFFFFC400),
    Icons.school,
    5,
    isGoal: true,
  ),
];

BudgetGroup? budgetGroupById(String? id) {
  for (final g in budgetGroups) {
    if (g.id == id) return g;
  }
  return null;
}

/// Assignment meaning "deliberately not counted" (no alert).
const String outOfBudget = 'fora';

/// Tag of a record left out of the budget on purpose (Editar item → "Não
/// considerar no orçamento"): neither income for the 100% nor spending in a
/// group. E.g. something bought for someone who paid it back by Pix.
const String outOfBudgetTag = 'Fora do orçamento';

/// The user's split: a percentage per group and which expense categories
/// and wallets feed each group. Categories are keyed by name (expense type
/// only) and wallets by name, so both survive a backup restore (wallet ids
/// change on restore). [incomeOut]: income categories that are not the
/// month's income (e.g. a loan): they stay out of the 100%.
class BudgetPlan {
  final Map<String, int> percents;
  final Map<String, String> categories;
  final Map<String, String> wallets;
  final Set<String> incomeOut;

  BudgetPlan({
    Map<String, int>? percents,
    Map<String, String>? categories,
    Map<String, String>? wallets,
    Set<String>? incomeOut,
  }) : percents = percents ??
           {for (final g in budgetGroups) g.id: g.defaultPercent},
       categories = categories ?? {},
       wallets = wallets ?? {},
       incomeOut = incomeOut ?? {};

  /// The saved plan (Configurações → Orçamento), or the default one.
  static BudgetPlan get saved =>
      decode(
        ServiceConfig.sharedPreferences?.getString(PreferencesKeys.budgetPlan),
      ) ??
      BudgetPlan();

  /// Group of money set aside in investments (vs. goals like the caixinhas).
  static const investedGroup = 'liberdade';

  /// Whether money moved to wallet [name] is invested: its group is
  /// Liberdade Financeira (else it's set aside for a goal).
  bool isInvestmentWallet(String name) =>
      groupOfWallet(name) == investedGroup;

  /// Whether income in category [name] is part of the 100%.
  bool countsAsIncome(String? name) => !incomeOut.contains(name);

  int percentOf(String groupId) => percents[groupId] ?? 0;

  int get totalPercent =>
      budgetGroups.fold(0, (t, g) => t + percentOf(g.id));

  /// Group id, [outOfBudget], or null when not assigned yet.
  String? groupOfCategory(String? name) =>
      name == null ? null : categories[name];

  String? groupOfWallet(String name) => wallets[walletKey(name)];

  static String walletKey(String name) => name.trim();

  BudgetPlan copy() => BudgetPlan(
    percents: Map.of(percents),
    categories: Map.of(categories),
    wallets: Map.of(wallets),
    incomeOut: Set.of(incomeOut),
  );

  Map<String, dynamic> toJson() => {
    'percents': percents,
    'categories': categories,
    'wallets': wallets,
    'incomeOut': incomeOut.toList()..sort(),
  };

  String encode() => jsonEncode(toJson());

  static BudgetPlan? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      Map<String, T> typed<T>(Object? v) => {
        for (final e in ((v as Map?) ?? const {}).entries)
          if (e.value is T) e.key as String: e.value as T,
      };
      return BudgetPlan(
        percents: {
          for (final g in budgetGroups) g.id: 0,
          ...typed<int>(map['percents']),
        },
        categories: typed<String>(map['categories']),
        wallets: typed<String>(map['wallets']),
        incomeOut: {
          for (final n in (map['incomeOut'] as List?) ?? const [])
            if (n is String) n,
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// Wallets whose money is the month's income: the spending wallets
  /// ([TotalWallets], the Extrato's "Total"), same as the Início's "O mês".
  static bool isBaseWallet(Wallet w, int? defaultWalletId) =>
      TotalWallets.includes(w, defaultWalletId);

  /// Expense categories still without a group (new ones show up here).
  List<Category> unassignedCategories(Iterable<Category> all) => [
    for (final c in all)
      if (c.categoryType == CategoryType.expense &&
          !c.isArchived &&
          c.name != null &&
          !categories.containsKey(c.name))
        c,
  ];

  /// Wallets (other than the base ones) still without a group.
  List<Wallet> unassignedWallets(Iterable<Wallet> all, int? defaultWalletId) =>
      [
        for (final w in all)
          if (!w.isArchived &&
              !isBaseWallet(w, defaultWalletId) &&
              !wallets.containsKey(walletKey(w.name)))
            w,
      ];

  /// Fills in a default for every category and wallet the user has today.
  /// Only names not assigned yet are touched. Returns whether anything was
  /// assigned.
  bool assignDefaults(
    Iterable<Category> allCategories,
    Iterable<Wallet> allWallets,
    int? defaultWalletId,
  ) {
    var changed = false;
    for (final c in allCategories) {
      if (c.categoryType != CategoryType.expense || c.name == null) continue;
      if (categories.containsKey(c.name)) continue;
      final group = defaultGroupForCategory(c.name!, c.parentName);
      if (group != null) {
        categories[c.name!] = group;
        changed = true;
      }
    }
    for (final w in allWallets) {
      if (isBaseWallet(w, defaultWalletId)) continue;
      final key = walletKey(w.name);
      if (wallets.containsKey(key)) continue;
      final group = defaultGroupForWallet(w);
      if (group != null) {
        wallets[key] = group;
        changed = true;
      }
    }
    return changed;
  }

  // ------------------------------------------------------------- defaults

  static const _categoryDefaults = <String, String>{
    // Custos Fixos
    'Moradia': 'fixos',
    'Aluguel/Prestação': 'fixos',
    'Condomínio': 'fixos',
    'Gás': 'fixos',
    'IPTU': 'fixos',
    'Internet': 'fixos',
    'Luz': 'fixos',
    'Água': 'fixos',
    'Seguro Residencial': 'fixos',
    'Supermercado': 'fixos',
    'Assinaturas/Serviços': 'fixos',
    'Telefone/Celular': 'fixos',
    'Impostos/Taxas': 'fixos',
    'Anuidade Cartão': 'fixos',
    'Imposto de Renda': 'fixos',
    'Tarifa Bancária': 'fixos',
    'Tributos': 'fixos',
    'Dívidas/Empréstimos': 'fixos',
    'Cartão de Crédito': 'fixos',
    'Cheque Especial': 'fixos',
    'Consórcio': 'fixos',
    'Empréstimo': 'fixos',
    'Empréstimo Consignado': 'fixos',
    'Encargos': 'fixos',
    'Financiamento': 'fixos',
    'Renegociação': 'fixos',
    'Saúde': 'fixos',
    'Consultas': 'fixos',
    'Dentista': 'fixos',
    'Exames': 'fixos',
    'Farmácia': 'fixos',
    'Plano Odontológico': 'fixos',
    'Plano de Saúde': 'fixos',
    'Seguro de Vida': 'fixos',
    'Transporte': 'fixos',
    'Combustível': 'fixos',
    'Estacionamento': 'fixos',
    'IPVA': 'fixos',
    'Licenciamento': 'fixos',
    'Manutenção': 'fixos',
    'Multa': 'fixos',
    'Pedágio': 'fixos',
    'Prestação': 'fixos',
    'Seguro do Carro': 'fixos',
    'Transporte Público': 'fixos',
    'Pets': 'fixos',
    'Alimentação Pet': 'fixos',
    'Medicamentos': 'fixos',
    'Veterinário': 'fixos',
    'Higiene Pessoal': 'fixos',
    // Conforto
    'Alimentação': 'conforto',
    'Cafeteria': 'conforto',
    'Delivery': 'conforto',
    'Padaria': 'conforto',
    'Cuidado Pessoal': 'conforto',
    'Cabeleireiro/Barbeiro': 'conforto',
    'Diarista': 'conforto',
    'Manicure': 'conforto',
    'Maquiagem': 'conforto',
    'Eletrodomésticos': 'conforto',
    'Móveis': 'conforto',
    'Reformas': 'conforto',
    'Vestuário': 'conforto',
    'Acessórios': 'conforto',
    'Calçados': 'conforto',
    'Roupas': 'conforto',
    'Compras': 'conforto',
    'Aplicativos': 'conforto',
    'Streamings': 'conforto',
    'Televisão': 'conforto',
    'Taxi/Uber': 'conforto',
    'Lavação': 'conforto',
    'Acessórios Pet': 'conforto',
    'Banho/Tosa': 'conforto',
    'Academia': 'conforto',
    'Outros': 'conforto',
    // Prazeres
    'Restaurante': 'prazeres',
    'Lazer/Hobbies': 'prazeres',
    'Bares': 'prazeres',
    'Cinema': 'prazeres',
    'Esportes': 'prazeres',
    'Parques': 'prazeres',
    'Shows e Eventos': 'prazeres',
    'Teatro': 'prazeres',
    'Viagens': 'prazeres',
    'Hotel': 'prazeres',
    'Passagem': 'prazeres',
    'Passeio': 'prazeres',
    'Jogos': 'prazeres',
    'Presentes/Doações': 'prazeres',
    'Transferência': 'prazeres',
    // Conhecimento
    'Educação': 'conhecimento',
    'Cursos': 'conhecimento',
    'Escola': 'conhecimento',
    'Faculdade': 'conhecimento',
    'Materiais e Livros': 'conhecimento',
    // Liberdade Financeira
    'Investimentos': 'liberdade',
    // Not real spending: still waiting for a category in Dinzo.
    'Sem categoria': outOfBudget,
  };

  static String? defaultGroupForCategory(String name, String? parentName) {
    final direct = _categoryDefaults[name];
    if (direct != null) return direct;
    final lower = name.toLowerCase();
    if (lower.contains('invest') || lower.contains('crypto') ||
        lower.contains('cripto')) {
      return 'liberdade';
    }
    return null;
  }

  /// Caixinhas (savings goals) are Metas; money waiting to be invested is
  /// Liberdade Financeira (user's choice).
  static String? defaultGroupForWallet(Wallet w) {
    final name = w.name.trim().toLowerCase();
    if (w.isInvestmentReserve) return 'liberdade';
    if (w.isEmergencyReserve || w.isOpportunityReserve) return 'metas';
    if (name.startsWith('caixinha') || name.contains('reserva')) {
      return 'metas';
    }
    return null;
  }
}

/// How the month is going against a [BudgetPlan].
class BudgetPlanUsage {
  /// Income already received in the base wallets this month.
  final double realIncome;

  /// Income the estimates (recurrences tagged "Estimativa") expect for the
  /// whole month, already received or not.
  final double estimatedIncome;

  /// Signed amount per group id: spending, or money put aside for the
  /// saving groups (money taken back out of a caixinha subtracts).
  final Map<String, double> used;

  /// Deliberately not counted ([outOfBudget]).
  final double outside;

  /// Counted nowhere because the category/wallet has no group yet.
  final double unassigned;

  /// The records behind [used], per group id, for the statistics screen.
  /// Expenses are the records themselves (matched by their own category,
  /// never the parent's); transfers become view-only expense copies whose
  /// category is the other wallet (out of the base = negative, back in =
  /// positive). Never saved.
  final Map<String, List<Record>> recordsByGroup;

  BudgetPlanUsage({
    required this.realIncome,
    required this.estimatedIncome,
    required this.used,
    required this.outside,
    required this.unassigned,
    this.recordsByGroup = const {},
  });

  List<Record> recordsOf(String groupId) => recordsByGroup[groupId] ?? [];

  /// The 100%: what came in, or what the estimates expect while the salary
  /// hasn't arrived yet.
  double get base => max(realIncome, estimatedIncome);

  bool get baseIsEstimate => estimatedIncome > realIncome;

  double usedOf(String groupId) => used[groupId] ?? 0;

  double allowanceOf(BudgetPlan plan, String groupId) =>
      base * plan.percentOf(groupId) / 100;

  /// 0..∞ (1 = 100% of the group's share).
  double ratioOf(BudgetPlan plan, String groupId) {
    final allowance = allowanceOf(plan, groupId);
    if (allowance <= 0) return 0;
    return usedOf(groupId) / allowance;
  }

  /// Usage over several months ([compute] of each): every month keeps its
  /// own 100% (received income, or the estimates while the salary hasn't
  /// arrived), and the period's 100% is their sum.
  static BudgetPlanUsage combine(List<BudgetPlanUsage> months) {
    final used = <String, double>{};
    final recordsByGroup = <String, List<Record>>{};
    var real = 0.0, base = 0.0, outside = 0.0, unassigned = 0.0;
    for (final m in months) {
      real += m.realIncome;
      base += m.base;
      outside += m.outside;
      unassigned += m.unassigned;
      m.used.forEach((g, v) => used[g] = (used[g] ?? 0) + v);
      m.recordsByGroup.forEach((g, v) => (recordsByGroup[g] ??= []).addAll(v));
    }
    return BudgetPlanUsage(
      realIncome: real,
      estimatedIncome: base,
      used: used,
      outside: outside,
      unassigned: unassigned,
      recordsByGroup: recordsByGroup,
    );
  }

  /// Month usage of [records] (any order, any month: filtered here), only
  /// between [from] and [to] when given.
  ///
  /// Expenses in the base wallets go to their category's group. Transfers
  /// from a base wallet to another wallet go to that wallet's group, and
  /// back the other way subtract from it. Transfers between base wallets
  /// and records only in other wallets don't count.
  static BudgetPlanUsage compute({
    required BudgetPlan plan,
    required Iterable<Record> records,
    required Map<int, Wallet> walletsById,
    required int? defaultWalletId,
    required DateTime month,
    required DateTime now,
    double estimatedIncome = 0,
    DateTime? from,
    DateTime? to,
  }) {
    bool isBase(int? walletId) {
      // Legacy records without a wallet belong to the default one.
      if (walletId == null) return true;
      final w = walletsById[walletId];
      return w != null && BudgetPlan.isBaseWallet(w, defaultWalletId);
    }

    final used = <String, double>{};
    final recordsByGroup = <String, List<Record>>{};
    var income = 0.0;
    var outside = 0.0;
    var unassigned = 0.0;
    void add(String? group, double amount, Record record) {
      if (group == null) {
        unassigned += amount;
      } else if (group == outOfBudget) {
        outside += amount;
      } else {
        used[group] = (used[group] ?? 0) + amount;
        (recordsByGroup[group] ??= []).add(record);
      }
    }

    // Purchases by dinzo_id, for the parts paid with a caixinha.
    final purchases = <String, Record>{
      for (final r in records)
        if (r.dinzoId != null && !r.isTransfer) r.dinzoId!: r,
    };

    for (final r in records) {
      final d = r.dateTime;
      // Upcoming occurrences of recurrences (never stored, see
      // [RecurrentRecordService]) count ahead of their day; stored records
      // only once they happened.
      final estimate = r.tags.contains(DinzoSyncService.estimateTag);
      if (d.year != month.year ||
          d.month != month.month ||
          (d.isAfter(now) && !r.isFutureRecord)) {
        continue;
      }
      if ((from != null && d.isBefore(from)) || (to != null && d.isAfter(to))) {
        continue;
      }
      final value = r.value;
      if (value == null) continue;
      // A refund and its expense: the money came back.
      if (r.isRefundPair) continue;
      if (r.tags.contains(outOfBudgetTag)) {
        if (!r.isTransfer &&
            isBase(r.walletId) &&
            r.category?.categoryType == CategoryType.expense) {
          outside -= value;
        }
        continue;
      }
      // Part of a purchase paid with a caixinha: not spent from this month's
      // income, so it comes off the purchase's group (not off Metas).
      final purchase = purchases[r.splitParentDinzoId];
      if (r.isTransfer &&
          purchase != null &&
          isBase(purchase.walletId) &&
          isBase(r.transferWalletId) &&
          !isBase(r.walletId)) {
        final amount = (r.transferValue ?? value).abs();
        add(
          plan.groupOfCategory(purchase.category?.name),
          -amount,
          _splitAsRefund(r, purchase, amount),
        );
        continue;
      }
      if (r.isTransfer) {
        final fromBase = isBase(r.walletId);
        final toBase = isBase(r.transferWalletId);
        if (fromBase == toBase) continue;
        final other = walletsById[fromBase ? r.transferWalletId : r.walletId];
        final group = other == null ? null : plan.groupOfWallet(other.name);
        final amount = fromBase
            ? value.abs()
            : (r.transferValue ?? value).abs();
        add(
          group,
          fromBase ? amount : -amount,
          _transferAsExpense(r, other, fromBase ? -amount : amount),
        );
        continue;
      }
      if (!isBase(r.walletId)) continue;
      if (r.isInvestmentFlow) {
        // From a wallet set aside, it already counted when it went there; a
        // withdrawal (BrokerPayment) lowers it.
        add(BudgetPlan.investedGroup, -value, r);
      } else if (r.category?.categoryType == CategoryType.income) {
        // Estimated income is already in [estimatedIncome].
        if (!estimate && plan.countsAsIncome(r.category?.name)) {
          income += value;
        }
      } else if (r.category?.categoryType == CategoryType.expense) {
        add(plan.groupOfCategory(r.category?.name), -value, r);
      }
    }
    return BudgetPlanUsage(
      realIncome: income,
      estimatedIncome: estimatedIncome,
      used: used,
      outside: outside,
      unassigned: unassigned,
      recordsByGroup: recordsByGroup,
    );
  }

  /// View-only copy of a caixinha's part of [purchase]: a refund in the
  /// purchase's category, so the statistics net it from the purchase.
  static Record _splitAsRefund(Record part, Record purchase, double amount) =>
      Record(
        amount,
        part.title,
        purchase.category,
        part.utcDateTime,
        id: part.id,
        timeZoneName: part.timeZoneName,
        walletId: part.walletId,
        tags: part.tags,
        dinzoId: part.dinzoId,
      );

  /// View-only copy of a transfer as an expense of the "category" [wallet],
  /// keeping the id so opening it loads the real transfer.
  static Record _transferAsExpense(Record r, Wallet? wallet, double value) =>
      Record(
        value,
        r.title,
        Category(
          wallet?.name ?? 'Carteira',
          categoryType: CategoryType.expense,
          color: wallet?.color,
          iconCodePoint: wallet?.iconCodePoint,
          iconEmoji: wallet?.iconEmoji,
        ),
        r.utcDateTime,
        id: r.id,
        description: r.description,
        timeZoneName: r.timeZoneName,
        walletId: r.walletId,
        tags: r.tags,
        dinzoId: r.dinzoId,
      );
}
