import 'package:flutter/material.dart';
import 'package:aupp/services/service-config.dart';

import '../../helpers/records-utility-functions.dart';
import '../controllers/tab_records_controller.dart';
import 'styled_action_buttons.dart';

class TabRecordsAppBar extends StatelessWidget {
  final TabRecordsController controller;
  final bool isAppBarExpanded;
  final bool simplifyAppBar;
  /// Opens the accounts shown in the Extrato (person button).
  final VoidCallback onAccountsTapped;

  /// Some account is switched off: the person button shows a dot.
  final bool accountsFiltered;

  /// Fork: sync state pill next to the person button (see RecordsPage).
  final Widget? syncPill;
  final VoidCallback onDatePickerPressed;

  /// Tapping the period text opens the month/year picker (fork-only).
  final VoidCallback? onPeriodTapped;
  final VoidCallback onStatisticsPressed;

  /// Raises the period, when a sheet covers the bottom of the picture.
  final double titleLift;

  /// Opens the Extrato as a table (computer only).
  final VoidCallback onSearchPressed;

  // Select-mode props (all optional — only used when isSelectMode is true)
  final bool isSelectMode;
  final int selectedCount;
  final VoidCallback? onClose;
  final VoidCallback? onDelete;
  final VoidCallback? onSelectAll;
  final VoidCallback? onDuplicate;
  final VoidCallback? onMoveToWallet;

  /// Title-cases the selected records' names (fork-only).
  final VoidCallback? onTitleCase;

  /// Hides the selected records from the Extrato, or shows them again when
  /// [selectionAllHidden] (fork-only).
  final VoidCallback? onToggleHidden;
  final bool selectionAllHidden;

  const TabRecordsAppBar({
    Key? key,
    required this.controller,
    required this.isAppBarExpanded,
    this.simplifyAppBar = false,
    required this.onAccountsTapped,
    this.accountsFiltered = false,
    this.syncPill,
    required this.onDatePickerPressed,
    this.onPeriodTapped,
    required this.onStatisticsPressed,
    required this.onSearchPressed,
    this.isSelectMode = false,
    this.selectedCount = 0,
    this.titleLift = 0,
    this.onClose,
    this.onDelete,
    this.onSelectAll,
    this.onDuplicate,
    this.onMoveToWallet,
    this.onTitleCase,
    this.onToggleHidden,
    this.selectionAllHidden = false,
  }) : super(key: key);

  /// Height of the bar with its picture.
  static double expandedHeightFor(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.20;
    return height < 180.0 ? 180.0 : height;
  }

  /// Height of the bar without its picture (toolbar + period row).
  static const double simplifiedHeight = kToolbarHeight + 48;

  @override
  Widget build(BuildContext context) {
    final headerFontSize = controller.getHeaderFontSize();
    final headerPaddingBottom = controller.getHeaderPaddingBottom();
    final canShiftBack = controller.canShiftBack();
    final canShiftForward = controller.canShiftForward();

    if (simplifyAppBar) {
      return SliverAppBar(
        elevation: 0,
        forceElevated: isSelectMode,
        backgroundColor: Theme.of(context).primaryColor,
        automaticallyImplyLeading: false,
        pinned: true,
        leadingWidth: isSelectMode ? null : _leadingWidth,
        leading: isSelectMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onClose,
              )
            : _buildLeading(),
        title: isSelectMode
            ? Text(
                "$selectedCount ${'selecionado'}",
                style: const TextStyle(color: Colors.white),
              )
            : null,
        actions: isSelectMode ? _buildSelectionActions() : _buildActions(),
        bottom: isSelectMode
            ? null
            : _buildBottomBar(headerFontSize, canShiftBack, canShiftForward),
      );
    }

