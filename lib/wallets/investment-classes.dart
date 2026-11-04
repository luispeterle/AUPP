import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:aupp/components/wallet_icon_square.dart';
import 'package:aupp/dinzo/daily-money.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/investments/asset-lots.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/benchmark.dart';
import 'package:aupp/investments/diagram.dart';
import 'package:aupp/investments/investments-analytics.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/services/crypto-quote-service.dart';

/// What is invested, by class, at the last prices. No entry moves these: they
/// come from the positions and the purchases.
class InvestmentTotals {
  /// In reais; what is abroad is in [dollars].
  final Map<DiagramClass, double> reais;
  final Map<DiagramClass, double> dollars;

  /// Reais per dollar; null while unknown.
  final double? dollar;

  const InvestmentTotals({
    this.reais = const {},
    this.dollars = const {},
    this.dollar,
  });

  /// Everything, in reais. What is abroad counts once the dollar is known.
  double get total =>
      reais.values.fold(0.0, (sum, v) => sum + v) +
      dollars.values.fold(0.0, (sum, v) => sum + v) * (dollar ?? 0);

  static Future<InvestmentTotals> load() async {
    final snapshot = await InvestmentsCache.load();
    final state = DiagramState.load();
    final overview = snapshot == null
        ? null
        : InvestmentsOverview.from(snapshot.investments, DateTime.now());
    final result = diagramAssetsFrom(
      positions: [
        for (final p in overview?.positions ?? const <Position>[])
          if (!DailyMoney.isMoney(p.inv)) p,
      ],
      coins: [
        for (final coin in AssetLots.coins.entries)
          DiagramCoin(
            coin.key,
            coin.key,
            coin.value,
            coin.value * (CryptoQuoteService.priceInMain(coin.key) ?? 0),
          ),
      ],
      state: state,
    );
    final reais = <DiagramClass, double>{};
    for (final asset in result.assets) {
      if (asset.value <= 0) continue;
      reais[asset.cls] = (reais[asset.cls] ?? 0) + asset.value;
    }
    final dollars = <DiagramClass, double>{};
    await Future.wait([
      for (final held in state.abroad.entries)
        if (held.value > 0 && state.watched[held.key] != null)
          AssetQuote.fetch(held.key, withHistory: false).then((quote) {
            if (quote == null) return;
            final cls = state.watched[held.key]!;
            dollars[cls] = (dollars[cls] ?? 0) + held.value * quote.price;
          }),
    ]);
    return InvestmentTotals(
      reais: reais,
      dollars: dollars,
      dollar: dollars.isEmpty ? null : await BenchmarkRates.dollar(),
    );
  }
}

/// The classes, in the rows of the wallets above.
class InvestmentClasses extends StatelessWidget {
  const InvestmentClasses(this.totals, {super.key, this.dividerOnTop = true});

  final InvestmentTotals totals;

  /// Under a section header the first row needs no line above it.
  final bool dividerOnTop;

  static final _looks = <DiagramClass, (IconData, Color)>{
    DiagramClass.fixedIncome: (
      FontAwesomeIcons.landmark.data,
      const Color(0xFF1E88E5),
    ),
    DiagramClass.nationalStock: (
      FontAwesomeIcons.chartLine.data,
      const Color(0xFF00897B),
    ),
    DiagramClass.intlStock: (
      FontAwesomeIcons.earthAmericas.data,
      const Color(0xFF3949AB),
    ),
    DiagramClass.fii: (
      FontAwesomeIcons.building.data,
      const Color(0xFF8E24AA),
    ),
    DiagramClass.reit: (FontAwesomeIcons.city.data, const Color(0xFFD81B60)),
    DiagramClass.crypto: (FontAwesomeIcons.coins.data, const Color(0xFFF9A825)),
  };

  Widget _amount(BuildContext context, DiagramClass cls) {
    final dollars = totals.dollars[cls];
    final value = dollars ?? totals.reais[cls]!;
    final style = TextStyle(
      fontSize: 18.0,
      fontWeight: FontWeight.normal,
      color: getAmountColor(value, Theme.of(context).brightness),
    );
    return Text(
      dollars == null
          ? getCurrencyValueString(value)
          : 'US\$ ${NumberFormat('#,##0.00', 'pt_BR').format(value)}',
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final classes = [
      for (final cls in DiagramClass.values)
        if (totals.reais.containsKey(cls) || totals.dollars.containsKey(cls))
          cls,
    ];
    if (classes.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final cls in classes) ...[
          if (dividerOnTop || cls != classes.first)
            const Divider(thickness: 0.5),
          ListTile(
            leading: WalletIconSquare(
              iconDataFromDefaultIconSet: _looks[cls]!.$1,
              backgroundColor: _looks[cls]!.$2,
            ),
            title: Text(cls.label, style: const TextStyle(fontSize: 18)),
            trailing: _amount(context, cls),
          ),
        ],
      ],
    );
  }
}
