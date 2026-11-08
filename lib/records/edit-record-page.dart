// file: edit-record-page.dart

import 'package:aupp/budget_plan/budget-plan.dart';
import 'package:aupp/budget_plan/budget-plan-page.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/dinzo/split-payment.dart';
import 'package:aupp/dinzo/dinzo-api.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/components/payment-code-sheet.dart';
import 'package:aupp/dinzo/aporte-shortfall-tile.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/dinzo/pix-code.dart';
import 'package:aupp/services/recurrent-record-service.dart';
import 'package:aupp/dinzo/payment-launcher.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:collection/collection.dart' show SetEquality;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:aupp/categories/categories-tab-page-view.dart';
import 'package:aupp/components/tag_chip.dart';
import 'package:aupp/helpers/alert-dialog-builder.dart';
import 'package:aupp/helpers/amount-input-utils.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/recurrent-period.dart';
import 'package:aupp/components/amount_input_field.dart';
import 'package:aupp/components/markup_text.dart';
import 'package:aupp/services/database/database-interface.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';

import '../components/category_icon_circle.dart';
import '../helpers/date_picker_utils.dart';
import '../models/recurrent-record-pattern.dart';
import '../models/wallet.dart';
import '../settings/constants/preferences-keys.dart';
import '../settings/preferences-utils.dart';
import 'components/custom_interval_dialog.dart';
import 'components/tag_selection_dialog.dart';
import 'components/wallet_transfer_row.dart';

class EditRecordPage extends StatefulWidget {
  final Record? passedRecord;
  final Category? passedCategory;
  final RecurrentRecordPattern? passedRecurrentRecordPattern;
  final bool readOnly;
  final Wallet? initialWallet;
  final Wallet? initialDestinationWallet;
  final bool isTransferFlow;

  /// Pre-selected record date (e.g. from tapping a day header on the
  /// homepage). Only the date part is used; the time stays "now".
  /// Null means today.
  final DateTime? initialDate;

  EditRecordPage({
    Key? key,
    this.passedRecord,
    this.passedCategory,
    this.passedRecurrentRecordPattern,
    this.readOnly = false,
    this.initialWallet,
    this.initialDestinationWallet,
    this.isTransferFlow = false,
    this.initialDate,
  }) : super(key: key);

  @override
  EditRecordPageState createState() => EditRecordPageState(
    this.passedRecord,
    this.passedCategory,
    this.passedRecurrentRecordPattern,
    this.readOnly,
  );
}

class EditRecordPageState extends State<EditRecordPage> {
  final _logger = Logger.withContext('EditRecordPage');
  DatabaseInterface database = ServiceConfig.database;
  TextEditingController _textEditingController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Record? record;

  Record? passedRecord;
  Category? passedCategory;
  bool readOnly = false;

  /// Records imported from Dinzo mirror the bank: only their name and note
  /// can change here, and a new name is written back to Dinzo.
  bool get _fromDinzo => record?.dinzoId != null;
  bool get _locked => readOnly || _fromDinzo;
  String? _originalTitle;
  String? _originalCategoryName;

  /// A Dinzo expense or income can change category; it goes to Dinzo too
  /// ([DinzoSyncService.pushCategory]). Same type only: the amount's sign
  /// comes from the bank.
  bool get _dinzoCategoryEditable =>
      _fromDinzo &&
      !readOnly &&
      !DinzoSyncService.isSynthetic(record!.dinzoId) &&
      record!.transferWalletId == null;

  /// A Dinzo expense or income can be moved to another wallet (e.g. paid by
  /// a caixinha); the sync keeps that choice. The app's own records stay locked.
  bool get _dinzoWalletEditable =>
      _fromDinzo &&
      !readOnly &&
      !DinzoSyncService.isSynthetic(record!.dinzoId) &&
      record!.transferWalletId == null;

  /// Forecast entry (see [DinzoSyncService.estimateTag]); never a transfer.
  bool _isEstimateChecked = false;

  /// Fork: a new record made with "+" gets [DinzoSyncService.cashTag] by
  /// itself, following estimate, transfer and Pix / boleto, until the user
  /// adds or removes the tag.
  bool _autoCash = false;

  /// Fork: an occurrence of an estimate (read-only view of a recurrence).
  bool get _isEstimateOccurrence =>
      record != null &&
      record!.isFutureRecord &&
      record!.recurrencePatternId != null &&
      record!.tags.contains(DinzoSyncService.estimateTag);

  /// Fork: an upcoming occurrence of a recurrence (estimate, boleto or
  /// plain), editable by hand ([_saveOccurrence]). Transfers stay read-only.
  bool get _isEditableOccurrence =>
      widget.passedRecord != null &&
      record != null &&
      record!.isFutureRecord &&
      record!.recurrencePatternId != null &&
      record!.transferWalletId == null &&
      record!.dinzoId == null;

  /// The occurrence as it was opened, before any edit.
  Record? _occurrenceBefore;

  /// Its recurrence was read and has more than one occurrence: an edit takes
  /// this one out of it.
  bool _occurrenceLeavesRecurrence = false;

  /// Upcoming occurrence of a recurrence paid by boleto / Pix
  /// ([Record.billingTags]): its code can be pasted here.
  bool get _isBillingOccurrence =>
      record != null &&
      record!.isFutureRecord &&
      record!.recurrencePatternId != null &&
      Record.billingKindOf(record!.tags) != null;

  /// Choosing boleto / Pix for a recurrence (or an estimate), never for a
  /// stored record or a transfer.
  bool get _showsBillingCard =>
      !readOnly &&
      !_fromDinzo &&
      record?.id == null &&
      _selectedDestinationWallet == null &&
      (recurrentPeriod != null || _isEstimate);

  /// Pix / boleto of this occurrence ([RecurrentRecordPattern.paymentCodes]).
  String? _paymentCode;

  /// The recurrence's default Pix, a key or a copia-e-cola, and the name used
  /// for a key's code ([RecurrentRecordPattern.defaultPixKey]).
  String? _defaultPix;
  String? _pixName;
  bool get _isEstimate =>
      (_isEstimateChecked || _forcedEstimate) &&
      _selectedDestinationWallet == null;

  /// Real records come from Dinzo (fork, 2026-10-12): unless manual records
  /// are allowed in Settings → Dinzo, a new one-off record is an estimate.
  /// Recurring records (e.g. meal voucher) and transfers stay as they are.
  bool get _forcedEstimate =>
      !(PreferencesUtils.getOrDefault<bool>(
            ServiceConfig.sharedPreferences!,
            PreferencesKeys.allowManualRecords,
          ) ??
          true) &&
      _sourceLocked &&
      recurrentPeriod == null &&
      _selectedDestinationWallet == null;

  /// New records (and new recurrent patterns) always use the default wallet
  /// as source; only transfers started from a wallet keep that wallet.
  bool get _sourceLocked =>
      record?.id == null &&
      passedRecurrentRecordPattern == null &&
      !isTransferFlow;
  bool isTransferFlow = false;
  RecurrentRecordPattern? passedRecurrentRecordPattern;

  /// Pattern behind a future (read-only) occurrence that happens just once,
  /// e.g. a one-day estimate: it can be deleted right here instead of going
  /// through Settings > Recurrent records.
  RecurrentRecordPattern? _singleOccurrencePattern;

  RecurrentPeriod? recurrentPeriod;
  int? recurrentPeriodIndex;
  int? _customIntervalValue;
  CustomIntervalUnit? _customIntervalUnit;

  late String currency;
  DateTime? lastCharInsertedMillisecond;
  late String categorySign;

  DateTime? localDisplayDate;
  DateTime? localDisplayEndDate;

  Set<String> _selectedTags = {};
  Set<String> _suggestedTags = {};

  Wallet? _selectedWallet;
  Wallet? _selectedDestinationWallet;
  int _totalWalletCount = 0;
  final _walletNameSizeGroup = AutoSizeGroup();
  final _dateTimeSizeGroup = AutoSizeGroup();

  bool _hasTime = false;
  TimeOfDay? _selectedTime;

  DateTime? _originalUtcDateTime;
  double? _originalValue;
  double? _originalTransferValue;

  EditRecordPageState(
    this.passedRecord,
    this.passedCategory,
    this.passedRecurrentRecordPattern,
    this.readOnly,
  );

