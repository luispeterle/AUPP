import 'package:flutter/material.dart';
import 'package:aupp/statistics/statistics-models.dart';

/// Categorias / Subcategorias pills choosing how the statistics summary
/// groups the records.
class GroupByDropdown extends StatelessWidget {
  final GroupByType groupByType;
  final void Function(GroupByType) onGroupByTypeChanged;

  const GroupByDropdown({
    Key? key,
    required this.groupByType,
    required this.onGroupByTypeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, GroupByType type) => ChoiceChip(
      label: Text(label),
      selected: groupByType == type,
      showCheckmark: false,
      onSelected: (_) => onGroupByTypeChanged(type),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          pill('Categorias', GroupByType.category),
          pill('Subcategorias', GroupByType.subcategory),
        ],
      ),
    );
  }
}
