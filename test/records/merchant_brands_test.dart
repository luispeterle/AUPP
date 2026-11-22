import 'dart:io';

import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/records/merchant-brands.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
  });

  Record record(String title, {String? bank, String? dinzoTitle}) => Record(
    -10,
    title,
    Category('Compras', categoryType: CategoryType.expense),
    DateTime.utc(2026, 11, 5, 12),
    description: bank == null ? null : 'Parcelado em 2x\nNo banco: $bank',
    dinzoSnapshot: dinzoTitle == null
        ? null
        : '{"src":{"t":"$dinzoTitle","v":-10,"d":"2026-11-05","c":"Compras",'
              '"w":1,"g":[],"a":"x"},"app":{"t":"$dinzoTitle","v":-10,'
              '"d":"2026-11-05","c":"Compras","w":1,"g":[],"a":"x"}}',
  );

  String? brand(Record r) => MerchantBrands.of(r)?.id;

  test('the bank text wins over an edited title', () {
    expect(brand(record('Uno no Mercy', bank: 'SHOPEE *EKEEP PRAIA GRANDE BRA')),
        'shopee');
    expect(brand(record('Amazon', bank: 'SHOPEE *X SAO PAULO BRA')), 'shopee');
    expect(brand(record('Uber', bank: 'Dl *Uberrides')), 'uber');
    expect(brand(record('Coisa', bank: 'MP *ALIEXPRESS SAO PAULO BRA')),
        'aliexpress');
    expect(brand(record('Yt', bank: 'Dl*Google Youtub')), 'youtube');
    expect(brand(record('Coisa', bank: 'EC *MELIMAIS OSASCO BRA')),
        'mercadolivre');
  });

  test('Dinzo\'s title counts as original too', () {
    expect(
      brand(record('Amazon',
          bank: 'Transferência enviada pelo Pix|FULANO DE TAL',
          dinzoTitle: 'Shopee - Cabide')),
      'shopee',
    );
  });

  test('without a brand in the original, the title decides', () {
    expect(brand(record('Amazon')), 'amazon');
    expect(brand(record('Podium', bank: 'POSTO QUALQUER ARARANGUA BRA')),
        'petrobras');
    expect(brand(record('Gasolina', bank: 'PETROBRAS PREMMIA RIO DE JANEIR BRA')),
        'petrobras');
  });

  test('a plain word is no brand', () {
    expect(brand(record('Mercado', bank: 'MERCADO PROGRESSO TURVO BRA')),
        isNull);
    expect(brand(record('Farmacia')), isNull);
    expect(brand(record('Gasolina')), isNull);
  });

  test('money between own wallets gets no brand', () {
    final aporte = Record(
      -100,
      'Aporte do Nubank',
      Category.investment(),
      DateTime.utc(2026, 11, 5, 12),
    );
    expect(brand(aporte), isNull);
    final transfer = record('Resgate do BTG para o Nubank')
      ..category = null
      ..transferWalletId = 2;
    expect(brand(transfer), isNull);
  });

  test('brands registered by an extension are matched too', () {
    MerchantBrands.register([
      MerchantBrand('loja', 'packages/inventado/x.png', RegExp('LOJA INVENTADA')),
    ]);
    expect(brand(record('Compra', bank: 'LOJA INVENTADA CIDADE BRA')), 'loja');
    expect(brand(record('Loja Inventada')), 'loja');
  });

  test('every logo is a file in a folder the app bundles', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final brand in MerchantBrands.all) {
      if (brand.asset.startsWith('packages/')) continue;
      expect(File(brand.asset).existsSync(), isTrue, reason: brand.asset);
      final dir = brand.asset.substring(0, brand.asset.lastIndexOf('/') + 1);
      expect(pubspec, contains('- $dir\n'), reason: '$dir in pubspec.yaml');
    }
  });
}
