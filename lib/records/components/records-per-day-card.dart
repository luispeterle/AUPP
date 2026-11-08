import 'package:aupp/components/known-tags.dart';
import 'package:aupp/components/missing-payment-code-icon.dart';
import 'package:aupp/components/due-date-badge.dart';
import 'package:aupp/desktop/record-popup.dart';
import 'package:aupp/dinzo/dinzo-sync-service.dart';
import 'package:aupp/dinzo/estimate-link.dart';
import 'package:aupp/dinzo/payment-launcher.dart';
import 'package:flutter/material.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/helpers/records-utility-functions.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/records-per-day.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/records/edit-record-page.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/services/transfer-icon-service.dart';

import '../../components/category_icon_circle.dart';
import '../../services/database/database-interface.dart';

class RecordsPerDayCard extends StatefulWidget {
  /// RecordsCard renders a MovementPerDay object as a Card
  /// The card contains an header with date and the balance of the day
  /// and a body, containing the list of movements included in the MovementsPerDay object
  /// refreshParentMovementList is a callback method called every time the card may change
  /// for example, from the deletion of a record or the editing of the record.
  /// The callback should re-fetch the newest version of the records list from the database and rebuild the card

  final Function? onListBackCallback;
  final RecordsPerDay _movementDay;
  final bool isSelectMode;
  final Set<int> selectedRecordIds;
  final void Function(int)? onRecordLongPressed;
  final void Function(int)? onRecordTapped;

  /// Called with the day's date when the date header is tapped (e.g. to
  /// start a new entry pre-dated to that day). Null means no action.
  final void Function(DateTime date)? onDateTapped;

  /// Estimate occurrence being linked (see EstimateLink): it shows selected
  /// and tapping a real record calls [onLinkTarget].
  final Record? linkingEstimate;

  /// Long press on an estimate occurrence (starts linking it).
  final void Function(Record estimate)? onEstimateLongPressed;
  final void Function(Record target)? onLinkTarget;
  final void Function(Record estimate)? onLinkMatch;

  const RecordsPerDayCard(this._movementDay,
      {this.onListBackCallback,
      this.isSelectMode = false,
      this.selectedRecordIds = const {},
      this.onRecordLongPressed,
      this.onRecordTapped,
      this.onDateTapped,
      this.linkingEstimate,
      this.onEstimateLongPressed,
      this.onLinkTarget,
      this.onLinkMatch});

  @override
  _RecordsPerDayCardState createState() => _RecordsPerDayCardState();
}

