import 'package:flutter/material.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/service-config.dart';

class TagsPageView extends StatefulWidget {
  @override
  TagsPageViewState createState() => TagsPageViewState();
}

class TagsPageViewState extends State<TagsPageView> {
  Set<String>? tags;
  Set<String> selectedTags = <String>{};
  bool isSelectionMode = false;
  DatabaseInterface database = ServiceConfig.database;

  @override
  void initState() {
    super.initState();
    fetchTagsFromDatabase();
  }

  fetchTagsFromDatabase() async {
    var tagSet = await database.getAllTags();
    setState(() {
      tags = tagSet;
    });
  }

  void _toggleSelection(String tag) {
    setState(() {
      if (selectedTags.contains(tag)) {
        selectedTags.remove(tag);
        if (selectedTags.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedTags.add(tag);
        isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      selectedTags.clear();
      isSelectionMode = false;
    });
  }

  void _editSelectedTag() {
    if (selectedTags.length == 1) {
      String tagToEdit = selectedTags.first;
      _showEditTagDialog(tagToEdit);
    }
  }

  void _deleteSelectedTags() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Excluir tags'),
          content: Text(
            selectedTags.length == 1
                ? 'Tem certeza de que deseja excluir essa tag?'
                : 'Tem certeza de que deseja excluir essas ${selectedTags.length.toString()} tags?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                _performDelete();
                Navigator.of(context).pop();
              },
              child: Text('Excluir'),
            ),
          ],
        );
      },
    );
  }

  void _performDelete() async {
    for (String tag in selectedTags) {
      await database.deleteTag(tag);
    }
    await fetchTagsFromDatabase();
    _clearSelection();
  }

  void _showEditTagDialog(String currentTag) {
    TextEditingController controller = TextEditingController(text: currentTag);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Editar Tag'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Nome da tag',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty &&
                    controller.text.trim() != currentTag) {
                  _performEdit(currentTag, controller.text.trim());
                }
                Navigator.of(context).pop();
              },
              child: Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  void _performEdit(String oldTag, String newTag) async {
    await database.renameTag(oldTag, newTag);
    await fetchTagsFromDatabase();
    _clearSelection();
  }

  final _biggerFont = const TextStyle(fontSize: 18.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: buildTagsList(),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(title: Text('Etiquetas'));
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      title: Text('${selectedTags.length.toString()} selecionada(s)'),
      leading: IconButton(icon: Icon(Icons.close), onPressed: _clearSelection),
      actions: [
        if (selectedTags.length == 1)
          IconButton(
            icon: Icon(Icons.edit),
            onPressed: _editSelectedTag,
            tooltip: 'Editar tag',
          ),
        IconButton(
          icon: Icon(Icons.delete),
          onPressed: _deleteSelectedTags,
          tooltip: 'Excluir tags',
        ),
      ],
    );
  }

  Widget buildTagsList() {
    if (tags == null) {
      return Center(child: CircularProgressIndicator());
    }

    if (tags!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.label_outline, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'Nenhuma tag encontrada',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    List<String> sortedTags = tags!.toList()..sort();

    return ListView.builder(
      itemCount: sortedTags.length,
      itemBuilder: (context, index) {
        String tag = sortedTags[index];
        bool isSelected = selectedTags.contains(tag);

        return Container(
          color: isSelected
              ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
              : null,
          child: ListTile(
            leading: isSelectionMode
                ? Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  )
                : Icon(
                    Icons.label,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            title: Text(tag, style: _biggerFont),
            selected: isSelected,
            onTap: () {
              if (isSelectionMode) {
                _toggleSelection(tag);
              }
            },
            onLongPress: () {
              _toggleSelection(tag);
            },
          ),
        );
      },
    );
  }
}
