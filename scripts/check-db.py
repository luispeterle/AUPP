#!/usr/bin/env python3
"""Checks that the database still makes sense. Read-only on the database.

Run it after anything that can touch the data (see "Data checks" in CLAUDE.md).
Exits with 1 on an error, which means stop and look. A warning is worth reading
but can be legitimate.

  check-db.py [--db PATH] [--support DIR] [--no-baseline]

--db       the database (default: ~/Documents/aupp/movements.db)
--support  the app's folder with shared_preferences.json and the Dinzo cache
           (default: ~/.local/share/app.aupp)

It keeps a baseline of the last good run in <support>/db-check/, outside the
repository, and compares against it: changes to what is already there must be
in change_log, because silent changes are how data gets lost.
"""
import argparse
import datetime as dt
import json
import math
import os
import sqlite3
import sys
from pathlib import Path

EPS = 1e-6
MONEY_EPS = 0.005
# The syncs rewrite recent records by themselves: only older ones must be stable.
SETTLED_DAYS = 45
# See CryptoQuoteService.coinIds and CategoryType.investment.
INVESTMENT_TYPE = 2


class Report:
    def __init__(self):
        self.errors, self.warnings, self.notes = [], [], []

    def error(self, text):
        self.errors.append(text)

    def warn(self, text):
        self.warnings.append(text)

    def note(self, text):
        self.notes.append(text)


def load_prefs(support):
    path = support / 'shared_preferences.json'
    if not path.exists():
        return None
    return json.loads(path.read_text())


def json_pref(prefs, key):
    raw = (prefs or {}).get(f'flutter.{key}')
    try:
        return json.loads(raw) if raw else None
    except (TypeError, ValueError):
        return None


def describe(row):
    day = dt.datetime.fromtimestamp(row['datetime'] / 1000).strftime('%d/%m/%Y')
    return f"#{row['id']} {day} {row['title']!r} {row['value']}"


def check_structure(db, report):
    result = [r[0] for r in db.execute('PRAGMA integrity_check')]
    if result != ['ok']:
        report.error(f'SQLite integrity check: {result[:3]}')
    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for table in ('records', 'wallets', 'categories', 'records_tags'):
        if table not in tables:
            report.error(f'Missing table: {table}')
    return tables


def check_records(db, report):
    wallets = {r['id']: r for r in db.execute('SELECT * FROM wallets')}
    categories = {(r['name'], r['category_type']) for r in db.execute('SELECT name, category_type FROM categories')}
    records = db.execute('SELECT * FROM records').fetchall()
    if not records:
        report.error('No records at all')
    for row in records:
        value = row['value']
        if row['datetime'] is None:
            report.error(f"#{row['id']} {row['title']!r} has no date")
            continue
        if value is None or math.isnan(value) or math.isinf(value):
            report.error(f'{describe(row)}: invalid value')
            continue
        if row['wallet_id'] not in wallets:
            report.error(f"{describe(row)}: wallet {row['wallet_id']} does not exist")
        target = row['transfer_wallet_id']
        if target is not None:
            if target not in wallets:
                report.error(f'{describe(row)}: destination wallet {target} does not exist')
            elif target == row['wallet_id']:
                report.error(f'{describe(row)}: transfer to its own wallet')
        elif row['category_name'] is not None and (row['category_name'], row['category_type']) not in categories:
            report.warn(f"{describe(row)}: category {row['category_name']!r} does not exist")
    for row in db.execute(
        'SELECT dinzo_id, COUNT(*) n FROM records WHERE dinzo_id IS NOT NULL GROUP BY dinzo_id HAVING n > 1'
    ):
        report.error(f"Same bank entry twice: {row['dinzo_id']} ({row['n']} records)")
    orphans = db.execute('SELECT COUNT(*) FROM records_tags WHERE record_id NOT IN (SELECT id FROM records)').fetchone()[0]
    if orphans:
        report.error(f'{orphans} tags point to records that do not exist')
    return wallets, records