class _RecordsPerDayCardState extends State<RecordsPerDayCard>
    with AutomaticKeepAliveClientMixin {
  // Fork: denser rows (smaller fonts, icon further left, less spacing).
  // The amount leads the row: bigger and bold, tabular figures so amounts
  // line up; the name is plain and smaller.
  final _titleFontStyle =
      const TextStyle(fontSize: 15.0, fontWeight: FontWeight.normal);
  final _currencyFontStyle = const TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Map<int, Wallet> _walletsById = {};
  final DatabaseInterface _database = ServiceConfig.database;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    if (!ServiceConfig.walletsEnabled) {
      if (mounted && _walletsById.isNotEmpty) {
        setState(() {
          _walletsById = {};
        });
      }
      return;
    }
    final wallets = await _database.getAllWallets();
    if (!mounted) return;
    setState(() {
      _walletsById = {
        for (final w in wallets)
          if (w.id != null) w.id!: w
      };
    });
  }

  Color? _amountColor(Record record) =>
      getRecordAmountColor(record, Theme.of(context).brightness);

  Widget _buildRecordAmountWidget(Record record) {
    final color = _amountColor(record);
    final style = color != null
        ? _currencyFontStyle.copyWith(color: color)
        : _currencyFontStyle;
    return Text(formatMoney(record.value!),
        style: style, textAlign: TextAlign.right);
  }

  double _dayBalanceNumeric() =>
      recordsTotal(balanceRelevantRecords(widget._movementDay.records ?? []));

  String _formatDayBalance() {
    final records = balanceRelevantRecords(widget._movementDay.records ?? []);
    // A day made up entirely of transfers has nothing to sum into a
    // meaningful balance — leave the header blank rather than show 0.
    if (records.isEmpty) return '';
    return formatMoney(recordsTotal(records));
  }

  /// Fork: the part of a purchase paid with a caixinha (Record.splitPrefix)
  /// is shown on the purchase itself (icon + "R\$ 600 por: Caixinha"), not
  /// as a row of its own — only when the purchase is in this same list (a
  /// view of the caixinha alone still lists its outgoing part).
  Map<String, Record> get _splitParts {
    final records = widget._movementDay.records!.whereType<Record>();
    final purchases = {
      for (final r in records)
        if (r.dinzoId != null && !r.isSplitPart) r.dinzoId!,
    };
    return {
      for (final r in records)
        if (r.isSplitPart && purchases.contains(r.splitParentDinzoId))
          r.splitParentDinzoId!: r,
    };
  }

  Widget _buildMovements() {
    /// Returns a ListView with all the movements contained in the MovementPerDay object
    final parts = _splitParts;
    final rows = [
      for (final r in widget._movementDay.records!.whereType<Record>())
        if (!(r.isSplitPart && parts.containsKey(r.splitParentDinzoId))) r,
    ];
    // An estimate right above the real record it matches.
    for (final estimate in rows.where((r) => r.estimateMatch != null).toList()) {
      if (!rows.contains(estimate.estimateMatch)) continue;
      rows.remove(estimate);
      rows.insert(rows.indexOf(estimate.estimateMatch!), estimate);
    }
    return ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: rows.length,
        separatorBuilder: (context, index) {
          if (identical(rows[index].estimateMatch, rows[index + 1]) &&
              widget.onLinkMatch != null) {
            return _buildMatchLink(rows[index]);
          }
          return Divider(
            height: 1,
            thickness: 0.5,
            endIndent: 10,
            indent: 10,
          );
        },
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        itemBuilder: /*1*/ (context, i) {
          return _buildMovementRow(rows[i], splitPart: parts[rows[i].dinzoId]);
        });
  }

  /// The dot joining an estimate to the real record of the same day and amount.
  Widget _buildMatchLink(Record estimate) {
    final scheme = Theme.of(context).colorScheme;
    final busy = widget.isSelectMode || widget.linkingEstimate != null;
    return Row(
      children: [
        const Expanded(child: Divider(height: 1, thickness: 0.5, indent: 10)),
        Tooltip(
          message: 'Vincular estimativa',
          child: Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: busy ? null : () => widget.onLinkMatch!(estimate),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.link, size: 18, color: scheme.onPrimary),
              ),
            ),
          ),
        ),
        const Expanded(child: Divider(height: 1, thickness: 0.5, endIndent: 10)),
      ],
    );
  }

  Widget _buildLeading(Record movement, bool isSelected, {Record? splitPart}) {
    final transferIcon = TransferIconService.icon;
    final transferEmoji = TransferIconService.iconEmoji;
    final isUncategorizedTransfer = movement.isTransfer && movement.category == null;
    final base = CategoryIconCircle(
      circleSize: 36,
      mainIconSize: 18,
      overlayIconSize: 13,
      iconEmoji: isUncategorizedTransfer
          ? transferEmoji
          : movement.category?.iconEmoji,
      iconDataFromDefaultIconSet: isUncategorizedTransfer
          ? transferIcon
          : movement.category?.icon ?? Icons.swap_horiz,
      backgroundColor: isUncategorizedTransfer
          ? TransferIconService.color
          : movement.category?.color,
      overlayIcon: movement.recurrencePatternId != null ? Icons.repeat : null,
      topOverlayIcon: splitPart != null
          ? Icons.savings
          : movement.isTransfer && movement.category != null &&
                  transferEmoji == null
              ? transferIcon
              : null,
      topOverlayEmoji: movement.isTransfer && movement.category != null
          ? transferEmoji
          : null,
      topOverlayBackgroundColor: splitPart != null
          ? Colors.purple
          : movement.isTransfer && movement.category != null
              ? TransferIconService.color
              : null,
      badgeIcon: movement.tags.contains(DinzoSyncService.estimateTag)
          ? Icons.query_stats
          : movement.tags.contains(DinzoSyncService.virtualTag)
              ? Icons.savings
              : movement.tags.contains(DinzoSyncService.manualTag)
                  ? Icons.edit
                  : null,
      badgeColor: movement.tags.contains(DinzoSyncService.estimateTag)
          ? const Color(0xFFF9A825)
          : movement.tags.contains(DinzoSyncService.virtualTag)
              ? Colors.purple
              : null,
    );
    if (!widget.isSelectMode && widget.linkingEstimate == null) return base;
    return Stack(
      alignment: Alignment.center,
      children: [
        base,
        AnimatedOpacity(
          opacity: isSelected ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.88),
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildMovementRow(Record movement, {Record? splitPart}) {
    /// Returns a ListTile rendering the single movement row

    final linking = widget.linkingEstimate != null;
    final isEstimate = EstimateLink.isOccurrence(movement);
    final isSelected = linking
        ? EstimateLink.sameOccurrence(movement, widget.linkingEstimate)
        : widget.isSelectMode &&
            movement.id != null &&
            widget.selectedRecordIds.contains(movement.id);
    final canSelect = !movement.isFutureRecord && movement.id != null;

    final VoidCallback? holdAction = !widget.isSelectMode &&
            !linking &&
            isEstimate &&
            widget.onEstimateLongPressed != null
        ? () => widget.onEstimateLongPressed!(movement)
        : widget.isSelectMode ||
                linking ||
                movement.isFutureRecord ||
                movement.id == null
            ? null
            : () => widget.onRecordLongPressed?.call(movement.id!);

    final listTile = ListTile(
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      horizontalTitleGap: 10,
      minLeadingWidth: 36,
      minVerticalPadding: 8,
      visualDensity: const VisualDensity(vertical: -1),
      onTap: linking
          ? isEstimate
              ? () => widget.onEstimateLongPressed?.call(movement)
              : EstimateLink.canBeLinked(movement)
                  ? () => widget.onLinkTarget?.call(movement)
                  : null
          : widget.isSelectMode && canSelect
          ? () => widget.onRecordTapped?.call(movement.id!)
          : !widget.isSelectMode
              ? () async {
                  // Lists may show view copies (destination side of a
                  // transfer, subcategory rolled up into its parent in the
                  // statistics) — always edit the canonical DB record.
                  final recordToEdit = movement.id != null
                      ? (await _database.getRecordById(movement.id!)) ??
                          movement
                      : movement;
                  if (!mounted) return;
                  await openRecord(
                    context,
                    (context) => EditRecordPage(
                      passedRecord: recordToEdit,
                      readOnly: movement.isFutureRecord,
                    ),
                  );
                  if (widget.onListBackCallback != null)
                    await widget.onListBackCallback!();
                }
              : null,
      onLongPress: holdAction,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            movement.title == null || movement.title!.trim().isEmpty
                ? movement.category?.name ?? 'Transferência'
                : movement.title!,
            style: _titleFontStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (movement.isHidden) _buildHiddenNote(),
          if (movement.tags.any((t) => t != Record.hiddenTag))
            _buildTagChipsRow(
                movement.tags.where((t) => t != Record.hiddenTag).toSet()),
        ],
      ),
      // Fork: paying opens the bank apps of the phone; a boleto / Pix
      // occurrence still without its code blinks red until it gets one.
      trailing: movement.markedPaid
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Tooltip(
                  message: 'Já pago, esperando chegar da Dinzo',
                  child: Icon(Icons.check_circle, color: Colors.green),
                ),
                const SizedBox(width: 8),
                _buildRecordAmountWidget(movement),
              ],
            )
          : movement.investShortfall != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BlinkingAlertIcon(
                  Icons.priority_high,
                  message: 'O Investir não tinha todo o dinheiro do aporte',
                ),
                const SizedBox(width: 8),
                _buildRecordAmountWidget(movement),
              ],
            )
          : movement.needsPaymentCode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MissingPaymentCodeIcon(Record.billingKindOf(movement.tags)!),
                const SizedBox(width: 8),
                _buildRecordAmountWidget(movement),
              ],
            )
          : movement.paymentCode != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DueDateBadge(
                  show: movement.dueDateUnknown,
                  child: _buildPayButton(movement.paymentCode!),
                ),
                const SizedBox(width: 8),
                _buildRecordAmountWidget(movement),
              ],
            )
          : movement.dueDateUnknown
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DueDateBadge(show: true, child: SizedBox(width: 8)),
                const SizedBox(width: 8),
                _buildRecordAmountWidget(movement),
              ],
            )
          : splitPart == null
          ? _buildRecordAmountWidget(movement)
          : Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildRecordAmountWidget(movement),
                _buildSplitNote(splitPart),
              ],
            ),
      leading: _buildLeading(movement, isSelected, splitPart: splitPart),
    );

    Widget result = GestureDetector(
      // Right click does what holding does on the phone.
      onSecondaryTap: holdAction,
      child: Material(
        color: isSelected
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.4)
            : Colors.transparent,
        child: listTile,
      ),
    );

    // Apply reduced opacity for future and hidden records
    if ((movement.isFutureRecord || movement.isHidden) && !isSelected) {
      return Opacity(
        opacity: 0.5,
        child: result,
      );
    }

    return result;
  }

  /// "Oculto" under the title of a record hidden from the Extrato, listed
  /// only because "Exibir ocultos" is on.
  Widget _buildHiddenNote() {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            'Oculto do Extrato',
            style: TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// "R\$ 600,00 por: Caixinha Saude" under the purchase amount.
  Widget _buildSplitNote(Record part) {
    final amount = (part.value ?? 0).abs();
    final payer = _walletsById[part.walletId]?.name ?? 'caixinha';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(
        '${getCurrencyValueString(amount)} '
        'por: $payer',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
    );
  }

  /// Fork: an estimate with a payment code ([Record.paymentCode]): amber
  /// Pix / boleto button left of the amount; tap copies the code and offers
  /// the bank apps ([PaymentLauncher]).
  Widget _buildPayButton(String code) {
    final kind = Record.paymentCodeKind(code);
    final IconData icon = kind == 'Pix'
        ? KnownTag.of('Pix')!.icon!
        : kind == 'Boleto'
            ? KnownTag.of('Boleto')!.icon!
            : Icons.qr_code_2;
    return Tooltip(
      message: 'Pagar $kind',
      child: Material(
        color: const Color(0xFFF9A825),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.isSelectMode
              ? null
              : () => PaymentLauncher.open(context, code),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 17, color: Colors.black87),
          ),
        ),
      ),
    );
  }

  /// Tags under the title: a known tag (bank, payment method, origin) is
  /// just its icon, without a border; any other tag is a small outlined pill.
  Widget _buildTagChipsRow(Set<String> tags) {
    const height = 22.0;
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tag in KnownTag.sortForDisplay(tags))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: KnownTag.of(tag) != null
                    ? TagLabel(tag,
                        size: height, textStyle: const TextStyle(fontSize: 11))
                    : Container(
                        height: height,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: outline, width: 0.8),
                          borderRadius: BorderRadius.circular(height / 2),
                        ),
                        child: Text(tag, style: const TextStyle(fontSize: 11)),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// Day header (day number plus weekday/month). Tapping it starts a new
  /// entry pre-dated to that day when [RecordsPerDayCard.onDateTapped] is set.
  Widget _buildDateHeader() {
    // One line ("28  terça-feira, outubro 2026") to keep the header short.
    final content = Row(
      children: [
        Text(
          widget._movementDay.dateTime!.day.toString(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Text(
          '${extractWeekdayString(widget._movementDay.dateTime!)}, '
          '${extractMonthString(widget._movementDay.dateTime!)} '
          '${extractYearString(widget._movementDay.dateTime!)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
    final onDateTapped = widget.onDateTapped;
    if (onDateTapped == null) return content;
    return InkWell(
      onTap: () => onDateTapped(widget._movementDay.dateTime!),
      borderRadius: BorderRadius.circular(4),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: Container(
          child: Column(
        children: <Widget>[
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDateHeader(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 22, 0),
                      child: Text(
                        _formatDayBalance(),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: getAmountColor(_dayBalanceNumeric(),
                                Theme.of(context).brightness)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  ])),
          const Divider(
            height: 8,
            thickness: 0.5,
          ),
          _buildMovements(),
        ],
      )),
    );
  }
}
