import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Moves the data of a computer from the folders of the app's old name.
///
/// Runs before anything opens them. A failure stops the start: opening without
/// the data would look like a brand-new installation. Android has nothing to
/// move: the new id is another app, and its data arrives through the sync.
class LegacyData {
  static Future<void> migrate() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    final documents = await getApplicationDocumentsDirectory();
    await move(join(documents.path, 'oinkoin'), join(documents.path, 'aupp'));
    if (!Platform.isLinux) return;
    final support = await getApplicationSupportDirectory();
    await move(
      join(support.parent.path, 'com.github.emavgl.oinkoin'),
      support.path,
    );
    final config = Platform.environment['XDG_CONFIG_HOME'] ??
        join(Platform.environment['HOME'] ?? '', '.config');
    final window = File(join(config, 'oinkoin-window.ini'));
    final newWindow = File(join(config, 'aupp-window.ini'));
    if (await window.exists() && !await newWindow.exists()) {
      await window.rename(newWindow.path);
    }
  }

  /// A destination with anything in it wins, and the old folder stays intact.
  /// An empty one is what the plugins create on their own.
  @visibleForTesting
  static Future<void> move(String from, String to) async {
    final old = Directory(from);
    if (!await old.exists()) return;
    final target = Directory(to);
    if (await target.exists()) {
      if (!await target.list().isEmpty) return;
      await target.delete();
    }
    await old.rename(to);
  }
}