def balances(db, wallets, until_ms=None):
    """The app's own balance: see _walletBalanceQuery in sqlite-database.dart."""
    limit = '' if until_ms is None else f' AND datetime <= {until_ms}'
    result = {}
    for wallet_id, wallet in wallets.items():
        out = db.execute(f'SELECT COALESCE(SUM(value), 0) FROM records WHERE wallet_id = ?{limit}', (wallet_id,)).fetchone()[0]
        into = db.execute(
            f'SELECT COALESCE(SUM(ABS(value)), 0) FROM records WHERE transfer_wallet_id = ?{limit}',
            (wallet_id,),
        ).fetchone()[0]
        result[wallet_id] = (wallet['initial_amount'] or 0) + out + into
    return result


def check_lots(db, prefs, report):
    lots = json_pref(prefs, 'assetLots')
    if lots is None:
        report.note('No purchases saved yet (assetLots)')
        return
    today = dt.date.today().isoformat()
    for asset, entries in lots.items():
        tied = set()
        for lot in entries:
            if not lot.get('qty'):
                report.error(f"{asset}: purchase {lot.get('day')} without a quantity")
            if str(lot.get('day', '')) > today:
                report.warn(f"{asset}: purchase dated in the future ({lot.get('day')})")
            record = lot.get('record')
            if not record:
                continue
            if record['id'] in tied:
                report.error(f"{asset}: two purchases tied to the same entry #{record['id']}")
            tied.add(record['id'])
            found = db.execute('SELECT datetime, value FROM records WHERE id = ?', (record['id'],)).fetchone()
            if found is None or found['datetime'] != record['at'] or abs(found['value'] - record['value']) > MONEY_EPS:
                report.warn(f"{asset}: purchase of {lot.get('day')} is tied to #{record['id']}, which changed (the app fixes this on opening)")
    diagram = json_pref(prefs, 'portfolioDiagram') or {}
    for ticker, quantity in (diagram.get('abroad') or {}).items():
        bought = sum(lot.get('qty', 0) for lot in lots.get(ticker, []))
        if abs(quantity - bought) > EPS:
            report.error(f'{ticker}: held abroad {quantity}, purchases add up to {bought}')


def check_money_model(db, wallets, report):
    """Wallets hold what was decided; yield and tax have no entries, and what
    follows a market has no wallet. See lib/dinzo/daily-money.dart."""
    old = db.execute(
        "SELECT COUNT(*) FROM records WHERE dinzo_id LIKE 'livre:rend:%' OR dinzo_id LIKE 'livre:ir:%' "
        "OR dinzo_id = 'livre:inicial' OR dinzo_id GLOB 'livre:[0-9][0-9][0-9][0-9]-[0-9][0-9]'"
    ).fetchone()[0]
    if old:
        report.error(f'{old} yield, tax or adjustment records: they should not exist')
    to_invest = [w for w in wallets.values() if w['kind'] == 'toInvest' and not w['is_archived']]
    if len(to_invest) > 1:
        report.error(f'{len(to_invest)} wallets to invest: there is one')
    for wallet in wallets.values():
        if wallet['kind'] == 'free':
            report.error(f"Wallet {wallet['name']!r} of the free kind: it became the wallet to invest")
    for row in db.execute(
        f'SELECT * FROM records WHERE category_type = {INVESTMENT_TYPE} AND transfer_wallet_id IS NOT NULL'
    ):
        report.error(f'{describe(row)}: an investment entry cannot be a transfer')
    for row in db.execute(f"SELECT * FROM records WHERE category_type = {INVESTMENT_TYPE} AND category_name = 'Aporte' AND value > 0"):
        report.error(f'{describe(row)}: an investment entry takes money out')


def default_wallet(wallets, current, report):
    default = next((i for i, w in wallets.items() if w['is_default']), None)
    if default is None:
        report.error('No default wallet')
        return
    report.note(
        f"{wallets[default]['name']} today: {current[default]:,.2f} "
        '(the home screen shows the end of the month: this plus what is still expected)'
    )


def fingerprint(row):
    return [row['datetime'], row['value'], row['wallet_id'], row['transfer_wallet_id']]


