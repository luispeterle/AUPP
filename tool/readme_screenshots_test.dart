// Draws the README screenshots off screen, from the demo's made-up data:
//   flutter test tool/readme_screenshots_test.dart
// Writes docs/screenshots/*.png. Uses the network for public market data only;
// the brapi key (quotes abroad) comes from private/chave_api_brapi and the last
// crypto quotes from the installed app, when there are.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/disguise/calculator-gate.dart';
import 'package:aupp/fiscal/fiscal-estimates.dart';
import 'package:aupp/investments/asset-sheet-page.dart';
import 'package:aupp/investments/diagram-page.dart';
import 'package:aupp/main.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/services/backup-service.dart';
import 'package:aupp/services/category-hierarchy.dart';
import 'package:aupp/services/locale-service.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:aupp/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../test/helpers/test_database.dart';

final _out = Platform.environment['SHOTS_OUT'] ?? 'docs/screenshots';
const _phone = Size(412, 892);
const _computer = Size(1360, 860);
const _ratio = 2.0;
const _fallback = ['Noto Sans', 'Noto Color Emoji'];

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final roboto = [
    for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black'])
      '$material/Roboto-$weight.ttf',
  ];
  await _font('Roboto', roboto);
  // Fallback for what Roboto lacks; the system's, when it has one.
  const noto = '/usr/share/fonts/noto';
  if (File('$noto/NotoSans-Regular.ttf').existsSync()) {
    await _font('Noto Sans', [
      '$noto/NotoSans-Regular.ttf',
      if (File('$noto/NotoSans-Bold.ttf').existsSync()) '$noto/NotoSans-Bold.ttf',
    ]);
  }
  const emoji = '/usr/share/fonts/noto/NotoColorEmoji.ttf';
  if (File(emoji).existsSync()) await _font('Noto Color Emoji', [emoji]);
  await _font('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  final packages =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())['packages']
          as List;
  final awesome = Uri.parse(
    packages.firstWhere((p) => p['name'] == 'font_awesome_flutter')['rootUri']
        as String,
  ).toFilePath();
  await _font('packages/font_awesome_flutter/FontAwesomeSolid', [
    '$awesome/lib/fonts/Font-Awesome-7-Free-Solid-900.otf',
  ]);
  await _font('packages/font_awesome_flutter/FontAwesomeRegular', [
    '$awesome/lib/fonts/Font-Awesome-7-Free-Regular-400.otf',
  ]);
  await _font('packages/font_awesome_flutter/FontAwesomeBrands', [
    '$awesome/lib/fonts/Font-Awesome-7-Brands-Regular-400.otf',
  ]);
}

/// Public caches of the installed app (CVM statements, B3 and SEC lists,
/// Banco Central rates, crypto history), so the screens need not download
/// them. The Dinzo's files hold personal data and stay out.
const _publicCaches = [
  'cvm',
  'b3-market.json',
  'sec-tickers.json',
  'bcb_rates.json',
  'crypto_history.json',
  'tesouro_bonds.json',
];

Future<void> _copyPublicCaches(Directory to) async {
  final from = '${Platform.environment['HOME']}/.local/share/app.aupp';
  for (final name in _publicCaches) {
    final source = '$from/$name';
    if (FileSystemEntity.isDirectorySync(source)) {
      await Process.run('cp', ['-r', source, to.path]);
    } else if (File(source).existsSync()) {
      await File(source).copy('${to.path}/$name');
    }
  }
}

/// Market data the demo carries from the real app ([DemoMode]): the brapi key
/// and the last crypto quotes, when this machine has them.
Map<String, Object> _marketPrefs() {
  final prefs = <String, Object>{};
  final key = File('private/chave_api_brapi');
  if (key.existsSync()) {
    prefs[PreferencesKeys.brapiApiKey] = key.readAsStringSync().trim();
  }
  final home = Platform.environment['HOME'];
  final installed = File('$home/.local/share/app.aupp/shared_preferences.json');
  if (installed.existsSync()) {
    final json = jsonDecode(installed.readAsStringSync()) as Map;
    for (final k in [
      PreferencesKeys.cryptoQuotesMain,
      PreferencesKeys.cryptoQuotesUsd,
      PreferencesKeys.cryptoQuotesUpdatedAt,
    ]) {
      if (json['flutter.$k'] case final Object value) prefs[k] = value;
    }
  }
  return prefs;
}

