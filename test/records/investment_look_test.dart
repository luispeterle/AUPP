import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/records/investment-look.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Record aporte(String title, {String category = Category.investmentName}) =>
      Record(
        -12.3,
        title,
        Category(category, categoryType: CategoryType.investment),
        DateTime.utc(2026, 11, 5, 12),
      );

  test("an order named by its ticker shows the company's logo", () {
    expect(InvestmentLook.logoOf(aporte('BBAS3 X 1')), isNotNull);
    expect(
      InvestmentLook.logoOf(aporte('BBAS3 X 1')),
      InvestmentLook.logoOf(aporte('BBAS3 X 100')),
    );
    // A sale too, and the ticker further in the title.
    expect(
      InvestmentLook.logoOf(
        aporte('Compra de GOLD11 no Rico', category: Category.withdrawalName),
      ),
      isNotNull,
    );
  });

  test("a Tesouro shows Tesouro Direto's logo", () {
    expect(
      InvestmentLook.logoOf(aporte('Tesouro IPCA+ 2032')),
      'assets/images/brands/tesouro.png',
    );
    expect(
      InvestmentLook.logoOf(aporte('Compra de Tesouro no BTG')),
      'assets/images/brands/tesouro.png',
    );
  });

  test('nothing for an aporte without a ticker or for other records', () {
    expect(InvestmentLook.logoOf(aporte('Aporte do Nubank para o BTG')), isNull);
    expect(InvestmentLook.logoOf(aporte('Taxa B3')), isNull);
    final purchase = Record(
      -10,
      'BBAS3 X 1',
      Category('Compras', categoryType: CategoryType.expense),
      DateTime.utc(2026, 11, 5, 12),
    );
    expect(InvestmentLook.logoOf(purchase), isNull);
  });
}
