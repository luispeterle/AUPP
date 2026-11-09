import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/components/category_icon_circle.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/service-config.dart';

import 'dinzo-api.dart';
import 'dinzo-auto-sync.dart';
import 'dinzo-config.dart';
import 'dinzo-settings-page.dart';
import 'dinzo-sync-engine.dart';
import 'dinzo-sync-service.dart';

/// Pulls from Dinzo and shows what would change before anything is written.
/// Strings are pt-BR on purpose: this screen exists only in the personal fork.
class DinzoSyncPage extends StatefulWidget {
  /// A plan the automatic sync already fetched and left for review.
  final DinzoPreparedSync? prepared;

  /// Starts by reading everything Dinzo has again (Ajustes da Dinzo).
  final bool full;

  const DinzoSyncPage({Key? key, this.prepared, this.full = false})
    : super(key: key);

  @override
  State<DinzoSyncPage> createState() => _DinzoSyncPageState();
}

enum _Section {
  needsCategory,
  create,
  update,
  conflict,
  remove,
  ignored,
  installments,
  internal,
  hidden,
}

const _sectionTitles = {
  _Section.needsCategory: 'Precisam de categoria',
  _Section.create: 'Novos',
  _Section.update: 'Atualizados na Dinzo',
  _Section.conflict: 'Conflitos (você editou)',
  _Section.remove: 'Removidos na Dinzo',
  _Section.ignored: 'Ignorados por você',
  _Section.installments: 'Parcelas de compras já lançadas',
  _Section.internal: 'Pagamentos de fatura',
  _Section.hidden: 'Investimentos, rendimentos e ocultos na Dinzo',
};

/// Sections that start collapsed: the noise of what is left out on purpose.
const _collapsedByDefault = {
  _Section.installments,
  _Section.internal,
  _Section.hidden,
};

/// Sections that only explain what is left out (not selectable).
const _infoSections = {
  _Section.ignored,
  _Section.installments,
  _Section.internal,
  _Section.hidden,
};

class _DinzoSyncPageState extends State<DinzoSyncPage> {
  final _dateFormat = DateFormat('dd/MM/yy');

  DinzoPreparedSync? _prepared;
  String _progress = 'Conectando…';
  String? _error;
  bool _applying = false;

  Map<String, Category> _categories = {};
  List<Wallet> _wallets = [];
  final Set<_Section> _expanded = {};

  /// Merge-screen edits survive a re-plan, keyed by Dinzo transaction id.
  final Map<String, DinzoSnapshot> _overrides = {};
  final Map<String, bool> _selection = {};

  @override
  void initState() {
    super.initState();
    DinzoAutoSync.pause();
    final ready = widget.prepared;
    if (ready != null) {
      // Replanned against the database as it is now.
      ready.replan();
      _show(ready);
    } else {
      _load();
    }
  }

  /// Full history + investments; otherwise the last ~2 months (and anything
  /// since the last sync). The very first sync is always full.
  late bool _full = widget.full || DinzoSyncService.lastSync == null;

