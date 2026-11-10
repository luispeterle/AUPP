import 'dart:math' as math;

import 'package:aupp/components/known-tags.dart';
import 'package:aupp/dashboard/dashboard-data.dart';
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
import 'package:aupp/records/refund-link-ui.dart';
import 'package:aupp/records/refund-link.dart';
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
    for (final estimate
        in rows.where((r) => r.estimateMatch != null).toList()) {
      if (!rows.contains(estimate.estimateMatch)) continue;
      rows.remove(estimate);
      rows.insert(rows.indexOf(estimate.estimateMatch!), estimate);
    }
    // A matched pair is one item, so no divider falls between the two.
    final items = <List<Record>>[];
    for (var i = 0; i < rows.length; i++) {
      if (widget.onLinkMatch != null &&
          i + 1 < rows.length &&
          identical(rows[i].estimateMatch, rows[i + 1])) {
        items.add([rows[i], rows[++i]]);
      } else {
        items.add([rows[i]]);
      }
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      // The pair's own outline separates it, so no divider next to it.
      separatorBuilder: (context, index) =>
          items[index].length == 2 || items[index + 1].length == 2
              ? const SizedBox.shrink()
              : const Divider(
                  height: 1, thickness: 0.5, endIndent: 10, indent: 10),
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      itemBuilder: /*1*/ (context, i) {
        final item = items[i];
        if (item.length == 2) return _buildMatchPair(item[0], item[1], parts);
        return _buildMovementRow(item[0], splitPart: parts[item[0].dinzoId]);
      },
    );
  }

  static const _estimateAmber = Color(0xFFF9A825);

  /// Width of a row's trailing (amount plus the icon left of it, see
  /// [_buildMovementRow]), to place the pair's link button beside it.
  double _trailingWidth(Record r, Map<String, Record> parts) {
    final amount = TextPainter(
      text: TextSpan(
        text: formatMoney(r.value!),
        style: DefaultTextStyle.of(context).style.merge(_currencyFontStyle),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final icon = r.markedPaid
        ? 32.0
        : _offersRefund(r) ||
              r.investShortfall != null ||
              r.needsCategory ||
              r.needsPaymentCode ||
              r.paymentCode != null
        ? 42.0
        : r.dueDateUnknown
        ? 16.0
        : 0.0;
    final width = amount.width + icon;
    amount.dispose();
    return parts[r.dinzoId] != null ? math.max(width, 150) : width;
  }

  /// An estimate and the real record of the same day and amount, as one
  /// block: outlined, no divider between them, and a link between the two
  /// icons (icon - link - icon) that links them when tapped.
  Widget _buildMatchPair(
    Record estimate,
    Record real,
    Map<String, Record> parts,
  ) {
    final busy = widget.isSelectMode || widget.linkingEstimate != null;
    // Center of the row icons: ListTile left padding (8) + half the icon (18).
    const iconCenterX = 26.0;
    const iconRadius = 18.0;
    const linkSize = 34.0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _estimateAmber.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Stack(
        children: [
          // Line from the bottom of the upper icon to the top of the lower
          // one (icons sit at the middle of each half).
          Positioned(
            left: iconCenterX - 1,
            width: 2,
            top: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, box) {
                final length = box.maxHeight / 2 - 2 * iconRadius;
                if (length <= 0) return const SizedBox.shrink();
                return Center(
                  child: Container(
                    height: length,
                    color: _estimateAmber.withValues(alpha: 0.7),
                  ),
                );
              },
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMovementRow(estimate, splitPart: parts[estimate.dinzoId]),
              _buildMovementRow(real, splitPart: parts[real.dinzoId]),
            ],
          ),
          // Right, between the two rows, just left of the widest trailing.
          Positioned(
            right:
                12 +
                math.max(
                  _trailingWidth(estimate, parts),
                  _trailingWidth(real, parts),
                ) +
                10,
            top: 0,
            bottom: 0,
            child: Center(
              child: Tooltip(
                message: 'Vincular estimativa',
                child: Material(
                  color: _estimateAmber,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : () => widget.onLinkMatch!(estimate),
                    child: SizedBox(
                      width: linkSize,
                      height: linkSize,
                      child: Transform.rotate(
                        angle: math.pi / 2,
                        child: const Icon(
                          Icons.link,
                          size: 20,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
      badgeIcon: movement.refundLink != null
          ? Icons.undo
          : movement.tags.contains(DinzoSyncService.estimateTag)
          ? Icons.query_stats
          : movement.tags.contains(DinzoSyncService.virtualTag)
              ? Icons.savings
              : movement.tags.contains(DinzoSyncService.manualTag)
                  ? Icons.edit
                  : null,
      badgeColor: movement.refundLink != null
          ? const Color(0xFF43A047)
          : movement.tags.contains(DinzoSyncService.estimateTag)
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
          if (_partialRefundOf(movement) case final refunded?)
            _buildPartialRefundNote(refunded),
          if (movement.tags.any((t) => t != Record.hiddenTag))
            _buildTagChipsRow(
                movement.tags.where((t) => t != Record.hiddenTag).toSet()),
        ],
      ),
      // Fork: tapping the code copies it to pay; a boleto / Pix
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
          : _offersRefund(movement)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRefundButton(movement),
                const SizedBox(width: 8),
                _buildRecordAmountWidget(movement),
              ],
            )
          : movement.needsCategory
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BlinkingAlertIcon(
                  Icons.question_mark,
                  message: 'Sem categoria: toque para dizer o que foi',
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

  /// What came back of an expense through a partial refund, if any.
  double? _partialRefundOf(Record r) {
    final link = RefundLink.decode(r.refundLink);
    return link != null && link.isPartial && !link.isRefund
        ? link.refunded
        : null;
  }

  /// "Reembolso parcial de R\$ 100,00" under the expense's title.
  Widget _buildPartialRefundNote(double refunded) {
    return Padding(
      padding: const EdgeInsets.only(top: 2.0),
      child: Text(
        'Reembolso parcial de ${formatMoney(refunded)}',
        style: const TextStyle(fontSize: 12.5, color: Color(0xFF43A047)),
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
      message: 'Copiar $kind',
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

  /// Money in named like a refund, not linked yet ([RefundLink]).
  bool _offersRefund(Record r) =>
      RefundLink.canBeRefund(r) && RefundLink.looksLikeRefund(r);

  /// Fork: money in that looks like a refund: tapping links it to an
  /// expense, the suggested one ([RefundLink.markSuggestions]) or another.
  Widget _buildRefundButton(Record refund) {
    final expense = refund.refundSuggestion;
    return Tooltip(
      message: expense == null
          ? 'Vincular como estorno'
          : 'Parece estorno de "${expense.title}"',
      child: Material(
        color: const Color(0xFFF9A825),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.isSelectMode || widget.linkingEstimate != null
              ? null
              : () async {
                  if (await linkRefund(
                        context,
                        refund,
                        suggestion: expense,
                      ) &&
                      widget.onListBackCallback != null) {
                    await widget.onListBackCallback!();
                  }
                },
          child: const SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.undo, size: 18, color: Colors.black87),
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

  /// Fork: a card bill due this day, as a reminder ([RecordsPerDay.reminders]):
  /// shaped like a row, but faded, italic, with an outlined icon and a gray
  /// amount, so it reads as a note and not as money. It sums nowhere.
  Widget _buildReminderRow(UpcomingBill bill) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final bank =
        bill.connector == null ? null : KnownTag.bankIn(bill.connector!);
    return Opacity(
      opacity: 0.7,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
        horizontalTitleGap: 10,
        minLeadingWidth: 36,
        minVerticalPadding: 8,
        visualDensity: const VisualDensity(vertical: -1),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: muted, width: 1.2),
          ),
          alignment: Alignment.center,
          child: bank != null
              ? BankMark(bank, size: 20)
              : Icon(Icons.credit_card, size: 18, color: muted),
        ),
        title: Text(
          'Fatura ${bank?.name ?? bill.cardTitle}',
          style: _titleFontStyle.copyWith(fontStyle: FontStyle.italic),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Icon(Icons.notifications_none, size: 13, color: muted),
            const SizedBox(width: 3),
            Text(
              'Lembrete · não soma',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
        trailing: Text(
          '${bill.isEstimate ? '≈ ' : ''}${formatMoney(bill.amount.abs())}',
          style: _currencyFontStyle.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
            color: muted,
          ),
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
          for (final (i, bill) in widget._movementDay.reminders.indexed) ...[
            if (i > 0 || widget._movementDay.records!.isNotEmpty)
              const Divider(
                  height: 1, thickness: 0.5, endIndent: 10, indent: 10),
            _buildReminderRow(bill),
          ],
        ],
      )),
    );
  }
}
