import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

enum KnownTagKind { bank, method, origin }

/// Tags shown as a logo or icon instead of text (fork-only): banks and
/// brokers, payment methods, and the origin tags of hand-entered records.
/// Also the single catalogue of banks used by the sync (account tags) and
/// the Investments tab (institutions).
class KnownTag {
  final String name;
  final KnownTagKind kind;

  /// Bank logo asset; null for banks without a usable logo (shown as their
  /// initial on [color]) and for methods/origins (shown as [icon]).
  final String? logo;
  final IconData? icon;
  final Color color;

  /// Small text next to the logo, e.g. "PJ" for a business account.
  final String? badge;

  /// Lowercase words that identify the bank inside an issuer or connector
  /// name ("nu financeira", "banco c6 consignado"...). Matched as whole
  /// words.
  final List<String> keywords;

  const KnownTag(
    this.name, {
    required this.kind,
    this.logo,
    this.icon,
    this.color = Colors.blueGrey,
    this.badge,
    this.keywords = const [],
  });

  static const _b = 'assets/images/banks';

  static const List<KnownTag> banks = [
    KnownTag(
      'Nubank',
      kind: KnownTagKind.bank,
      logo: '$_b/nubank.png',
      color: Color(0xFF820AD1),
      keywords: [
        'nubank',
        'nu financeira',
        'nu pagamentos',
        'nu invest',
        'nu reserva',
      ],
    ),
    KnownTag(
      'Nubank PJ',
      kind: KnownTagKind.bank,
      logo: '$_b/nubank.png',
      color: Color(0xFF820AD1),
      badge: 'PJ',
      keywords: ['nubank empresas'],
    ),
    KnownTag(
      'C6',
      kind: KnownTagKind.bank,
      logo: '$_b/c6.png',
      color: Color(0xFF242424),
      keywords: ['c6'],
    ),
    KnownTag(
      'Mercado Pago',
      kind: KnownTagKind.bank,
      logo: '$_b/mercadopago.png',
      color: Color(0xFF00B1EA),
      keywords: ['mercado pago', 'mercadopago', 'cofrinho'],
    ),
    KnownTag(
      'Itaú',
      kind: KnownTagKind.bank,
      logo: '$_b/itau.png',
      color: Color(0xFFEC7000),
      keywords: ['itau', 'itaú', 'unibanco'],
    ),
    KnownTag(
      'Bradesco',
      kind: KnownTagKind.bank,
      color: Color(0xFFCC092F),
      keywords: ['bradesco'],
    ),
    KnownTag(
      'Santander',
      kind: KnownTagKind.bank,
      logo: '$_b/santander.png',
      color: Color(0xFFEC0000),
      keywords: ['santander'],
    ),
    KnownTag(
      'Banco do Brasil',
      kind: KnownTagKind.bank,
      logo: '$_b/bb.png',
      color: Color(0xFFFCD535),
      keywords: ['banco do brasil', 'bb'],
    ),
    KnownTag(
      'Caixa',
      kind: KnownTagKind.bank,
      color: Color(0xFF005CA9),
      keywords: ['caixa economica', 'caixa econômica', 'caixa'],
    ),
    KnownTag(
      'Inter',
      kind: KnownTagKind.bank,
      logo: '$_b/inter.png',
      color: Color(0xFFFF7A00),
      keywords: ['inter', 'banco inter'],
    ),
    KnownTag(
      'BTG',
      kind: KnownTagKind.bank,
      logo: '$_b/btg.png',
      color: Color(0xFF0D2C6C),
      keywords: ['btg'],
    ),
    KnownTag(
      'XP',
      kind: KnownTagKind.bank,
      logo: '$_b/xp.png',
      color: Color(0xFF000000),
      keywords: ['xp'],
    ),
    KnownTag(
      'Rico',
      kind: KnownTagKind.bank,
      logo: '$_b/rico.png',
      color: Color(0xFFFF5A00),
      keywords: ['rico'],
    ),
    KnownTag(
      'Clear',
      kind: KnownTagKind.bank,
      logo: '$_b/clear.png',
      color: Color(0xFF0000FF),
      keywords: ['clear'],
    ),
    KnownTag(
      'AUVP',
      kind: KnownTagKind.bank,
      logo: '$_b/auvp.png',
      color: Color(0xFFC9A227),
      keywords: ['auvp'],
    ),
    KnownTag(
      'PicPay',
      kind: KnownTagKind.bank,
      logo: '$_b/picpay.png',
      color: Color(0xFF21C25E),
      keywords: ['picpay'],
    ),
    KnownTag(
      'PagBank',
      kind: KnownTagKind.bank,
      logo: '$_b/pagbank.png',
      color: Color(0xFF1BB99A),
      keywords: ['pagbank', 'pagseguro'],
    ),
    KnownTag(
      'Sicredi',
      kind: KnownTagKind.bank,
      color: Color(0xFF3FA110),
      keywords: ['sicredi'],
    ),
    KnownTag(
      'Sicoob',
      kind: KnownTagKind.bank,
      logo: '$_b/sicoob.png',
      color: Color(0xFF003641),
      keywords: ['sicoob'],
    ),
    KnownTag(
      'Banrisul',
      kind: KnownTagKind.bank,
      color: Color(0xFF00529B),
      keywords: ['banrisul'],
    ),
    KnownTag(
      'Neon',
      kind: KnownTagKind.bank,
      logo: '$_b/neon.png',
      color: Color(0xFF00E5FF),
      keywords: ['neon'],
    ),
    KnownTag(
      'Original',
      kind: KnownTagKind.bank,
      logo: '$_b/original.png',
      color: Color(0xFF00A651),
      keywords: ['banco original'],
    ),
    KnownTag(
      'Modal',
      kind: KnownTagKind.bank,
      logo: '$_b/modal.png',
      color: Color(0xFF1C1C1C),
      keywords: ['modal', 'modalmais'],
    ),
    KnownTag(
      'Avenue',
      kind: KnownTagKind.bank,
      logo: '$_b/avenue.png',
      color: Color(0xFF14213D),
      keywords: ['avenue'],
    ),
    KnownTag(
      'Toro',
      kind: KnownTagKind.bank,
      logo: '$_b/toro.png',
      color: Color(0xFFE30613),
      keywords: ['toro'],
    ),
    KnownTag(
      'Genial',
      kind: KnownTagKind.bank,
      logo: '$_b/genial.png',
      color: Color(0xFF0E1E5B),
      keywords: ['genial'],
    ),
    KnownTag(
      'Órama',
      kind: KnownTagKind.bank,
      logo: '$_b/orama.png',
      color: Color(0xFF7B2CBF),
      keywords: ['orama', 'órama'],
    ),
    KnownTag(
      'Warren',
      kind: KnownTagKind.bank,
      logo: '$_b/warren.png',
      color: Color(0xFFEE2E5D),
      keywords: ['warren'],
    ),
    KnownTag(
      'Ágora',
      kind: KnownTagKind.bank,
      color: Color(0xFFE30613),
      keywords: ['agora investimentos', 'ágora'],
    ),
    KnownTag(
      'Will Bank',
      kind: KnownTagKind.bank,
      logo: '$_b/will.png',
      color: Color(0xFFFFD500),
      keywords: ['will bank', 'willbank'],
    ),
    KnownTag(
      'Safra',
      kind: KnownTagKind.bank,
      logo: '$_b/safra.png',
      color: Color(0xFF0B2240),
      keywords: ['safra'],
    ),
    KnownTag(
      'BV',
      kind: KnownTagKind.bank,
      logo: '$_b/bv.png',
      color: Color(0xFF1F3C88),
      keywords: ['banco bv', 'bv financeira', 'votorantim'],
    ),
    KnownTag(
      'Next',
      kind: KnownTagKind.bank,
      color: Color(0xFF00FF5F),
      keywords: ['next'],
    ),
    KnownTag(
      'Banco Pan',
      kind: KnownTagKind.bank,
      logo: '$_b/pan.png',
      color: Color(0xFF00AEEF),
      keywords: ['banco pan', 'pan'],
    ),
    KnownTag(
      'Stone',
      kind: KnownTagKind.bank,
      logo: '$_b/stone.png',
      color: Color(0xFF00A868),
      keywords: ['stone'],
    ),
    KnownTag(
      'Binance',
      kind: KnownTagKind.bank,
      logo: '$_b/binance.png',
      color: Color(0xFFF3BA2F),
      keywords: ['binance'],
    ),
  ];

