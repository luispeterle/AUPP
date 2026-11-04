enum CategoryType {
  expense,
  income,

  /// Money moved to or from investments: neither spent nor earned. See
  /// [Record.isInvestmentBuy] and [Category.adjustment].
  investment,
}
