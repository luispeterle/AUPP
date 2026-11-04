import 'package:flutter/material.dart';
import 'package:aupp/desktop/asset-workspaces.dart';

/// What the app's internal browser keeps on this computer: cookies and other
/// data of each site. Deleting it logs out of that site.
class SiteDataPage extends StatefulWidget {
  const SiteDataPage({super.key});

  @override
  State<SiteDataPage> createState() => _SiteDataPageState();
}

class _SiteDataPageState extends State<SiteDataPage> {
  final _workspaces = AssetWorkspaces.instance;
  List<String>? _sites;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sites = await _workspaces.siteData();
      if (mounted) setState(() => _sites = sites);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _remove(String site) async {
    await _workspaces.removeSiteData(site);
    await _load();
  }

  Future<void> _clear() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar tudo?'),
        content: const Text(
          'Apaga os cookies e os dados de todos os sites deste navegador, e '
          'você precisará entrar neles de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await _workspaces.clearSiteData();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sites = _sites;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navegador interno'),
        actions: [
          TextButton(
            onPressed: sites == null || sites.isEmpty ? null : _clear,
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
      body: _failed
          ? const Center(child: Text('Não foi possível ler os dados dos sites.'))
          : sites == null
          ? const Center(child: CircularProgressIndicator())
          : sites.isEmpty
          ? const Center(child: Text('Nenhum site guardou dados.'))
          : ListView(
              children: [
                for (final site in sites)
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: Text(site),
                    trailing: IconButton(
                      tooltip: 'Apagar os dados de $site',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(site),
                    ),
                  ),
              ],
            ),
    );
  }
}
