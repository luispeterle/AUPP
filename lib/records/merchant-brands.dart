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

  MerchantBrand(this.id, this.asset, RegExp pattern)
    : pattern = RegExp(pattern.pattern, caseSensitive: false);
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
    MerchantBrand('shopee', '$_dir/shopee.png', RegExp(r'SHOPEE|\bSHPP\b|MAREE INSTITUICAO')),
    MerchantBrand('mercadolivre', '$_dir/mercadolivre.png', RegExp(r'MERCADO ?LIVRE|MERCADO ?LIBRE|MELIMAIS|\bMELI\+')),
    MerchantBrand('aliexpress', '$_dir/aliexpress.png', RegExp(r'ALIEXPRESS')),
    MerchantBrand('amazon', '$_dir/amazon.png', RegExp(r'AMAZON')),
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
      for (final brand in _all) {
        if (brand.pattern.hasMatch(text)) return brand;
      }
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
