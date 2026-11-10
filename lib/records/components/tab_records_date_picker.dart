import 'package:flutter/material.dart';
import 'package:aupp/services/locale-service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:month_picker_dialog/month_picker_dialog.dart';

import '../../components/year-picker.dart' as yp;
import '../../helpers/datetime-utility-functions.dart';
import '../../helpers/date_picker_utils.dart';
import '../../helpers/records-utility-functions.dart';
import '../../settings/constants/homepage-time-interval.dart';
import '../../services/service-config.dart';
import '../controllers/tab_records_controller.dart';

/// Whether the Extrato shows a month or a year: a picked period ([from]–[to])
/// wins over the homepage [setting]. Anything else is
/// [HomepageTimeInterval.All] (range, all, week).
HomepageTimeInterval shownPeriodOf(
    DateTime? from, DateTime? to, HomepageTimeInterval setting) {
  if (from == null || to == null) return setting;
  if (isFullYear(from, to)) return HomepageTimeInterval.CurrentYear;
  final calendarMonth = from.day == 1 &&
      to.year == from.year &&
      to.month == from.month &&
      to.day == getEndOfMonth(from.year, from.month).day;
  // A month cycle that starts on another day also comes from the month view.
  final days = to.difference(from).inDays;
  final monthCycle =
      setting == HomepageTimeInterval.CurrentMonth && days >= 27 && days <= 31;
  if (calendarMonth || monthCycle) return HomepageTimeInterval.CurrentMonth;
  return HomepageTimeInterval.All;
}

class TabRecordsDatePicker extends StatelessWidget {
  final TabRecordsController controller;
  final VoidCallback onDateSelected;

  const TabRecordsDatePicker({
    Key? key,
    required this.controller,
    required this.onDateSelected,
  }) : super(key: key);

  /// Tapping the period on the Extrato: the month view opens the month
  /// picker and the year view the year picker, straight away. Any other view
  /// (date range, all, week) opens the full dialog.
  static Future<void> pickSamePeriod(
    BuildContext context,
    TabRecordsController controller,
    VoidCallback onDateSelected,
  ) async {
    final picker = TabRecordsDatePicker(
      controller: controller,
      onDateSelected: onDateSelected,
    );
    switch (picker._shownPeriod()) {
      case HomepageTimeInterval.CurrentMonth:
        await picker._pickMonth(context, inDialog: false);
      case HomepageTimeInterval.CurrentYear:
        await picker._pickYear(context, inDialog: false);
      default:
        await showDialog(context: context, builder: (_) => picker);
    }
  }

  HomepageTimeInterval _shownPeriod() => shownPeriodOf(
        controller.customIntervalFrom,
        controller.customIntervalTo,
        getHomepageTimeIntervalEnumSetting(),
      );

  @override
  Widget build(BuildContext context) {
    var isDarkMode = Theme.of(context).brightness == Brightness.dark;
    var boxBackgroundColor = isDarkMode
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.secondary;

    return SimpleDialog(
      title: Text('Período'),
      children: <Widget>[
        _buildDialogOption(
          context,
          title: 'Mês',
          icon: FontAwesomeIcons.calendarDays.data,
          color: boxBackgroundColor,
          onPressed: () => _pickMonth(context),
        ),
        _buildDialogOption(
          context,
          title: 'Ano',
          icon: FontAwesomeIcons.calendarDay.data,
          color: boxBackgroundColor,
          onPressed: () => _pickYear(context),
        ),
        _buildDialogOption(
          context,
          title: 'Intervalo de datas',
          icon: FontAwesomeIcons.calendarWeek.data,
          color: boxBackgroundColor,
          onPressed: () => _pickDateRange(context),
        ),
        _buildDialogOption(
          context,
          title: 'Tudo',
          icon: FontAwesomeIcons.calendar.data,
          color: boxBackgroundColor,
          onPressed: () => _pickAllTime(context),
        ),
        if (controller.customIntervalFrom != null)
          _buildDialogOption(
            context,
            title: 'Redefinir para as datas padrão',
            icon: FontAwesomeIcons.calendarXmark.data,
            color: boxBackgroundColor,
            onPressed: () => _resetToDefault(context),
          ),
      ],
    );
  }

