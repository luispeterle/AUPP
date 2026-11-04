
enum RecurrentPeriod {
  EveryDay,
  EveryWeek,
  EveryMonth,
  EveryTwoWeeks,
  EveryThreeMonths,
  EveryFourMonths,
  EveryYear,
  EveryFourWeeks,
  // Appended at the end: the enum index is persisted in the database, so
  // existing values must keep their index and new ones must be added last.
  Custom,
}

/// Unit for a [RecurrentPeriod.Custom] interval (e.g. "every 6 months").
/// Persisted as an index in the database: append-only, like [RecurrentPeriod].
enum CustomIntervalUnit {
  day,
  week,
  month,
  year,
}

String recurrentPeriodString(RecurrentPeriod? r) {
  if (r == RecurrentPeriod.EveryDay) return 'Todo dia';
  if (r == RecurrentPeriod.EveryWeek) return 'Toda semana';
  if (r == RecurrentPeriod.EveryMonth) return 'Todo mês';
  if (r == RecurrentPeriod.EveryTwoWeeks) return 'A cada duas semanas';
  if (r == RecurrentPeriod.EveryFourWeeks) return 'A cada quatro semanas';
  if (r == RecurrentPeriod.EveryThreeMonths) return 'A cada três meses';
  if (r == RecurrentPeriod.EveryFourMonths) return 'A cada quatro meses';
  if (r == RecurrentPeriod.EveryYear) return 'Anualmente';
  if (r == RecurrentPeriod.Custom) return 'Personalizado';
  new Exception("Unexpected value");
  return "";
}

String customIntervalUnitString(CustomIntervalUnit unit) {
  switch (unit) {
    case CustomIntervalUnit.day:
      return 'Dias';
    case CustomIntervalUnit.week:
      return 'Semanas';
    case CustomIntervalUnit.month:
      return 'Meses';
    case CustomIntervalUnit.year:
      return 'Anos';
  }
}

/// Label for a fully-specified custom interval, e.g. "Every 6 Months".
/// Falls back to the generic "Custom" label when the interval is incomplete.
String customIntervalString(int? value, CustomIntervalUnit? unit) {
  if (value == null || unit == null) return 'Personalizado';
  return 'A cada ${value} ${customIntervalUnitString(unit)}';
}

/// Display label for a recurrent pattern's period, expanding
/// [RecurrentPeriod.Custom] into its concrete interval instead of the
/// generic "Custom" label.
String recurrentPeriodDisplayString(RecurrentPeriod? period,
    {int? customIntervalValue, CustomIntervalUnit? customIntervalUnit}) {
  if (period == RecurrentPeriod.Custom) {
    return customIntervalString(customIntervalValue, customIntervalUnit);
  }
  return recurrentPeriodString(period);
}
