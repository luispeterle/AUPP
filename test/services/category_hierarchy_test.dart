import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/services/category-hierarchy.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Category expense(String name, {String? parent}) => Category(
    name,
    categoryType: CategoryType.expense,
    parentName: parent,
  );

  test('topOf: the parent of a subcategory, else the category itself', () {
    final alimentacao = expense('Alimentação');
    final cafeteria = expense('Cafeteria', parent: 'Alimentação');
    final orfa = expense('Órfã', parent: 'Sumiu');
    CategoryHierarchy.load([alimentacao, cafeteria, orfa]);

    expect(CategoryHierarchy.topOf(cafeteria), same(alimentacao));
    expect(CategoryHierarchy.topOf(alimentacao), same(alimentacao));
    expect(CategoryHierarchy.topOf(orfa), same(orfa));
    expect(CategoryHierarchy.topOf(null), isNull);
  });

  test('topOf: a category not loaded stays itself', () {
    CategoryHierarchy.load([]);
    final nova = expense('Nova', parent: 'Alimentação');
    expect(CategoryHierarchy.topOf(nova), same(nova));
  });

  test('iconOf: the subcategory by default, the parent when chosen', () async {
    final alimentacao = expense('Alimentação');
    final cafeteria = expense('Cafeteria', parent: 'Alimentação');
    CategoryHierarchy.load([alimentacao, cafeteria]);

    SharedPreferences.setMockInitialValues({});
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
    expect(CategoryHierarchy.iconOf(cafeteria), same(cafeteria));

    await ServiceConfig.sharedPreferences!
        .setBool(PreferencesKeys.extratoParentIcon, true);
    expect(CategoryHierarchy.iconOf(cafeteria), same(alimentacao));
    expect(CategoryHierarchy.iconOf(alimentacao), same(alimentacao));
  });
}
