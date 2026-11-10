import 'package:flutter/material.dart';

class TabRecordsSelectionAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onSelectAll;
  final VoidCallback onDuplicate;
  final VoidCallback? onMoveToWallet;

  /// Title-cases the selected records' names.
  final VoidCallback onTitleCase;

  /// Hides the selected records from the Extrato, or shows them again when
  /// [selectionAllHidden].
  final VoidCallback onToggleHidden;
  final bool selectionAllHidden;

  const TabRecordsSelectionAppBar({
    Key? key,
    required this.selectedCount,
    required this.onClose,
    required this.onDelete,
    required this.onSelectAll,
    required this.onDuplicate,
    this.onMoveToWallet,
    required this.onTitleCase,
    required this.onToggleHidden,
    this.selectionAllHidden = false,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).primaryColor,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onClose,
      ),
      title: Text("$selectedCount ${'selecionado'}"),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Excluir',
          onPressed: selectedCount > 0 ? onDelete : null,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'select_all') {
              onSelectAll();
            } else if (value == 'duplicate') {
              onDuplicate();
            } else if (value == 'move_wallet') {
              onMoveToWallet?.call();
            } else if (value == 'toggle_hidden') {
              onToggleHidden();
            } else if (value == 'title_case') {
              onTitleCase();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'select_all',
              child: Text('Selecionar tudo'),
            ),
            PopupMenuItem(
              value: 'duplicate',
              child: Text('Duplicar'),
            ),
            PopupMenuItem(
              value: 'toggle_hidden',
              child: Text(selectionAllHidden
                  ? 'Mostrar no Extrato'
                  : 'Ocultar do Extrato'),
            ),
            const PopupMenuItem(
              value: 'title_case',
              child: Text('Primeira Letra Maiúscula'),
            ),
            PopupMenuItem(
              value: 'move_wallet',
              child: Text('Mover para carteira'),
            ),
          ],
        ),
      ],
    );
  }
}