  static final recurrentIntervalDropdownList = [
    DropdownMenuItem<int>(
      value: RecurrentPeriod.EveryDay.index,
      child: Text('Todo dia', style: TextStyle(fontSize: 18.0)),
    ),
    DropdownMenuItem<int>(
      value: RecurrentPeriod.EveryWeek.index,
      child: Text('Toda semana', style: TextStyle(fontSize: 18.0)),
    ),
    DropdownMenuItem<int>(
      value: RecurrentPeriod.EveryTwoWeeks.index,
      child: Text('A cada duas semanas', style: TextStyle(fontSize: 18.0)),
    ),
    DropdownMenuItem<int>(
      value: RecurrentPeriod.EveryFourWeeks.index,
      child: Text('A cada quatro semanas', style: TextStyle(fontSize: 18.0)),
    ),
    DropdownMenuItem<int>(
      value: RecurrentPeriod.EveryMonth.index,
      child: Text('Todo mês', style: TextStyle(fontSize: 18.0)),
    ),
    DropdownMenuItem<int>(
      value: RecurrentPeriod.EveryThreeMonths.index,
      child: Text('A cada três meses', style: TextStyle(fontSize: 18.0)),
    ),
    DropdownMenuItem<int>(
      value: RecurrentPeriod.EveryFourMonths.index,
      child: Text('A cada quatro meses', style: TextStyle(fontSize: 18.0)),
    ),
    DropdownMenuItem<int>(
      value: RecurrentPeriod.EveryYear.index,
      child: Text('Anualmente', style: TextStyle(fontSize: 18.0)),
    ),
    DropdownMenuItem<int>(
      value: RecurrentPeriod.Custom.index,
      child: Text('Personalizado', style: TextStyle(fontSize: 18.0)),
    ),
  ];

  @override
  void initState() {
    super.initState();
    isTransferFlow =
        widget.isTransferFlow ||
        passedRecord?.isTransfer == true ||
        passedRecurrentRecordPattern?.transferWalletId != null;

    // Loading parameters passed to the page

    if (passedRecord != null) {
      // I am editing an existing record
      record = passedRecord;
      if (_isEditableOccurrence) {
        // Fork: an upcoming occurrence opens editable (see _saveOccurrence).
        readOnly = false;
        _occurrenceBefore = passedRecord!.copyWith(
          tags: Set.of(passedRecord!.tags),
        )..occurrenceUtc = passedRecord!.occurrenceUtc;
      }
      // Capture original values to detect changes for pattern-linked records
      _originalUtcDateTime = passedRecord!.utcDateTime;
      _originalValue = passedRecord!.value;
      _originalTransferValue = passedRecord!.transferValue;
      // Use the localDateTime getter for display purposes
      localDisplayDate = passedRecord!.localDateTime;
      // Initialize time if the record has a non-midnight time
      final localDT = passedRecord!.localDateTime;
      if (localDT.hour != 0 || localDT.minute != 0) {
        _hasTime = true;
        _selectedTime = TimeOfDay(hour: localDT.hour, minute: localDT.minute);
      }
      final v = record!.value!.abs();
      _textEditingController.text = v % 1 == 0
          ? v.toInt().toString()
          : v.toString().replaceAll('.', getDecimalSeparator());
      if (record!.recurrencePatternId != null) {
        database.getRecurrentRecordPattern(record!.recurrencePatternId).then((
          value,
        ) {
          if (value != null) {
            final start = value.localDateTime;
            final end = value.localEndDate;
            setState(() {
              _occurrenceLeavesRecurrence =
                  record!.isFutureRecord && !value.happensOnce;
              if (record!.isFutureRecord &&
                  end != null &&
                  !DateTime(
                    end.year,
                    end.month,
                    end.day,
                  ).isAfter(DateTime(start.year, start.month, start.day))) {
                _singleOccurrencePattern = value;
              }
              recurrentPeriod = value.recurrentPeriod;
              recurrentPeriodIndex = value.recurrentPeriod!.index;
              localDisplayEndDate = value.localEndDate;
              _customIntervalValue = value.customIntervalValue;
              _customIntervalUnit = value.customIntervalUnit;
            });
          }
        });
      }
      _paymentCode = passedRecord!.paymentCode;
      // Initialize selected tags for existing record
      _selectedTags = Set.from(record!.tags);
      _isEstimateChecked = _selectedTags.contains(DinzoSyncService.estimateTag);
      _originalTitle = record!.title;
      _originalCategoryName = record!.category?.name;
    } else if (passedRecurrentRecordPattern != null) {
      // I am editing a recurrent pattern
      // Instantiate a new Record object from the pattern
      record = Record(
        passedRecurrentRecordPattern!.value,
        passedRecurrentRecordPattern!.title,
        passedRecurrentRecordPattern!.category,
        // The record's utcDateTime is from the pattern's utcDateTime
        passedRecurrentRecordPattern!.utcDateTime,
        // The record's timezone name is from the pattern's timezone name
        timeZoneName: passedRecurrentRecordPattern!.timeZoneName,
        description: passedRecurrentRecordPattern!.description,
        tags: passedRecurrentRecordPattern!.tags, // Pass tags from pattern
        walletId: passedRecurrentRecordPattern!.walletId,
        transferWalletId: passedRecurrentRecordPattern!.transferWalletId,
        transferValue: passedRecurrentRecordPattern!.transferValue,
      );
      // Use the localDateTime for display
      localDisplayDate = passedRecurrentRecordPattern!.localDateTime;
      localDisplayEndDate = passedRecurrentRecordPattern!.localEndDate;
      // Initialize time if the recurrent pattern has a non-midnight time
      final localDT = passedRecurrentRecordPattern!.localDateTime;
      if (localDT.hour != 0 || localDT.minute != 0) {
        _hasTime = true;
        _selectedTime = TimeOfDay(hour: localDT.hour, minute: localDT.minute);
      }

      final v = record!.value!.abs();
      _textEditingController.text = v % 1 == 0
          ? v.toInt().toString()
          : v.toString().replaceAll('.', getDecimalSeparator());
      setState(() {
        recurrentPeriod = passedRecurrentRecordPattern!.recurrentPeriod;
        recurrentPeriodIndex =
            passedRecurrentRecordPattern!.recurrentPeriod!.index;
        _customIntervalValue =
            passedRecurrentRecordPattern!.customIntervalValue;
        _customIntervalUnit = passedRecurrentRecordPattern!.customIntervalUnit;
      });
      _defaultPix = passedRecurrentRecordPattern!.defaultPix;
      _pixName = passedRecurrentRecordPattern!
          .paymentCodes[RecurrentRecordPattern.pixNameKey];
      // Initialize selected tags for existing recurrent pattern
      _selectedTags = Set.from(passedRecurrentRecordPattern!.tags);
      _isEstimateChecked = _selectedTags.contains(DinzoSyncService.estimateTag);
    } else {
      // I am adding a new record
      // Create a new record with a UTC timestamp and the current local timezone
      final now = DateTime.now();
      final preset = widget.initialDate;
      final recordDateTime = preset == null
          ? now
          : DateTime(
              preset.year,
              preset.month,
              preset.day,
              now.hour,
              now.minute,
            );
      record = Record(
        null,
        null,
        passedCategory,
        recordDateTime.toUtc(),
        walletId: widget.initialWallet?.id,
        transferWalletId: widget.initialDestinationWallet?.id,
      );
      localDisplayDate = record!.localDateTime;
      _hasTime = true;
      _selectedTime = TimeOfDay(hour: now.hour, minute: now.minute);
      _selectedTags = {
        record!.transferWalletId != null
            ? DinzoSyncService.virtualTag
            : DinzoSyncService.manualTag,
      };
      _autoCash = true;
      _applyAutoCash(isTransfer: record!.transferWalletId != null);
      if (record!.value == null) {
        final zeroText = buildZeroAmountText();
        if (zeroText != '0') {
          _textEditingController.value = _textEditingController.value.copyWith(
            text: zeroText,
            selection: TextSelection.collapsed(offset: zeroText.length),
            composing: TextRange.empty,
          );
          changeRecordValue(zeroText);
        }
      }
    }

    // Load most used tags for the current category
    if (record?.category != null) {
      _loadSuggestedTags();
    }

    // Load wallet
    _initWallet();

    // Keyboard listeners initializations (the same as before)
    _textEditingController.addListener(() async {
      if (_locked) return;
      var text = _textEditingController.text.toLowerCase();
      await Future.delayed(Duration(seconds: 2));
      if (!mounted) return;
      var textAfterPause = _textEditingController.text.toLowerCase();
      if (text == textAfterPause) {
        solveMathExpressionAndUpdateController(
          _textEditingController,
          onSolved: changeRecordValue,
        );
      }
    });

    categorySign =
        isTransferFlow || record?.category?.categoryType == CategoryType.expense
        ? "-"
        : "+";

    String initialValue = record?.title ?? "";
    _typeAheadController.text = initialValue;
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    _typeAheadController.dispose();
    super.dispose();
  }

