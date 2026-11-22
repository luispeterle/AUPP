/// Portuguese title case: "PAÇOCA DE GOIABA" → "Paçoca de Goiaba".
///
/// Every word gets its first letter upper and the rest lower, except the
/// small words that join others (de, da, e, o, com…), which stay lower —
/// unless they open the title. Parts joined by "-" or "/" are treated as
/// words too ("Guarda-Chuva", "Pão de Queijo/Café"). Known acronyms and
/// dotted abbreviations stay upper ("IR Sobre Resgate · CDB - Nu Financeira
/// S.A."). A title someone wrote keeps the capitals put there on purpose
/// ("AliExpress", "NX2", "Truthear RED"); only one all in capitals, as banks
/// send them, is converted whole.
String titleCasePtBr(String text) {
  // Capitals from a bank: the whole title, or a name in it ("Pix recebido de
  // FULANO DE TAL"): a word of 4+ capital letters and no digit.
  final shouting = (!RegExp(r'\p{Ll}', unicode: true).hasMatch(text) &&
          RegExp(r'\p{L}', unicode: true).allMatches(text).length > 3) ||
      RegExp(r'(^|[\s\-/|*])\p{Lu}{4,}(?=$|[\s\-/|*.,])', unicode: true)
          .hasMatch(text);
  var first = true;
  return text.replaceAllMapped(RegExp(r'[^\s\-/]+'), (m) {
    final written = m[0]!;
    final word = written.toLowerCase();
    final bare = word.replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
        unicode: true), '');
    final keepLower = !first && _connectors.contains(bare);
    first = false;
    if (_keepsCapitals(written, shouting)) return written;
    if (keepLower) return word;
    if (_acronyms.contains(bare) || _dotted.hasMatch(bare)) {
      return word.toUpperCase();
    }
    // Capitalize the first letter, skipping leading punctuation ("(pix)");
    // words starting with a digit stay as they are ("24h").
    final i = word.indexOf(RegExp(r'[\p{L}\p{N}]', unicode: true));
    if (i < 0 || !RegExp(r'\p{L}', unicode: true).hasMatch(word[i])) {
      return word;
    }
    return word.substring(0, i) +
        word[i].toUpperCase() +
        word.substring(i + 1);
  });
}

/// Capitals put there on purpose: inside a word ("AliExpress", "iPhone"),
/// or a whole word with a digit ("NX2"), or short ("RED") when the title is
/// not a bank shouting.
bool _keepsCapitals(String word, bool shouting) {
  final letters = word.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
  if (letters.length < 2) return false;
  if (!RegExp(r'\p{Lu}', unicode: true).hasMatch(letters.substring(1))) {
    return false;
  }
  if (RegExp(r'\p{Ll}', unicode: true).hasMatch(letters)) return true;
  return RegExp(r'\d').hasMatch(word) || (!shouting && letters.length <= 3);
}

/// "s.a", "s.a.s" (trailing dot already stripped).
final _dotted = RegExp(r'^(\p{L}\.)+\p{L}$', unicode: true);

/// Acronyms that show up in bank statements and app records. Not "Pix" (a
/// name) nor "DAS" (also the connector "das").
const _acronyms = {
  'ir', 'irpf', 'iof', 'cdb', 'lci', 'lca', 'cri', 'cra', 'rdb', 'fii', 'fiis',
  'etf', 'bdr', 'cdi', 'ipca', 'mei', 'inss', 'iptu', 'ipva', 'fgts',
  'cpf', 'cnpj', 'ted', 'doc', 'pj', 'pf', 'btg', 'xp', 'bb', 'c6', 'btc',
  'xmr', 'usd', 'brl', 'okx', 'nf', 'nfe', 'obd', 'tv', 'pc', 'sus', 'cpap',
  'iptv', 'irrf', 'darf', 'dctf', 'icms', 'csll', 'pis', 'cofins', 'nfse',
  'usb', 'hdmi', 'ssd', 'gpu', 'cpu', 'ram',
};

const _connectors = {
  'a', 'à', 'ao', 'aos', 'as', 'às', 'o', 'os', 'e', 'ou', 'é',
  'de', 'da', 'do', 'das', 'dos', 'd',
  'em', 'na', 'no', 'nas', 'nos', 'num', 'numa',
  'com', 'sem', 'por', 'pra', 'pras', 'para', 'pela', 'pelo',
  'pelas', 'pelos', 'um', 'uma',
};
