import 'dart:developer';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:future_progress_dialog/future_progress_dialog.dart';

import '../helpers/alert-dialog-builder.dart';
import '../services/backup-service.dart';

class BackupRestoreDialog {

  static Future<void> importFromBackupFile(BuildContext context) async {
    try {
      FilePicker.clearTemporaryFiles();
      log("FilePicker temporary cache cleared");
    } catch (e) {
      log("FilePicker.clearTemporaryFiles() not implemented on this platform");
    }
    List<PlatformFile> result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
    } catch (e) {
      // strange issue on android-9 due to filter
      result = await FilePicker.pickFiles();
    }
    if (result.isNotEmpty && result.single.path != null) {
      File file = File(result.single.path!);
      bool successful = await showDialog(
        context: context,
        builder: (context) => FutureProgressDialog(
          BackupService.importDataFromBackupFile(file),
        ),
      );
      if (successful) {
        await showBackupRestoreDialog(
          context,
          'Restauração bem-sucedida',
          'Os dados do arquivo de backup foram restaurados.',
        );
      } else {
        await showBackupRestoreDialog(
          context,
          'Erro ao Restaurar',
          'Certifique-se de que você tem a versão mais recente do aplicativo. Nesse caso, o arquivo de backup pode estar corrompido.',
        );
      }
    } else {
      // User has canceled the picker
      log("User canceled file picking");
    }
  }

  static Future<void> showBackupRestoreDialog(
    BuildContext context,
    String title,
    String subtitle,
  ) async {
    AlertDialogBuilder resultDialog = AlertDialogBuilder(title)
        .addSubtitle(subtitle)
        .addTrueButtonName('OK');
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return resultDialog.build(context);
      },
    );
  }
}
