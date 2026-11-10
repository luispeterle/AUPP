import 'package:flutter/material.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/investments/investments-page.dart' show InstitutionLogo;
import 'package:aupp/services/service-config.dart';

import 'daily-money.dart';

/// What each bank holds as everyday money and what as an investment: the
/// bank's choice, and the kinds of product that go the other way.
class DailyBanksPage extends StatefulWidget {
  const DailyBanksPage({super.key});

  @override
  State<DailyBanksPage> createState() => _DailyBanksPageState();
}

class _DailyBanksPageState extends State<DailyBanksPage> {
  /// Bank → product → how much is there, the largest first.
  Map<String, Map<String, double>> _banks = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snapshot = await InvestmentsCache.load();
    final tags = await ServiceConfig.database.getAllTags();
    final held = <String, Map<String, double>>{};
    for (final inv in snapshot?.investments ?? const []) {
      if (inv.archived) continue;
      final products = held.putIfAbsent(Institution.of(inv).name, () => {});
      final product = productOf(inv);
      products[product] = (products[product] ?? 0) + inv.balance;
    }
    for (final tag in tags) {
      if (KnownTag.of(tag) case final known?
          when known.kind == KnownTagKind.bank) {
        held.putIfAbsent(known.name, () => {});
      }
    }
    final names = held.keys.toList()..sort();
    if (mounted) {
      setState(
        () => _banks = {
          for (final name in names)
            name: Map.fromEntries(
              held[name]!.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)),
            ),
        },
      );
    }
  }

  static Institution _institution(String bank) {
    final tag = KnownTag.of(bank);
    return tag == null
        ? Institution(bank, null, Colors.blueGrey)
        : Institution.fromTag(tag);
  }

  Future<void> _changed(Future<void> Function() choice) async {
    await choice();
    await DailyMoney.refreshFromCache();
    if (mounted) setState(() {});
  }

  /// "Dia a dia, menos Ações e Fundo".
  String _summary(String bank) {
    final side = DailyBanks.isDaily(bank) ? 'Dia a dia' : 'Investir';
    final against = [
      for (final p in _banks[bank]!.keys)
        if (DailyBanks.isException(bank, p)) p,
    ];
    if (against.isEmpty) return side;
    final last = against.removeLast();
    return '$side, menos '
        '${against.isEmpty ? last : '${against.join(', ')} e $last'}';
  }

  Widget _side(bool daily, ValueChanged<bool> onChanged) =>
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity(horizontal: -3, vertical: -3),
          textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        ),
        segments: const [
          ButtonSegment(value: true, label: Text('Dia a dia')),
          ButtonSegment(value: false, label: Text('Investir')),
        ],
        selected: {daily},
        onSelectionChanged: (value) => onChanged(value.single),
      );

  Widget _bank(String bank) {
    final products = _banks[bank]!;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: InstitutionLogo(institution: _institution(bank)),
        title: Text(bank),
        subtitle: Text(_summary(bank)),
        shape: const Border(),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          ListTile(
            dense: true,
            title: const Text('O banco'),
            subtitle: const Text('A conta e o que chegar'),
            trailing: _side(
              DailyBanks.isDaily(bank),
              (daily) => _changed(() => DailyBanks.choose(bank, daily)),
            ),
          ),
          for (final MapEntry(key: product, value: total) in products.entries)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              title: Text(product),
              subtitle: Text(
                DailyBanks.isException(bank, product)
                    ? '${getCurrencyValueString(total)} · escolhido por você'
                    : getCurrencyValueString(total),
              ),
              trailing: _side(
                DailyBanks.holdsProduct(bank, product),
                (daily) => _changed(
                  () => DailyBanks.chooseProduct(bank, product, daily),
                ),
              ),
            ),
          if (products.keys.any((p) => DailyBanks.isException(bank, p)))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: TextButton(
                  onPressed: () => _changed(() => DailyBanks.followBank(bank)),
                  child: const Text('Tudo como o banco'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bancos do dia a dia')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'O que é dia a dia é o seu dinheiro, repartido nas carteiras. O '
              'resto é investimento e vai para Carteira e aporte. Tudo num '
              'banco segue a escolha dele, o que chegar depois também; um '
              'produto pode ir para o outro lado. Ações e ETFs no dia a dia '
              'trazem a cotação junto: o que ela mexer entra no ajuste do mês.',
            ),
          ),
          for (final bank in _banks.keys) _bank(bank),
        ],
      ),
    );
  }
}
