import 'package:aupp/accounts/money-accounts.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/fiscal/fiscal-page.dart';
import 'package:aupp/services/service-config.dart';
import 'package:flutter/material.dart';

/// The person's accounts and those of each company, each with a switch
/// (what the Extrato shows), and the names and documents of each one (how
/// the Dinzo sync tells money between own accounts). Opened from the person
/// button and from the Dinzo settings.
class AccountsSheet extends StatefulWidget {
  const AccountsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const AccountsSheet(),
  );

  @override
  State<AccountsSheet> createState() => _AccountsSheetState();
}

class _AccountsSheetState extends State<AccountsSheet> {
  /// Every bank account the records have, by catalogue name.
  List<String> _banks = [];
  List<Company> _companies = [];

  /// The person's names and documents (the companies keep their own).
  List<String> _personalIds = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tags = await ServiceConfig.database.getAllTags();
    final banks = <String>{
      for (final tag in tags)
        if (KnownTag.of(tag)?.kind == KnownTagKind.bank) KnownTag.of(tag)!.name,
    };
    final companies = MoneyAccounts.companies(known: banks);
    for (final company in companies) {
      banks.addAll(company.banks);
    }
    final allIds = DinzoSyncService.loadConfig().selfIdentifiers;
    if (!mounted) return;
    setState(() {
      _personalIds = MoneyAccounts.personalIds(allIds, companies);
      _banks = banks.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _companies = companies;
      _loaded = true;
    });
  }

  List<String> get _personal => [
    for (final bank in _banks)
      if (MoneyAccounts.companyOf(bank, _companies) == null) bank,
    MoneyAccounts.noBank,
  ];

  /// Saves the companies, and every name and document into the Dinzo
  /// config the sync reads.
  Future<void> _saveCompanies() async {
    await MoneyAccounts.saveCompanies(_companies);
    final config = DinzoSyncService.loadConfig();
    config.selfIdentifiers = MoneyAccounts.allIds(_personalIds, _companies);
    await DinzoSyncService.saveConfig(config);
    if (mounted) setState(() {});
  }

  Future<void> _editIds(String group, List<String> ids) async {
    final controller = TextEditingController(text: ids.join('\n'));
    final isPerson = identical(ids, _personalIds);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nomes e documentos · $group'),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 8,
            autofocus: true,
            decoration: InputDecoration(
              hintText: isPerson
                  ? 'Maria Souza Lima\nMaria Lima\n123.456.789'
                  : 'Padaria Exemplo Ltda\n12.345.678/0001-90\n12.345.678',
              helperText:
                  'Um por linha, como aparecem nos extratos'
                  '${isPerson ? ': seu nome completo e abreviado e o começo '
                            'do CPF' : ': a razão social e o CNPJ'}. Um Pix '
                  'entre contas suas com esses textos entra marcado "Entre '
                  'contas" e só aparece quando um dos lados está desligado. '
                  'Nome precisa abrir o nome ("Maria Lima" não pega "Ana '
                  'Maria Lima"); CPF/CNPJ vale em qualquer lugar.',
              helperMaxLines: 8,
              border: const OutlineInputBorder(),
            ),
          ),
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
    );
    final text = controller.text;
    controller.dispose();
    if (ok != true) return;
    ids
      ..clear()
      ..addAll(
        text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
    await _saveCompanies();
  }

  Future<void> _setShown(Iterable<String> banks, bool shown) async {
    await MoneyAccounts.setHidden(banks, !shown);
    setState(() {});
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _newCompany({String? withBank}) async {
    final name = (await _askName('Nova empresa'))?.trim();
    if (name == null || name.isEmpty) return;
    _companies.add(Company(name, [?withBank]));
    if (withBank != null) _removeFromOthers(withBank, keep: _companies.last);
    await _saveCompanies();
  }

  void _removeFromOthers(String bank, {Company? keep}) {
    for (final company in _companies) {
      if (identical(company, keep)) continue;
      company.banks.removeWhere((b) => b.toLowerCase() == bank.toLowerCase());
    }
  }

  Future<void> _openTaxes(Company company) async {
    // The taxes keep their own copy of the companies: save this one first.
    await MoneyAccounts.saveCompanies(_companies);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FiscalPage(companyName: company.name)),
    );
    await _load();
  }

  Future<void> _companyMenu(Company company) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renomear'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Excluir empresa'),
              subtitle: const Text('As contas dela voltam para Pessoal'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'rename') {
      final name = (await _askName(
        'Renomear empresa',
        initial: company.name,
      ))?.trim();
      if (name == null || name.isEmpty) return;
      company.name = name;
      await _saveCompanies();
    } else if (choice == 'delete') {
      _companies.remove(company);
      _personalIds.addAll(company.ids);
      await _saveCompanies();
    }
  }

  Future<void> _moveMenu(String bank) async {
    final current = MoneyAccounts.companyOf(bank, _companies);
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Mover $bank para',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Pessoal'),
              selected: current == null,
              onTap: () => Navigator.pop(context, 'pessoal'),
            ),
            for (final company in _companies)
              ListTile(
                leading: const Icon(Icons.business_outlined),
                title: Text(company.name),
                selected: identical(company, current),
                onTap: () => Navigator.pop(context, company),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Nova empresa…'),
              onTap: () => Navigator.pop(context, 'nova'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'nova') return _newCompany(withBank: bank);
    if (choice == 'pessoal') {
      _removeFromOthers(bank);
    } else if (choice is Company && !identical(choice, current)) {
      _removeFromOthers(bank, keep: choice);
      choice.banks.add(bank);
    }
    await _saveCompanies();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: !_loaded
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    child: Text('Contas', style: theme.textTheme.titleLarge),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      'O Extrato mostra só as contas ligadas.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  ..._group(
                    title: 'Pessoal',
                    icon: Icons.person_outline,
                    banks: _personal,
                    ids: _personalIds,
                  ),
                  for (final company in _companies)
                    ..._group(
                      title: company.name,
                      icon: Icons.business_outlined,
                      banks: company.banks,
                      ids: company.ids,
                      onMenu: () => _companyMenu(company),
                      onOpen: () => _openTaxes(company),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _newCompany(),
                        icon: const Icon(Icons.add),
                        label: const Text('Nova empresa'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _group({
    required String title,
    required IconData icon,
    required List<String> banks,
    required List<String> ids,
    VoidCallback? onMenu,
    VoidCallback? onOpen,
  }) {
    final anyShown = banks.any((b) => !MoneyAccounts.isHidden(b));
    return [
      const Divider(height: 8),
      ListTile(
        leading: Icon(icon),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: onOpen == null ? null : const Text('Impostos, notas e Fator R'),
        onTap: onOpen ?? onMenu,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onMenu != null)
              IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Opções da empresa',
                onPressed: onMenu,
              ),
            Switch(
              value: banks.isNotEmpty && anyShown,
              onChanged: banks.isEmpty ? null : (v) => _setShown(banks, v),
            ),
          ],
        ),
      ),
      ListTile(
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        leading: const Icon(Icons.badge_outlined),
        title: const Text('Nomes e documentos'),
        subtitle: Text(
          ids.isEmpty
              ? 'Nenhum: Pix entre suas contas não é reconhecido'
              : ids.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editIds(title, ids),
      ),
      if (banks.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(72, 0, 24, 8),
          child: Text('Nenhuma conta. Mova uma conta para cá.'),
        ),
      for (final bank in banks) _account(bank),
    ];
  }

  Widget _account(String bank) {
    final known = KnownTag.of(bank);
    final isNoBank = bank == MoneyAccounts.noBank;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: isNoBank || known == null
          ? const Icon(Icons.payments_outlined)
          : BankMark(known, size: 28),
      title: Text(isNoBank ? 'Sem banco' : bank),
      subtitle: isNoBank
          ? const Text('Dinheiro, caixinhas e lançamentos à mão')
          : null,
      onLongPress: isNoBank ? null : () => _moveMenu(bank),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isNoBank)
            IconButton(
              icon: const Icon(Icons.drive_file_move_outline),
              tooltip: 'Mover para outra empresa',
              onPressed: () => _moveMenu(bank),
            ),
          Switch(
            value: !MoneyAccounts.isHidden(bank),
            onChanged: (v) => _setShown([bank], v),
          ),
        ],
      ),
    );
  }
}
