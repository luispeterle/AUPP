// The person button: which accounts the Extrato shows, and the companies.
import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Record record(String title, Set<String> tags) =>
      Record(-10, title, null, DateTime.utc(2026, 5, 4), tags: tags);

  final rent = record('Aluguel', {'Nubank PJ', 'Boleto'});
  final market = record('Mercado', {'C6', 'Crédito'});
  final cash = record('Feira', {'Manual'});

  Future<void> start(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
  }

  test('the account is the bank tag, or none', () {
    expect(MoneyAccounts.accountOf(rent), 'Nubank PJ');
    expect(MoneyAccounts.accountOf(market), 'C6');
    expect(MoneyAccounts.accountOf(cash), MoneyAccounts.noBank);
    // Another spelling of the same bank.
    expect(
      MoneyAccounts.accountOf(record('Luz', {'Nubank Empresas'})),
      'Nubank PJ',
    );
  });

  test('nothing hidden: every record is shown', () async {
    await start({});
    final all = [rent, market, cash, null];
    expect(MoneyAccounts.filtering, isFalse);
    expect(MoneyAccounts.shown(all), same(all));
  });

  test('a hidden account leaves its records out', () async {
    await start({});
    await MoneyAccounts.setHidden(['nubank pj'], true);
    expect(MoneyAccounts.filtering, isTrue);
    expect(MoneyAccounts.shown([rent, market, cash]), [market, cash]);

    await MoneyAccounts.setHidden([MoneyAccounts.noBank, 'C6'], true);
    expect(MoneyAccounts.shown([rent, market, cash]), isEmpty);

    await MoneyAccounts.setHidden(['Nubank PJ'], false);
    expect(MoneyAccounts.shown([rent, market, cash]), [rent]);
  });

  test('until set, the business accounts make one company', () async {
    await start({});
    final companies = MoneyAccounts.companies(known: ['C6', 'Nubank PJ']);
    expect(companies.single.name, MoneyAccounts.defaultCompanyName);
    expect(companies.single.banks, ['Nubank PJ']);
    expect(MoneyAccounts.companies(known: ['C6']), isEmpty);
  });

  test('companies are kept as set, several of them', () async {
    await start({});
    await MoneyAccounts.saveCompanies([
      Company('Padaria Exemplo', ['Nubank PJ']),
      Company('Loja Exemplo', ['Inter']),
    ]);
    final companies = MoneyAccounts.companies(known: ['Nubank PJ', 'Inter']);
    expect(companies.map((c) => c.name), ['Padaria Exemplo', 'Loja Exemplo']);
    expect(MoneyAccounts.companyOf('inter', companies)?.name, 'Loja Exemplo');
    expect(MoneyAccounts.companyOf('C6', companies), isNull);
    expect(MoneyAccounts.companyOf(MoneyAccounts.noBank, companies), isNull);
  });

  test('a broken saved value falls back to the default', () async {
    await start({PreferencesKeys.companies: 'not json'});
    expect(
      MoneyAccounts.companies(known: ['Nubank PJ']).single.banks,
      ['Nubank PJ'],
    );
  });

  group('transfers between own accounts', () {
    Record move(double value, String bank, int day) => Record(
      value,
      'Luis',
      null,
      DateTime.utc(2026, 5, day, 12),
      tags: {bank, 'Pix', MoneyAccounts.transferTag},
    );

    final out = move(-900, 'Nubank PJ', 4);
    final into = move(900, 'C6', 5);
    final client = Record(1200, 'Cliente', null, DateTime.utc(2026, 5, 3),
        tags: {'Nubank PJ'});

    test('the two sides pair up, a day apart at most', () {
      final pairs = MoneyAccounts.transferPairs([out, into, client]);
      expect(pairs[out], same(into));
      expect(pairs[into], same(out));
      expect(
        MoneyAccounts.transferPairs([out, move(900, 'C6', 7)]),
        isEmpty,
      );
    });

    test('everything on: both sides cancel out and stay off', () async {
      await start({});
      expect(MoneyAccounts.shown([client, out, into]), [client]);
      expect(MoneyAccounts.withoutTransfers([client, out, into]), [client]);
    });

    test('only the company: the money leaving it shows', () async {
      await start({});
      await MoneyAccounts.setHidden(['C6', MoneyAccounts.noBank], true);
      expect(MoneyAccounts.shown([client, out, into]), [client, out]);
    });

    test('only the person: the money arriving shows', () async {
      await start({});
      await MoneyAccounts.setHidden(['Nubank PJ'], true);
      expect(MoneyAccounts.shown([client, out, into]), [into]);
    });

    test('a side without its other half always shows', () async {
      await start({});
      expect(MoneyAccounts.shown([client, out]), [client, out]);
    });
  });
}
