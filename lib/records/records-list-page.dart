import 'package:flutter/material.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/records/components/records-day-list.dart';

/// Just the records behind a total (Investido, Guardado, Retirado), by day
/// as in the Extrato.
class RecordsListPage extends StatelessWidget {
  final String title;
  final List<Record> records;

  const RecordsListPage({super.key, required this.title, required this.records});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: records.isEmpty
          ? const Center(child: Text('Nada neste período.'))
          : CustomScrollView(slivers: [RecordsDayList(records)]),
    );
  }
}
