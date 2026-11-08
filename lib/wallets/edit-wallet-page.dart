import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aupp/services/logger.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:aupp/components/wallet_icon_square.dart';
import 'package:aupp/components/icon_color_picker_section.dart';
import 'package:aupp/helpers/alert-dialog-builder.dart';
import 'package:aupp/components/amount_input_field.dart';
import 'package:aupp/helpers/amount-input-utils.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/style.dart';
import 'package:aupp/services/cash-wallet.dart';
import 'package:aupp/services/total-wallets.dart';
import 'package:aupp/wallets/wallet-picker-page.dart';
import 'package:aupp/wallets/wallet-sections.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';

enum _WalletDeletionChoice { deleteAll, moveToWallet, keepInDefault }

class EditWalletPage extends StatefulWidget {
  /// EditWalletPage is a page for creating or editing a Wallet.
  /// Pass [passedWallet] to edit an existing wallet; leave null to create a new one.

  final Wallet? passedWallet;

  EditWalletPage({Key? key, this.passedWallet}) : super(key: key);

  @override
  _EditWalletPageState createState() => _EditWalletPageState(passedWallet);
}

class _EditWalletPageState extends State<EditWalletPage> {
  static final _logger = Logger.withContext('EditWalletPage');

  Wallet? passedWallet;
  late Wallet wallet;

  DatabaseInterface database = ServiceConfig.database;

  String? walletName;
  final _formKey = GlobalKey<FormState>();
  final _balanceController = TextEditingController();
  Timer? _mathDebounce;

  _EditWalletPageState(this.passedWallet);

  /// With the bank sync, the wallet to invest is what the others leave: it
  /// always exists, and stays that wallet.
  bool get _managed =>
      passedWallet?.isInvestmentReserve == true &&
      DinzoSyncService.apiKey != null;

  /// There is one wallet to invest.
  bool _otherToInvest = false;

  /// Paper money: manual records go here ([CashWallet]).
  bool _isCash = false;

  @override
  void initState() {
    super.initState();
    ServiceConfig.database.getAllWallets().then((wallets) {
      if (!mounted) return;
      setState(() {
        _otherToInvest = wallets.any(
          (w) => w.isInvestmentReserve && w.id != passedWallet?.id,
        );
        // Fork: a new one goes after the caixinhas there are.
        if (passedWallet == null) {
          wallet.sortOrder = WalletSection.nextSortOrder(wallets);
        }
      });
    });

    if (passedWallet == null) {
      wallet = Wallet(
        '',
        color: Wallet.colors[0],
        iconCodePoint: FontAwesomeIcons.wallet.codePoint,
        isDefault: false,
        sortOrder: 0,
      );
    } else {
      wallet = Wallet.fromMap(
          passedWallet!.toMap()..['balance'] = passedWallet!.balance);
      walletName = passedWallet!.name;
      _isCash = CashWallet.isCash(passedWallet!);
    }

    if (passedWallet == null) {
      final zeroText = buildZeroAmountText();
      if (zeroText != '0') {
        _balanceController.value = TextEditingValue(
          text: zeroText,
          selection: TextSelection.collapsed(offset: zeroText.length),
        );
      }
    } else {
      // Existing wallet: load current balance with grouping separators
      final displayBalance = wallet.balance ?? wallet.initialAmount;
      _balanceController.text =
          getCurrencyValueString(displayBalance, turnOffGrouping: false);
    }

    _balanceController.addListener(() {
      _mathDebounce?.cancel();
      _mathDebounce = Timer(const Duration(seconds: 2), () {
        solveMathExpressionAndUpdateController(_balanceController);
      });
    });
  }

  @override
  void dispose() {
    _mathDebounce?.cancel();
    _balanceController.dispose();
    super.dispose();
  }