  Widget _buildDialogOption(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SimpleDialogOption(
      onPressed: onPressed,
      child: ListTile(
        title: Text(title),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
          child: Icon(
            icon,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _pickMonth(BuildContext context, {bool inDialog = true}) async {
    DateTime? currentDate = controller.customIntervalFrom ?? DateTime.now();
    int currentYear = DateTime.now().year;

    DateTime? dateTime = await showMonthPicker(
      context: context,
      lastDate: DateTime(currentYear + 1, 12),
      initialDate: currentDate,
    );

    if (dateTime != null) {
      DateTime from = DateTime(dateTime.year, dateTime.month, 1);
      DateTime to = getEndOfMonth(dateTime.year, dateTime.month);
      String header = getMonthStr(dateTime);

      updateAndClose(context, from, to, header, dateTime.month,
          inDialog: inDialog);
    }
  }

  Future<void> _pickYear(BuildContext context, {bool inDialog = true}) async {
    DateTime currentDate = DateTime.now();
    DateTime initialDate =
        DateTime((controller.customIntervalFrom ?? currentDate).year, 1);
    DateTime lastDate = DateTime(currentDate.year + 1, 1);
    DateTime firstDate = DateTime(1950, currentDate.month);

    DateTime? yearPicked = await yp.showYearPicker(
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: initialDate,
      context: context,
    );

    if (yearPicked != null) {
      DateTime from = DateTime(yearPicked.year, 1, 1);
      DateTime to = DateTime(yearPicked.year, 12, 31, 23, 59);
      String header = getYearStr(from);

      updateAndClose(context, from, to, header, null, inDialog: inDialog);
    }
  }

  Future<void> _pickDateRange(BuildContext context) async {
    DateTime currentDate = DateTime.now();
    DateTime lastDate = DateTime(currentDate.year + 1, currentDate.month + 1);
    DateTime firstDate = DateTime(1970);
    DateTimeRange initialDateTimeRange = DateTimeRange(
      start: DateTime.now().subtract(Duration(days: 7)),
      end: currentDate,
    );

    int firstDayOfWeek = getFirstDayOfWeekIndex();

    DateTimeRange? dateTimeRange = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialDateTimeRange,
      locale: LocaleService.locale,
      builder: (BuildContext context, Widget? child) {
        return DatePickerUtils.buildDatePickerWithFirstDayOfWeek(
            context, child, firstDayOfWeek);
      },
    );

    if (dateTimeRange != null) {
      DateTime from = DateTime(
        dateTimeRange.start.year,
        dateTimeRange.start.month,
        dateTimeRange.start.day,
      );
      DateTime to = DateTime(
        dateTimeRange.end.year,
        dateTimeRange.end.month,
        dateTimeRange.end.day,
        23,
        59,
      );
      String header = getDateRangeStr(from, to);

      updateAndClose(context, from, to, header, to.month);
    }
  }

  Future<void> _pickAllTime(BuildContext context) async {
    DateTime currentDate = DateTime.now();
    DateTime? firstRecordDate =
        await getDateTimeFirstRecord(ServiceConfig.database);
    // Fall back to today if there are no records yet, so the range collapses
    // to "nothing to show" instead of a meaningless placeholder like 1970.
    DateTime from = firstRecordDate ?? currentDate;
    DateTime to = getEndOfMonth(currentDate.year, currentDate.month);
    String header = 'Tudo';

    if (!context.mounted) return;
    updateAndClose(context, from, to, header, null);
  }

  void updateAndClose(BuildContext context, DateTime from, DateTime to,
      String header, int? backgroundImageIndex,
      {bool inDialog = true}) async {
    if (backgroundImageIndex != null) {
      controller.backgroundImageIndex = backgroundImageIndex;
    }
    controller.updateCustomInterval(from, to, header);
    await controller.updateRecurrentRecordsAndFetchRecords();
    onDateSelected();
    if (inDialog && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _resetToDefault(BuildContext context) async {
    controller.customIntervalFrom = null;
    controller.customIntervalTo = null;
    controller.backgroundImageIndex = DateTime.now().month;
    await controller.updateRecurrentRecordsAndFetchRecords();
    controller.onStateChanged();
    onDateSelected();
    Navigator.of(context, rootNavigator: true).pop();
  }
}
