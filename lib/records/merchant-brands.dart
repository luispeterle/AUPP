import 'package:aupp/dinzo/dinzo-sync-engine.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:aupp/models/record.dart';

/// A store or service whose logo the Extrato shows in place of the
/// category's icon.
class MerchantBrand {
  final String id;

  /// Square image, shown cut to a circle.
  final String asset;

  /// Matched, ignoring case, against the bank's text and the titles.
  final RegExp pattern;

  /// How the store is written in a title, to take it out when the logo
  /// already says it ([MerchantBrands.withoutBrand]); null keeps titles.
  final RegExp? name;

  MerchantBrand(this.id, this.asset, RegExp pattern, {RegExp? name})
    : pattern = RegExp(pattern.pattern, caseSensitive: false),
      name = name == null ? null : RegExp(name.pattern, caseSensitive: false);
}

/// Which brand a record is from. What the bank or Dinzo wrote decides first,
/// so renaming a Shopee purchase keeps the Shopee logo; only when that names
/// no brand does the record's own title count.
class MerchantBrands {
  static const _dir = 'assets/images/brands';
  static const _banks = 'assets/images/banks';

  /// In order: a more specific brand comes before a looser one (YouTube
  /// before Google, the stores before Mercado Pago, which also processes
  /// their payments).
  static final List<MerchantBrand> _all = [
    MerchantBrand('shopee', '$_dir/shopee.png', RegExp(r'SHOPEE|\bSHPP\b|MAREE INSTITUICAO'), name: RegExp(r'SHOPEE')),
    MerchantBrand('mercadolivre', '$_dir/mercadolivre.png', RegExp(r'MERCADO ?LIVRE|MERCADO ?LIBRE|MELIMAIS|\bMELI\+'), name: RegExp(r'MERCADO ?LIVRE|MERCADO ?LIBRE')),
    MerchantBrand('aliexpress', '$_dir/aliexpress.png', RegExp(r'ALIEXPRESS'), name: RegExp(r'ALIEXPRESS')),
    MerchantBrand('amazon', '$_dir/amazon.png', RegExp(r'AMAZON'), name: RegExp(r'AMAZON')),
    MerchantBrand('uber', '$_dir/uber.png', RegExp(r'\bUBER')),
    MerchantBrand('youtube', '$_dir/youtube.png', RegExp(r'YOUTUB|\bYT PREMIUM')),
    MerchantBrand('google', '$_dir/google.png', RegExp(r'\bGOOGLE')),
    MerchantBrand('claude', '$_dir/claude.png', RegExp(r'ANTHROPIC|\bCLAUDE\b')),
    MerchantBrand('nubank', '$_banks/nubank.png', RegExp(r'NUBANK|\bNU SEGURO|\bNU PAGAMENTOS')),
    MerchantBrand('c6', '$_banks/c6.png', RegExp(r'\bC6 ?TAG|\bC6 ?BANK')),
    MerchantBrand('wise', '$_dir/wise.png', RegExp(r'\bWISE\b')),
    MerchantBrand('okx', '$_dir/okx.png', RegExp(r'\bOKX\b')),
    MerchantBrand('tuta', '$_dir/tuta.png', RegExp(r'TUTANOTA|\bTUTA\b')),
    MerchantBrand('steam', '$_dir/steam.png', RegExp(r'\bSTEAM')),
    MerchantBrand('xbox', '$_dir/xbox.png', RegExp(r'XBOX')),
    MerchantBrand('alura', '$_dir/alura.png', RegExp(r'\bALURA\b')),
    // Podium is Petrobras' gasoline: a title saying it is enough.
    MerchantBrand('petrobras', '$_dir/petrobras.png', RegExp(r'PETROBRAS|PREMMIA|\bPODIUM\b')),
    MerchantBrand('motiva', '$_dir/motiva.png', RegExp(r'VIA ?COSTEIRA|\bVIA ?SUL\b|\bCCR\b|MOTIVA RODOVIAS')),
    MerchantBrand('cacaushow', '$_dir/cacaushow.png', RegExp(r'CACAU SHOW')),
    MerchantBrand('americanas', '$_dir/americanas.png', RegExp(r'AMERICANAS')),
    MerchantBrand('olx', '$_dir/olx.png', RegExp(r'\bOLX\b')),
    MerchantBrand('milkymoo', '$_dir/milkymoo.png', RegExp(r'MILKY ?MOO')),
    MerchantBrand('ifood', '$_dir/ifood.png', RegExp(r'IFOOD|\bIFD\*')),
    MerchantBrand('panvel', '$_dir/panvel.png', RegExp(r'PANVEL')),
    MerchantBrand('growth', '$_dir/growth.png', RegExp(r'GROWTH SUPPLEMENTS|^GROWTH\b|\|GROWTH\b')),
    MerchantBrand('brunx', '$_dir/brunx.png', RegExp(r'BRUNX')),
    MerchantBrand('receita', '$_dir/receita.png', RegExp(r'MINISTERIO DA FAZENDA|RECEITA FEDERAL')),
    MerchantBrand('mercadopago', '$_banks/mercadopago.png', RegExp(r'MERCADO ?PAGO')),
  ];

  @visibleForTesting
  static List<MerchantBrand> get all => _all;

  /// Brands from outside this repository (regional stores), checked before
  /// the ones above.
  static void register(Iterable<MerchantBrand> brands) =>
      _all.insertAll(0, brands);

  /// Null for money moving between the user's own wallets (transfers,
  /// aportes and resgates): no store there.
  static MerchantBrand? of(Record record) {
    if (record.isTransfer || record.isInvestmentFlow) return null;
    final link = DinzoLink.fromJsonString(record.dinzoSnapshot);
    for (final text in [
      _bankText(record.description),
      link?.source.title,
      record.title,
    ]) {
      if (text == null || text.isEmpty) continue;
      final brand = _brandOfText(text);
      if (brand != null) return brand;
    }
    return null;
  }

  /// [title] without the store that [bankText] names: "Shopee - Cabide"
  /// bought at "SHOPEE *REALCABIDES" is "Cabide", the logo says the rest.
  /// Unchanged when the bank names no such store, so the logo never depends
  /// on a title that lost it, or when nothing else would be left.
  static String withoutBrand(String title, String? bankText) {
    if (bankText == null) return title;
    final name = _brandOfText(bankText)?.name;
    if (name == null) return title;
    final n = name.pattern;
    final left = title
        .replaceFirst(
          RegExp('^\\s*(?:$n)\\b\\s*[-–:|*]?\\s*', caseSensitive: false),
          '',
        )
        .replaceFirst(
          RegExp('\\s*[-–]?\\s*\\b(?:$n)\\s*\$', caseSensitive: false),
          '',
        )
        .trim();
    return left.isEmpty ? title : left;
  }

  static MerchantBrand? _brandOfText(String text) {
    for (final brand in _all) {
      if (brand.pattern.hasMatch(text)) return brand;
    }
    return null;
  }

  static String? _bankText(String? description) {
    if (description == null) return null;
    for (final line in description.split('\n')) {
      if (line.startsWith(DinzoSyncEngine.bankNamePrefix)) {
        return line.substring(DinzoSyncEngine.bankNamePrefix.length);
      }
    }
    return null;
  }
}
