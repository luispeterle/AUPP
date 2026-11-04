import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:aupp/disguise/calc-engine.dart';
import 'package:aupp/disguise/calculator-gate.dart';
import 'package:aupp/disguise/split-bill-page.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';

/// Yellow palette of the disguise calculator, shared with the split page.
class CalcColors {
  static const background = Color(0xFFFFD65B);
  static const paper = Color(0xFFFFF8DC);
  static const paperLine = Color(0xFFF0E2B0);
  static const ink = Color(0xFF2E2300);
  static const muted = Color(0xFF8A7330);
  static const digitKey = Color(0xFFFFF1C2);
  static const functionKey = Color(0xFFF5C842);
  static const operatorKey = Color(0xFF2E2300);
  static const operatorText = Color(0xFFFFD65B);
  static const accent = Color(0xFFE09A00);

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: background,
        brightness: Brightness.light,
        primary: ink,
        onPrimary: operatorText,
        surface: paper,
        onSurface: ink,
      ),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
    );
  }
}

class _TapeEntry {
  final String expr;
  final double result;
  final DateTime at;

  _TapeEntry(this.expr, this.result, this.at);

  Map<String, dynamic> toJson() =>
      {'e': expr, 'r': result, 't': at.millisecondsSinceEpoch};

  static _TapeEntry fromJson(Map<String, dynamic> j) => _TapeEntry(
        j['e'] as String,
        (j['r'] as num).toDouble(),
        DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
      );
}

/// Adding-machine style calculator: every "=" goes to a paper tape that can
/// be reused (tap) or cleaned (long press). The gate code never reaches it.
class CalculatorPage extends StatefulWidget {
  final void Function(BuildContext context, String code) onCode;

  const CalculatorPage({super.key, required this.onCode});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  static const _maxTape = 300;

