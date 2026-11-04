import 'package:flutter/material.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/models/wallet.dart';
import 'package:aupp/components/category_icon_circle.dart';
import 'package:aupp/statistics/statistics-models.dart';
import 'package:aupp/statistics/statistics-utils.dart';
import 'package:aupp/statistics/category-tag-records-page.dart';
import 'package:aupp/statistics/category-tag-balance-page.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/helpers/records-utility-functions.dart';

/// Base widget for summary rows displaying aggregated data.
///
/// Provides common layout with label, amount, percentage, and progress bar.
/// Subclasses must implement [buildLeading] and [onTap].
abstract class SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final double maxSum;
  final double totalSum;
  final List<Record?> records;
  final DateTime? from;
  final DateTime? to;
  final DateTime? selectedDate;
  final AggregationMethod? aggregationMethod;
  final bool showPercentage;
  final bool showProgressBar;


  /// Signed (non-absolute) values used to color the amounts by sign.
  ///
  /// [value]/[originalValue] may be absolute magnitudes for display; when the
  /// totals carry their sign already (e.g. category sums) these stay null and
  /// the signed values fall back to [value]/[originalValue].
  final double? signedValue;

  const SummaryRow({
    Key? key,
    required this.label,
    required this.value,
    required this.maxSum,
    required this.totalSum,
    required this.records,
    this.from,
    this.to,
    this.selectedDate,
    this.aggregationMethod,
    this.showPercentage = true,
    this.showProgressBar = true,
    this.signedValue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final percentage = (100 * value.abs()) / totalSum;
    final percentageBar = value.abs() / maxSum;
    final percentageStr = percentage.toStringAsFixed(2);
    final biggerFont = const TextStyle(fontSize: 16.0);

    Widget amountWidget;
    {
      final valueStr = getCurrencyValueString(value.abs());
      // Colorize by sign (red for expenses, green for income) using the real
      // signed value, matching the rest of the colorized amounts in the app.
      final amountColor = getAmountColor(
          signedValue ?? value, Theme.of(context).brightness);
      amountWidget = Text(
        showPercentage ? '$valueStr ($percentageStr%)' : valueStr,
        style: amountColor != null
            ? biggerFont.copyWith(color: amountColor)
            : biggerFont,
      );
    }

    final List<Widget> columnChildren = [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: biggerFont,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            margin: EdgeInsets.only(left: 5),
            child: amountWidget,
          ),
        ],
      ),
    ];

    if (showProgressBar) {
      columnChildren.add(
        Container(
          padding: EdgeInsets.fromLTRB(0, 8, 0, 0),
          child: SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              value: percentageBar,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      );
    }

    return ListTile(
      onTap: () => onTap(context),
      contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
      horizontalTitleGap: 16.0,
      minLeadingWidth: 40.0,
      title: Column(
        children: columnChildren,
      ),
      leading: buildLeading(context),
    );
  }

  /// Builds the leading widget (icon). Must be implemented by subclasses.
  Widget buildLeading(BuildContext context);

  /// Called when the row is tapped. Must be implemented by subclasses.
  void onTap(BuildContext context);
}

/// Widget that displays a row for a single category in the summary list.
class CategorySummaryRow extends SummaryRow {
  final Category category;

  CategorySummaryRow({
    Key? key,
    required this.category,
    required double value,
    required double maxSum,
    required double totalSum,
    required List<Record?> records,
    DateTime? from,
    DateTime? to,
    DateTime? selectedDate,
    AggregationMethod? aggregationMethod,
  }) : super(
          key: key,
          label: category.name!,
          value: value,
          maxSum: maxSum,
          totalSum: totalSum,
          records: records,
          from: from,
          to: to,
          selectedDate: selectedDate,
          aggregationMethod: aggregationMethod,
        );

  @override
  Widget buildLeading(BuildContext context) {
    return CategoryIconCircle(
      iconEmoji: category.iconEmoji,
      iconDataFromDefaultIconSet: category.icon,
      backgroundColor: category.color,
      overlayIcon: category.isArchived ? Icons.archive : null,
    );
  }

  @override
  void onTap(BuildContext context) {
    final categoryRecords = records
        .where((element) => element?.category?.name == category.name)
        .toList();

    DateTime? detailFrom = from;
    DateTime? detailTo = to;
    List<Record?> detailRecords = categoryRecords;
    DateTime? detailSelectedDate = selectedDate;

    if (selectedDate != null) {
      detailFrom = selectedDate;
      detailTo = getEndOfInterval(selectedDate!, aggregationMethod);

      // Include all category records within the date range, not just the single selected date
      // Use inclusive range check: not before start AND not after end
      detailRecords = categoryRecords.where((r) {
        final recordDate = r!.dateTime;
        return !recordDate.isBefore(detailFrom!) &&
            !recordDate.isAfter(detailTo!);
      }).toList();

      detailSelectedDate = null;
    }
    String intervalTitle = getDateRangeStr(detailFrom!, detailTo!);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryTagRecordsPage(
          title: "$intervalTitle: ${category.name}",
          records: detailRecords,
          from: detailFrom,
          to: detailTo,
          aggregationMethod: aggregationMethod,
          category: category,
          headerColor: category.color,
          selectedDate: detailSelectedDate,
        ),
      ),
    );
  }
}

/// Widget that displays a row for a single tag in the summary list.
class TagSummaryRow extends SummaryRow {
  final bool isBalance;

