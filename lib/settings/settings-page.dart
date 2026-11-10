import 'package:aupp/hybrid_sync/hybrid-sync-page.dart';
import 'package:aupp/budget_plan/budget-plan-page.dart';
import 'package:aupp/categories/categories-tab-page-edit.dart';
import 'package:aupp/disguise/disguise-settings-page.dart';
import 'package:aupp/dinzo/welcome-page.dart';

import 'package:flutter/material.dart';
import 'package:aupp/desktop/asset-workspaces.dart';
import 'package:aupp/desktop/site-data-page.dart';
import 'package:aupp/recurrent_record_patterns/patterns-page-view.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/home-widget-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/database-directory-service.dart';
import 'package:aupp/settings/backup-page.dart';
import 'package:aupp/settings/database-folder-page.dart';
import 'package:aupp/settings/home-widgets-page.dart';
import 'package:aupp/settings/settings-item.dart';
import 'package:aupp/tags/tags-page-view.dart';

import 'integrations-item.dart';

// look here for how to store settings

class TabSettings extends StatelessWidget {

  final DatabaseInterface database = ServiceConfig.database;

  goToRecurrentRecordPage(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PatternsPageView()),
    );
  }

  goToTagsPage(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TagsPageView()),
    );
  }

  goToDatabaseFolderPage(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DatabaseFolderPage()),
    );
  }

  goToHomeWidgetsPage(BuildContext context) async {
    if (!HomeWidgetService.isSupported) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HomeWidgetsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        child: Scaffold(
      appBar: AppBar(
        title: Text('Ajustes'),
      ),
      body: ListView(
        children: <Widget>[
          SettingsItem(
              icon: Icon(
                Icons.waving_hand,
                color: Colors.white,
              ),
              iconBackgroundColor: Colors.amber.shade700,
              title: 'Como o app funciona',
              subtitle: 'Rever a apresentação',
              onPressed: () async => await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WelcomePage()))),
          Divider(),
          const IntegrationsItem(),
          SettingsItem(
              icon: Icon(
                Icons.devices,
                color: Colors.white,
              ),
              iconBackgroundColor: Colors.indigo.shade400,
              title: 'Celular e computador',
              subtitle: 'Mesmos dados nos dois, pelo Syncthing',
              onPressed: () async => await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const HybridSyncPage()))),
          if (DatabaseDirectoryService.isSupported)
            SettingsItem(
                icon: Icon(
                  Icons.folder,
                  color: Colors.white,
                ),
                iconBackgroundColor: Colors.blue.shade600,
                title: 'Pasta do banco de dados',
                subtitle: 'Onde o banco de dados fica',
                onPressed: () async => await goToDatabaseFolderPage(context)),
          if (HomeWidgetService.isSupported)
            SettingsItem(
                icon: Icon(
                  Icons.widgets,
                  color: Colors.white,
                ),
                iconBackgroundColor: Colors.teal.shade600,
                title: 'Widgets da tela inicial',
                subtitle: 'Totais na tela inicial do celular',
                onPressed: () async => await goToHomeWidgetsPage(context)),
          Divider(),
          SettingsItem(
              icon: Icon(
                Icons.savings,
                color: Colors.white,
              ),
              iconBackgroundColor: Colors.green.shade600,
              title: 'Orçamento',
              subtitle: 'Como dividir a receita do mês',
              onPressed: () async => await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BudgetPlanPage()))),
          SettingsItem(
              icon: Icon(
                Icons.repeat,
                color: Colors.white,
              ),
              iconBackgroundColor: Colors.pink.shade600,
              title: 'Itens Recorrentes',
              subtitle: 'Ver ou excluir Itens recorrentes',
              onPressed: () async => await goToRecurrentRecordPage(context)),
          SettingsItem(
              icon: Icon(
                Icons.category,
                color: Colors.white,
              ),
              iconBackgroundColor: Colors.indigo.shade500,
              title: 'Categorias',
              subtitle: 'Categorias de despesas e receitas',
              onPressed: () async => await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TabCategories()))),
          SettingsItem(
              icon: Icon(
                Icons.tag,
                color: Colors.white,
              ),
              iconBackgroundColor: Colors.amber.shade600,
              title: 'Etiquetas',
              subtitle: 'Gerencie suas tags existentes',
              onPressed: () async => await goToTagsPage(context)),
          Divider(),
          SettingsItem(
              icon: Icon(
                Icons.calculate,
                color: Colors.white,
              ),
              iconBackgroundColor: Colors.amber.shade800,
              title: 'Disfarce e demonstração',
              subtitle: 'Abrir como calculadora, modo demonstração',
              onPressed: () async => await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DisguiseSettingsPage()))),
          if (AssetWorkspaces.instance.supported)
            SettingsItem(
                icon: Icon(
                  Icons.public,
                  color: Colors.white,
                ),
                iconBackgroundColor: Colors.blueGrey.shade600,
                title: 'Navegador interno',
                subtitle: 'Apagar cookies e dados dos sites',
                onPressed: () async => await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SiteDataPage()))),
          SettingsItem(
              icon: Icon(
                Icons.backup,
                color: Colors.white,
              ),
              iconBackgroundColor: Colors.orange.shade600,
              title: 'Backup',
              subtitle: 'Exportar ou restaurar todos os dados',
              onPressed: () async => await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BackupPage()))),
        ],
      ),
    ));
  }
}