  static final List<KnownTag> others = [
    KnownTag(
      'Pix',
      kind: KnownTagKind.method,
      icon: FontAwesomeIcons.pix.data,
      color: const Color(0xFF32BCAD),
    ),
    const KnownTag(
      'Crédito',
      kind: KnownTagKind.method,
      icon: Icons.credit_card,
      color: Color(0xFF3949AB),
    ),
    const KnownTag(
      'Débito',
      kind: KnownTagKind.method,
      icon: Icons.payment,
      color: Color(0xFF00897B),
    ),
    KnownTag(
      'Boleto',
      kind: KnownTagKind.method,
      icon: FontAwesomeIcons.barcode.data,
      color: const Color(0xFF6D4C41),
    ),
    KnownTag(
      'Dinheiro',
      kind: KnownTagKind.method,
      icon: FontAwesomeIcons.moneyBillWave.data,
      color: const Color(0xFF2E7D32),
    ),
    const KnownTag(
      'Transferência',
      kind: KnownTagKind.method,
      icon: Icons.sync_alt,
      color: Color(0xFF546E7A),
    ),
    const KnownTag(
      'Vale alimentação',
      kind: KnownTagKind.method,
      icon: Icons.restaurant,
      color: Color(0xFFEF6C00),
    ),
    const KnownTag(
      'Manual',
      kind: KnownTagKind.origin,
      icon: Icons.edit,
      color: Color(0xFF7E57C2),
    ),
    const KnownTag(
      'Virtual',
      kind: KnownTagKind.origin,
      icon: Icons.savings,
      color: Colors.purple,
    ),
    const KnownTag(
      'Estimativa',
      kind: KnownTagKind.origin,
      icon: Icons.query_stats,
      color: Color(0xFFF9A825),
    ),
    const KnownTag(
      'Fora do orçamento',
      kind: KnownTagKind.origin,
      icon: Icons.money_off,
      color: Color(0xFF78909C),
    ),
    const KnownTag(
      'Entre contas',
      kind: KnownTagKind.origin,
      icon: Icons.swap_horiz,
      color: Color(0xFF546E7A),
    ),
    const KnownTag(
      'Oculto',
      kind: KnownTagKind.origin,
      icon: Icons.visibility_off,
      color: Color(0xFF78909C),
    ),
  ];