def compare_baseline(db, tables, records, wallets, current, support, report):
    path = support / 'db-check' / 'baseline.json'
    settled = (dt.datetime.now() - dt.timedelta(days=SETTLED_DAYS)).timestamp() * 1000
    snapshot = {
        'at': int(dt.datetime.now().timestamp() * 1000),
        'wallets': {w['name']: current[i] for i, w in wallets.items()},
        'records': len(records),
        'initial': {w['name']: w['initial_amount'] or 0 for w in wallets.values()},
        # Without a bank's id: those the sync may rewrite, and rightly.
        'settled': sorted(
            json.dumps(fingerprint(r))
            for r in records
            if r['datetime'] and r['datetime'] < settled and r['dinzo_id'] is None
        ),
    }
    if not path.exists():
        report.note('First run: baseline saved')
        return snapshot, path
    old = json.loads(path.read_text())
    for name, value in snapshot['wallets'].items():
        before = old['wallets'].get(name)
        if before is not None and abs(before - value) > MONEY_EPS:
            report.note(f'{name}: {before:,.2f} -> {value:,.2f}')
    if snapshot['records'] != old['records']:
        report.note(f"Records: {old['records']} -> {snapshot['records']}")
    for name, value in snapshot['initial'].items():
        before = old.get('initial', {}).get(name)
        if before is None or abs(before - value) <= MONEY_EPS:
            continue
        logged = 0
        if 'change_log' in tables:
            logged = db.execute(
                "SELECT COUNT(*) FROM change_log WHERE at >= ? AND target = 'wallets' AND title = ?",
                (old['at'], name),
            ).fetchone()[0]
        text = f'{name}: initial amount {before:,.2f} -> {value:,.2f}, which moves its balance on every date'
        if logged:
            report.note(text)
        else:
            report.error(f'{text}, and it is not in change_log')
    now_settled = set(snapshot['settled'])
    gone = [json.loads(key) for key in old['settled'] if key not in now_settled]
    if gone:
        logged = 0
        if 'change_log' in tables:
            logged = db.execute('SELECT COUNT(*) FROM change_log WHERE at >= ?', (old['at'],)).fetchone()[0]
        text = f'{len(gone)} records older than {SETTLED_DAYS} days changed since the last check; {logged} in change_log'
        if logged < len(gone):
            report.error(f'{text}. First ones: {gone[:3]}')
        else:
            report.note(text)
    return snapshot, path


def main():
    home = Path.home()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--db', type=Path, default=home / 'Documents/aupp/movements.db')
    parser.add_argument('--support', type=Path, default=home / '.local/share/app.aupp')
    parser.add_argument('--no-baseline', action='store_true')
    args = parser.parse_args()

    if not args.db.exists():
        print(f'ERROR: no database at {args.db}')
        return 1
    report = Report()
    db = sqlite3.connect(f'file:{args.db}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    try:
        tables = check_structure(db, report)
        if report.errors:
            raise sqlite3.DatabaseError('structure')
        wallets, records = check_records(db, report)
        now_ms = int(dt.datetime.now().timestamp() * 1000)
        current = balances(db, wallets, until_ms=now_ms)
        prefs = load_prefs(args.support)
        check_lots(db, prefs, report)
        check_money_model(db, wallets, report)
        default_wallet(wallets, current, report)
        baseline = None
        if not args.no_baseline:
            baseline = compare_baseline(db, tables, records, wallets, current, args.support, report)
    except sqlite3.DatabaseError as error:
        report.error(f'Could not read the database: {error}')
        baseline = None
    finally:
        db.close()

    for text in report.notes:
        print(f'  {text}')
    for text in report.warnings:
        print(f'WARNING: {text}')
    for text in report.errors:
        print(f'ERROR: {text}')
    if report.errors:
        print(f'FAILED: {len(report.errors)} error(s). Baseline kept. Stop and look before going on.')
        return 1
    if baseline:
        snapshot, path = baseline
        path.parent.mkdir(exist_ok=True)
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps(snapshot, ensure_ascii=False))
        os.replace(temporary, path)
    print(f'OK: {len(report.warnings)} warning(s)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
