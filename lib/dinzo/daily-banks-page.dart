import 'package:flutter/material.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/investments/investments-page.dart' show InstitutionLogo;
import 'package:aupp/services/service-config.dart';

import 'daily-money.dart';

/// Which banks are for everyday money and which are for investing.
class DailyBanksPage extends StatefulWidget {
  const DailyBanksPage({super.key});

  @override
  State<DailyBanksPage> createState() => _DailyBanksPageState();
}

class _DailyBanksPageState extends State<DailyBanksPage> {
  List<String> _banks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snapshot = await InvestmentsCache.load();
    final tags = await ServiceConfig.database.getAllTags();
    final names = {
      for (final inv in snapshot?.investments ?? const []) Institution.of(inv).name,
      for (final tag in tags)
        if (KnownTag.of(tag)?.kind == KnownTagKind.bank) tag,
    }.toList()..sort();
    if (mounted) setState(() => _banks = names);
  }

  static Institution _institution(String bank) {
    final tag = KnownTag.of(bank);
    return tag == null
        ? Institution(bank, null, Colors.blueGrey)
        : Institution.fromTag(tag);
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
              'Conta e renda fixa nesses bancos são o seu dinheiro, repartido '
              'nas carteiras. O que está nos outros é investimento. Ações, FIIs '
              'e fundos são investimento em qualquer banco.',
            ),
          ),
          for (final bank in _banks)
            SwitchListTile(
              secondary: InstitutionLogo(institution: _institution(bank)),
              title: Text(bank),
              value: DailyBanks.isDaily(bank),
              onChanged: (daily) async {
                await DailyBanks.choose(bank, daily);
                await DailyMoney.refreshFromCache();
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    );
  }
}
