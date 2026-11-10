import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:aupp/components/icon_color_picker_section.dart';
import 'package:aupp/helpers/alert-dialog-builder.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/service-config.dart';
import '../style.dart';

class EditCategoryPage extends StatefulWidget {
  /// EditCategoryPage is a page containing forms for the editing of a Category object.
  /// EditCategoryPage can take the category object to edit as a constructor parameters
  /// or can create a new Category otherwise.

  final Category? passedCategory;
  final CategoryType? categoryType;

  EditCategoryPage({Key? key, this.passedCategory, this.categoryType})
      : super(key: key);

  @override
  EditCategoryPageState createState() =>
      EditCategoryPageState(passedCategory, categoryType);
}

class EditCategoryPageState extends State<EditCategoryPage> {
  Category? passedCategory;
  Category? category;
  CategoryType? categoryType;

  EditCategoryPageState(this.passedCategory, this.categoryType);

  String? categoryName;

  DatabaseInterface database = ServiceConfig.database;

  final _formKey = GlobalKey<FormState>();

  Category initCategory() {
    Category category = new Category(null);
    if (this.passedCategory == null) {
      category.color = Category.colors[0];
      category.icon = FontAwesomeIcons.question.data;
      category.iconCodePoint = category.icon!.codePoint;
      category.categoryType = categoryType;
    } else {
      category = Category.fromMap(passedCategory!.toMap());
      categoryName = passedCategory!.name;
    }
    return category;
  }

  @override
  void initState() {
    super.initState();
    category = initCategory();
  }

