import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/components/wallet_icon_square.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:aupp/wallets/wallet-sort-option.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WalletPickerPage extends StatefulWidget {
  /// A page for selecting a wallet. Returns the selected Wallet via Navigator.pop.
  /// Used both in EditRecordPage (to pick a wallet for a record) and
  /// in EditWalletPage (to pick a target wallet when deleting/moving records).
  ///
  /// When [multiSelect] is true, shows checkboxes and an OK button; pops with
  /// a List<Wallet> instead of a single Wallet.

  final int? excludeWalletId;
  final bool multiSelect;
  final List<Wallet> initiallySelected;

  /// When provided, shows a "Save as default" checkbox. On confirm, saves the
  /// selection under this key in SharedPreferences.
  final String? preferencesKey;

  /// When provided, wallet balances shown are a point-in-time snapshot as of
  /// this date (inclusive) instead of the live balance, and a banner informs
  /// the user of this.
  final DateTime? asOfDate;

  /// In the Extrato, balances already computed by the caller (wallet id →
  /// balance, planned records included), shown instead of reading them.
  final Map<int, double>? balances;

  /// In the Extrato, when set, each wallet gets a second checkbox, "Total",
  /// for the wallets counted in the totals and balance; the page then pops a
  /// [WalletPickerResult].
  final List<Wallet>? initiallyCounted;

  /// In the Extrato, with [initiallyCounted]: the "Exibir ocultos" switch
  /// and how many hidden records the period has.
  final bool initiallyShowHidden;
  final int hiddenCount;

  WalletPickerPage({
    this.excludeWalletId,
    this.multiSelect = false,
    this.initiallySelected = const [],
    this.preferencesKey,
    this.asOfDate,
    this.balances,
    this.initiallyCounted,
    this.initiallyShowHidden = false,
    this.hiddenCount = 0,
  });

  @override
  _WalletPickerPageState createState() => _WalletPickerPageState();
}

/// What the Extrato's picker returns: the listed wallets and the wallets
/// counted in the totals (empty = same as listed), and whether hidden
/// records are listed too.
class WalletPickerResult {
  final List<Wallet> listed;
  final List<Wallet> counted;
  final bool showHidden;

  WalletPickerResult(this.listed, this.counted, {this.showHidden = false});
}

class _WalletPickerPageState extends State<WalletPickerPage> {
  DatabaseInterface database = ServiceConfig.database;
  List<Wallet>? _wallets;
  late Set<int?> _selectedIds;
  late Set<int?> _countedIds;
  bool _saveAsDefault = false;
  late bool _showHidden = widget.initiallyShowHidden;