  Widget _getPageSeparatorLabel(String labelText) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.fromLTRB(15, 15, 0, 5),
        child: Text(
          labelText,
          style: TextStyle(
            fontFamily: FontNameDefault,
            fontWeight: FontWeight.w300,
            fontSize: 26.0,
            color: MaterialThemeInstance.currentTheme?.colorScheme.onSurface,
          ),
          textAlign: TextAlign.left,
        ),
      ),
    );
  }

  Widget _getWalletCirclePreview() {
    return Container(
      margin: EdgeInsets.all(10),
      child: WalletIconSquare(
        iconEmoji: wallet.iconEmoji,
        iconDataFromDefaultIconSet: wallet.icon,
        backgroundColor: wallet.color,
        size: 70,
        mainIconSize: 30,
      ),
    );
  }

  Widget _getNameField() {
    return Expanded(
      child: Container(
        margin: EdgeInsets.all(10),
        child: TextFormField(
          onChanged: (text) => setState(() => walletName = text),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Por favor, insira o nome da carteira';
            }
            return null;
          },
          initialValue: walletName,
          style: TextStyle(
              fontSize: 22.0, color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Nome da carteira',
            errorStyle: TextStyle(fontSize: 16.0),
          ),
        ),
      ),
    );
  }

  Widget _getBalanceField() {
    return Container(
      margin: const EdgeInsets.fromLTRB(15, 5, 15, 5),
      child: AmountInputField(
        controller: _balanceController,
        labelText: 'Saldo',
        allowNegative: true,
        autofocus: false,
        validator: (value) {
          // Empty is allowed — defaults to 0
          if (value == null || value.isEmpty) return null;
          var numericValue = tryParseSignedCurrencyString(value);
          if (numericValue == null) {
            return amountFormatErrorMessage();
          }
          return null;
        },
      ),
    );
  }

  Widget _getKindSection() {
    final isDefaultWallet = passedWallet?.isDefault ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Fork: what is created here is a caixinha; the reserves exist
        // already, and an existing wallet can still change what it is for.
        if (!isDefaultWallet && !_managed && passedWallet != null) ...[
          _getPageSeparatorLabel('Para que serve'),
          Divider(thickness: 0.5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<WalletKind>(
              initialValue: wallet.kind,
              items: [
                for (final kind in WalletKind.values)
                  if (kind != WalletKind.toInvest || !_otherToInvest)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
              ],
              onChanged: (kind) {
                if (kind != null) setState(() => wallet.kind = kind);
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Dinheiro em papel'),
            subtitle: const Text(
              'Lançamentos manuais sempre entram e saem desta carteira, '
              'nunca da padrão.',
            ),
            value: _isCash,
            onChanged: (value) => setState(() => _isCash = value),
          ),
        ],
      ],
    );
  }

  AppBar _getAppBar() {
    return AppBar(
      title:
          Text(passedWallet == null ? 'Nova caixinha' : 'Editar carteira'),
      leading: BackButton(onPressed: () => Navigator.pop(context)),
      actions: [
        if (passedWallet != null && !_managed)
          IconButton(
            icon: passedWallet!.isArchived
                ? const Icon(Icons.unarchive)
                : const Icon(Icons.archive),
            tooltip:
                passedWallet!.isArchived ? 'Desarquivar' : 'Arquivar',
            onPressed: () async {
              bool isCurrentlyArchived = passedWallet!.isArchived;
              String message = isCurrentlyArchived
                  ? 'Você realmente quer desarquivar esta carteira?'
                  : 'Você realmente quer arquivar esta carteira?';

              AlertDialogBuilder dialog = AlertDialogBuilder(message)
                  .addTrueButtonName('Sim')
                  .addFalseButtonName('Não');

              var confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => dialog.build(ctx),
              );

              if (confirmed == true) {
                await database.archiveWallet(
                    passedWallet!.id!, !isCurrentlyArchived);
                Navigator.of(context).pop();
              }
            },
          ),
        if (passedWallet != null &&
            !passedWallet!.isDefault &&
            !_managed)
          PopupMenuButton<int>(
            icon: Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10.0))),
            onSelected: (index) async {
              if (index == 1) {
                await _showDeleteDialog();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<int>(
                padding: EdgeInsets.all(20),
                value: 1,
                child: Text('Excluir', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _showDeleteDialog() async {
    final choice = await showDialog<_WalletDeletionChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir carteira'),
        content: Text(
            'O que deveria acontecer com os registros nesta carteira? Os registros de transferência envolvendo esta carteira sempre serão excluídos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true)
                .pop(_WalletDeletionChoice.deleteAll),
            child: Text('Excluir todos os registros'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true)
                .pop(_WalletDeletionChoice.moveToWallet),
            child: Text('Mover registros para outra carteira'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true)
                .pop(_WalletDeletionChoice.keepInDefault),
            child: Text('Manter registros na carteira padrão'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(null),
            child: Text('Cancelar'),
          ),
        ],
      ),
    );

    if (choice == null) return;

    _logger.info('Deleting wallet "${passedWallet!.name}" (ID ${passedWallet!.id}), choice: ${choice.name}');

    if (choice == _WalletDeletionChoice.moveToWallet) {
      final targetWallet = await Navigator.push<Wallet>(
        context,
        MaterialPageRoute(
          builder: (_) => WalletPickerPage(excludeWalletId: passedWallet!.id),
        ),
      );
      if (targetWallet == null || !mounted) return;
      _logger.debug('Moving records to wallet "${targetWallet.name}" (ID ${targetWallet.id})');
      await database.moveRecordsToWallet(passedWallet!.id!, targetWallet.id!);
    } else if (choice == _WalletDeletionChoice.keepInDefault) {
      final defaultWallet = await database.getDefaultWallet();
      if (!mounted) return;
      _logger.debug('Moving records to default wallet (ID ${defaultWallet!.id})');
      await database.moveRecordsToWallet(passedWallet!.id!, defaultWallet.id!);
    }

    await database.deleteWalletAndRecords(passedWallet!.id!);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveWallet() async {
    if (!_formKey.currentState!.validate()) return;

    wallet.name = walletName!;

    // Calculate initial_amount from the entered balance
    final enteredBalanceText = _balanceController.text;
    final enteredBalance = tryParseSignedCurrencyString(enteredBalanceText) ??
        double.tryParse(enteredBalanceText) ??
        0.0;

    // initial_amount = entered_balance - sum_of_records
    // sum_of_records = wallet.balance - wallet.initialAmount
    final sumOfRecords =
        (wallet.balance ?? wallet.initialAmount) - wallet.initialAmount;
    wallet.initialAmount = enteredBalance - sumOfRecords;

    if (passedWallet == null) {
      _logger.info('Creating new wallet "${wallet.name}" (currency: ${wallet.currency ?? 'none'}, initialAmount: ${wallet.initialAmount})');
      await database.addWallet(wallet);
    } else {
      _logger.info('Updating wallet "${wallet.name}" (ID ${passedWallet!.id}, initialAmount: ${wallet.initialAmount})');
      await database.updateWallet(passedWallet!.id!, wallet);
      await TotalWallets.rename(passedWallet!.name, wallet.name);
      if (_isCash) {
        await CashWallet.save(wallet);
      } else if (CashWallet.isCash(passedWallet!)) {
        await CashWallet.save(null);
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _getAppBar(),
      resizeToAvoidBottomInset: false,
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Name + preview
              _getPageSeparatorLabel('Nome'),
              Divider(thickness: 0.5),
              Row(
                children: [
                  _getWalletCirclePreview(),
                  _getNameField(),
                ],
              ),
              // Balance
              _getPageSeparatorLabel('Saldo'),
              Divider(thickness: 0.5),
              _getBalanceField(),
              _getKindSection(),
              // Color + Icon (shared component, sections are collapsible internally)
              IconColorPickerSection(
                initialIconEmoji: wallet.iconEmoji,
                initialIcon: wallet.icon,
                initialColor: wallet.color,
                colors: Wallet.colors,
                onChange: (iconEmoji, icon, iconCodePoint, color) {
                  setState(() {
                    wallet.iconEmoji = iconEmoji;
                    wallet.icon = icon;
                    wallet.iconCodePoint = iconCodePoint;
                    wallet.color = color;
                  });
                },
              ),
              SizedBox(height: 75),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: _saveWallet,
        tooltip: 'Salvar',
        child: const Icon(Icons.save),
      ),
    );
  }
}