  final _scroll = ScrollController();
  List<_TapeEntry> _tape = [];
  String _expr = '';
  double? _lastResult;
  bool _showingResult = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tape = _loadTape();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<_TapeEntry> _loadTape() {
    try {
      final raw =
          ServiceConfig.sharedPreferences?.getString(PreferencesKeys.calcTape);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => _TapeEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _saveTape() {
    if (_tape.length > _maxTape) {
      _tape = _tape.sublist(_tape.length - _maxTape);
    }
    ServiceConfig.sharedPreferences?.setString(
      PreferencesKeys.calcTape,
      jsonEncode(_tape.map((e) => e.toJson()).toList()),
    );
  }

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      switch (key) {
        case 'C':
          if (!_showingResult && CalculatorGate.isCode(_expr)) {
            final code = _expr;
            _expr = '';
            widget.onCode(context, code);
            return;
          }
          _expr = '';
          _showingResult = false;
          return;
        case '⌫':
          if (_showingResult) {
            _showingResult = false;
            _expr = '';
          } else {
            _expr = CalcEngine.backspace(_expr);
          }
          return;
        case '=':
          _equals();
          return;
      }
      if (_showingResult) {
        _showingResult = false;
        final continues = CalcEngine.operators.contains(key) ||
            key == CalcEngine.percent;
        _expr = continues && _lastResult != null
            ? CalcEngine.toInput(_lastResult!)
            : '';
      }
      _expr = CalcEngine.press(_expr, key);
    });
  }

  void _equals() {
    if (_expr.isEmpty) return;
    final result = CalcEngine.evaluate(_expr);
    if (result == null) {
      if (_expr.contains(CalcEngine.divide)) {
        _error = 'Não dá para dividir por zero';
      }
      return;
    }
    final hasOperation =
        RegExp(r'[0-9,][+−×÷%]|%').hasMatch(_expr.replaceFirst(RegExp(r'^−'), ''));
    if (hasOperation) {
      _tape.add(_TapeEntry(CalcEngine.display(_expr), result, DateTime.now()));
      _saveTape();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    _lastResult = result;
    _showingResult = true;
    _expr = '';
  }

  void _reuse(_TapeEntry entry) {
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      final last = _expr.isEmpty ? '' : _expr[_expr.length - 1];
      if (!_showingResult &&
          CalcEngine.operators.contains(last) &&
          entry.result >= 0) {
        _expr += CalcEngine.toInput(entry.result);
      } else {
        _expr = CalcEngine.toInput(entry.result);
      }
      _showingResult = false;
    });
  }

  Future<void> _entryMenu(_TapeEntry entry) async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CalcColors.paper,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '${entry.expr} = ${CalcEngine.format(entry.result)}',
                style: const TextStyle(
                  color: CalcColors.muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined, color: CalcColors.ink),
              title: const Text('Copiar resultado'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.call_split, color: CalcColors.ink),
              title: const Text('Rachar este valor'),
              onTap: () => Navigator.pop(context, 'split'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: CalcColors.ink),
              title: const Text('Apagar da fita'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(
            ClipboardData(text: CalcEngine.format(entry.result)));
        break;
      case 'split':
        _openSplit(entry.result);
        break;
      case 'delete':
        setState(() => _tape.remove(entry));
        _saveTape();
        break;
    }
  }

  Future<void> _clearTape() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CalcColors.paper,
        title: const Text('Limpar a fita?'),
        content: const Text('Todas as contas salvas na fita serão apagadas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _tape.clear());
    _saveTape();
  }

  double? get _currentValue {
    if (_showingResult) return _lastResult;
    return CalcEngine.evaluate(_expr) ?? _lastResult;
  }

  void _openSplit([double? value]) {
    final v = value ?? _currentValue;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SplitBillPage(initialTotal: v != null && v > 0 ? v : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CalcColors.theme(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: CalcColors.background,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: CalcColors.background,
          body: SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(child: _paper()),
                _keypad(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, color: CalcColors.ink),
          const SizedBox(width: 8),
          const Text(
            'Calculadora',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: CalcColors.ink,
            ),
          ),
          const Spacer(),
          Material(
            color: CalcColors.ink,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _openSplit(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_outlined,
                        size: 18, color: CalcColors.operatorText),
                    SizedBox(width: 6),
                    Text(
                      'Racha conta',
                      style: TextStyle(
                        color: CalcColors.operatorText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: CalcColors.ink),
            color: CalcColors.paper,
            onSelected: (v) {
              if (v == 'clear') _clearTape();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clear',
                enabled: _tape.isNotEmpty,
                child: const Text('Limpar fita'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paper() {
    const tabular = [FontFeature.tabularFigures()];
    final exprText = _showingResult
        ? '= ${CalcEngine.format(_lastResult ?? 0)}'
        : (_expr.isEmpty ? '0' : CalcEngine.display(_expr));
    final preview = _showingResult ? null : CalcEngine.evaluate(_expr);
    final showPreview = preview != null &&
        RegExp(r'[+−×÷%]').hasMatch(_expr.replaceFirst(RegExp(r'^−'), ''));

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: CalcColors.paper,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332E2300),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: _tape.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Suas contas ficam guardadas aqui na fita.\n'
                        'Toque numa conta para reaproveitar o resultado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: CalcColors.muted),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _tape.length,
                    itemBuilder: (context, i) {
                      final index = _tape.length - 1 - i;
                      final entry = _tape[index];
                      final previous = index > 0 ? _tape[index - 1] : null;
                      final newDay = previous == null ||
                          !DateUtils.isSameDay(previous.at, entry.at);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (newDay) _dayHeader(entry.at),
                          _tapeRow(entry),
                        ],
                      );
                    },
                  ),
          ),
          // Tear line between the tape and what is being typed.
          const _Perforation(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  height: 22,
                  child: Text(
                    _error ??
                        (showPreview ? '= ${CalcEngine.format(preview)}' : ''),
                    style: TextStyle(
                      fontSize: 18,
                      color: _error != null
                          ? const Color(0xFFB3261E)
                          : CalcColors.muted,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FittedBox(
                    alignment: Alignment.centerRight,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      exprText,
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                        color: CalcColors.ink,
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayHeader(DateTime at) {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(at);
    final label = day == today
        ? 'Hoje'
        : day == today.subtract(const Duration(days: 1))
            ? 'Ontem'
            : DateFormat('dd/MM/yyyy').format(at);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: CalcColors.muted,
        ),
      ),
    );
  }

  Widget _tapeRow(_TapeEntry entry) {
    const tabular = [FontFeature.tabularFigures()];
    return InkWell(
      onTap: () => _reuse(entry),
      onLongPress: () => _entryMenu(entry),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: CalcColors.paperLine, width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              entry.expr,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                color: CalcColors.muted,
                fontFeatures: tabular,
              ),
            ),
            Text(
              '= ${CalcEngine.format(entry.result)}',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: CalcColors.ink,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keypad() {
    const rows = [
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['00', '0', ',', '='],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        children: [
          for (final row in rows)
            Row(
              children: [
                for (final key in row) Expanded(child: _key(key)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _key(String key) {
    final isOperator = CalcEngine.operators.contains(key) || key == '=';
    final isFunction = key == 'C' || key == '⌫' || key == '%';
    final bg = isOperator
        ? CalcColors.operatorKey
        : isFunction
            ? CalcColors.functionKey
            : CalcColors.digitKey;
    final fg = isOperator ? CalcColors.operatorText : CalcColors.ink;
    final child = key == '⌫'
        ? Icon(Icons.backspace_outlined, color: fg, size: 24)
        : Text(
            key,
            style: TextStyle(
              fontSize: key == '00' ? 24 : 28,
              fontWeight: isOperator ? FontWeight.w500 : FontWeight.w600,
              color: fg,
            ),
          );
    return Padding(
      padding: const EdgeInsets.all(5),
      child: AspectRatio(
        aspectRatio: 1.08,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          elevation: isOperator ? 0 : 1,
          shadowColor: const Color(0x552E2300),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _press(key),
            onLongPress: key == '⌫' ? () => _press('C') : null,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Dotted tear line of the paper tape.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = (constraints.maxWidth / 12).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              count,
              (_) => Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: CalcColors.paperLine,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