  bool get _withTotals => widget.initiallyCounted != null;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initiallySelected.map((w) => w.id).toSet();
    _countedIds = (widget.initiallyCounted ?? []).map((w) => w.id).toSet();
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    final wallets = widget.asOfDate != null
        ? await database.getWalletsBalanceAsOf(widget.asOfDate!)
        : await database.getAllWallets();
    final balances = widget.balances;
    if (balances != null) {
      for (final w in wallets) {
        if (balances.containsKey(w.id)) w.balance = balances[w.id];
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(PreferencesKeys.walletListSortOption);
    final sortOption = (savedIndex != null &&
            savedIndex < WalletSortOption.values.length)
        ? WalletSortOption.values[savedIndex]
        : WalletSortOption.original;

    var filtered =
        wallets.where((w) => !w.isArchived && w.id != widget.excludeWalletId).toList();
    switch (sortOption) {
      case WalletSortOption.byName:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case WalletSortOption.byAmountAsc:
        filtered.sort((a, b) => (a.balance ?? 0.0).compareTo(b.balance ?? 0.0));
        break;
      case WalletSortOption.byAmountDesc:
        filtered.sort((a, b) => (b.balance ?? 0.0).compareTo(a.balance ?? 0.0));
        break;
      case WalletSortOption.original:
        break;
    }
    setState(() {
      _wallets = filtered;
      // "Nothing ticked" means all of them: show it that way.
      if (_withTotals && _selectedIds.isEmpty) {
        _selectedIds = filtered.map((w) => w.id).toSet();
      }
    });
  }

  void _toggleCounted(Wallet wallet) {
    setState(() {
      if (!_countedIds.remove(wallet.id)) _countedIds.add(wallet.id);
    });
  }

  void _toggleSelection(Wallet wallet) {
    setState(() {
      if (_selectedIds.contains(wallet.id)) {
        _selectedIds.remove(wallet.id);
      } else {
        _selectedIds.add(wallet.id);
      }
    });
  }

  Future<void> _confirmSelection() async {
    final selected =
        _wallets!.where((w) => _selectedIds.contains(w.id)).toList();
    if (_saveAsDefault && widget.preferencesKey != null) {
      final prefs = await SharedPreferences.getInstance();
      final ids = selected.map((w) => w.id.toString()).toList();
      await prefs.setStringList(widget.preferencesKey!, ids);
    }
    if (!mounted) return;
    if (_withTotals) {
      Navigator.of(context).pop(WalletPickerResult(
        selected,
        _wallets!.where((w) => _countedIds.contains(w.id)).toList(),
        showHidden: _showHidden,
      ));
      return;
    }
    Navigator.of(context).pop(selected);
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _wallets!.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = _wallets!.map((w) => w.id).toSet();
      }
    });
  }

  /// Column header of the two-checkbox mode; the "Lista" one also toggles
  /// all.
  Widget _columnLabel(String label, bool? value, VoidCallback? onTap) =>
      SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            if (value != null)
              Checkbox(value: value, onChanged: (_) => onTap?.call())
            else
              const SizedBox(height: 48),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _wallets != null && _selectedIds.length == _wallets!.length;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text('Selecionar carteira'),
      ),
      body: _wallets == null
          ? Center(child: CircularProgressIndicator())
          : _wallets!.isEmpty
              ? Center(child: Text('Nenhuma carteira disponível'))
              : Column(
                  children: [
                    if (widget.asOfDate != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Text(
                          'Saldo em ${DateFormat.yMMMd().format(widget.asOfDate!)}',
                          style: const TextStyle(
                              fontSize: 13, fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (widget.multiSelect)
                      ListTile(
                        title: Text(
                          allSelected ? 'Deselect all' : 'Selecionar tudo',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: _withTotals
                            ? const Text(
                                'Lista: lançamentos que aparecem no Extrato. '
                                'Total: o que entra nas receitas, despesas e '
                                'saldo do topo (nenhuma = as da lista).',
                              )
                            : null,
                        trailing: _withTotals
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _columnLabel('Lista', allSelected,
                                      _toggleSelectAll),
                                  _columnLabel('Total', null, null),
                                ],
                              )
                            : Checkbox(
                                value: allSelected,
                                onChanged: (_) => _toggleSelectAll(),
                              ),
                        onTap: _toggleSelectAll,
                      ),
                    if (widget.multiSelect) const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        separatorBuilder: (_, __) => Divider(thickness: 0.5),
                        itemCount: _wallets!.length,
                        itemBuilder: (context, i) {
                          final wallet = _wallets![i];
                          final isSelected = _selectedIds.contains(wallet.id);

                          if (widget.multiSelect) {
                            return ListTile(
                              leading: WalletIconSquare(
                                iconEmoji: wallet.iconEmoji,
                                iconDataFromDefaultIconSet: wallet.icon,
                                backgroundColor: wallet.color,
                              ),
                              title: Text(wallet.name,
                                  style: TextStyle(fontSize: 18)),
                              subtitle: wallet.balance != null
                                  ? Text(formatMoney(wallet.balance ?? 0.0))
                                  : null,
                              trailing: _withTotals
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 52,
                                          child: Checkbox(
                                            value: isSelected,
                                            onChanged: (_) =>
                                                _toggleSelection(wallet),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 52,
                                          child: Checkbox(
                                            value: _countedIds
                                                .contains(wallet.id),
                                            onChanged: (_) =>
                                                _toggleCounted(wallet),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Checkbox(
                                      value: isSelected,
                                      onChanged: (_) => _toggleSelection(wallet),
                                    ),
                              onTap: () => _toggleSelection(wallet),
                            );
                          }

                          return ListTile(
                            leading: WalletIconSquare(
                              iconEmoji: wallet.iconEmoji,
                              iconDataFromDefaultIconSet: wallet.icon,
                              backgroundColor: wallet.color,
                            ),
                            title: Text(wallet.name,
                                style: TextStyle(fontSize: 18)),
                            subtitle: wallet.isPredefined
                                ? Text('Predefinido')
                                : null,
                            trailing: wallet.balance != null
                                ? Text(
                                    formatMoney(wallet.balance ?? 0.0),
                                    style: TextStyle(fontSize: 16),
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(wallet),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: widget.multiSelect
          ? SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_withTotals) ...[
                    SwitchListTile(
                      value: _showHidden,
                      onChanged: (v) => setState(() => _showHidden = v),
                      secondary: const Icon(Icons.visibility_off),
                      title: const Text('Exibir ocultos',
                          style: TextStyle(fontSize: 17)),
                      subtitle: Text(widget.hiddenCount == 0
                          ? 'Nenhum oculto neste período'
                          : '${widget.hiddenCount} oculto(s) neste período'),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                    ),
                    const Divider(height: 1),
                  ],
                  if (widget.preferencesKey != null) ...[
                    CheckboxListTile(
                      value: _saveAsDefault,
                      onChanged: (v) =>
                          setState(() => _saveAsDefault = v ?? false),
                      title: Text(
                        'Salvar como seleção padrão',
                        style: const TextStyle(fontSize: 17),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                    ),
                    const Divider(height: 1),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _confirmSelection,
                        child: Text('Aplicar'),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );

    return scaffold;
  }
}