  Widget _getPageSeparatorLabel(String labelText) {
    TextStyle textStyle = TextStyle(
      fontFamily: FontNameDefault,
      fontWeight: FontWeight.w300,
      fontSize: 26.0,
      color: MaterialThemeInstance.currentTheme?.colorScheme.onSurface,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.fromLTRB(15, 15, 0, 5),
        child: Text(labelText, style: textStyle, textAlign: TextAlign.left),
      ),
    );
  }

  Widget _createCategoryCirclePreview() {
    return Container(
      margin: EdgeInsets.all(10),
      child: ClipOval(
        child: Material(
          color: category!.color, // Button color
          child: InkWell(
            splashColor: category!.color, // InkWell color
            child: SizedBox(
              width: 70,
              height: 70,
              child: category!.iconEmoji != null
                  ? Center(
                      child: Text(
                      category!.iconEmoji!, // Display the emoji
                      style: TextStyle(
                        fontSize: 30, // Adjust the font size for the emoji
                      ),
                    ))
                  : Icon(
                      category!.icon, // Fallback to the icon
                      color: category!.color != null
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      size: 30,
                    ),
            ),
            onTap: () {},
          ),
        ),
      ),
    );
  }

  Widget _getTextField() {
    return Expanded(
        child: Form(
      key: _formKey,
      child: Container(
        margin: EdgeInsets.all(10),
        child: TextFormField(
            onChanged: (text) {
              setState(() {
                categoryName = text;
              });
            },
            validator: (value) {
              if (value!.isEmpty) {
                return 'Por favor, informe o nome da categoria';
              }
              return null;
            },
            initialValue: categoryName,
            style: TextStyle(
                fontSize: 22.0, color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Nome da categoria',
              errorStyle: TextStyle(
                fontSize: 16.0,
              ),
            )),
      ),
    ));
  }

  Widget _getAppBar() {
    return AppBar(title: Text('Editar Categoria'), actions: <Widget>[
      Visibility(
          visible: widget.passedCategory != null,
          child: IconButton(
            icon: widget.passedCategory == null
                ? const Icon(Icons.archive)
                : !(widget.passedCategory!.isArchived)
                    ? const Icon(Icons.archive)
                    : const Icon(Icons.unarchive),
            tooltip: widget.passedCategory == null
                ? ""
                : !(widget.passedCategory!.isArchived)
                    ? 'Arquivar'
                    : 'Desarquivar',
            onPressed: () async {
              bool isCurrentlyArchived = widget.passedCategory!.isArchived;

              String dialogMessage = !isCurrentlyArchived
                  ? 'Você realmente quer arquivar a categoria?'
                  : 'Você realmente quer desarquivar a categoria?';

              AlertDialogBuilder archiveDialog =
                  AlertDialogBuilder(dialogMessage)
                      .addTrueButtonName('Sim')
                      .addFalseButtonName('Não');

              if (!isCurrentlyArchived) {
                archiveDialog.addSubtitle(
                    'Arquivando a categoria NÃO removerá os registros associados');
              }

              var continueArchivingAction = await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return archiveDialog.build(context);
                  });

              if (continueArchivingAction) {
                await database.archiveCategory(widget.passedCategory!.name!,
                    widget.passedCategory!.categoryType!, !isCurrentlyArchived);
                Navigator.pop(context);
              }
            },
          )),
      Visibility(
        visible: widget.passedCategory != null,
        child: PopupMenuButton<int>(
          icon: Icon(Icons.more_vert),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(10.0),
            ),
          ),
          onSelected: (index) async {
            if (index == 1) {
              AlertDialogBuilder deleteDialog = AlertDialogBuilder(
                      'Deseja realmente excluir esta categoria?')
                  .addSubtitle(
                      'Excluindo a categoria que você irá remover todos os Itens associados a ela')
                  .addTrueButtonName('Sim')
                  .addFalseButtonName('Não');

              var continueDelete = await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return deleteDialog.build(context);
                  });

              if (continueDelete) {
                database.deleteCategory(widget.passedCategory!.name,
                    widget.passedCategory!.categoryType);
                Navigator.pop(context);
              }
            }
          },
          itemBuilder: (BuildContext context) {
            var deleteStr = 'Excluir';
            return {deleteStr: 1}.entries.map((entry) {
              return PopupMenuItem<int>(
                padding: EdgeInsets.all(20),
                value: entry.value,
                child: Text(entry.key,
                    style: TextStyle(
                      fontSize: 16,
                    )),
              );
            }).toList();
          },
        ),
      ),
    ]);
  }

  Widget _getIconColorPickerSection() {
    return IconColorPickerSection(
      initialIconEmoji: category!.iconEmoji,
      initialIcon: category!.icon,
      initialColor: category!.color,
      onChange: (iconEmoji, icon, iconCodePoint, color) {
        setState(() {
          category!.iconEmoji = iconEmoji;
          category!.icon = icon;
          category!.iconCodePoint = iconCodePoint;
          category!.color = color;
        });
      },
    );
  }

  Widget _getPreviewAndTitleCard() {
    return Container(
        child: Column(
      children: [
        _getPageSeparatorLabel('Nome'),
        Divider(
          thickness: 0.5,
        ),
        Container(
          child: Row(
            children: <Widget>[
              Container(child: _createCategoryCirclePreview()),
              Container(child: _getTextField()),
            ],
          ),
        ),
      ],
    ));
  }

  saveCategory() async {
    if (_formKey.currentState!.validate()) {
      if (category!.name == null) {
        // Then it is a newly created category
        category!.name = categoryName;
        await database.addCategory(category);
      } else {
        // If category.name is already set
        // I'm editing an existing category
        String? existingName = category!.name;
        var existingType = category!.categoryType;
        category!.name = categoryName;
        await database.updateCategory(existingName, existingType, category);
      }
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _getAppBar() as PreferredSizeWidget?,
      resizeToAvoidBottomInset: false,
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            _getPreviewAndTitleCard(),
            _getIconColorPickerSection(),
            SizedBox(height: 75),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: saveCategory,
        tooltip: 'Adicionar uma nova categoria',
        child: const Icon(Icons.save),
      ),
    );
  }
}