void main() {
  testWidgets('README screenshots', (tester) async {
    debugDisableShadows = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    final tmp = Directory.systemTemp.createTempSync('readme_shots');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => {
        'appName': 'AUPP',
        'packageName': 'app.aupp',
        'version': '1.0.0',
        'buildNumber': '1',
      },
    );
    late ThemeData light, dark;
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tz.initializeTimeZones();
      ServiceConfig.localTimezone = 'America/Sao_Paulo';
      SharedPreferences.setMockInitialValues({});
      ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
      await TestDatabaseHelper.setupTestDatabase();
      BackupService.database = ServiceConfig.database;
      await _loadFonts();
      await _copyPublicCaches(tmp);
      DemoMode.active = true;
      await DemoMode.prepare();
      // A new database has the default categories; the demo has its own.
      for (final (name, type) in [
        ('Casa', CategoryType.expense),
        ('Transporte', CategoryType.expense),
        ('Alimentação', CategoryType.expense),
        ('Salário', CategoryType.income),
      ]) {
        await ServiceConfig.database.deleteCategory(name, type);
      }
      final prefs = ServiceConfig.sharedPreferences!;
      for (final MapEntry(:key, :value) in _marketPrefs().entries) {
        value is int
            ? await prefs.setInt(key, value)
            : await prefs.setString(key, value as String);
      }
      await CategoryHierarchy.init();
      await FiscalEstimates.init();
      CalculatorGate.startUnlocked();
      light = await MaterialThemeInstance.getLightTheme();
      dark = await MaterialThemeInstance.getDarkTheme();
    });
    LocaleService.setCurrencyLocale();

    Future<void> settle([int rounds = 12]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> shot(String name) async {
      final boundary =
          tester.renderObject(find.byKey(const ValueKey('shot')))
              as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: _ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('$_out/$name.png').writeAsBytesSync(bytes!);
    }

    // The test engine has no system fonts to fall back on.
    ThemeData withFallback(ThemeData theme) => theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamilyFallback: _fallback),
      primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamilyFallback: _fallback,
      ),
    );

    Future<void> open(Size size) async {
      await tester.pumpWidget(const SizedBox());
      await settle(1);
      tester.view.physicalSize = size * _ratio;
      tester.view.devicePixelRatio = _ratio;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('shot'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size == _phone ? 26 : 12),
            child: KeyedSubtree(
              key: UniqueKey(),
              child: MyApp(
                lightTheme: withFallback(light),
                darkTheme: withFallback(dark),
                themeMode: ThemeMode.light,
              ),
            ),
          ),
        ),
      );
      await settle(25);
    }

    Future<void> tap(String label) async {
      await tester.tap(find.text(label).last);
      await settle(14);
    }

    /// Scrolls until [text] sits near the top of the screen.
    Future<void> scrollTo(String text, {double top = 110}) async {
      final center = tester.getCenter(find.byKey(const ValueKey('shot')));
      for (var i = 0; i < 40; i++) {
        final found = find.text(text);
        if (found.evaluate().isNotEmpty) {
          final y = tester.getTopLeft(found.first).dy;
          if ((y - top).abs() < 40) break;
          await tester.dragFrom(center, Offset(0, (top - y).clamp(-420, 420)));
        } else {
          await tester.dragFrom(center, const Offset(0, -420));
        }
        await settle(3);
      }
      await settle(4);
    }

    // Phone.
    await open(_phone);
    await shot('android-inicio');
    await tap('Extrato');
    await shot('android-extrato');
    await tap('Início');
    await scrollTo('Ajustar', top: 300);
    await tap('Ajustar');
    await shot('android-orcamento');

    // Computer.
    await open(_computer);
    await tap('Investimentos');
    // Quotes come one by one: the brapi allows a few a second.
    await settle(60);
    await scrollTo('Divisão', top: 90);
    await shot('desktop-carteira');
    await tap('Árvore');
    await shot('desktop-arvore');
    await tap('Meus ativos');
    await shot('desktop-meus-ativos');
    AssetSheetPage.open(tester.element(find.byType(DiagramPage)), 'PETR4');
    await settle(60);
    await shot('desktop-analise');

    await tester.pumpWidget(const SizedBox());
    await settle(2);
    await tester.pump(const Duration(hours: 1));
    tester.view.reset();
    debugDisableShadows = true;
  }, timeout: const Timeout(Duration(minutes: 8)));
}
