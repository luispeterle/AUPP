import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/b3-market.dart';
import 'package:aupp/investments/cvm-statements.dart';
import 'package:aupp/investments/cvm-store.dart';
import 'package:aupp/investments/fundamentals.dart';
import 'package:aupp/investments/home-listing.dart';
import 'package:aupp/investments/sec-data.dart';

/// A company abroad as Análise shows it.
class ForeignAnalysis {
  final Fundamentals fundamentals;
  final List<CvmNotice> notices;

  /// The price used, per ordinary share; null when none was found.
  final SharePrice? price;

  /// Reais per unit of the statements' currency (PTAX), when known.
  final double? brlPerUnit;

  const ForeignAnalysis(
    this.fundamentals,
    this.notices,
    this.price,
    this.brlPerUnit,
  );

  /// An annual report the SEC received for a later year than the numbers it
  /// already gives: its structured data comes some months after the filing.
  /// Indicators against today's price are then off.
  DateTime? get newerAnnualReport {
    final end = fundamentals.company.ttmEnd;
    if (end == null) return null;
    for (final n in notices) {
      if (n.category == 'Relatório anual' &&
          n.date.difference(end).inDays > 400) {
        return n.date;
      }
    }
    return null;
  }
}

/// Where the numbers of any ticker come from: the B3's from the CVM at
/// brapi's list prices, the rest from the SEC at its home price.
class AnalysisSource {
  static final _foreign = <String, ForeignAnalysis>{};
  static final _pending = <String, Future<ForeignAnalysis?>>{};

  /// A ticker the SEC gave nothing for, and when: answered as such for a
  /// while (Comparar asks again for what is not loaded), then asked again
  /// (the SEC may just not have answered).
  static final _failedAt = <String, DateTime>{};
  static const _retryAfter = Duration(minutes: 1);

  static bool _failedLately(String ticker) {
    final at = _failedAt[ticker];
    return at != null && DateTime.now().difference(at) < _retryAfter;
  }

  static void resetForTests() {
    _foreign.clear();
    _pending.clear();
    _failedAt.clear();
  }

  /// Ready now: a B3 ticker, or one abroad already loaded.
  static Fundamentals? now(String ticker) {
    if (isB3Ticker(ticker)) {
      final company = CvmStore.instance.byTicker(ticker);
      return company == null
          ? null
          : Fundamentals(company, ticker, B3Market.instance.prices);
    }
    return _foreign[ticker]?.fundamentals;
  }

  static bool loaded(String ticker) =>
      isB3Ticker(ticker) ||
      _foreign.containsKey(ticker) ||
      _failedLately(ticker);

  static ForeignAnalysis? cached(String ticker) => _foreign[ticker];

  /// Null when the SEC has no statements of it (a stock only abroad, an ETF).
  static Future<ForeignAnalysis?> foreign(String ticker) {
    if (_foreign.containsKey(ticker)) return Future.value(_foreign[ticker]);
    if (_failedLately(ticker)) return Future.value(null);
    // A block: an arrow would hand back the pending future, which then
    // waits for itself.
    return _pending[ticker] ??= _load(ticker).whenComplete(() {
      _pending.remove(ticker);
    });
  }

  static Future<ForeignAnalysis?> _load(String ticker) async {
    final loaded = await SecStore.instance.load(ticker);
    if (loaded == null) {
      _failedAt[ticker] = DateTime.now();
      return null;
    }
    final (company, notices) = loaded;
    final price = await HomeListing.priceFor(company, ticker);
    final fx = await Fx.brlPer(company.currency);
    return _foreign[ticker] = ForeignAnalysis(
      Fundamentals.priced(company, ticker, price?.price),
      notices,
      price,
      fx,
    );
  }
}
