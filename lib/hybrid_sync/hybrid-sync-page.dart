import 'package:flutter/material.dart';
import 'package:aupp/hybrid_sync/change-log-page.dart';
import 'package:aupp/hybrid_sync/hybrid-sync-core.dart';
import 'package:aupp/hybrid_sync/hybrid-sync.dart';
import 'package:aupp/services/backup-directory-service.dart';

/// Another device has data to replace this one's: one of them wins, and the
/// other stays as `.old`.
Future<void> showHybridConflictDialog(
  BuildContext context,
  SnapshotHeader remote, {
  bool bothChanged = true,
}) async {
  final useRemote = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        bothChanged ? 'Mudanças nos dois aparelhos' : 'Dados mais novos',
      ),
      content: Text(
        '${bothChanged ? 'Este aparelho e ${HybridSync.describe(remote)} '
                  'mudaram os dados e não dá para juntar os dois.' : '${HybridSync.describe(remote)} enviou dados mais novos que os deste '
                  'aparelho.'} Escolha qual fica.\n\n'
        'Usar de ${remote.device}: os dados daqui ficam guardados como .old '
        'neste aparelho.\n'
        'Manter os daqui: os de ${remote.device} ficam guardados como .old na '
        'pasta, e os daqui vão para lá.\n\n'
        'Dá para voltar em "Celular e computador". Lançamentos dos syncs '
        'automáticos voltam na próxima sincronização.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Decidir depois'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Manter os daqui'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Usar de ${remote.device}'),
        ),
      ],
    ),
  );
  if (useRemote == true) {
    await HybridSync.useRemote();
  } else if (useRemote == false) {
    await HybridSync.keepLocal();
  }
}

/// Configurações → Celular e computador.
class HybridSyncPage extends StatefulWidget {
  const HybridSyncPage({super.key});

  @override
  State<HybridSyncPage> createState() => _HybridSyncPageState();
}

class _HybridSyncPageState extends State<HybridSyncPage> {
  final _password = TextEditingController();
  String? _path;
  String? _uri;
  String? _error;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _path = HybridSync.folderPath;
    _uri = HybridSync.folderUri;
    _password.text = HybridSync.password ?? '';
    if (HybridSync.enabled) HybridSync.check();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final pick = await BackupDirectoryService.pickDirectory(
      initialFolder: 'Syncthing/AUPP',
    );
    if (!mounted) return;
    setState(() {
      switch (pick.outcome) {
        case BackupDirectoryPickOutcome.success:
          _path = pick.path;
          _uri = pick.uri;
          _error = null;
        case BackupDirectoryPickOutcome.notWritable:
          _error = 'O app não consegue gravar nessa pasta.';
        case BackupDirectoryPickOutcome.cancelled:
          break;
      }
    });
  }

  Future<void> _save() async {
    if (_path == null) {
      setState(() => _error = 'Escolha a pasta.');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'Use uma senha com pelo menos 8 caracteres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await HybridSync.configure(
      path: _path!,
      uri: _uri,
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    final remote = HybridSync.conflict.value;
    if (error == null && remote != null) {
      await showHybridConflictDialog(context, remote);
    }
  }

  Future<void> _disable() async {
    await HybridSync.disable();
    if (!mounted) return;
    setState(() {
      _path = null;
      _uri = null;
      _password.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Celular e computador')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Mantém este aparelho e o outro com os mesmos dados, por um arquivo '
            'criptografado numa pasta do Syncthing. Use a mesma pasta e a mesma '
            'senha nos dois. O que muda em cada aparelho se junta sozinho, sem '
            'perguntar: só pergunta na primeira vez, quando ainda não sabe o '
            'que cada um tinha. A chave da Dinzo e outros logins não vão no '
            'arquivo: configure em cada aparelho.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Pasta'),
            subtitle: Text(_path ?? 'Nenhuma escolhida'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _pickFolder,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Senha do arquivo',
              helperText:
                  'Sem ela ninguém lê o arquivo, nem você: não há como recuperar.',
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(HybridSync.enabled ? 'Salvar e sincronizar' : 'Ativar'),
          ),
          if (HybridSync.enabled)
            TextButton(
              onPressed: _busy ? null : _disable,
              child: const Text('Desativar neste aparelho'),
            ),
          const SizedBox(height: 16),
          ValueListenableBuilder<String?>(
            valueListenable: HybridSync.lastEvent,
            builder: (context, event, _) => event == null
                ? const SizedBox.shrink()
                : ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: const Text('Último evento'),
                    subtitle: Text(event),
                  ),
          ),
          if (HybridSync.enabled) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore),
              title: const Text('Backups diários'),
              subtitle: const Text(
                'Um por dia em cada aparelho, na mesma pasta e com a mesma '
                'senha. Ficam 90 dias, e os 10 últimos nunca são apagados.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const _BackupsDialog(),
              ),
            ),
          ],
          if (HybridSync.enabled) const _OldVersions(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.manage_history),
            title: const Text('Histórico de alterações'),
            subtitle: const Text(
              'O que foi mudado à mão, em cada aparelho. Fica 1 ano, e as 500 '
              'últimas nunca são apagadas.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangeLogPage()),
            ),
          ),
          ValueListenableBuilder<SnapshotHeader?>(
            valueListenable: HybridSync.incoming,
            builder: (context, remote, _) => remote == null
                ? const SizedBox.shrink()
                : ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sync_problem),
                    title: const Text('Dados mais novos'),
                    subtitle: Text(HybridSync.describe(remote)),
                    onTap: () => showHybridConflictDialog(
                      context,
                      remote,
                      bothChanged: false,
                    ),
                  ),
          ),
          ValueListenableBuilder<SnapshotHeader?>(
            valueListenable: HybridSync.conflict,
            builder: (context, remote, _) => remote == null
                ? const SizedBox.shrink()
                : ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.warning_amber,
                      color: theme.colorScheme.error,
                    ),
                    title: const Text('Mudanças nos dois aparelhos'),
                    subtitle: Text(HybridSync.describe(remote)),
                    onTap: () => showHybridConflictDialog(context, remote),
                  ),
          ),
        ],
      ),
    );
  }
}