  TagSummaryRow({
    Key? key,
    required String tag,
    required double value,
    required double maxSum,
    required double totalSum,
    required List<Record?> records,
    DateTime? from,
    DateTime? to,
    DateTime? selectedDate,
    AggregationMethod? aggregationMethod,
    this.isBalance = false,
    double? signedValue,
  }) : super(
          key: key,
          label: tag,
          value: value,
          maxSum: maxSum,
          totalSum: totalSum,
          records: records,
          from: from,
          to: to,
          selectedDate: selectedDate,
          aggregationMethod: aggregationMethod,
          signedValue: signedValue,
        );

  @override
  Widget buildLeading(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.label, color: Colors.blue, size: 20),
    );
  }

  @override
  void onTap(BuildContext context) {
    final tagRecords = records
        .where((element) => element?.tags.contains(label) ?? false)
        .toList();

    DateTime? detailFrom = from;
    DateTime? detailTo = to;
    List<Record?> detailRecords = tagRecords;
    DateTime? detailSelectedDate = selectedDate;

    if (selectedDate != null) {
      detailFrom = selectedDate;
      detailTo = getEndOfInterval(selectedDate!, aggregationMethod);
      detailRecords = tagRecords.where((r) {
        final recordDate = r!.dateTime;
        return !recordDate.isBefore(detailFrom!) &&
            !recordDate.isAfter(detailTo!);
      }).toList();
      detailSelectedDate = null;
    }
    String intervalTitle = getDateRangeStr(detailFrom!, detailTo!);

    if (isBalance) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CategoryTagBalancePage(
            title: "$intervalTitle: #$label",
            records: detailRecords,
            from: detailFrom!,
            to: detailTo!,
            aggregationMethod: aggregationMethod,
            selectedDate: detailSelectedDate,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CategoryTagRecordsPage(
            title: "$intervalTitle: #$label",
            records: detailRecords,
            from: detailFrom,
            to: detailTo,
            aggregationMethod: aggregationMethod,
            headerColor: Colors.blue,
            selectedDate: detailSelectedDate,
          ),
        ),
      );
    }
  }
}

/// Widget that displays a row for viewing all records in the selection.
/// Shows as a special row with yellow star icon, used when a date interval is selected.
class ViewAllSummaryRow extends SummaryRow {
  final VoidCallback onTapCallback;

  ViewAllSummaryRow({
    required String label,
    required double totalAmount,
    required this.onTapCallback,
    List<Record?> records = const [],
  }) : super(
          label: label,
          value: totalAmount,
          maxSum: totalAmount,
          totalSum: totalAmount,
          records: records,
          showPercentage: false,
          showProgressBar: false,
        );

  @override
  Widget buildLeading(BuildContext context) {
    return CategoryIconCircle(
      iconEmoji: null,
      iconDataFromDefaultIconSet: Icons.align_horizontal_left,
      backgroundColor: Colors.yellow.shade700,
    );
  }

  @override
  void onTap(BuildContext context) => onTapCallback();
}

/// Widget that displays a row for a single wallet in the summary list.
class WalletSummaryRow extends SummaryRow {
  final Wallet wallet;
  final bool isBalance;

  WalletSummaryRow({
    Key? key,
    required this.wallet,
    required double value,
    required double maxSum,
    required double totalSum,
    required List<Record?> records,
    DateTime? from,
    DateTime? to,
    DateTime? selectedDate,
    AggregationMethod? aggregationMethod,
    this.isBalance = false,
    double? signedValue,
  }) : super(
          key: key,
          label: wallet.name,
          value: value,
          maxSum: maxSum,
          totalSum: totalSum,
          records: records,
          from: from,
          to: to,
          selectedDate: selectedDate,
          aggregationMethod: aggregationMethod,
          signedValue: signedValue,
        );

  @override
  Widget buildLeading(BuildContext context) {
    return CategoryIconCircle(
      iconEmoji: wallet.iconEmoji,
      iconDataFromDefaultIconSet: wallet.icon,
      backgroundColor: wallet.color,
    );
  }

  @override
  void onTap(BuildContext context) {
    final walletRecords =
        records.where((element) => element?.walletId == wallet.id).toList();

    DateTime? detailFrom = from;
    DateTime? detailTo = to;
    List<Record?> detailRecords = walletRecords;
    DateTime? detailSelectedDate = selectedDate;

    if (selectedDate != null) {
      detailFrom = selectedDate;
      detailTo = getEndOfInterval(selectedDate!, aggregationMethod);
      detailRecords = walletRecords.where((r) {
        final recordDate = r!.dateTime;
        return !recordDate.isBefore(detailFrom!) &&
            !recordDate.isAfter(detailTo!);
      }).toList();
      detailSelectedDate = null;
    }
    String intervalTitle = getDateRangeStr(detailFrom!, detailTo!);

    if (isBalance) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CategoryTagBalancePage(
            title: "$intervalTitle: ${wallet.name}",
            records: detailRecords,
            from: detailFrom!,
            to: detailTo!,
            aggregationMethod: aggregationMethod,
            selectedDate: detailSelectedDate,
            walletName: wallet.name,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CategoryTagRecordsPage(
            title: "$intervalTitle: ${wallet.name}",
            records: detailRecords,
            from: detailFrom,
            to: detailTo,
            aggregationMethod: aggregationMethod,
            headerColor: wallet.color,
            selectedDate: detailSelectedDate,
            walletName: wallet.name,
          ),
        ),
      );
    }
  }
}
