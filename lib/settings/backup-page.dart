import 'package:flutter/material.dart';
import 'package:path/path.dart' show basename;
import 'package:path_provider/path_provider.dart';
import 'package:aupp/services/backup-service.dart';
import 'package:aupp/services/platform-file-service.dart';
import 'package:aupp/settings/backup-restore-dialogs.dart';
import 'package:aupp/settings/settings-item.dart';

/// Configurações → Backup: exporting and restoring in one place.
class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _export() async {
    final dir = await getTemporaryDirectory();
    final file = await BackupService.createJsonBackupFile(
      backupFileName: await BackupService.generateBackupFileName(),
      directoryPath: dir.path,
    );
    await PlatformFileService.shareOrSaveFile(
      filePath: file.path,
      suggestedName: basename(file.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        children: [
          SettingsItem(
            icon: const Icon(Icons.backup, color: Colors.white),
            iconBackgroundColor: Colors.orange.shade600,
            title: 'Exportar backup',
            subtitle: 'Gera um arquivo com todos os dados',
            onPressed: _export,
          ),
          SettingsItem(
            icon: const Icon(Icons.restore_page, color: Colors.white),
            iconBackgroundColor: Colors.teal,
            title: 'Restaurar backup',
            subtitle: 'Restaurar dados de um arquivo de backup. Depois, o '
                'primeiro sync da Dinzo é o completo.',
            onPressed: () => BackupRestoreDialog.importFromBackupFile(context),
          ),
        ],
      ),
    );
  }
}