/// What lost the last choice between devices, to go back to it.
class _OldVersions extends StatelessWidget {
  const _OldVersions();

  Future<void> _confirm(
    BuildContext context,
    String title,
    Future<void> Function() restore,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Os dados deste aparelho viram .old e o app reinicia. Depois essa '
          'versão vai também para os outros aparelhos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Voltar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await restore();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(DateTime?, bool)>(
      future: (() async => (
        await HybridSync.oldDataDate(),
        await HybridSync.hasRemoteOld(),
      ))(),
      builder: (context, snapshot) {
        final (local, remote) = snapshot.data ?? (null, false);
        return Column(
          children: [
            if (local != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.undo),
                title: const Text('Voltar para a versão anterior deste aparelho'),
                subtitle: Text('.old de ${HybridSync.clockText(local)}'),
                onTap: () => _confirm(
                  context,
                  'Voltar para a versão anterior?',
                  HybridSync.restoreOld,
                ),
              ),
            if (remote)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.undo),
                title: const Text('Voltar para a versão substituída na pasta'),
                subtitle: const Text(HybridSync.remoteOldName),
                onTap: () => _confirm(
                  context,
                  'Voltar para a versão da pasta?',
                  HybridSync.restoreRemoteOld,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BackupsDialog extends StatelessWidget {
  const _BackupsDialog();

  static String _day(DateTime day) =>
      '${day.day.toString().padLeft(2, '0')}/'
      '${day.month.toString().padLeft(2, '0')}/${day.year}';

  Future<void> _restore(BuildContext context, DailyBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restaurar ${_day(backup.day)}?'),
        content: const Text(
          'Os dados deste aparelho são substituídos pelos desse backup, e o '
          'app reinicia. Os dados atuais ficam guardados como .old neste '
          'aparelho. Depois o backup vai também para os outros aparelhos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await HybridSync.restoreBackup(backup);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backups diários'),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: FutureBuilder<List<DailyBackup>>(
          future: HybridSync.listBackups(),
          builder: (context, snapshot) {
            final backups = snapshot.data;
            if (backups == null) {
              return Center(
                child: snapshot.hasError
                    ? const Text('Não consegui ler a pasta.')
                    : const CircularProgressIndicator(),
              );
            }
            if (backups.isEmpty) {
              return const Center(child: Text('Nenhum backup ainda.'));
            }
            return ListView.builder(
              itemCount: backups.length,
              itemBuilder: (context, index) {
                final backup = backups[index];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(_day(backup.day)),
                  subtitle: Text(backup.device),
                  onTap: () => _restore(context, backup),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
