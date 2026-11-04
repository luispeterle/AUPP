import 'us-catalog.dart';

/// Tickers abroad ([usCatalog]) for what is being typed: by ticker or by
/// name, and close enough to forgive a typo ("nvdea" → NVDA, NVIDIA). Best
/// first.
List<String> searchAbroad(String query, {int limit = 8}) {
  final q = _plain(query);
  if (q.isEmpty) return const [];
  final scored = <(String, int)>[];
  for (final entry in usCatalog.entries) {
    final score = _score(q, _plain(entry.key), _plain(entry.value.$1));
    if (score != null) scored.add((entry.key, score));
  }
  scored.sort((a, b) {
    final byScore = a.$2.compareTo(b.$2);
    return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
  });
  return [for (final (ticker, _) in scored.take(limit)) ticker];
}

/// Lower is better; null is no match.
int? _score(String q, String ticker, String name) {
  if (ticker == q) return 0;
  if (ticker.startsWith(q)) return 1;
  final words = name.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.any((w) => w.startsWith(q))) return 2;
  if (name.replaceAll(' ', '').contains(q.replaceAll(' ', ''))) return 3;
  // A typo: a few letters off the ticker or a word of the name.
  if (q.length < 3) return null;
  final allowed = q.length <= 4 ? 1 : 2;
  var best = _distance(q, ticker);
  for (final w in words) {
    final d = _distance(q, w.length > q.length + 1 ? w.substring(0, q.length + 1) : w);
    if (d < best) best = d;
  }
  return best <= allowed ? 4 + best : null;
}

String _plain(String text) {
  const accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', 'í': 'i',
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ç': 'c',
  };
  final lower = text.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    final c = accents[char] ?? char;
    buffer.write(RegExp(r'[a-z0-9 ]').hasMatch(c) ? c : ' ');
  }
  return buffer.toString().replaceAll(RegExp(r' +'), ' ').trim();
}

/// Edits (insert, delete, change, swap of two letters) from [a] to [b].
int _distance(String a, String b) {
  final rows = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    rows[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    rows[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = [
        rows[i - 1][j] + 1,
        rows[i][j - 1] + 1,
        rows[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          rows[i - 2][j - 2] + 1 < best) {
        best = rows[i - 2][j - 2] + 1;
      }
      rows[i][j] = best;
    }
  }
  return rows[a.length][b.length];
}
