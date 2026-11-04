import 'package:flutter/material.dart';

import 'budget-plan-groups.dart';
import 'budget-plan-page.dart';
import 'budget-plan-service.dart';

/// Orçamento tab of the Extrato statistics: the same bars as the Início,
/// over the Extrato's interval (a month, a year, a custom range…).
class BudgetPlanTab extends StatefulWidget {
  final DateTime from;
  final DateTime to;

  const BudgetPlanTab({super.key, required this.from, required this.to});

  @override
  State<BudgetPlanTab> createState() => _BudgetPlanTabState();
}

class _BudgetPlanTabState extends State<BudgetPlanTab> {
  BudgetPlanSnapshot? _snap;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await BudgetPlanService.loadRange(
        from: widget.from,
        to: widget.to,
      );
      if (mounted) setState(() => _snap = snap);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _openPlan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BudgetPlanPage()),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    if (snap == null) {
      return Center(
        child: _error != null
            ? Text('Não foi possível calcular o orçamento: $_error')
            : const CircularProgressIndicator(),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: BudgetPlanGroups(
              snap: snap,
              from: widget.from,
              to: widget.to,
              onReturn: _load,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _openPlan,
            child: const Text('Ajustar'),
          ),
        ),
      ],
    );
  }
}

/// The Orçamento below the summaries of the Extrato on the computer, over the
/// period on screen. [interval] gives the period; a new [revision] (another
/// period, or the records changed) calculates it again.
class BudgetPlanSummaryCard extends StatefulWidget {
  final Future<(DateTime, DateTime)> Function() interval;
  final Object revision;
  final String title;

  const BudgetPlanSummaryCard({
    super.key,
    required this.interval,
    required this.revision,
    required this.title,
  });

  @override
  State<BudgetPlanSummaryCard> createState() => _BudgetPlanSummaryCardState();
}

class _BudgetPlanSummaryCardState extends State<BudgetPlanSummaryCard> {
  BudgetPlanSnapshot? _snap;
  late DateTime _from;
  late DateTime _to;
  int _loading = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BudgetPlanSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    // Only the latest one counts: months can be switched faster than this.
    final loading = ++_loading;
    try {
      final (from, to) = await widget.interval();
      final snap = await BudgetPlanService.loadRange(from: from, to: to);
      if (!mounted || loading != _loading) return;
      setState(() {
        _from = from;
        _to = to;
        _snap = snap;
      });
    } catch (_) {
      // Without the bars the Extrato still works; the next change tries again.
      if (mounted && loading == _loading) setState(() => _snap = null);
    }
  }

  Future<void> _openPlan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BudgetPlanPage()),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    if (snap == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Orçamento · ${widget.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(onPressed: _openPlan, child: const Text('Ajustar')),
            ],
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: BudgetPlanGroups(
                snap: snap,
                from: _from,
                to: _to,
                onReturn: _load,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
