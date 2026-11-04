#!/bin/sh
# Run after changing anything that reads or writes the data, before installing.
# 1. Code: analyzer and the tests of the data.
# 2. The real data, read-only: scripts/check-db.py.
# 3. A copy of the real data opened with the current code, checked again, with
#    the balances compared. The real files are never written.
#
# Without flutter (only the data, after editing it by hand): check-data.sh --db
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
database="$HOME/Documents/aupp/movements.db"
support="$HOME/.local/share/app.aupp"

# The logs of a failed run are worth keeping; a passing one only says so.
run_tests() {
  log=$(mktemp)
  if flutter test "$@" > "$log" 2>&1; then
    tail -1 "$log" | sed 's/\x1b\[[0-9;]*m//g'
    rm -f "$log"
  else
    tail -40 "$log" | sed 's/\x1b\[[0-9;]*m//g'
    echo "FAILED: tests (whole log in $log)"
    exit 1
  fi
}

if [ "${1:-}" != "--db" ]; then
  echo "== Analyzer"
  analysis=$(flutter analyze lib test/tools 2>&1 || true)
  printf '%s\n' "$analysis" | grep -E " error • |No issues found|issues? found" || true
  if printf '%s\n' "$analysis" | grep -q " error • "; then
    echo "FAILED: analyzer errors"
    exit 1
  fi
  echo "== Tests of the data"
  run_tests test/hybrid_sync test/change_log_test.dart test/asset_lots_test.dart test/money_model_test.dart test/crypto_analytics_test.dart test/crypto_history_test.dart
fi

[ -f "$database" ] || { echo "No real database here: nothing else to check."; exit 0; }

echo "== Real data"
python3 scripts/check-db.py --db "$database" --support "$support"

[ "${1:-}" = "--db" ] && exit 0

echo "== Copy of the real data, opened with the current code"
copy=$(mktemp -d)
trap 'rm -rf "$copy"' EXIT
mkdir "$copy/aupp"
sqlite3 "file:$database?mode=ro" ".backup '$copy/aupp/movements.db'"
cp "$support/shared_preferences.json" "$copy/"
[ -f "$support/dinzo_investments.json" ] && cp "$support/dinzo_investments.json" "$copy/"
balances() {
  sqlite3 "file:$1?mode=ro" "SELECT w.name, round(COALESCE(w.initial_amount,0)
    + COALESCE((SELECT SUM(value) FROM records r WHERE r.wallet_id=w.id),0)
    + COALESCE((SELECT SUM(ABS(COALESCE(transfer_value,value))) FROM records r WHERE r.transfer_wallet_id=w.id),0), 6)
    FROM wallets w ORDER BY w.id; SELECT COUNT(*) FROM records;"
}
schema() { sqlite3 "file:$1?mode=ro" "PRAGMA user_version;"; }
balances "$copy/aupp/movements.db" > "$copy/before.txt"
schema_before=$(schema "$copy/aupp/movements.db")
AUPP_CHECK_DIR="$copy" run_tests test/tools/real_database_check.dart
balances "$copy/aupp/movements.db" > "$copy/after.txt"
schema_after=$(schema "$copy/aupp/movements.db")
if [ "$schema_before" = "$schema_after" ]; then
  if ! diff "$copy/before.txt" "$copy/after.txt"; then
    echo "FAILED: opening with the current code changed the balances above (< before, > after)"
    exit 1
  fi
else
  # A new schema may drop wallets and records, but a wallet that stays keeps
  # its balance.
  echo "  Schema $schema_before -> $schema_after"
  changed=$(grep '|' "$copy/before.txt" | while IFS='|' read -r name value; do
    grep -F "$name|" "$copy/after.txt" | grep -qvF "|$value" && echo "$name: $value" || true
  done)
  if [ -n "$changed" ]; then
    echo "FAILED: the new schema changed these balances:"
    echo "$changed"
    grep '|' "$copy/after.txt"
    exit 1
  fi
fi
python3 scripts/check-db.py --db "$copy/aupp/movements.db" --support "$copy" --no-baseline
echo "OK: code and data"