    return SliverAppBar(
      elevation: 0,
      forceElevated: isSelectMode,
      backgroundColor: Theme.of(context).primaryColor,
      automaticallyImplyLeading: false,
      pinned: true,
      expandedHeight: expandedHeightFor(context),
      leadingWidth:
          isSelectMode || !isAppBarExpanded ? null : _leadingWidth,
      leading: isSelectMode
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onClose,
            )
          : isAppBarExpanded
              ? _buildLeading()
              : null,
      title: isSelectMode
          ? Text(
              "$selectedCount ${'selecionado'}",
              style: const TextStyle(color: Colors.white),
            )
          : null,
      actions: isSelectMode ? _buildSelectionActions() : _buildActions(),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const <StretchMode>[
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
          StretchMode.fadeTitle,
        ],
        centerTitle: false,
        titlePadding: _getTitlePadding(
            headerPaddingBottom + titleLift, canShiftBack, canShiftForward),
        title: isSelectMode && !isAppBarExpanded
            ? null
            : _buildTitle(headerFontSize, canShiftBack, canShiftForward),
        background: _buildBackground(),
      ),
    );
  }

  /// Bottom row of the simplified app bar: the period text with its shift
  /// arrows, mirroring the search app bar's two-row (toolbar + bottom) shape.
  PreferredSizeWidget _buildBottomBar(
      double headerFontSize, bool canShiftBack, bool canShiftForward) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 5, 10),
        child: _buildTitle(headerFontSize, canShiftBack, canShiftForward),
      ),
    );
  }

  /// Person button (the accounts shown) in the AppBar leading slot.
  Widget _buildLeading() {
    return Row(
      children: [
        Badge(
          isLabelVisible: accountsFiltered,
          smallSize: 9,
          alignment: const AlignmentDirectional(0.45, -0.45),
          child: StyledActionButton(
            icon: Icons.person,
            onPressed: onAccountsTapped,
            tooltip: 'Contas',
            semanticsId: 'accounts',
          ),
        ),
        if (syncPill != null) syncPill!,
      ],
    );
  }

  /// Room for the person button plus the sync pill.
  double? get _leadingWidth => syncPill == null ? null : 150;

  List<Widget> _buildActions() {
    const double actionButtonScale = 1.0;
    return <Widget>[
      StyledActionButton(
        icon: Icons.calendar_today,
        onPressed: onDatePickerPressed,
        semanticsId: 'select-date',
        scaleFactor: actionButtonScale,
      ),
      StyledActionButton(
        icon: Icons.donut_small,
        onPressed: onStatisticsPressed,
        semanticsId: 'statistics',
        scaleFactor: actionButtonScale,
      ),
      StyledActionButton(
        icon: Icons.search,
        onPressed: onSearchPressed,
        semanticsId: 'search-button',
        scaleFactor: actionButtonScale,
      ),
    ];
  }

  List<Widget> _buildSelectionActions() {
    return [
      IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.white),
        tooltip: 'Excluir',
        onPressed: selectedCount > 0 ? onDelete : null,
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white),
        onSelected: (value) {
          if (value == 'select_all') {
            onSelectAll?.call();
          } else if (value == 'duplicate') {
            onDuplicate?.call();
          } else if (value == 'move_wallet') {
            onMoveToWallet?.call();
          } else if (value == 'toggle_hidden') {
            onToggleHidden?.call();
          } else if (value == 'title_case') {
            onTitleCase?.call();
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
          if (ServiceConfig.walletsEnabled)
            PopupMenuItem(
              value: 'move_wallet',
              child: Text('Mover para carteira'),
            ),
        ],
      ),
    ];
  }

  Widget _buildTitle(
      double headerFontSize, bool canShiftBack, bool canShiftForward) {
    final bool showShiftButtons = simplifyAppBar || isAppBarExpanded;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (showShiftButtons && canShiftBack)
          _buildShiftButton(Icons.arrow_left, -1),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isSelectMode ? null : onPeriodTapped,
            child: Semantics(
              identifier: 'date-text',
              child: Text(
                controller.header,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(color: Colors.white, fontSize: headerFontSize),
              ),
            ),
          ),
        ),
        if (showShiftButtons && canShiftForward)
          _buildShiftButton(Icons.arrow_right, 1),
        if (showShiftButtons && controller.canToggleMonthYear)
          _buildMonthYearToggle(),
      ],
    );
  }

  /// Fork: switches the period on screen between its month and its year.
  Widget _buildMonthYearToggle() {
    return SizedBox(
      height: 30,
      width: 34,
      child: IconButton(
        tooltip: controller.showsYear ? 'Ver mês' : 'Ver ano',
        icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 22),
        onPressed: () => controller.toggleMonthYear(),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildShiftButton(IconData icon, int direction) {
    return SizedBox(
      height: 30,
      width: 30,
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 24),
        onPressed: () => controller.shiftInterval(direction),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildBackground() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withAlpha((255.0 * 0.1).round()),
        BlendMode.srcATop,
      ),
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            fit: BoxFit.cover,
            image: getBackgroundImage(controller.backgroundImageIndex),
          ),
        ),
      ),
    );
  }

  EdgeInsets _getTitlePadding(
      double headerPaddingBottom, bool canShiftBack, bool canShiftForward) {
    if (!isAppBarExpanded) {
      // When collapsed the title sits in the toolbar alongside the leading
      // widget (56 dp) — use the standard Material offset (56 + 16 = 72) so
      // the text doesn't slide behind the person button.
      return EdgeInsets.fromLTRB(15, 15, 15, headerPaddingBottom);
    }
    return EdgeInsets.fromLTRB(
      canShiftBack ? 0 : 15,
      15,
      canShiftForward ? 0 : 15,
      headerPaddingBottom,
    );
  }
}
