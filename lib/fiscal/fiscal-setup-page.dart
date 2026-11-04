import 'package:aupp/services/service-config.dart';
import 'package:flutter/material.dart';

import 'fiscal-data.dart';
import 'fiscal-store.dart';
import 'fiscal-tables.dart';
import 'fiscal-ui.dart';

/// The company's registration: regimes over time, activities, pró-labore,
/// the revenue forecast and the estimates the taxes fill in.
class FiscalSetupPage extends StatefulWidget {
  final String companyName;

  const FiscalSetupPage({super.key, required this.companyName});

  @override
  State<FiscalSetupPage> createState() => _FiscalSetupPageState();
}

class _FiscalSetupPageState extends State<FiscalSetupPage> {
  FiscalSession? _session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await FiscalSession.load(widget.companyName);
    if (mounted) setState(() => _session = s);
  }

  FiscalData get _data => _session!.data;

  Future<void> _save() async {
    await _session!.save();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro da empresa')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _regimes(),
                _activities(s),
                _proLabore(),
                _accountant(),
                _forecast(s),
                _estimates(s),
              ],
            ),
    );
  }

  // -------------------------------------------------------------- regimes

  Widget _regimes() => FiscalCard(
    'Regimes ao longo do tempo',
    [
      const Text(
        'Ex.: MEI de 29/07/2025 a 31/10/2026, depois ME no Simples desde '
        '01/11/2026. Se virou ME no mesmo CNPJ, o faturamento do MEI conta '
        'para a faixa e o Fator R (com folha zero).',
      ),
      const SizedBox(height: 8),
      if (_data.regimes.isEmpty) const Text('Nenhum ainda.'),
      for (final r in _data.regimes)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Text(
            regimeShort(r.kind),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          title: Text(r.kind == RegimeKind.mei ? 'MEI' : 'ME no Simples Nacional'),
          subtitle: Text(
            '${dayFormat.format(r.start)} até '
            '${r.end == null ? 'hoje' : dayFormat.format(r.end!)}',
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editRegime(r),
        ),
    ],
    action: IconButton(
      icon: const Icon(Icons.add),
      tooltip: 'Novo período',
      onPressed: () => _editRegime(null),
    ),
  );

  Future<void> _editRegime(Regime? existing) async {
    var kind = existing?.kind ??
        (_data.regimes.isEmpty ? RegimeKind.mei : RegimeKind.simples);
    DateTime? start = existing?.start;
    DateTime? end = existing?.end;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(existing == null ? 'Novo período' : 'Período'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<RegimeKind>(
                segments: const [
                  ButtonSegment(value: RegimeKind.mei, label: Text('MEI')),
                  ButtonSegment(
                    value: RegimeKind.simples,
                    label: Text('ME (Simples)'),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setDialog(() => kind = v.first),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Desde'),
                subtitle: Text(start == null ? 'Escolher' : dayFormat.format(start!)),
                onTap: () async {
                  final d = await askDate(context, start);
                  if (d != null) setDialog(() => start = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Até'),
                subtitle: Text(end == null ? 'Hoje (ainda é)' : dayFormat.format(end!)),
                trailing: end == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setDialog(() => end = null),
                      ),
                onTap: () async {
                  final d = await askDate(context, end ?? start);
                  if (d != null) setDialog(() => end = d);
                },
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                child: const Text('Excluir'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: start == null ? null : () => Navigator.pop(context, 'save'),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (result == 'delete' && existing != null) {
      _data.regimes.remove(existing);
    } else if (result == 'save' && start != null) {
      if (existing == null) {
        _data.regimes.add(Regime(kind, start!, end));
      } else {
        existing
          ..kind = kind
          ..start = start!
          ..end = end;
      }
      _data.regimes.sort((a, b) => a.start.compareTo(b.start));
    } else {
      return;
    }
    await _save();
  }

  // ----------------------------------------------------------- activities

  Widget _activities(FiscalSession s) => FiscalCard(
    'Atividades (CNAE ou código da nota)',
    [
      const Text(
        'A primeira é a principal: as notas entram nela, a não ser que você '
        'diga outra. Anexo III direto paga 6% na primeira faixa; as que '
        'dependem do Fator R vão para o Anexo V (15,5%) se a folha ficar '
        'abaixo de 28% do faturamento.',
      ),
      const SizedBox(height: 8),
      if (_data.activities.isEmpty) const Text('Nenhuma ainda.'),
      for (final code in _data.activities)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            code == _data.mainActivity ? Icons.star : Icons.star_border,
          ),
          title: Text(s.activityLabel(code)),
          subtitle: Text(_data.activityOf(code)?.kindLabel ?? ''),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              _data.activities.remove(code);
              if (v == 'main') _data.activities.insert(0, code);
              await _save();
            },
            itemBuilder: (_) => [
              if (code != _data.mainActivity)
                const PopupMenuItem(value: 'main', child: Text('Tornar principal')),
              const PopupMenuItem(value: 'remove', child: Text('Remover')),
            ],
          ),
        ),
    ],
    action: IconButton(
      icon: const Icon(Icons.add),
      tooltip: 'Nova atividade',
      onPressed: _addActivity,
    ),
  );

  Future<void> _addActivity() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Atividade (CNAE ou código da nota)'),
        children: [
          for (final a in FiscalTables.activities)
            if (!_data.activities.contains(a.code))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, a.code),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${a.code} · ${a.name}'),
                  subtitle: Text(a.kindLabel),
                ),
              ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'outra'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add),
              title: Text('Outra…'),
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice != 'outra') {
      _data.activities.add(choice);
      await _save();
      return;
    }
    final code = TextEditingController();
    final name = TextEditingController();
    var kind = ActivityKind.annexIII;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Outra atividade'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: 'CNAE'),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 12),
              DropdownButton<ActivityKind>(
                value: kind,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: ActivityKind.annexIII,
                    child: Text('Anexo III direto'),
                  ),
                  DropdownMenuItem(
                    value: ActivityKind.fatorR,
                    child: Text('Depende do Fator R (III ou V)'),
                  ),
                  DropdownMenuItem(
                    value: ActivityKind.annexV,
                    child: Text('Anexo V direto'),
                  ),
                ],
                onChanged: (k) => setDialog(() => kind = k ?? kind),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || code.text.trim().isEmpty) return;
    final c = code.text.trim();
    _data.customActivities.add(
      Activity(c, name.text.trim().isEmpty ? c : name.text.trim(), kind),
    );
    _data.activities.add(c);
    await _save();
  }

  // ----------------------------------------------------------- pró-labore

  Widget _proLabore() {
    final changes = [..._data.proLabore]
      ..sort((a, b) => a.since.compareTo(b.since));
    final min = FiscalTables.forYear(DateTime.now().year).minimumWage;
    return FiscalCard(
      'Pró-labore',
      [
        Text(
          'Só na ME (MEI não tem). Cada valor vale a partir do mês indicado '
          'até a próxima mudança. O mínimo é um salário mínimo '
          '(${money(min)}); sobre ele a empresa retém 11% de INSS e o IRRF, '
          'pagos na DCTFWeb.',
        ),
        const SizedBox(height: 8),
        if (changes.isEmpty) const Text('Nenhum informado.'),
        for (final c in changes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(money(c.value)),
            subtitle: Text('A partir de ${c.since.label}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'remove') {
                  _data.proLabore.remove(c);
                } else {
                  final value = await askMoney(context, 'Pró-labore',
                      initial: c.value);
                  if (value == null) return;
                  c.value = value;
                }
                await _save();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Mudar valor')),
                PopupMenuItem(value: 'remove', child: Text('Remover')),
              ],
            ),
          ),
      ],
      action: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Mudar o pró-labore',
        onPressed: () async {
          // Only the ME has a pró-labore: the months start at the first one.
          YearMonth? firstMe;
          for (final r in _data.regimes) {
            if (r.kind != RegimeKind.simples) continue;
            if (firstMe == null || r.startMonth.isBefore(firstMe)) {
              firstMe = r.startMonth;
            }
          }
          if (firstMe == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pró-labore só existe na ME: cadastre o período '
                    'no Simples primeiro'),
              ),
            );
            return;
          }
          final current = FiscalStore.currentMonth;
          final since = await askMonth(
            context,
            'A partir de que mês?',
            first: firstMe,
            initial: current.isBefore(firstMe) ? firstMe : current,
          );
          if (since == null || !mounted) return;
          final value = await askMoney(context, 'Pró-labore a partir de ${since.label}');
          if (value == null) return;
          _data.proLabore.removeWhere((c) => c.since == since);
          _data.proLabore.add(MonthlyValue(since, value));
          await _save();
        },
      ),
    );
  }

  // ------------------------------------------------------------- forecast

  Widget _forecast(FiscalSession s) {
    final income = s.patterns.where((p) => (p.value ?? 0) > 0).toList();
    return FiscalCard('Faturamento previsto', [
      const Text(
        'Estimativas de entrada que preveem as notas dos próximos meses. '
        'Contam enquanto o mês não tem entrada real; mudando a estimativa '
        '(um aumento), os impostos acompanham.',
      ),
      if (income.isEmpty) const Text('Nenhuma estimativa de entrada.'),
      for (final p in income)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _data.forecastPatterns.contains(p.id),
          title: Text(p.title ?? 'Sem nome'),
          subtitle: Text('${money(p.value ?? 0)} · dia ${p.utcDateTime.toLocal().day}'),
          onChanged: (v) async {
            v == true
                ? _data.forecastPatterns.add(p.id!)
                : _data.forecastPatterns.remove(p.id);
            await _save();
          },
        ),
    ]);
  }

  // ------------------------------------------------------------ estimates

  Widget _accountant() {
    final changes = [..._data.accountantFee]
      ..sort((a, b) => a.since.compareTo(b.since));
    return FiscalCard(
      'Contador',
      [
        const Text(
          'Honorário mensal: cada valor vale a partir do mês indicado até a '
          'próxima mudança (também dá para digitar na planilha). Entra nas '
          'despesas do IR anual.',
        ),
        const SizedBox(height: 8),
        if (changes.isEmpty) const Text('Nenhum informado.'),
        for (final c in changes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(money(c.value)),
            subtitle: Text('A partir de ${c.since.label}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remover',
              onPressed: () async {
                _data.accountantFee.remove(c);
                await _save();
              },
            ),
          ),
        Row(
          children: [
            const Expanded(child: Text('Dia do pagamento')),
            DropdownButton<int>(
              value: _data.accountantDay.clamp(1, 28),
              items: [
                for (var d = 1; d <= 28; d++)
                  DropdownMenuItem(value: d, child: Text('dia $d')),
              ],
              onChanged: (d) async {
                if (d == null) return;
                _data.accountantDay = d;
                await _moveTo(_data.feePattern, d);
                await _save();
              },
            ),
          ],
        ),
      ],
      action: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Mudar o honorário',
        onPressed: () async {
          final since = await askMonth(
            context,
            'A partir de que mês?',
            first: _data.firstMonth,
          );
          if (since == null || !mounted) return;
          final value = await askMoney(context, 'Honorário a partir de ${since.label}');
          if (value == null) return;
          _data.accountantFee.removeWhere((c) => c.since == since);
          _data.accountantFee.add(MonthlyValue(since, value));
          await _save();
        },
      ),
    );
  }

  Widget _estimates(FiscalSession s) {
    final names = {for (final p in s.patterns) p.id: p};
    String state(String? id, String missing) {
      final p = id == null ? null : names[id];
      return p == null ? missing : '${p.title} · dia ${p.utcDateTime.toLocal().day}';
    }

    return FiscalCard('Estimativas no Extrato', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Criar e manter automaticamente'),
        subtitle: const Text(
          'DAS e DCTFWeb no dia 20 (impostos do mês anterior) e o contador '
          'no dia dele, com o valor calculado de cada mês. Um boleto colado '
          'numa ocorrência continua valendo.',
        ),
        value: _data.autoEstimates,
        onChanged: (v) async {
          _data.autoEstimates = v;
          await _save();
        },
      ),
      FiscalRow('DAS', state(_data.dasPattern, 'ainda não criada')),
      FiscalRow(
        'DCTFWeb (INSS + IRRF)',
        state(_data.dctfwebPattern, 'criada quando houver pró-labore'),
      ),
      FiscalRow(
        'Contabilidade',
        state(_data.feePattern, 'criada quando houver honorário'),
      ),
    ]);
  }

  /// Moves the estimate [id] to day [day] of the month.
  Future<void> _moveTo(String? id, int day) async {
    if (id == null) return;
    final db = ServiceConfig.database;
    final p = await db.getRecurrentRecordPattern(id);
    if (p == null) return;
    final local = p.utcDateTime.toLocal();
    if (local.day == day) return;
    p.utcDateTime = DateTime(local.year, local.month, day, local.hour, local.minute)
        .toUtc();
    await db.updateRecordPatternById(id, p);
  }
}