  Widget _createAddNoteCard() {
    if (readOnly && record!.description == null) {
      return Container();
    }
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 40.0,
        top: 10,
        right: 16,
        left: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SizedBox(
              width: 40,
              child: Center(
                child: Icon(
                  Icons.notes,
                  size: 28,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              identifier: 'note-field',
              child: TextFormField(
                onChanged: (text) {
                  setState(() {
                    record!.description = text;
                  });
                },
                enabled: !readOnly,
                style: TextStyle(
                  fontSize: 18.0,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                initialValue: record!.description,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: 'Adicione uma nota',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(20, 10, 10, 10),
                  label: Text("Note"),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  final TextEditingController _typeAheadController = TextEditingController();

  Widget _createTitleCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Center(
              child: Icon(
                Icons.title,
                size: 28,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: TypeAheadField<String>(
              controller: _typeAheadController,
              builder: (context, controller, focusNode) {
                return Semantics(
                  identifier: 'record-name-field',
                  child: TextFormField(
                    enabled: !readOnly,
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (text) {
                      setState(() {
                        record!.title = text;
                      });
                    },
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      contentPadding: EdgeInsets.fromLTRB(20, 10, 10, 10),
                      border: InputBorder.none,
                      hintText: record!.category?.name ?? 'Nome do Item',
                      labelText: 'Nome do Item',
                    ),
                  ),
                );
              },
              suggestionsCallback: (search) {
                if (search.isNotEmpty && record!.category != null) {
                  return database.suggestedRecordTitles(
                    search,
                    record!.category!.name!,
                  );
                }
                return null;
              },
              itemBuilder: (context, record) {
                return ListTile(title: Text(record));
              },
              onSelected: (selectedTitle) => {
                _typeAheadController.text = selectedTitle,
                setState(() {
                  record!.title = selectedTitle;
                }),
              },
              hideOnEmpty: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _createCategoryCard() {
    final category = record!.category;
    return InkWell(
      onTap: () async {
        if (_locked && !_dinzoCategoryEditable) return;
        final selectedCategory = await Navigator.push<Category?>(
          context,
          MaterialPageRoute(builder: (context) => CategoryTabPageView()),
        );
        if (selectedCategory == null || !mounted) return;
        if (_fromDinzo) {
          if (selectedCategory.categoryType != category?.categoryType) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  category?.categoryType == CategoryType.expense
                      ? 'Lançamento da Dinzo: escolha uma categoria de despesa.'
                      : 'Lançamento da Dinzo: escolha uma categoria de receita.',
                ),
              ),
            );
            return;
          }
          // The amount comes from the bank: only the category changes.
          setState(() => record!.category = selectedCategory);
          return;
        }
        setState(() {
          record!.category = selectedCategory;
          changeRecordValue(_textEditingController.text.toLowerCase());
        });
      },
      child: Semantics(
        identifier: 'category-field',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              category != null
                  ? CategoryIconCircle(
                      iconEmoji: category.iconEmoji,
                      iconDataFromDefaultIconSet: category.icon,
                      backgroundColor: category.color,
                    )
                  : SizedBox(
                      width: 40,
                      child: Center(
                        child: Icon(
                          Icons.category_outlined,
                          size: 28,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
              Expanded(
                child: Container(
                  margin: EdgeInsets.fromLTRB(20, 10, 10, 10),
                  child: Text(
                    category?.name ?? 'Selecione a categoria',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      color: category == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              // Fork: which budget group the category counts in.
              if (category?.categoryType == CategoryType.expense)
                BudgetGroupLabel(
                  _selectedTags.contains(outOfBudgetTag)
                      ? outOfBudget
                      : BudgetPlan.decode(
                          ServiceConfig.sharedPreferences?.getString(
                            PreferencesKeys.budgetPlan,
                          ),
                        )?.groupOfCategory(category!.name),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createWalletCard() {
    final bool isExpense =
        record?.category?.categoryType == CategoryType.expense;
    return WalletTransferRow(
      selectedWallet: _selectedWallet,
      selectedDestinationWallet: _selectedDestinationWallet,
      showTransferSide:
          !_fromDinzo &&
          (isTransferFlow || (isExpense && _totalWalletCount > 1)),
      requireDestination: isTransferFlow,
      readOnly: _locked && !_dinzoWalletEditable,
      sourceLocked: _sourceLocked,
      walletNameSizeGroup: _walletNameSizeGroup,
      onSourceChanged: (wallet) {
        if (wallet?.id == _selectedWallet?.id) return;
        setState(() {
          _selectedWallet = wallet;
          if (_selectedDestinationWallet?.id == wallet?.id) {
            _selectedDestinationWallet = null;
          }
        });
      },
      onDestinationChanged: (wallet) {
        if (wallet?.id == _selectedDestinationWallet?.id) return;
        setState(() {
          _selectedDestinationWallet = wallet;
        });
      },
    );
  }

  Widget _createDateAndRepeatCard() {
    final bool isRecordFromPattern = record!.recurrencePatternId != null;

    final bool showRepeatRow = record!.id == null || recurrentPeriod != null;
    final bool showEndDateRow =
        recurrentPeriod != null &&
        (!isRecordFromPattern || localDisplayEndDate != null);

    final bool canChangeRepeat =
        !_locked && record!.id == null && record!.recurrencePatternId == null;
    final bool canChangeEndDate = !_locked && !isRecordFromPattern;

    final bool showClearRepeat =
        record!.id == null &&
        record!.recurrencePatternId == null &&
        recurrentPeriod != null;
    final bool showClearEndDate =
        localDisplayEndDate != null && record!.recurrencePatternId == null;

    return _buildDateRepeatSection(
      showRepeatRow: showRepeatRow,
      showEndDateRow: showEndDateRow,
      canChangeRepeat: canChangeRepeat,
      canChangeEndDate: canChangeEndDate,
      showClearRepeat: showClearRepeat,
      showClearEndDate: showClearEndDate,
    );
  }

  Widget _buildDateRepeatSection({
    required bool showRepeatRow,
    required bool showEndDateRow,
    required bool canChangeRepeat,
    required bool canChangeEndDate,
    required bool showClearRepeat,
    required bool showClearEndDate,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, showRepeatRow ? 0 : 12),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: 'date-field',
                  child: InkWell(
                    onTap: () async {
                      if (_locked) return;
                      FocusScope.of(context).unfocus();
                      DateTime initialDate = localDisplayDate ?? DateTime.now();
                      int firstDayOfWeek = getFirstDayOfWeekIndex();
                      // An upcoming occurrence can be months ahead.
                      final lastDate = DateTime.now().add(Duration(days: 365));
                      DateTime? result = await showDatePicker(
                        context: context,
                        initialDate: initialDate,
                        firstDate: DateTime(1970),
                        lastDate: initialDate.isAfter(lastDate)
                            ? DateTime(initialDate.year + 1, 12, 31)
                            : lastDate,
                        builder: (BuildContext context, Widget? child) {
                          return DatePickerUtils.buildDatePickerWithFirstDayOfWeek(
                            context,
                            child,
                            firstDayOfWeek,
                          );
                        },
                      );
                      if (result != null) {
                        setState(() {
                          // Something that happens once (a one-off estimate
                          // ends on its own day) moves with its date.
                          final end = localDisplayEndDate;
                          if (end != null &&
                              DateUtils.isSameDay(end, initialDate)) {
                            localDisplayEndDate = result;
                          }
                          localDisplayDate = result;
                          _hasTime = false;
                          _selectedTime = null;
                          record!.utcDateTime = DateTime(
                            result.year,
                            result.month,
                            result.day,
                          ).toUtc();
                          record!.timeZoneName = ServiceConfig.localTimezone;
                        });
                      }
                    },
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Center(
                            child: Icon(
                              Icons.calendar_today,
                              size: 28,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Container(
                            margin: EdgeInsets.fromLTRB(20, 10, 10, 10),
                            child: AutoSizeText(
                              getDateStr(localDisplayDate, shortYear: true),
                              maxLines: 1,
                              minFontSize: 10,
                              group: _dateTimeSizeGroup,
                              style: TextStyle(
                                fontSize: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Clock icon as separator — same Padding(horizontal: 8) as
              // the arrow_forward in the wallet row, so they align exactly.
              InkWell(
                onTap: () async {
                  if (_locked) return;
                  FocusScope.of(context).unfocus();
                  final TimeOfDay? result = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime ?? TimeOfDay.now(),
                  );
                  if (result != null) {
                    setState(() {
                      _hasTime = true;
                      _selectedTime = result;
                      DateTime date = localDisplayDate ?? DateTime.now();
                      DateTime localDateTime = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        result.hour,
                        result.minute,
                      );
                      record!.utcDateTime = localDateTime.toUtc();
                      record!.timeZoneName = ServiceConfig.localTimezone;
                    });
                  }
                },
                onLongPress: _locked
                    ? null
                    : () {
                        setState(() {
                          _hasTime = false;
                          _selectedTime = null;
                          DateTime date = localDisplayDate ?? DateTime.now();
                          record!.utcDateTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                          ).toUtc();
                          record!.timeZoneName = ServiceConfig.localTimezone;
                        });
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.access_time,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Semantics(
                  identifier: 'time-field',
                  child: InkWell(
                    onTap: () async {
                      if (_locked) return;
                      FocusScope.of(context).unfocus();
                      final TimeOfDay? result = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime ?? TimeOfDay.now(),
                      );
                      if (result != null) {
                        setState(() {
                          _hasTime = true;
                          _selectedTime = result;
                          DateTime date = localDisplayDate ?? DateTime.now();
                          DateTime localDateTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            result.hour,
                            result.minute,
                          );
                          record!.utcDateTime = localDateTime.toUtc();
                          record!.timeZoneName = ServiceConfig.localTimezone;
                        });
                      }
                    },
                    onLongPress: _locked
                        ? null
                        : () {
                            setState(() {
                              _hasTime = false;
                              _selectedTime = null;
                              DateTime date =
                                  localDisplayDate ?? DateTime.now();
                              record!.utcDateTime = DateTime(
                                date.year,
                                date.month,
                                date.day,
                              ).toUtc();
                              record!.timeZoneName =
                                  ServiceConfig.localTimezone;
                            });
                          },
                    child: Container(
                      margin: EdgeInsets.fromLTRB(20, 10, 10, 10),
                      child: AutoSizeText(
                        _hasTime && _selectedTime != null
                            ? _selectedTime!.format(context)
                            : 'Adicionar hora',
                        maxLines: 1,
                        minFontSize: 10,
                        group: _dateTimeSizeGroup,
                        style: TextStyle(
                          fontSize: 18,
                          color: _hasTime && _selectedTime != null
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Visibility(
          visible: showRepeatRow,
          child: Column(
            children: [
              Divider(indent: 75, thickness: 1),
              Semantics(
                identifier: 'repeat-field',
                child: InkWell(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      showEndDateRow ? 0 : 12,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Center(
                            child: Icon(
                              Icons.repeat,
                              size: 28,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.only(left: 20, right: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: DropdownButton<int>(
                                    iconSize: 0.0,
                                    items: recurrentIntervalDropdownList,
                                    selectedItemBuilder: (context) =>
                                        recurrentIntervalDropdownList.map((
                                          item,
                                        ) {
                                          final period = RecurrentPeriod
                                              .values[item.value!];
                                          return Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              recurrentPeriodDisplayString(
                                                period,
                                                customIntervalValue:
                                                    _customIntervalValue,
                                                customIntervalUnit:
                                                    _customIntervalUnit,
                                              ),
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.normal,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                    onChanged: canChangeRepeat
                                        ? (value) async {
                                            if (value == null) return;
                                            if (value ==
                                                RecurrentPeriod.Custom.index) {
                                              // Open a dialog rather than
                                              // committing to Custom
                                              // immediately: this keeps
                                              // recurrentPeriod/Index
                                              // untouched (so the dropdown
                                              // stays on its previous
                                              // selection) unless the user
                                              // explicitly confirms a valid
                                              // interval. Dismissing via
                                              // the barrier, back button, or
                                              // Cancel all resolve to null.
                                              final result =
                                                  await showDialog<
                                                    CustomIntervalSelection
                                                  >(
                                                    context: context,
                                                    builder: (context) =>
                                                        CustomIntervalDialog(
                                                          initialValue:
                                                              _customIntervalValue,
                                                          initialUnit:
                                                              _customIntervalUnit,
                                                        ),
                                                  );
                                              if (result == null) return;
                                              setState(() {
                                                recurrentPeriodIndex = value;
                                                recurrentPeriod =
                                                    RecurrentPeriod.Custom;
                                                _customIntervalValue =
                                                    result.value;
                                                _customIntervalUnit =
                                                    result.unit;
                                              });
                                            } else {
                                              setState(() {
                                                recurrentPeriodIndex = value;
                                                recurrentPeriod =
                                                    RecurrentPeriod
                                                        .values[value];
                                              });
                                            }
                                          }
                                        : null,
                                    onTap: () {
                                      FocusScope.of(context).unfocus();
                                    },
                                    value: recurrentPeriodIndex,
                                    underline: SizedBox(),
                                    isExpanded: true,
                                    hint: Text(
                                      'Não repetir',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                Visibility(
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      size: 28,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        recurrentPeriod = null;
                                        recurrentPeriodIndex = null;
                                        _customIntervalValue = null;
                                        _customIntervalUnit = null;
                                      });
                                    },
                                  ),
                                  visible: showClearRepeat,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // End Date Picker - visible when recurrent period is selected and end date is set
              Visibility(
                visible: showEndDateRow,
                child: Column(
                  children: [
                    Divider(indent: 75, thickness: 1),
                    Semantics(
                      identifier: 'end-date-field',
                      child: InkWell(
                        onTap: canChangeEndDate
                            ? () async {
                                FocusScope.of(context).unfocus();
                                // Default to 30 days from now (not 1 year, which is confusing)
                                DateTime initialDate =
                                    localDisplayEndDate ??
                                    DateTime.now().add(Duration(days: 30));
                                int firstDayOfWeek = getFirstDayOfWeekIndex();
                                DateTime? result = await showDatePicker(
                                  context: context,
                                  initialDate: initialDate,
                                  firstDate: localDisplayDate ?? DateTime(1970),
                                  lastDate: DateTime.now().add(
                                    Duration(days: 365 * 10),
                                  ),
                                  builder: (BuildContext context, Widget? child) {
                                    return DatePickerUtils.buildDatePickerWithFirstDayOfWeek(
                                      context,
                                      child,
                                      firstDayOfWeek,
                                    );
                                  },
                                );
                                if (result != null) {
                                  setState(() {
                                    localDisplayEndDate = result;
                                  });
                                }
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Center(
                                  child: Icon(
                                    Icons.event_busy,
                                    size: 28,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(left: 20, right: 10),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Data de término (opcional)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.7),
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              localDisplayEndDate != null
                                                  ? getDateStr(
                                                      localDisplayEndDate!,
                                                    )
                                                  : 'Não definido',
                                              style: TextStyle(
                                                fontSize: 18,
                                                color:
                                                    localDisplayEndDate != null
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Visibility(
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.close,
                                            size: 28,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              localDisplayEndDate = null;
                                            });
                                          },
                                        ),
                                        visible: showClearEndDate,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _createAmountCard() {
    final shouldAutofocus =
        !_locked &&
        passedRecord == null &&
        passedRecurrentRecordPattern == null;

    return Container(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 25, bottom: 10),
              child: SizedBox(
                width: 40,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        categorySign,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(right: 10),
                child: Semantics(
                  identifier: 'amount-field',
                  child: AmountInputField(
                    controller: _textEditingController,
                    labelText: 'Quantia',
                    enabled: !_locked,
                    allowNegative: false,
                    autofocus: shouldAutofocus,
                    onChanged: changeRecordValue,
                    validator:
                        isTransferFlow || _selectedDestinationWallet != null
                        ? _validatePositiveTransferAmount
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void changeRecordValue(String text) {
    var numericValue = tryParseCurrencyString(text);
    if (numericValue != null) {
      numericValue = numericValue.abs();
      if (isTransferFlow ||
          record!.category?.categoryType == CategoryType.expense) {
        numericValue = numericValue * -1;
      }
      record!.value = numericValue;
    }
  }

  String? _validatePositiveTransferAmount(String? text) {
    final amount = text == null ? null : tryParseSignedCurrencyString(text);
    if (amount == null || !amount.isFinite || amount <= 0) {
      return 'Insira um valor positivo.';
    }
    if (isMathExpression(text!)) return amountFormatErrorMessage();
    return null;
  }

  /// Evaluates any pending math expression left in the amount field and
  /// updates the record value accordingly.
  ///
  /// The debounced listener that normally resolves expressions waits a couple
  /// of seconds after typing. Saving before it fires would otherwise persist a
  /// concatenated amount (e.g. "10.05+1234" -> 10.051234) because the raw
  /// expression's operators are stripped during parsing.
  void _resolvePendingAmountExpression() {
    solveMathExpressionAndUpdateController(
      _textEditingController,
      onSolved: changeRecordValue,
    );
  }

  addOrUpdateRecord() async {
    _resolvePendingAmountExpression();

    if (isTransferFlow &&
        (_selectedWallet?.id == null ||
            _selectedDestinationWallet?.id == null ||
            _selectedWallet!.id == _selectedDestinationWallet!.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: MarkupText(
            'Selecione as carteiras de <b>origem</b> e <b>destino</b>',
          ),
        ),
      );
      return;
    }

    if (ServiceConfig.walletsEnabled) {
      record!.walletId = _selectedWallet?.id;
      record!.transferWalletId = _selectedDestinationWallet?.id;
    } else if (record!.id == null) {
      // New record while wallets are disabled: silently assign the default
      // wallet so that re-enabling wallets keeps data consistent. Existing
      // records keep their current wallet/transfer assignment untouched.
      record!.walletId = (await database.getDefaultWallet())?.id;
    }
    _applyOriginTag(isTransfer: record!.transferWalletId != null);
    record!.tags = _selectedTags; // Assign selected tags to the record
    _logger.debug('Saving record with ${_selectedTags.length} tags');
    if (record!.recurrencePatternId != null) {
      final dateChanged =
          _originalUtcDateTime != null &&
          record!.utcDateTime.millisecondsSinceEpoch !=
              _originalUtcDateTime!.millisecondsSinceEpoch;
      final amountChanged =
          _originalValue != null && record!.value != _originalValue;
      final receivedAmountChanged =
          (record!.transferValue ?? record!.value?.abs()) !=
          (_originalTransferValue ?? _originalValue?.abs());
      if (dateChanged || amountChanged || receivedAmountChanged) {
        record!.recurrencePatternId = null;
      }
    }
    if (record!.id == null) {
      await database.addRecord(record);
    } else {
      await database.updateRecordById(record!.id, record);
      if (_fromDinzo &&
          !DinzoSyncService.isSynthetic(record!.dinzoId) &&
          record!.title != _originalTitle) {
        await _pushTitleToDinzo();
      }
      if (_dinzoCategoryEditable &&
          record!.category?.name != _originalCategoryName) {
        await _pushCategoryToDinzo();
      }
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Hand-entered records carry exactly one origin tag: "Virtual" for moves
  /// between wallets, "Manual" for everything else. Dinzo imports carry none.
  void _applyOriginTag({required bool isTransfer}) {
    if (_fromDinzo) return;
    // The "Estimativa" box starts from the tag, so it decides (unchecking
    // turns an estimate into a plain recurrence).
    final estimate = _isEstimate;
    _selectedTags
      ..remove(DinzoSyncService.manualTag)
      ..remove(DinzoSyncService.virtualTag)
      ..remove(DinzoSyncService.estimateTag)
      ..add(
        estimate
            ? DinzoSyncService.estimateTag
            : isTransfer
            ? DinzoSyncService.virtualTag
            : DinzoSyncService.manualTag,
      );
    _applyAutoCash(isTransfer: isTransfer);
  }

  /// Puts or takes off the automatic "Dinheiro" tag ([_autoCash]): an
  /// estimate, a transfer or a Pix / boleto is not paid in cash.
  void _applyAutoCash({required bool isTransfer}) {
    if (!_autoCash) return;
    final cash =
        !_isEstimate &&
        !isTransfer &&
        Record.billingKindOf(_selectedTags) == null;
    if (cash) {
      _selectedTags.add(DinzoSyncService.cashTag);
    } else {
      _selectedTags.remove(DinzoSyncService.cashTag);
    }
  }

  /// Estimates become a recurrent pattern tagged [estimateTag]; without a
  /// repetition they occur once (end date = date). Returns false when the
  /// date is not in the future (it would vanish right away).
  bool _prepareEstimate() {
    // Keep the estimate once a repetition is set below (a forced estimate
    // only applies while there is none).
    _isEstimateChecked = true;
    final date = localDisplayDate ?? DateTime.now();
    final today = DateTime.now();
    if (!DateTime(
      date.year,
      date.month,
      date.day,
    ).isAfter(DateTime(today.year, today.month, today.day))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A estimativa precisa de uma data futura: ela some quando o dia chega.',
          ),
        ),
      );
      return false;
    }
    if (recurrentPeriod == null) {
      recurrentPeriod = RecurrentPeriod.EveryMonth;
      localDisplayEndDate = date;
    }
    return true;
  }

  Widget _createEstimateCard() {
    final forced = _forcedEstimate;
    return CheckboxListTile(
      value: _isEstimateChecked || forced,
      onChanged: forced || readOnly
          ? null
          : (v) => setState(() {
              _isEstimateChecked = v ?? false;
              _applyAutoCash(isTransfer: _selectedDestinationWallet != null);
            }),
      secondary: const Icon(Icons.query_stats, color: Color(0xFFF9A825)),
      title: const Text('Estimativa'),
      subtitle: Text(
        forced
            ? 'Os lançamentos reais vêm da Dinzo, então um lançamento avulso '
                  'vira estimativa (data futura). Para um recorrente de verdade, '
                  'como o vale-alimentação, escolha uma repetição. Dá pra liberar '
                  'lançamentos manuais em Configurações → Integrações com API.'
            : _isEditableOccurrence
            ? 'Desmarque e salve para virar um lançamento real nesta data, com '
                  'estes dados. As outras ocorrências continuam estimativa.'
            : 'Para prever os próximos meses. Fica no Extrato até ser vinculada '
                  'ao lançamento real: segure a estimativa e toque no lançamento. '
                  'Use a repetição para salário e gastos médios.',
      ),
    );
  }

  /// Marks the recurrence as paid by boleto or Pix (a [Record.billingTags]
  /// tag): the Extrato then flags each occurrence still without its code.
  Widget _createBillingCard() {
    final kind = Record.billingKindOf(_selectedTags);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Icon(
              Icons.qr_code_2,
              size: 28,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pago com boleto ou Pix',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Cada ocorrência pede o código dela. Sem ele, o ícone '
                  'pisca em vermelho no Extrato.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: '', label: Text('Não')),
                    ButtonSegment(value: 'Boleto', label: Text('Boleto')),
                    ButtonSegment(value: 'Pix', label: Text('Pix')),
                  ],
                  selected: {kind ?? ''},
                  onSelectionChanged: (v) => setState(() {
                    _selectedTags.removeAll(Record.billingTags);
                    if (v.first.isNotEmpty) _selectedTags.add(v.first);
                    _applyAutoCash(
                      isTransfer: _selectedDestinationWallet != null,
                    );
                  }),
                ),
                if (kind == 'Pix') _createDefaultPixTile(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The same Pix every month (e.g. to a person): a key, so each occurrence
  /// gets a copia-e-cola with its amount, or a fixed copia-e-cola.
  Widget _createDefaultPixTile() {
    final pix = _defaultPix;
    return ListTile(
      contentPadding: const EdgeInsets.only(top: 4),
      leading: const Icon(Icons.push_pin_outlined),
      title: const Text('Pix padrão'),
      subtitle: Text(
        pix == null
            ? 'Toque para definir a chave da pessoa: cada mês já sai com o '
                  'valor'
            : PixCode.isPayload(pix)
            ? 'Copia-e-cola fixo'
            : 'Chave ${PixCode.normalizeKey(pix)}'
                  '${_pixName == null ? '' : ' · $_pixName'} · com o valor',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: _editDefaultPix,
    );
  }

  Future<void> _editDefaultPix() async {
    final result = await DefaultPixSheet.show(
      context,
      initialKey: _defaultPix,
      initialName: _pixName,
    );
    if (result == null) return;
    setState(() {
      final k = result.$1.trim();
      final n = result.$2.trim();
      _defaultPix = k.isEmpty ? null : k;
      _pixName = k.isEmpty || n.isEmpty ? null : n;
    });
  }

  /// Fork: Pix copia-e-cola / boleto digitable line of this estimate
  /// occurrence, saved on the recurrence right away.
  Widget _createPaymentCodeTile() {
    final code = _paymentCode;
    final unknown = record!.dueDateUnknown;
    return ListTile(
      leading: const Icon(Icons.qr_code_2),
      title: const Text('Pix / linha digitável'),
      subtitle: Text(
        [
          code == null
              ? 'Toque para colar o código desta ocorrência'
              : '${Record.paymentCodeKind(code)} · $code',
          if (unknown)
            'O código não trouxe o vencimento: confira a data acima e salve.',
        ].join('\n'),
        maxLines: unknown ? 4 : 2,
        overflow: TextOverflow.ellipsis,
        style: unknown
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      trailing: code == null
          ? null
          : FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF9A825),
                foregroundColor: Colors.black87,
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Pagar'),
              onPressed: () => PaymentLauncher.open(context, code),
            ),
      onTap: _editPaymentCode,
    );
  }

  /// "Já paguei" only means something for a bill: a Pix / boleto code on the
  /// occurrence, or a recurrence paid by Pix or boleto. Once marked it stays,
  /// so it can be undone.
  bool get _canMarkPaid =>
      _paymentCode != null ||
      Record.billingKindOf(record!.tags) != null ||
      record!.markedPaid;

  /// Turns this estimate occurrence into a stored record of its own, with
  /// what is on the screen and on its date, tagged "Manual" ("Estimativa"
  /// unchecked, then save). The occurrence is consumed like a link
  /// ([EstimateLink.link]), so it leaves the estimate, which is deleted once
  /// nothing is left of it.
  Future<void> _makeReal() async {
    final occurrence = record!;
    if (ServiceConfig.walletsEnabled) occurrence.walletId = _selectedWallet?.id;
    final tags = {..._selectedTags}
      ..remove(DinzoSyncService.estimateTag)
      ..remove(DinzoSyncService.virtualTag)
      ..add(DinzoSyncService.manualTag);
    final id = await database.addRecord(
      Record(
        occurrence.value,
        occurrence.title,
        occurrence.category,
        occurrence.utcDateTime,
        timeZoneName: occurrence.timeZoneName,
        description: occurrence.description,
        walletId: occurrence.walletId,
        tags: tags,
      ),
    );
    await EstimateLink.link(occurrence, id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Agora é um lançamento real')),
    );
  }

  /// Says that changing this occurrence takes it out of its recurrence.
  Widget _createOccurrenceNote() {
    return ListTile(
      leading: const Icon(Icons.link_off),
      title: const Text('Só esta ocorrência'),
      subtitle: const Text(
        'Mudar valor, data ou outro dado aqui solta esta ocorrência do '
        'recorrente: ela fica como você deixar, mesmo que o recorrente '
        'mude depois, e não aparece outra no lugar.',
      ),
    );
  }

  /// Tags that only say where a record came from; they do not make an edit.
  static Set<String> _withoutOrigin(Set<String> tags) => {...tags}
    ..remove(DinzoSyncService.manualTag)
    ..remove(DinzoSyncService.virtualTag);

  /// Saves an upcoming occurrence edited by hand. Unchecking "Estimativa"
  /// makes it a real record; any other change makes it an item of its own
  /// ([RecurrentRecordService.saveOccurrence]). Nothing changed: a code
  /// without a due date gets the day shown as checked.
  Future<void> _saveOccurrence() async {
    _resolvePendingAmountExpression();
    final before = _occurrenceBefore!;
    final edited = record!;
    if (ServiceConfig.walletsEnabled) edited.walletId = _selectedWallet?.id;
    final wasEstimate = before.tags.contains(DinzoSyncService.estimateTag);
    if (wasEstimate && !_isEstimate) {
      await _makeReal();
      return;
    }
    _applyOriginTag(isTransfer: false);
    edited.tags = Set.of(_selectedTags);
    final changed =
        edited.value != before.value ||
        (edited.title ?? '') != (before.title ?? '') ||
        (edited.description ?? '') != (before.description ?? '') ||
        edited.category?.name != before.category?.name ||
        edited.walletId != before.walletId ||
        edited.utcDateTime.millisecondsSinceEpoch !=
            before.utcDateTime.millisecondsSinceEpoch ||
        !const SetEquality<String>().equals(
          _withoutOrigin(edited.tags),
          _withoutOrigin(before.tags),
        );
    final messenger = ScaffoldMessenger.of(context);
    if (!changed) {
      if (before.dueDateUnknown) {
        final pattern = await database.getRecurrentRecordPattern(
          before.recurrencePatternId,
        );
        if (pattern != null) {
          pattern.setDueDate(
            pattern.occurrenceDayOf(before),
            before.localDateTime,
          );
          await database.updateRecordPatternById(pattern.id, pattern);
        }
      }
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final leaves = _occurrenceLeavesRecurrence;
    final saved = await RecurrentRecordService.saveOccurrence(edited);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (saved != null && leaves) {
      messenger.showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text(
            'Só esta ocorrência mudou. O recorrente continua '
            'igual nas outras datas.',
          ),
        ),
      );
    }
  }

  /// "Já paguei" on this occurrence while the real record has not come.
  Widget _createMarkedPaidTile() {
    return CheckboxListTile(
      value: record!.markedPaid,
      onChanged: (v) async {
        await RecurrentRecordService.setMarkedPaid(record!, v ?? false);
        if (mounted) setState(() {});
      },
      secondary: const Icon(Icons.check_circle_outline, color: Colors.green),
      title: const Text('Já paguei'),
      subtitle: const Text(
        'Para de avisar enquanto o lançamento não chega da Dinzo. Quando '
        'chegar, vincule como sempre.',
      ),
    );
  }

  Future<void> _editPaymentCode() async {
    final local = record!.localDateTime;
    final name = record!.title == null || record!.title!.trim().isEmpty
        ? record!.category?.name ?? 'Conta'
        : record!.title!;
    final result = await PaymentCodeSheet.show(
      context,
      subtitle: '$name · ${getDateStr(local)}',
      initial: _paymentCode,
      amount: record!.value?.abs(),
    );
    if (result == null) return;
    final code = result.trim().isEmpty ? null : result.trim();
    final saved = await RecurrentRecordService.savePaymentCode(record!, code);
    if (saved == null) return;
    final pattern = saved.pattern;
    final day = saved.day;
    final dueAfter = saved.dueAfter;
    final moved = saved.moved;
    if (!mounted) return;
    // The code's amount is this occurrence's only (see valueFor).
    final before = record!.value;
    final after = pattern.valueFor(day);
    final shown = dueAfter ?? day;
    setState(() {
      _paymentCode = pattern.paymentCodeFor(day);
      record!.paymentCode = _paymentCode;
      record!.dueDateUnknown = pattern.dueDateMissing(day);
      if (moved) {
        localDisplayDate = DateTime(
          shown.year,
          shown.month,
          shown.day,
          local.hour,
          local.minute,
        );
      }
      if (after != null) {
        record!.value = after;
        final v = after.abs();
        _textEditingController.text = v % 1 == 0
            ? v.toInt().toString()
            : v.toString().replaceAll('.', getDecimalSeparator());
      }
    });
    final valueChanged =
        after != null && before != null && (after - before).abs() >= 0.005;
    final message = saved.message(code, before);
    // Saved: back to the list, where the message shows.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: valueChanged || moved ? 6 : 3),
        content: Text(message),
      ),
    );
  }

  /// Which estimate this real record was linked to (see EstimateLink).
  Widget _createEstimateLinkTile(EstimateLink link) {
    final details = [
      getDateStr(link.utcDateTime.toLocal()),
      if (link.value != null) getCurrencyValueString(link.value),
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.link, color: Color(0xFFF9A825)),
      title: Text('Vinculado à estimativa "${link.title ?? ''}"'),
      subtitle: Text(details),
    );
  }

  /// Leaves the record out of the budget ([outOfBudgetTag]): neither income
  /// for the 100% nor spending. Works on Dinzo records too: the sync keeps
  /// tags it did not write.
  Widget _createOutOfBudgetCard() {
    return CheckboxListTile(
      value: _selectedTags.contains(outOfBudgetTag),
      onChanged: (v) => setState(() {
        if (v ?? false) {
          _selectedTags.add(outOfBudgetTag);
        } else {
          _selectedTags.remove(outOfBudgetTag);
        }
      }),
      secondary: const Icon(Icons.money_off, color: Color(0xFF78909C)),
      title: const Text('Não considerar no orçamento'),
      subtitle: const Text(
        'Não conta como gasto nem entra nos 100% da receita. Ex.: comprou '
        'algo para alguém e a pessoa te devolveu por Pix: marque os dois.',
      ),
    );
  }

  Future<void> _pushCategoryToDinzo() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DinzoSyncService.pushCategory(record!);
      messenger.showSnackBar(
        const SnackBar(content: Text('Categoria atualizada também na Dinzo')),
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to change category in Dinzo');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Salvo aqui, mas não foi possível mudar a categoria na Dinzo: '
            '${e is DinzoApiException ? e.message : e}',
          ),
        ),
      );
    }
  }

  Future<void> _pushTitleToDinzo() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DinzoSyncService.pushTitle(record!);
      messenger.showSnackBar(
        const SnackBar(content: Text('Nome atualizado também na Dinzo')),
      );
    } catch (e, st) {
      _logger.handle(e, st, 'Failed to rename transaction in Dinzo');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Salvo aqui, mas não foi possível renomear na Dinzo: $e',
          ),
        ),
      );
    }
  }

  Future<void> _initWallet() async {
    if (!ServiceConfig.walletsEnabled) {
      // Wallets feature disabled: no wallet selection shown or restored.
      _selectedWallet = null;
      _selectedDestinationWallet = null;
      return;
    }
    final allWallets = await database.getAllWallets();
    final activeWallets = allWallets.where((w) => !w.isArchived).toList();

    Wallet? walletToSelect;
    if (_sourceLocked) {
      walletToSelect = await database.getDefaultWallet();
    } else if (record?.walletId != null) {
      // Fall back to the Predefined Wallet if the assigned wallet no longer exists
      walletToSelect =
          await database.getWalletById(record!.walletId!) ??
          await database.getPredefinedWallet() ??
          await database.getDefaultWallet();
    } else {
      // Start with the predefined wallet for new records
      walletToSelect = await database.getPredefinedWallet();
      if (walletToSelect == null && activeWallets.length == 1) {
        walletToSelect = activeWallets.first;
      }
      walletToSelect ??= await database.getDefaultWallet();
    }

    if (mounted) {
      setState(() {
        _selectedWallet = walletToSelect;
        _totalWalletCount = activeWallets.length;
      });
    }

    // Load destination wallet if editing an existing transfer
    if (record?.transferWalletId != null) {
      final destWallet = await database.getWalletById(
        record!.transferWalletId!,
      );
      if (destWallet != null && mounted) {
        setState(() {
          _selectedDestinationWallet = destWallet;
        });
      }
    }
  }

  Future<void> _loadSuggestedTags() async {
    if (record?.category != null) {
      Set<String> suggestedTags = Set();
      final mostUsedForCategory = (await database.getMostUsedTagsForCategory(
        record!.category!.name!,
        record!.category!.categoryType!,
      )).take(4);
      final mostRecentTags = (await database.getRecentlyUsedTags()).take(4);
      suggestedTags.addAll(mostUsedForCategory);
      suggestedTags.addAll(mostRecentTags);
      suggestedTags.removeAll(_selectedTags);
      setState(() {
        _suggestedTags = suggestedTags;
      });
    }
  }

  recurrentPeriodHasBeenUpdated(RecurrentRecordPattern toSet) {
    bool recurrentPeriodHasChanged =
        toSet.recurrentPeriod!.index !=
        passedRecurrentRecordPattern!.recurrentPeriod!.index;
    // A custom interval can change (e.g. "every 3 months" -> "every 6 months")
    // without the RecurrentPeriod enum value itself changing.
    bool customIntervalHasChanged =
        toSet.recurrentPeriod == RecurrentPeriod.Custom &&
        (toSet.customIntervalValue !=
                passedRecurrentRecordPattern!.customIntervalValue ||
            toSet.customIntervalUnit !=
                passedRecurrentRecordPattern!.customIntervalUnit);
    // Compare the UTC timestamps
    bool startingDateHasChanged =
        toSet.utcDateTime.millisecondsSinceEpoch !=
        passedRecurrentRecordPattern!.utcDateTime.millisecondsSinceEpoch;
    return recurrentPeriodHasChanged ||
        customIntervalHasChanged ||
        startingDateHasChanged;
  }

  addOrUpdateRecurrentPattern({id}) async {
    _resolvePendingAmountExpression();

    // Assign wallet and transfer fields before creating the pattern
    if (ServiceConfig.walletsEnabled) {
      record!.walletId = _selectedWallet?.id;
      record!.transferWalletId = _selectedDestinationWallet?.id;
    } else if (id == null) {
      // New recurrent pattern while wallets are disabled: silently assign the
      // default wallet. Existing patterns keep their wallet assignment.
      record!.walletId = (await database.getDefaultWallet())?.id;
    }
    // Create a new recurrent pattern from the updated record
    RecurrentRecordPattern recordPattern = RecurrentRecordPattern.fromRecord(
      record!,
      recurrentPeriod!,
      id: id,
      utcEndDate: localDisplayEndDate?.toUtc(),
      customIntervalValue: recurrentPeriod == RecurrentPeriod.Custom
          ? _customIntervalValue
          : null,
      customIntervalUnit: recurrentPeriod == RecurrentPeriod.Custom
          ? _customIntervalUnit
          : null,
    );
    _applyOriginTag(isTransfer: record!.transferWalletId != null);
    recordPattern.tags =
        _selectedTags; // Assign selected tags to the recurrent pattern
    // Fork: editing the pattern keeps the occurrences' payment codes.
    recordPattern.paymentCodes =
        Map.of(passedRecurrentRecordPattern?.paymentCodes ?? const {})
          ..remove(RecurrentRecordPattern.defaultPixKey)
          ..remove(RecurrentRecordPattern.pixNameKey);
    if (Record.billingKindOf(_selectedTags) == 'Pix' && _defaultPix != null) {
      recordPattern.paymentCodes[RecurrentRecordPattern.defaultPixKey] =
          _defaultPix!;
      if (_pixName != null && !PixCode.isPayload(_defaultPix!)) {
        recordPattern.paymentCodes[RecurrentRecordPattern.pixNameKey] =
            _pixName!;
      }
    }
    if (id != null) {
      // Preserve utcLastUpdate from the existing pattern so that
      // generateRecurrentRecordsFromDateTime does not regenerate all records
      // from the start date (which would create duplicates and ignore the last
      // update position).
      final existingPattern = await database.getRecurrentRecordPattern(id);
      if (existingPattern != null) {
        recordPattern.utcLastUpdate = existingPattern.utcLastUpdate;
      }
      // Always use the current time to delete future records, not the pattern's
      // start date. Using the start date would delete all past historical records.
      final now = DateTime.now().toUtc();
      if (recurrentPeriodHasBeenUpdated(recordPattern)) {
        await database.deleteFutureRecordsByPatternId(id, now);
        await database.deleteRecurrentRecordPatternById(id);
        await database.addRecurrentRecordPattern(recordPattern);
      } else {
        await database.deleteFutureRecordsByPatternId(id, now);
        await database.updateRecordPatternById(id, recordPattern);
      }
    } else {
      await database.addRecurrentRecordPattern(recordPattern);
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openTagSelectionDialog() async {
    final selectedTags = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) =>
            TagSelectionDialog(initialSelectedTags: _selectedTags),
      ),
    );

    if (selectedTags != null) {
      _logger.debug(
        'Tag selection applied: ${selectedTags.length} tags selected',
      );
      setState(() {
        if (selectedTags.contains(DinzoSyncService.cashTag) !=
            _selectedTags.contains(DinzoSyncService.cashTag)) {
          _autoCash = false;
        }
        _selectedTags = selectedTags;
        _applyOriginTag(isTransfer: _selectedDestinationWallet != null);
      });
    }
  }

  AppBar _getAppBar() {
    final bgColor = Theme.of(context).colorScheme.secondaryContainer;
    final fgColor = Theme.of(context).colorScheme.onSecondaryContainer;
    return AppBar(
      backgroundColor: bgColor,
      foregroundColor: fgColor,
      leading: BackButton(onPressed: () => Navigator.pop(context)),
      title: Text(readOnly ? 'View record' : 'Editar Item'),
      actions: <Widget>[
        Visibility(
          visible:
              ((widget.passedRecord != null ||
                      widget.passedRecurrentRecordPattern != null) &&
                  !readOnly) ||
              _singleOccurrencePattern != null,
          child: IconButton(
            icon: Semantics(
              identifier: "delete-button",
              child: const Icon(Icons.delete),
            ),
            tooltip: 'Excluir',
            onPressed: () async {
              AlertDialogBuilder deleteDialog = AlertDialogBuilder(
                'Ação crítica',
              ).addTrueButtonName('Sim').addFalseButtonName('Não');
              if (_singleOccurrencePattern != null) {
                deleteDialog = deleteDialog.addSubtitle(
                  'Quer mesmo excluir este Item?',
                );
              } else if (_isEditableOccurrence) {
                deleteDialog = deleteDialog.addSubtitle(
                  'Excluir só esta ocorrência? O recorrente continua '
                  'nas outras datas.',
                );
              } else if (widget.passedRecord != null) {
                deleteDialog = deleteDialog.addSubtitle(
                  'Você realmente deseja excluir este Item?',
                );
              } else {
                deleteDialog = deleteDialog.addSubtitle(
                  'Quer mesmo excluir este Item?',
                );
              }
              var continueDelete = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return deleteDialog.build(context);
                },
              );
              if (continueDelete) {
                if (_singleOccurrencePattern != null) {
                  final patternId = _singleOccurrencePattern!.id!;
                  await database.deleteFutureRecordsByPatternId(
                    patternId,
                    DateTime.now().toUtc(),
                  );
                  await database.deleteRecurrentRecordPatternById(patternId);
                } else if (_isEditableOccurrence) {
                  await RecurrentRecordService.deleteOccurrence(
                    _occurrenceBefore!,
                  );
                } else if (widget.passedRecord != null) {
                  if (record!.dinzoId != null) {
                    await DinzoSyncService.ignoreDeleted([record!.dinzoId!]);
                  }
                  await database.deleteRecordById(record!.id);
                } else {
                  String patternId = widget.passedRecurrentRecordPattern!.id!;
                  // Use the current UTC time when deleting future records
                  await database.deleteFutureRecordsByPatternId(
                    patternId,
                    DateTime.now().toUtc(),
                  );
                  await database.deleteRecurrentRecordPatternById(patternId);
                }
                Navigator.pop(context);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _getForm() {
    return Container(
      margin: EdgeInsets.only(bottom: 80),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _createAmountCard(),
            Divider(height: 1),
            _createTitleCard(),
            Divider(height: 1),
            _createCategoryCard(),
            Divider(height: 1),
            if (ServiceConfig.walletsEnabled) ...[
              _createWalletCard(),
              // Fork: part of a Dinzo purchase paid with a caixinha.
              if (!readOnly && SplitPayment.supports(record))
                SplitPaymentTile(purchase: record!),
              // Fork: an aporte the wallet to invest could not pay alone.
              if (!readOnly && record?.id != null && record!.isInvestmentBuy)
                AporteShortfallTile(aporte: record!),
              Divider(height: 1),
            ],
            _createDateAndRepeatCard(),
            Divider(height: 1),
            if (EstimateLink.decode(record?.estimateLink) case final link?) ...[
              _createEstimateLinkTile(link),
              Divider(height: 1),
            ],
            if (_isEditableOccurrence && _occurrenceLeavesRecurrence) ...[
              _createOccurrenceNote(),
              Divider(height: 1),
            ],
            if ((_sourceLocked ||
                    passedRecurrentRecordPattern != null ||
                    (_isEditableOccurrence && _isEstimateOccurrence)) &&
                !_fromDinzo &&
                _selectedDestinationWallet == null) ...[
              _createEstimateCard(),
              Divider(height: 1),
            ],
            if (_showsBillingCard) ...[
              _createBillingCard(),
              Divider(height: 1),
            ],
            if (_isEstimateOccurrence || _isBillingOccurrence) ...[
              _createPaymentCodeTile(),
              Divider(height: 1),
              if (_canMarkPaid) ...[
                _createMarkedPaidTile(),
                Divider(height: 1),
              ],
            ],
            if (!readOnly) ...[_createOutOfBudgetCard(), Divider(height: 1)],
            _createTagsSection(),
            Divider(height: 1),
            _createAddNoteCard(),
          ],
        ),
      ),
    );
  }

  Widget _createTagsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Center(
                  child: Icon(
                    Icons.label_outline,
                    size: 28,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_locked && _selectedTags.isEmpty)
                Expanded(
                  child: Container(
                    margin: EdgeInsets.fromLTRB(20, 10, 10, 10),
                    child: Text(
                      'Nenhuma tag aplicada.',
                      style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              if (!_locked && _selectedTags.isEmpty)
                Expanded(
                  child: InkWell(
                    onTap: _openTagSelectionDialog,
                    child: Container(
                      margin: EdgeInsets.fromLTRB(20, 10, 10, 10),
                      width: double.infinity,
                      child: Text(
                        'Adicionar tags',
                        style: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_selectedTags.isNotEmpty)
                Flexible(
                  child: Container(
                    margin: EdgeInsets.fromLTRB(20, 10, 10, 10),
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: [
                        ...KnownTag.sortForDisplay(_selectedTags).map((tag) {
                          return TagChip(
                            labelText: tag,
                            isSelected: true,
                            onSelected:
                                _locked ||
                                    tag == DinzoSyncService.manualTag ||
                                    tag == DinzoSyncService.virtualTag ||
                                    tag == DinzoSyncService.estimateTag ||
                                    tag == outOfBudgetTag
                                ? null
                                : (selected) {
                                    setState(() {
                                      if (tag == DinzoSyncService.cashTag) {
                                        _autoCash = false;
                                      }
                                      _selectedTags.remove(tag);
                                      _suggestedTags.add(tag);
                                    });
                                  },
                          );
                        }).toList(),
                        if (!_locked)
                          TagChip(
                            labelText: "+",
                            isSelected: false,
                            onSelected: (selected) {
                              _openTagSelectionDialog();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (!_locked && _suggestedTags.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(left: 60, bottom: 6),
              child: _createSuggestedTagsChips(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _createSuggestedTagsChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags sugeridas',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        SizedBox(height: 5),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            ..._suggestedTags.map((tag) {
              return TagChip(
                labelText: tag,
                isSelected: _selectedTags.contains(tag),
                onSelected: _locked
                    ? null
                    : (selected) {
                        setState(() {
                          if (tag == DinzoSyncService.cashTag) {
                            _autoCash = false;
                          }
                          if (selected) {
                            _selectedTags.add(tag);
                            _suggestedTags.remove(tag);
                          } else {
                            _selectedTags.remove(tag);
                          }
                        });
                      },
              );
            }).toList(),
          ],
        ),
      ],
    );
  }

  isARecurrentPattern() {
    return recurrentPeriod != null && record?.recurrencePatternId == null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _getAppBar(),
      resizeToAvoidBottomInset: false,
      body: SingleChildScrollView(child: _getForm()),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton(
              heroTag: null,
              onPressed: () async {
                _resolvePendingAmountExpression();
                if (_formKey.currentState!.validate()) {
                  if (_isEditableOccurrence) {
                    await _saveOccurrence();
                    return;
                  }
                  // A new estimate needs a future date; an existing one
                  // (its pattern) keeps its dates.
                  if (_isEstimate && _sourceLocked && !_prepareEstimate()) {
                    return;
                  }
                  if (isARecurrentPattern()) {
                    String? recurrentPatternId;
                    if (passedRecurrentRecordPattern != null) {
                      recurrentPatternId =
                          this.passedRecurrentRecordPattern!.id;
                    }
                    await addOrUpdateRecurrentPattern(id: recurrentPatternId);
                  } else {
                    await addOrUpdateRecord();
                  }
                }
              },
              tooltip: 'Salvar',
              child: Semantics(
                identifier: 'save-button',
                child: const Icon(Icons.save),
              ),
            ),
    );
  }
}
