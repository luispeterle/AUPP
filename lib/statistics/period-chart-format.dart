import 'package:intl/intl.dart';
import 'package:aupp/statistics/statistics-models.dart';

/// How the dates of a statistics chart read, by its grouping: in the box
/// over the chart and, shorter, under the axis.
class PeriodChartFormat {
  PeriodChartFormat(AggregationMethod? method)
      : box = switch (method) {
          AggregationMethod.YEAR => DateFormat('yyyy', 'pt_BR'),
          AggregationMethod.MONTH => DateFormat('MMMM yyyy', 'pt_BR'),
          AggregationMethod.WEEK => DateFormat("'Semana de' dd/MM", 'pt_BR'),
          _ => DateFormat('EEE, dd/MM/yyyy', 'pt_BR'),
        },
        axis = switch (method) {
          AggregationMethod.YEAR => DateFormat('yyyy', 'pt_BR'),
          AggregationMethod.MONTH => DateFormat('MMM', 'pt_BR'),
          AggregationMethod.WEEK => DateFormat('dd/MM', 'pt_BR'),
          _ => DateFormat('dd', 'pt_BR'),
        };

  final DateFormat box;
  final DateFormat axis;
}