  Future<void> _load({bool refreshBanks = true, bool? full}) async {
    if (full != null) _full = full;
    setState(() {
      _prepared = null;
      _error = null;
    });
    try {
      // An automatic sync may be applying right now: never plan on top of it.
      await DinzoAutoSync.whenIdle();
      final prepared = await DinzoSyncService.prepare(
        full: _full,
        refreshBanks: refreshBanks,
        onProgress: (step) {
          if (mounted) setState(() => _progress = step);
        },
      );
      await _show(prepared);
    } on DinzoApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.code == 'missing_key'
            ? 'Configure a chave da API da Dinzo para sincronizar.'
            : 'A Dinzo respondeu com erro (${e.status ?? ''} ${e.code}): ${e.message}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível sincronizar: $e');
    }
  }

  Future<void> _show(DinzoPreparedSync prepared) async {
    _full = prepared.full;
    final categories = await ServiceConfig.database.getAllCategories();
    final wallets = await ServiceConfig.database.getAllWallets();
    if (!mounted) return;
    setState(() {
      _categories = {
        for (final c in categories)
          if (c != null && !c.isArchived) _catKey(c.name!, c.categoryType!): c,
      };
      _wallets = wallets.where((w) => !w.isArchived).toList();
      _prepared = prepared;
    });
    if (prepared.connectionsNeedingAttention.isNotEmpty) {
      _showAttentionBanner(prepared.connectionsNeedingAttention);
    }
  }

  void _showAttentionBanner(List<String> names) {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text(
          'Conexões que precisam de ação no app da Dinzo: ${names.join(', ')}',
        ),
        leading: const Icon(Icons.warning_amber),
        actions: [
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    DinzoAutoSync.resume();
    _messenger?.clearMaterialBanners();
    super.dispose();
  }

  static String _catKey(String name, CategoryType type) =>
      '$name|${type.index}';

  DinzoConfig get _config => _prepared!.engine.config;

  void _replan() {
    _prepared!.replan();
    for (final item in _prepared!.plan.items) {
      final id = item.transaction?.id;
      if (id == null) continue;
      if (_overrides.containsKey(id)) item.desired = _overrides[id];
      if (_selection.containsKey(id)) item.selected = _selection[id]!;
    }
  }

  _Section? _sectionOf(DinzoPlanItem item) {
    switch (item.kind) {
      case DinzoPlanKind.create:
        return item.selected && item.needsCategory
            ? _Section.needsCategory
            : _Section.create;
      case DinzoPlanKind.update:
        return item.selected && item.needsCategory
            ? _Section.needsCategory
            : _Section.update;
      case DinzoPlanKind.conflict:
        return _Section.conflict;
      case DinzoPlanKind.remove:
        return _Section.remove;
      case DinzoPlanKind.unchanged:
        return null;
      case DinzoPlanKind.skipped:
        switch (item.skipReason!) {
          case DinzoSkipReason.ignoredByUser:
            return _Section.ignored;
          case DinzoSkipReason.laterInstallment:
            return _Section.installments;
          case DinzoSkipReason.internalTransfer:
            return _Section.internal;
          case DinzoSkipReason.hidden:
          case DinzoSkipReason.investment:
          case DinzoSkipReason.outsideDailyBanks:
            return _Section.hidden;
        }
    }
  }

  Map<_Section, List<DinzoPlanItem>> _grouped() {
    final groups = {for (final s in _Section.values) s: <DinzoPlanItem>[]};
    for (final item in _prepared!.plan.items) {
      final section = _sectionOf(item);
      if (section != null) groups[section]!.add(item);
    }
    String dateOf(DinzoPlanItem i) =>
        i.desired?.date ??
        i.transaction?.date ??
        DinzoSnapshot.ofRecord(i.existing!).date;
    for (final list in groups.values) {
      list.sort((a, b) => dateOf(b).compareTo(dateOf(a)));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronizar com a Dinzo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Buscar histórico completo',
            onPressed: _prepared == null
                ? null
                : () => _load(refreshBanks: false, full: true),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configurações da Dinzo',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DinzoSettingsPage()),
              );
              _overrides.clear();
              _selection.clear();
              _load(refreshBanks: false);
            },
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _prepared == null ? null : _buildApplyBar(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _load(refreshBanks: false),
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    if (_prepared == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_progress),
          ],
        ),
      );
    }

    final groups = _grouped();
    final rows = <Widget Function()>[];
    rows.add(() => _buildSummary(groups));
    for (final section in _Section.values) {
      final items = groups[section]!;
      if (items.isEmpty) continue;
      // [_expanded] holds the sections the user toggled away from their
      // default state.
      final expanded =
          _expanded.contains(section) != !_collapsedByDefault.contains(section);
      rows.add(() => _buildSectionHeader(section, items, expanded));
      if (expanded) {
        for (final item in items) {
          rows.add(() => _buildItem(item, section));
        }
      }
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i](),
    );
  }

  Widget _buildSummary(Map<_Section, List<DinzoPlanItem>> groups) {
    final b = _prepared!.balances;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dinheiro na Dinzo', style: theme.textTheme.labelLarge),
            Text(
              getCurrencyValueString(b.money),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Renda fixa ${getCurrencyValueString(b.fixedIncome)} · '
              'Em conta ${getCurrencyValueString(b.bank)} · '
              'Cartões −${getCurrencyValueString(b.cardDebt)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'A conta corrente será ajustada para esse valor menos o que está '
              'nas caixinhas e no Investir.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 20),
            Row(
              children: [
                Icon(_full ? Icons.history : Icons.bolt, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _full
                        ? 'Histórico completo e investimentos'
                        : 'Rápido: últimos ${DinzoSyncService.quickWindowDays} dias',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (!_full)
                  TextButton(
                    onPressed: () => _load(refreshBanks: false, full: true),
                    child: const Text('Buscar tudo'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    _Section section,
    List<DinzoPlanItem> items,
    bool expanded,
  ) {
    final info = _infoSections.contains(section);
    final selectable = !info;
    final selectedCount = items.where((i) => i.selected).length;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => setState(() {
          if (!_expanded.remove(section)) _expanded.add(section);
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(expanded ? Icons.expand_less : Icons.expand_more),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_sectionTitles[section]} '
                  '(${selectable ? '$selectedCount/' : ''}${items.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (section == _Section.needsCategory)
                TextButton(
                  onPressed: () => _bulkCategory(items),
                  child: const Text('Definir todos'),
                ),
              if (selectable && section != _Section.needsCategory)
                Checkbox(
                  tristate: true,
                  value: selectedCount == 0
                      ? false
                      : selectedCount == items.length
                      ? true
                      : null,
                  onChanged: (_) => setState(() {
                    final value = selectedCount != items.length;
                    for (final i in items) {
                      _setSelected(i, value);
                    }
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _setSelected(DinzoPlanItem item, bool value) {
    item.selected = value;
    final id = item.transaction?.id;
    if (id != null) _selection[id] = value;
  }

  Widget _buildItem(DinzoPlanItem item, _Section section) {
    final theme = Theme.of(context);
    final tx = item.transaction;
    final shown =
        item.desired ??
        (item.existing != null
            ? DinzoSnapshot.ofRecord(item.existing!)
            : _prepared!.engine.sourceFor(tx!));
    final category = shown.categoryName == null || item.categoryType == null
        ? null
        : _categories[_catKey(shown.categoryName!, item.categoryType!)];
    final account = tx == null
        ? null
        : _prepared!.engine.accounts[tx.accountId];
    final subtitle = <String>[
      _dateFormat.format(DateTime.parse(shown.date)),
      if (account != null) account.title,
      if (tx?.status == 'PENDING') 'pendente',
      if (_infoSections.contains(section) && tx != null)
        tx.isInstallment
            ? 'parcela ${tx.installmentCurrent}/${tx.installmentTotal}'
            : '',
      if (!_infoSections.contains(section) && section != _Section.remove)
        shown.categoryName ?? 'sem categoria',
      if (shown.walletId != null &&
          shown.walletId != _prepared!.engine.defaultWalletId)
        _walletName(shown.walletId),
    ].where((s) => s.isNotEmpty).join(' · ');

    final detail = _detailFor(item);
    final selectable = !_infoSections.contains(section);
    final value = section == _Section.installments && tx != null
        ? (tx.isDebit ? -tx.amount : tx.amount)
        : shown.value;

    return ListTile(
      dense: true,
      leading: selectable
          ? Checkbox(
              value: item.selected,
              onChanged: (v) => setState(() => _setSelected(item, v ?? false)),
            )
          : CategoryIconCircle(
              iconEmoji: null,
              iconDataFromDefaultIconSet: Icons.remove_circle_outline,
              backgroundColor: Colors.grey,
              circleSize: 32,
              mainIconSize: 16,
            ),
      title: Row(
        children: [
          if (category != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CategoryIconCircle(
                iconEmoji: category.iconEmoji,
                iconDataFromDefaultIconSet: category.icon,
                backgroundColor: category.color,
                circleSize: 24,
                mainIconSize: 14,
              ),
            ),
          Expanded(
            child: Text(
              shown.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        detail == null ? subtitle : '$subtitle\n$detail',
        style: shown.categoryName == null && selectable
            ? TextStyle(color: theme.colorScheme.error)
            : null,
      ),
      isThreeLine: detail != null,
      trailing: Text(
        getCurrencyValueString(value),
        style: TextStyle(
          color: value < 0 ? null : Colors.green.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => _onItemTap(item, section),
    );
  }

  String? _detailFor(DinzoPlanItem item) {
    switch (item.kind) {
      case DinzoPlanKind.create:
        return item.description;
      case DinzoPlanKind.update:
      case DinzoPlanKind.conflict:
        final before = DinzoSnapshot.ofRecord(item.existing!);
        final after = item.desired!;
        final changes = <String>[
          if (before.title != after.title) 'título: ${after.title}',
          if ((before.value - after.value).abs() >= 0.005)
            'valor: ${getCurrencyValueString(before.value)} → '
                '${getCurrencyValueString(after.value)}',
          if (before.date != after.date)
            'data: ${_dateFormat.format(DateTime.parse(after.date))}',
          if (before.categoryName != after.categoryName)
            'categoria: ${before.categoryName ?? '—'} → ${after.categoryName ?? '—'}',
          if (before.walletId != after.walletId)
            'carteira: ${_walletName(after.walletId)}',
        ];
        final prefix = item.kind == DinzoPlanKind.conflict
            ? (item.selected
                  ? 'Usar versão da Dinzo: '
                  : 'Mantendo a sua. Dinzo diz: ')
            : '';
        return changes.isEmpty ? null : prefix + changes.join('; ');
      case DinzoPlanKind.remove:
        switch (item.skipReason) {
          case DinzoSkipReason.hidden:
            return 'Ficou oculto na Dinzo';
          case DinzoSkipReason.investment:
            return 'É movimentação de investimento';
          case DinzoSkipReason.internalTransfer:
            return 'Agora é visto como pagamento de fatura';
          case DinzoSkipReason.ignoredByUser:
            return 'Você marcou para não integrar';
          case DinzoSkipReason.outsideDailyBanks:
            return 'Ficou dentro da corretora';
          default:
            return 'Não existe mais na Dinzo';
        }
      default:
        return null;
    }
  }

  String _walletName(int? id) =>
      _wallets.where((w) => w.id == id).map((w) => w.name).firstOrNull ?? '—';

  Future<void> _onItemTap(DinzoPlanItem item, _Section section) async {
    final tx = item.transaction;
    if (tx == null) return;
    if (section == _Section.ignored) {
      final back = await _confirm(
        'Voltar a integrar?',
        '"${DinzoSyncEngine.cleanTitle(tx.description)}" voltará a ser importado.',
      );
      if (back) {
        _config.ignoredIds.remove(tx.id);
        setState(_replan);
      }
      return;
    }
    if (_infoSections.contains(section) || item.kind == DinzoPlanKind.remove) {
      return;
    }
    if (item.kind == DinzoPlanKind.update ||
        item.kind == DinzoPlanKind.conflict) {
      final edit = await _showChanges(item);
      if (edit != true) return;
    }
    await _editItem(item);
  }

  /// What an update changes, field by field. Returns true to edit it.
  Future<bool?> _showChanges(DinzoPlanItem item) {
    final before = DinzoSnapshot.ofRecord(
      item.existing!,
      syncedTags:
          DinzoLink.fromJsonString(item.existing!.dinzoSnapshot)
              ?.applied
              .tags ??
          const [],
    );
    final after = item.desired!;
    String date(String d) => _dateFormat.format(DateTime.parse(d));
    String tags(List<String> t) => t.isEmpty ? '—' : t.join(', ');
    final rows = <(String, String, String)>[
      ('Título', before.title, after.title),
      (
        'Valor',
        getCurrencyValueString(before.value),
        getCurrencyValueString(after.value),
      ),
      ('Data', date(before.date), date(after.date)),
      ('Categoria', before.categoryName ?? '—', after.categoryName ?? '—'),
      ('Carteira', _walletName(before.walletId), _walletName(after.walletId)),
      ('Tags', tags(before.tags), tags(after.tags)),
    ];
    final tx = item.transaction;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.kind == DinzoPlanKind.conflict
                      ? 'Mudou na Dinzo e você também editou'
                      : 'O que mudou na Dinzo',
                  style: theme.textTheme.titleMedium,
                ),
                if (tx != null)
                  Text(
                    tx.originalDescription ?? tx.description,
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                for (final (label, from, to) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(label, style: theme.textTheme.bodySmall),
                        ),
                        Expanded(
                          child: from == to
                              ? Text(to, style: theme.textTheme.bodyMedium)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      from,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            decoration:
                                                TextDecoration.lineThrough,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    Text(
                                      to,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                if (item.kind == DinzoPlanKind.conflict)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      item.selected
                          ? 'Marcado: vai usar a versão da Dinzo.'
                          : 'Desmarcado: mantém a sua versão.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Editar'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editItem(DinzoPlanItem item) async {
    final result = await showModalBottomSheet<_ItemEdit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemEditSheet(
        item: item,
        categories:
            _categories.values
                .where((c) => c.categoryType == item.categoryType)
                .toList()
              ..sort((a, b) => a.name!.compareTo(b.name!)),
        wallets: _wallets,
        defaultWalletId: _prepared!.engine.defaultWalletId,
        dinzoCategoryTitle: item.transaction?.categoryId == null
            ? null
            : _prepared!.engine.categories[item.transaction!.categoryId]?.title,
      ),
    );
    if (result == null) return;
    final tx = item.transaction!;
    if (result.ignore) {
      _config.ignoredIds.add(tx.id);
      _overrides.remove(tx.id);
      setState(_replan);
      return;
    }
    final d = item.desired!;
    final edited = DinzoSnapshot(
      title: result.title,
      value: d.value,
      date: d.date,
      categoryName: result.categoryName,
      walletId: result.walletId,
      tags: d.tags,
      accountId: d.accountId,
    );
    final defaultWallet = _prepared!.engine.defaultWalletId;
    if (result.rememberMerchant) {
      _config.merchantRules[DinzoSyncEngine.merchantKey(
        tx.description,
      )] = DinzoMerchantRule(
        categoryName: result.categoryName,
        walletId: result.walletId == defaultWallet ? null : result.walletId,
      );
    }
    if (result.rememberDinzoCategory &&
        tx.categoryId != null &&
        result.categoryName != null) {
      _config.categoryMap[DinzoConfig.categoryKey(
            tx.categoryId!,
            item.categoryType!,
          )] =
          result.categoryName!;
    }
    _overrides[tx.id] = edited;
    _selection[tx.id] = true;
    if (result.rememberMerchant || result.rememberDinzoCategory) {
      // Persist right away so the rule is not lost if the sync is abandoned.
      await DinzoSyncService.saveConfig(_config);
      setState(_replan);
    } else {
      setState(() {
        item.desired = edited;
        item.selected = true;
      });
    }
  }

  Future<void> _bulkCategory(List<DinzoPlanItem> items) async {
    for (final type in [CategoryType.expense, CategoryType.income]) {
      final ofType = items.where((i) => i.categoryType == type).toList();
      if (ofType.isEmpty) continue;
      final chosen = await showModalBottomSheet<Category>(
        context: context,
        builder: (_) => _CategoryPicker(
          title: type == CategoryType.expense
              ? 'Categoria para ${ofType.length} despesas sem categoria'
              : 'Categoria para ${ofType.length} receitas sem categoria',
          categories:
              _categories.values.where((c) => c.categoryType == type).toList()
                ..sort((a, b) => a.name!.compareTo(b.name!)),
        ),
      );
      if (chosen == null) continue;
      setState(() {
        for (final item in ofType) {
          final d = item.desired!;
          final edited = DinzoSnapshot(
            title: d.title,
            value: d.value,
            date: d.date,
            categoryName: chosen.name,
            walletId: d.walletId,
            tags: d.tags,
            accountId: d.accountId,
          );
          item.desired = edited;
          _overrides[item.transaction!.id] = edited;
        }
      });
    }
  }

  Widget _buildApplyBar() {
    final items = _prepared!.plan.items;
    final missing = items.where((i) => i.selected && i.needsCategory).length;
    int count(DinzoPlanKind k) =>
        items.where((i) => i.kind == k && i.selected).length;
    final total =
        count(DinzoPlanKind.create) +
        count(DinzoPlanKind.update) +
        count(DinzoPlanKind.conflict) +
        count(DinzoPlanKind.remove);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                missing > 0
                    ? '$missing sem categoria'
                    : '${count(DinzoPlanKind.create)} novos · '
                          '${count(DinzoPlanKind.update) + count(DinzoPlanKind.conflict)} atualizados · '
                          '${count(DinzoPlanKind.remove)} removidos',
                style: missing > 0
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
            FilledButton.icon(
              icon: _applying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(total == 0 ? 'Só ajustar saldo' : 'Aplicar'),
              onPressed: missing > 0 || _applying ? null : _apply,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final result = await DinzoSyncService.apply(_prepared!);
      DinzoAutoSync.clear();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sincronizado'),
          content: Text(
            '${result.created} novos, ${result.updated} '
            'atualizados, ${result.removed} removidos.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha ao aplicar: $e')));
    }
  }
}

class _ItemEdit {
  final String title;
  final String? categoryName;
  final int? walletId;
  final bool rememberMerchant;
  final bool rememberDinzoCategory;
  final bool ignore;

  _ItemEdit({
    required this.title,
    this.categoryName,
    this.walletId,
    this.rememberMerchant = false,
    this.rememberDinzoCategory = false,
    this.ignore = false,
  });
}

class _ItemEditSheet extends StatefulWidget {
  final DinzoPlanItem item;
  final List<Category> categories;
  final List<Wallet> wallets;
  final int? defaultWalletId;
  final String? dinzoCategoryTitle;

  const _ItemEditSheet({
    required this.item,
    required this.categories,
    required this.wallets,
    required this.defaultWalletId,
    required this.dinzoCategoryTitle,
  });

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  late final TextEditingController _title;
  String? _category;
  int? _wallet;
  bool _rememberMerchant = false;
  bool _rememberDinzoCategory = false;

  @override
  void initState() {
    super.initState();
    final d = widget.item.desired!;
    _title = TextEditingController(text: d.title);
    _category = d.categoryName;
    _wallet = d.walletId;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.item.transaction!;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tx.originalDescription ?? tx.description,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 16),
              Text('Categoria', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in widget.categories)
                    ChoiceChip(
                      avatar: CategoryIconCircle(
                        iconEmoji: c.iconEmoji,
                        iconDataFromDefaultIconSet: c.icon,
                        backgroundColor: c.color,
                        circleSize: 20,
                        mainIconSize: 12,
                      ),
                      label: Text(c.name!),
                      selected: _category == c.name,
                      onSelected: (_) => setState(() => _category = c.name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                initialValue: _wallet,
                decoration: const InputDecoration(labelText: 'Carteira'),
                items: [
                  for (final w in widget.wallets)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(() => _wallet = v),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _rememberMerchant,
                onChanged: (v) =>
                    setState(() => _rememberMerchant = v ?? false),
                title: Text(
                  'Lembrar para "${DinzoSyncEngine.cleanTitle(tx.description)}"',
                ),
                subtitle: const Text(
                  'Próximos lançamentos deste estabelecimento usam esta categoria e carteira',
                ),
              ),
              if (widget.dinzoCategoryTitle != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _rememberDinzoCategory,
                  onChanged: (v) =>
                      setState(() => _rememberDinzoCategory = v ?? false),
                  title: Text(
                    'Usar sempre para a categoria Dinzo "${widget.dinzoCategoryTitle}"',
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.block),
                    label: const Text('Não integrar'),
                    onPressed: () => Navigator.pop(
                      context,
                      _ItemEdit(title: _title.text, ignore: true),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _ItemEdit(
                        title: _title.text.trim().isEmpty
                            ? widget.item.desired!.title
                            : _title.text.trim(),
                        categoryName: _category,
                        walletId: _wallet,
                        rememberMerchant: _rememberMerchant,
                        rememberDinzoCategory: _rememberDinzoCategory,
                      ),
                    ),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final String title;
  final List<Category> categories;

  const _CategoryPicker({required this.title, required this.categories});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in categories)
                  ListTile(
                    leading: CategoryIconCircle(
                      iconEmoji: c.iconEmoji,
                      iconDataFromDefaultIconSet: c.icon,
                      backgroundColor: c.color,
                      circleSize: 32,
                      mainIconSize: 16,
                    ),
                    title: Text(c.name!),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