  static final Map<String, KnownTag> _byName = {
    for (final t in [...banks, ...others]) t.name.toLowerCase(): t,
  };

  /// Other spellings, e.g. how bank connectors name themselves.
  static const Map<String, String> _aliases = {
    'c6 bank': 'c6',
    'btg pactual': 'btg',
    'btg pactual empresas': 'btg',
    'rico investimentos': 'rico',
    'auvp capital': 'auvp',
    'nubank empresas': 'nubank pj',
    'mercadopago': 'mercado pago',
    'itau': 'itaú',
    'itaú unibanco': 'itaú',
    'banco inter': 'inter',
    'xp investimentos': 'xp',
    'caixa econômica federal': 'caixa',
    'orama': 'órama',
    'agora': 'ágora',
    'credito': 'crédito',
    'debito': 'débito',
    'transferencia': 'transferência',
    'espécie': 'dinheiro',
    'especie': 'dinheiro',
    'dinheiro vivo': 'dinheiro',
  };

  /// Names and aliases without spaces: connectors also write them together
  /// ("BTGPactual", "MercadoPago").
  static final Map<String, KnownTag> _byCompact = {
    for (final e in _byName.entries) _compact(e.key): e.value,
    for (final e in _aliases.entries)
      if (_byName[e.value] case final tag?) _compact(e.key): tag,
  };

  static String _compact(String key) => key.replaceAll(' ', '');

  static KnownTag? of(String tag) {
    final key = tag.trim().toLowerCase();
    return _byName[_aliases[key] ?? key] ?? _byCompact[_compact(key)];
  }

  /// The bank named in free text (issuer, connector, position name), if any.
  /// Exact names/aliases first, then whole-word keywords; the longest keyword
  /// wins so "nubank empresas" beats "nubank".
  static KnownTag? bankIn(String text) {
    final exact = of(text);
    if (exact != null && exact.kind == KnownTagKind.bank) return exact;
    final lower = text.toLowerCase();
    KnownTag? best;
    var bestLength = 0;
    for (final bank in banks) {
      for (final keyword in bank.keywords) {
        if (keyword.length <= bestLength) continue;
        final pattern = RegExp(
          '(^|[^a-zà-ú0-9])${RegExp.escape(keyword)}'
          r'($|[^a-zà-ú0-9])',
        );
        if (pattern.hasMatch(lower)) {
          best = bank;
          bestLength = keyword.length;
        }
      }
    }
    return best;
  }

  /// Display order: bank, then payment method, then origin, then the rest
  /// (alphabetical within each group), e.g. "C6, Crédito".
  static List<String> sortForDisplay(Iterable<String> tags) {
    int rank(String t) => switch (of(t)?.kind) {
      KnownTagKind.bank => 0,
      KnownTagKind.method => 1,
      KnownTagKind.origin => 2,
      null => 3,
    };

    return tags.toList()..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.toLowerCase().compareTo(b.toLowerCase());
    });
  }
}

/// A bank's logo in a rounded white square, or its initial on its colour.
class BankMark extends StatelessWidget {
  final KnownTag bank;
  final double size;

  const BankMark(this.bank, {Key? key, this.size = 18}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Container(
        width: size,
        height: size,
        color: bank.logo != null ? Colors.white : bank.color,
        alignment: Alignment.center,
        child: bank.logo != null
            ? Image.asset(bank.logo!, fit: BoxFit.contain)
            : Text(
                bank.name.characters.first.toUpperCase(),
                style: TextStyle(
                  color: bank.color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: size * 0.55,
                ),
              ),
      ),
    );
  }
}

/// A tag as an icon/logo when it is a [KnownTag], otherwise as text.
class TagLabel extends StatelessWidget {
  final String tag;
  final double size;
  final TextStyle? textStyle;

  const TagLabel(this.tag, {Key? key, this.size = 18, this.textStyle})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final known = KnownTag.of(tag);
    if (known == null) return Text(tag, style: textStyle);
    final Widget image = known.kind == KnownTagKind.bank
        ? BankMark(known, size: size)
        : Icon(known.icon, size: size, color: known.color);
    return Tooltip(
      message: known.name,
      child: Semantics(
        label: known.name,
        child: known.badge == null
            ? image
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  image,
                  const SizedBox(width: 3),
                  Text(
                    known.badge!,
                    style: (textStyle ?? const TextStyle()).copyWith(
                      fontSize: size * 0.6,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
