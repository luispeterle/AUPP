import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:aupp/accounts/accounts-sheet.dart';
import 'package:aupp/investments/brapi-api.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/sync-extensions.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:aupp/settings/preferences-utils.dart';
import 'package:aupp/settings/settings-item.dart';
import 'package:aupp/settings/style.dart';

import 'dinzo-api.dart';
import 'dinzo-config.dart';
import 'dinzo-models.dart';
import 'dinzo-rate-limit.dart';
import 'dinzo-sync-history-page.dart';
import 'dinzo-sync-page.dart';
import 'dinzo-sync-service.dart';
import 'daily-banks-page.dart';

/// Dinzo integration settings (pt-BR only: fork-only screen).
class DinzoSettingsPage extends StatefulWidget {
  const DinzoSettingsPage({Key? key}) : super(key: key);

  @override
  State<DinzoSettingsPage> createState() => _DinzoSettingsPageState();
}

class _DinzoSettingsPageState extends State<DinzoSettingsPage> {
  late DinzoConfig _config;

  /// Redraws the request counter as the last minute rolls by.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _config = DinzoSyncService.loadConfig();
    _tick = Timer.periodic(
      const Duration(seconds: 5),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Requests sent from this device against Dinzo's limits.
  Widget _requestsTile() {
    final minute = DinzoRateLimiter.lastMinute;
    final day = DinzoRateLimiter.last24h;
    final server = DinzoRateLimiter.serverRemaining;
    final blocked = DinzoRateLimiter.blockedUntil;
    final isBlocked = blocked != null && blocked.isAfter(DateTime.now());
    final lastSync = DinzoSyncService.lastSync;
    final theme = Theme.of(context);
    Widget bar(String label, int used, int limit, {int? appLimit}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: $used / $limit'
            '${appLimit == null ? '' : ' (app para em $appLimit)'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: (used / limit).clamp(0.0, 1.0),
            color: used >= (appLimit ?? limit) * 0.9
                ? Colors.orange
                : theme.colorScheme.primary,
          ),
        ],
      ),
    );
    return SettingsItem(
      icon: Icon(isBlocked ? Icons.block : Icons.speed, color: Colors.white),
      iconBackgroundColor:
          isBlocked ? theme.colorScheme.error : Colors.blueGrey.shade600,
      title: 'Requisições à Dinzo',
      subtitle:
          'Última sincronização: '
          '${lastSync == null ? 'nunca' : DateFormat('dd/MM/yyyy HH:mm').format(lastSync)}'
          ' · toque para ver o histórico',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DinzoSyncHistoryPage()),
      ),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(
            'Último minuto',
            minute,
            DinzoRateLimiter.serverPerMinute,
            appLimit: DinzoRateLimiter.perMinute,
          ),
          bar('Últimas 24 h', day, DinzoRateLimiter.serverPerDay),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [
                if (isBlocked)
                  '⛔ Cota diária esgotada: libera às '
                      '${DateFormat('HH:mm').format(blocked)}',
                if (server != null)
                  'Na última resposta a Dinzo tinha $server livres no '
                      'minuto (conta qualquer aparelho)',
                'Contagem deste aparelho; a cota diária é por chave.',
              ].join('\n'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() => DinzoSyncService.saveConfig(_config);

  Future<void> _editKey() async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chave da API'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'dz_live_...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Remover'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (key == null) return;
    if (key.isNotEmpty && !key.trim().startsWith('dz_live_')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A chave da Dinzo começa com dz_live_')),
      );
      return;
    }
    await DinzoSyncService.setApiKey(key);
    setState(() {});
    // The Dinzo is optional: connecting it (first key) starts the first,
    // full sync right here.
    if (key.isNotEmpty && DinzoSyncService.lastSync == null && mounted) {
      await _save();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DinzoSyncPage()),
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _editBrapiKey() async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chave da brapi.dev'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autocorrect: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Remover'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (key == null) return;
    await BrapiApi.setKey(key);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = DinzoSyncService.apiKey != null;
    return PopScope(
      onPopInvokedWithResult: (_, __) => _save(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Integrações com API')),
        body: ListView(
          children: [
            SettingsItem(
              icon: const Icon(Icons.key, color: Colors.white),
              iconBackgroundColor: Colors.deepPurple.shade400,
              title: 'Chave da Dinzo',
              subtitle: hasKey ? 'Configurada' : 'Não configurada',
              onPressed: _editKey,
            ),
            SettingsItem(
              icon: const Icon(Icons.show_chart, color: Colors.white),
              iconBackgroundColor: Colors.green.shade600,
              title: 'Chave da brapi.dev',
              subtitle: BrapiApi.key != null
                  ? 'Configurada'
                  : 'Não configurada: sem ela, a B3 fica sem cotação',
              onPressed: _editBrapiKey,
            ),
            for (final extension in SyncExtensions.all)
              extension.settingsSection(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'As chaves ficam só neste aparelho, fora dos backups.',
                style: subtitleTextStyle,
              ),
            ),
            const Divider(),
            SettingsItem(
              icon: const Icon(Icons.account_balance, color: Colors.white),
              iconBackgroundColor: Colors.indigo.shade400,
              title: 'Bancos do dia a dia',
              subtitle: 'O que está nos outros é investimento',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DailyBanksPage()),
              ),
            ),
            SettingsItem(
              icon: const Icon(Icons.person, color: Colors.white),
              iconBackgroundColor: Colors.teal.shade600,
              title: 'Contas e empresas',
              subtitle: 'Suas contas e as de cada empresa, com nomes e '
                  'documentos de cada uma',
              onPressed: () async {
                await _save();
                if (!mounted) return;
                await AccountsSheet.show(context);
                // The sheet saved the names and documents into the config.
                _config.selfIdentifiers =
                    DinzoSyncService.loadConfig().selfIdentifiers;
                if (mounted) setState(() {});
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Dinzo',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            SettingsItem(
              icon: const Icon(Icons.history, color: Colors.white),
              iconBackgroundColor: Colors.blue.shade600,
              title: 'Sincronizar tudo de novo',
              subtitle: 'Busca todo o histórico e os investimentos; você '
                  'confere antes de gravar',
              onPressed: DinzoSyncService.apiKey == null
                  ? null
                  : () async {
                      await _save();
                      if (!mounted) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DinzoSyncPage(full: true),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
            ),
            ValueListenableBuilder<int>(
              valueListenable: DinzoRateLimiter.changes,
              builder: (_, __, ___) => _requestsTile(),
            ),
            SettingsItem(
              icon: const Icon(Icons.block, color: Colors.white),
              iconBackgroundColor: Colors.grey.shade600,
              title: 'Lançamentos ignorados',
              subtitle:
                  '${_config.ignoredIds.length} ignorados · para reativar, '
                  'toque neles na tela de sincronização',
              onPressed: null,
            ),
            SettingsItem(
              icon: const Icon(Icons.category, color: Colors.white),
              iconBackgroundColor: Colors.indigo.shade500,
              title: 'Categorias da Dinzo → AUPP',
              subtitle: '${_config.categoryMap.length} mapeadas',
              onPressed: () async {
                await _save();
                if (!mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DinzoCategoryMapPage(config: _config),
                  ),
                );
                await _save();
                setState(() {});
              },
            ),
            SettingsItem(
              icon: const Icon(Icons.storefront, color: Colors.white),
              iconBackgroundColor: Colors.pink.shade600,
              title: 'Regras por estabelecimento',
              subtitle: '${_config.merchantRules.length} regras',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _MerchantRulesPage(config: _config),
                  ),
                );
                await _save();
                setState(() {});
              },
            ),
            SettingsSwitchItem(
              icon: const Icon(Icons.edit_note, color: Colors.white),
              iconBackgroundColor: Colors.orange.shade600,
              title: 'Permitir lançamentos manuais',
              subtitle:
                  'Desligado: os lançamentos reais vêm só da Dinzo e um '
                  'lançamento avulso adicionado aqui vira estimativa. '
                  'Recorrentes (ex.: vale-alimentação) e transferências entre '
                  'carteiras continuam normais.',
              value:
                  PreferencesUtils.getOrDefault<bool>(
                    ServiceConfig.sharedPreferences!,
                    PreferencesKeys.allowManualRecords,
                  ) ??
                  true,
              onChanged: (v) async {
                await ServiceConfig.sharedPreferences!.setBool(
                  PreferencesKeys.allowManualRecords,
                  v,
                );
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps each Dinzo category, per direction, to an AUPP category. A parent
/// mapping covers its subcategories unless they have their own.
class DinzoCategoryMapPage extends StatefulWidget {
  final DinzoConfig config;

  const DinzoCategoryMapPage({Key? key, required this.config})
    : super(key: key);

  @override
  State<DinzoCategoryMapPage> createState() => _DinzoCategoryMapPageState();
}

class _DinzoCategoryMapPageState extends State<DinzoCategoryMapPage> {
  List<DinzoCategory>? _dinzo;
  List<Category> _aupp = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = DinzoSyncService.apiKey;
    if (key == null) {
      setState(() => _error = 'Configure a chave da API primeiro.');
      return;
    }
    final api = DinzoApi(key);
    try {
      final dinzo = await api.categories();
      final aupp = await ServiceConfig.database.getAllCategories();
      if (!mounted) return;
      setState(() {
        _aupp =
            aupp.whereType<Category>().where((c) => !c.isArchived).toList()
              ..sort((a, b) => a.name!.compareTo(b.name!));
        _dinzo = _treeOrder(dinzo);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Erro ao buscar categorias: $e');
    } finally {
      api.close();
    }
  }

  List<DinzoCategory> _treeOrder(List<DinzoCategory> all) {
    final roots = all.where((c) => c.parentId == null).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return [
      for (final root in roots) ...[
        root,
        ...(all.where((c) => c.parentId == root.id).toList()
          ..sort((a, b) => a.title.compareTo(b.title))),
      ],
    ];
  }

  Future<void> _pick(DinzoCategory dinzo, CategoryType type) async {
    final key = DinzoConfig.categoryKey(dinzo.id, type);
    final options = _aupp.where((c) => c.categoryType == type).toList();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                '${dinzo.title} (${type == CategoryType.expense ? 'despesa' : 'receita'})',
              ),
              subtitle: const Text('Escolha a categoria do AUPP'),
            ),
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Sem mapeamento'),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final c in options)
              ListTile(
                title: Text(c.name!),
                onTap: () => Navigator.pop(context, c.name),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      if (chosen.isEmpty) {
        widget.config.categoryMap.remove(key);
      } else {
        widget.config.categoryMap[key] = chosen;
      }
    });
    await DinzoSyncService.saveConfig(widget.config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias da Dinzo')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _dinzo == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _dinzo!.length,
              itemBuilder: (context, i) {
                final c = _dinzo![i];
                final child = c.parentId != null;
                String? mapped(CategoryType t) =>
                    widget.config.categoryMap[DinzoConfig.categoryKey(c.id, t)];
                return ListTile(
                  dense: child,
                  contentPadding: EdgeInsets.only(
                    left: child ? 40 : 16,
                    right: 8,
                  ),
                  title: Text(
                    c.title,
                    style: child
                        ? null
                        : const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Wrap(
                    spacing: 6,
                    children: [
                      for (final t in [
                        CategoryType.expense,
                        CategoryType.income,
                      ])
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            t == CategoryType.expense
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 16,
                          ),
                          label: Text(mapped(t) ?? (child ? 'herda' : '—')),
                          onPressed: () => _pick(c, t),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _MerchantRulesPage extends StatefulWidget {
  final DinzoConfig config;

  const _MerchantRulesPage({required this.config});

  @override
  State<_MerchantRulesPage> createState() => _MerchantRulesPageState();
}

class _MerchantRulesPageState extends State<_MerchantRulesPage> {
  @override
  Widget build(BuildContext context) {
    final rules = widget.config.merchantRules.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Scaffold(
      appBar: AppBar(title: const Text('Regras por estabelecimento')),
      body: rules.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma regra ainda. Ao editar um lançamento na '
                  'sincronização, marque "Lembrar para..." para criar uma.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final rule in rules)
                  ListTile(
                    title: Text(rule.key),
                    subtitle: Text(
                      [
                        rule.value.categoryName ?? 'categoria da Dinzo',
                        if (rule.value.walletId != null)
                          'carteira #${rule.value.walletId}',
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        setState(
                          () => widget.config.merchantRules.remove(rule.key),
                        );
                        await DinzoSyncService.saveConfig(widget.config);
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
