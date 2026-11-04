import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' show join;
import 'package:aupp/helpers/alert-dialog-builder.dart';
import 'package:aupp/services/database-directory-service.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/clickable-customization-item.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// Where the database file lives (desktop only). Applies on the next start.
class DatabaseFolderPage extends StatefulWidget {
  const DatabaseFolderPage({super.key});

  @override
  State<DatabaseFolderPage> createState() => _DatabaseFolderPageState();
}

class _DatabaseFolderPageState extends State<DatabaseFolderPage> {
  String? _folder;
  bool _isCustom = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folder = await SqliteDatabase.getDatabaseDirectory();
    if (!mounted) return;
    setState(() {
      _folder = folder;
      _isCustom = (ServiceConfig.sharedPreferences!
                  .getString(PreferencesKeys.databaseFolderPath) ??
              '')
          .isNotEmpty;
    });
  }

  Future<void> _askToRestart() async {
    await _load();
    if (!mounted) return;
    final dialog = AlertDialogBuilder('Reinicialização necessária')
        .addSubtitle(
            'Feche e reabra o aplicativo para usar o novo local do banco de dados')
        .addTrueButtonName('OK');
    await showDialog(context: context, builder: dialog.build);
  }

  /// The current database is copied over unless the target already holds one,
  /// which is then kept and used.
  Future<void> _change() async {
    final picked = await DatabaseDirectoryService.pickDirectory();
    if (picked == null || !mounted) return;
    final targetHasDb =
        await File(join(picked, SqliteDatabase.databaseFileName)).exists();
    if (!mounted) return;
    final dialog = AlertDialogBuilder('Alterar a pasta do banco de dados')
        .addSubtitle(targetHasDb
            ? 'A pasta já contém um banco de dados, que será usado daqui em diante. Reinicie o aplicativo para aplicar a alteração. Nunca abra o mesmo banco de dados em dois aplicativos ao mesmo tempo.'
            : 'O banco de dados atual será copiado para a nova pasta. Reinicie o aplicativo para aplicar a alteração. Nunca abra o mesmo banco de dados em dois aplicativos ao mesmo tempo.')
        .addTrueButtonName('Alterar pasta')
        .addFalseButtonName('Cancelar');
    final proceed = await showDialog(context: context, builder: dialog.build);
    if (proceed != true || !mounted) return;
    if (!targetHasDb && !await SqliteDatabase.relocateDatabase(picked)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Não foi possível mover o banco de dados para a pasta selecionada'),
        ));
      }
      return;
    }
    await ServiceConfig.sharedPreferences!
        .setString(PreferencesKeys.databaseFolderPath, picked);
    await _askToRestart();
  }

  Future<void> _reset() async {
    await ServiceConfig.sharedPreferences!
        .remove(PreferencesKeys.databaseFolderPath);
    await _askToRestart();
  }

  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    return Scaffold(
      appBar: AppBar(title: Text('Pasta do banco de dados')),
      body: folder == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ClickableCustomizationItem(
                  title: 'Pasta do banco de dados',
                  subtitle: folder,
                  enabled: true,
                  onTap: _change,
                ),
                if (_isCustom)
                  ClickableCustomizationItem(
                    title: 'Usar o local padrão',
                    subtitle: 'Voltar para a pasta interna do aplicativo',
                    enabled: true,
                    onTap: _reset,
                  ),
              ],
            ),
    );
  }
}
