import 'dart:convert';

import 'package:aupp/components/known-tags.dart';
import 'package:aupp/fiscal/fiscal-data.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:flutter/foundation.dart';

/// A company of the user, the bank accounts that are its own, the names
/// and documents (razão social, CNPJ) that identify it in statements, and
/// its taxes ([FiscalData]).
class Company {
  String name;
  final List<String> banks;
  final List<String> ids;
  FiscalData fiscal;

  Company(this.name, [List<String>? banks, List<String>? ids, FiscalData? fiscal])
    : banks = banks ?? [],
      ids = ids ?? [],
      fiscal = fiscal ?? FiscalData();

  Map<String, dynamic> toJson() => {
    'nome': name,
    'contas': banks,
    'documentos': ids,
    if (fiscal.isSetUp || fiscal.activities.isNotEmpty) 'fiscal': fiscal.toJson(),
  };

  static List<String> _strings(Object? list) => [
    if (list is List)
      for (final b in list)
        if (b is String && b.trim().isNotEmpty) b,
  ];

  static Company? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['nome'];
    if (name is! String || name.trim().isEmpty) return null;
    return Company(
      name,
      _strings(json['contas']),
      _strings(json['documentos']),
      FiscalData.fromJson(json['fiscal']),
    );
  }
}

/// Where the money of each record moved, and which of those accounts the
/// Extrato shows. An account is a bank tag (the sync puts one on every
/// record it brings); records without one (cash, caixinhas, typed by hand)
/// are [noBank]. The person's own accounts are "Pessoal"; a company's are
/// the ones listed in it.
class MoneyAccounts {
  MoneyAccounts._();

  /// Key of the records with no bank tag.
  static const noBank = '';

  /// Money between the user's own accounts (PJ to PF, one bank to another).
  /// The sync keeps both sides; they show only when one side is left out.
  static const transferTag = 'Entre contas';

  static const defaultCompanyName = 'Empresa';

  /// Shown/hidden changes, for the Extrato to reload.
  static final changes = ValueNotifier<int>(0);

  /// The account of [record]: its bank tag's catalogue name, else [noBank].
  static String accountOf(Record record) {
    for (final tag in KnownTag.sortForDisplay(record.tags)) {
      final known = KnownTag.of(tag);
      if (known?.kind == KnownTagKind.bank) return known!.name;
    }
    return noBank;
  }

  static String _key(String bank) => bank.trim().toLowerCase();

  /// The user's companies. Until they are set, one [defaultCompanyName]
  /// with the business accounts of the catalogue (the "PJ" ones) among
  /// [known].
  static List<Company> companies({Iterable<String> known = const []}) {
    final saved = _savedCompanies();
    if (saved != null) return saved;
    final banks = [
      for (final bank in known)
        if (KnownTag.of(bank)?.badge == 'PJ') bank,
    ];
    return banks.isEmpty ? [] : [Company(defaultCompanyName, banks)];
  }

  static List<Company>? _savedCompanies() {
    final raw = ServiceConfig.sharedPreferences?.getString(
      PreferencesKeys.companies,
    );
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      final list = json is Map ? json['empresas'] : null;
      if (list is! List) return null;
      return [for (final c in list) ?Company.fromJson(c)];
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCompanies(List<Company> companies) async {
    await ServiceConfig.sharedPreferences?.setString(
      PreferencesKeys.companies,
      jsonEncode({'empresas': [for (final c in companies) c.toJson()]}),
    );
    changes.value++;
  }

  /// Names and documents of the person: those of [all] (every one the sync
  /// knows, [DinzoConfig.selfIdentifiers]) that no company has.
  static List<String> personalIds(List<String> all, List<Company> companies) {
    final ofCompanies = {
      for (final c in companies)
        for (final id in c.ids) _key(id),
    };
    return [
      for (final id in all)
        if (!ofCompanies.contains(_key(id))) id,
    ];
  }

  /// Every name and document, the person's first, without repeats: what
  /// the sync matches transfers between own accounts against.
  static List<String> allIds(List<String> personal, List<Company> companies) {
    final seen = <String>{};
    return [
      for (final id in [...personal, for (final c in companies) ...c.ids])
        if (seen.add(_key(id))) id.trim(),
    ];
  }

  /// The company [bank] belongs to, or null when it is a personal account.
  static Company? companyOf(String bank, List<Company> companies) {
    if (bank == noBank) return null;
    for (final company in companies) {
      if (company.banks.any((b) => _key(b) == _key(bank))) return company;
    }
    return null;
  }

  /// Accounts this device leaves out of the Extrato.
  static Set<String> get hidden => {
    for (final bank
        in ServiceConfig.sharedPreferences?.getStringList(
              PreferencesKeys.hiddenAccounts,
            ) ??
            const <String>[])
      _key(bank),
  };

  static bool isHidden(String bank) => hidden.contains(_key(bank));

  static Future<void> setHidden(Iterable<String> banks, bool hide) async {
    final next = hidden;
    for (final bank in banks) {
      hide ? next.add(_key(bank)) : next.remove(_key(bank));
    }
    await ServiceConfig.sharedPreferences?.setStringList(
      PreferencesKeys.hiddenAccounts,
      next.toList()..sort(),
    );
    changes.value++;
  }

  /// Whether some account is left out.
  static bool get filtering => hidden.isNotEmpty;

  /// The two sides of each transfer between own accounts in [records]: an
  /// outgoing one and an incoming one of the same amount, up to a day apart
  /// (the closest). Maps each side to the other.
  static Map<Record, Record> transferPairs(Iterable<Record?> records) {
    final outgoing = <Record>[];
    final incoming = <Record>[];
    for (final r in records) {
      if (r == null || !r.tags.contains(transferTag) || r.value == null) {
        continue;
      }
      (r.value! < 0 ? outgoing : incoming).add(r);
    }
    final pairs = Map<Record, Record>.identity();
    for (final out in outgoing) {
      Record? best;
      var bestGap = 2 * 24 * 60;
      for (final into in incoming) {
        if (pairs.containsKey(into)) continue;
        if ((into.value! + out.value!).abs() >= 0.005) continue;
        if (accountOf(into) == accountOf(out)) continue;
        final gap = into.utcDateTime
            .difference(out.utcDateTime)
            .inMinutes
            .abs();
        if (gap > 24 * 60 + 12 * 60 || gap >= bestGap) continue;
        best = into;
        bestGap = gap;
      }
      if (best != null) {
        pairs[out] = best;
        pairs[best] = out;
      }
    }
    return pairs;
  }

  /// [records] without the transfers between own accounts whose two sides
  /// are there: they cancel out. What the screens that show everything use.
  static List<T> withoutTransfers<T extends Record?>(List<T> records) {
    final pairs = transferPairs(records);
    if (pairs.isEmpty) return records;
    return [
      for (final r in records)
        if (r == null || !pairs.containsKey(r)) r,
    ];
  }

  /// [records] as the Extrato shows them: only the accounts switched on,
  /// and a transfer between own accounts only when its other side is left
  /// out (with both sides on, the money did not leave).
  static List<T> shown<T extends Record?>(List<T> records) {
    final out = hidden;
    final pairs = transferPairs(records);
    if (out.isEmpty && pairs.isEmpty) return records;
    bool on(Record r) => !out.contains(_key(accountOf(r)));
    return [
      for (final r in records)
        if (r == null ||
            (on(r) && !(pairs.containsKey(r) && on(pairs[r]!))))
          r,
    ];
  }
}
