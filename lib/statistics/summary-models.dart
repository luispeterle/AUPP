import '../models/category.dart';

class SumTuple<T> {
  final T key;
  final double value;

  /// [value] may be an absolute magnitude for display; the sign of the
  /// underlying data lives here, to color amounts by sign.
  final double signedValue;

  SumTuple(this.key, this.value, {double? signedValue})
      : signedValue = signedValue ?? value;
}

class TagSumTuple extends SumTuple<String> {
  TagSumTuple(super.tag, super.value, {super.signedValue});
}

class CategorySumTuple extends SumTuple<Category> {
  CategorySumTuple(super.category, super.value, {super.signedValue});
}

class WalletSumTuple extends SumTuple<int> {
  WalletSumTuple(super.walletId, super.value, {super.signedValue});
}
