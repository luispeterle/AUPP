import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:aupp/investments/asset-sheet.dart';
import 'package:aupp/investments/stock-catalog.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';

/// A site of an asset's workspace.
class SiteTab {
  final String id;
  final String label;

  /// Current address. Starts as the one it was opened with.
  String url;
  String title = '';
  bool loading = false;
  bool canBack = false;
  bool canForward = false;

  /// Its page exists, whether on screen or in standby.
  bool opened = false;

  /// Where it starts, and goes back to once closed.
  final String home;

  SiteTab(this.id, this.label, this.url) : home = url;
}

/// An asset being studied on the computer: its Ficha and its sites, all loaded
/// when it opens. It is then in [standby]: it stays alive, listed below Ajustes
/// in the side rail, until the user closes it.
class AssetWorkspace {
  final String ticker;
  final List<SiteTab> tabs = [];

  /// The site on screen; null is the asset's page (its analysis, for a stock)
  /// and [comparePage] the comparison.
  String? activeSite;
  bool standby = false;

  /// Known once the sites are chosen; only stocks (and BDRs of a company
  /// known at the SEC) have Análise; they, FIIs and the other funds and ETFs
  /// whose reports are known have Comparar.
  AssetKind? kind;

  static const comparePage = '#comparar';

  AssetWorkspace(this.ticker);

  bool get hasAnalysis => analysed != null;
  bool get hasCompare =>
      hasAnalysis ||
      kind == AssetKind.fii ||
      ((kind == AssetKind.etf || kind == AssetKind.fund) &&
          B3Instrument.of(ticker)?.id != null);

  /// Whose numbers Análise and Comparar show: a BDR's are its company's.
  String? get analysed => switch (kind) {
    AssetKind.stock => ticker,
    AssetKind.bdr => B3Instrument.of(ticker)?.secTicker,
    _ => null,
  };

  SiteTab? get active =>
      tabs.where((tab) => tab.id == activeSite).firstOrNull;
}

/// The workspaces. The site pages are native WebKit views
/// (linux/runner/site_webviews.cc) laid over the area the workspace reserves.
///
/// A view lives until it is closed: going back to a workspace finds the page as
/// it was, and closing one destroys its views and frees their memory. Logins are
/// in WebKit's own storage, on disk, so they outlast that. This is about this
/// computer alone: nothing here goes to the backup or to the other devices.
class AssetWorkspaces extends ChangeNotifier {
  static final instance = AssetWorkspaces();

  static const _prefKey = 'desktopStandby';
  static const _darkKey = 'desktopDarkPages';
  static const _channel = MethodChannel('aupp/sites');
  static final _logger = Logger.withClass(AssetWorkspaces);

  final List<AssetWorkspace> workspaces = [];

  /// The sites of the Calculadoras tab. Unlike an asset's, a page only exists
  /// after it is opened, and then stays in standby until closed.
  final calculators = AssetWorkspace('Calculadoras');

  /// The workspace on screen in Ativos; null is the search.
  AssetWorkspace? current;
  bool _supported = false;
  int _nextId = 0;
  String? _shown;

  /// Sites inside the app. Without it (no WebKit, or off Linux) a workspace is
  /// just the Ficha, whose links open in the browser.
  bool get supported => _supported;

  List<AssetWorkspace> get inStandby =>
      workspaces.where((w) => w.standby).toList();

  /// Called once at startup.
  Future<void> init() async {
    if (!Platform.isLinux) return;
    try {
      _channel.setMethodCallHandler(_onNativeCall);
      await _channel.invokeMethod<void>('supported');
      _supported = true;
      _call('darkMode', {'on': darkPages});
    } on MissingPluginException {
      return;
    } catch (e, st) {
      _logger.handle(e, st, 'Web views unavailable');
      return;
    }
    _restore();
    notifyListeners();
  }

  /// Dark mode in the pages, for all of them. On by default.
  bool get darkPages =>
      ServiceConfig.sharedPreferences?.getBool(_darkKey) ?? true;

  void toggleDarkPages() {
    final on = !darkPages;
    ServiceConfig.sharedPreferences?.setBool(_darkKey, on);
    _call('darkMode', {'on': on});
    notifyListeners();
  }

  /// The sites holding cookies or other data in the pages of this app.
  Future<List<String>> siteData() async {
    if (!_supported) return const [];
    final names = await _channel.invokeListMethod<String>('siteData') ?? [];
    return names..sort();
  }

  /// Logs out of that site: pages already open only notice on their next load.
  Future<void> removeSiteData(String name) async {
    if (_supported) await _channel.invokeMethod<void>('removeSiteData', {'name': name});
  }

  Future<void> clearSiteData() async {
    if (_supported) await _channel.invokeMethod<void>('clearSiteData');
  }

  /// The Calculadoras' sites; nothing loads here.
  void setCalculators(List<({String label, String url})> sites) {
    if (calculators.tabs.isNotEmpty) return;
    for (final (i, site) in sites.indexed) {
      calculators.tabs.add(SiteTab('calc$i', site.label, site.url));
    }
  }

  void showCalculator(SiteTab? tab) {
    tab?.opened = true;
    calculators.activeSite = tab?.id;
    notifyListeners();
  }

  /// Destroys the page and frees its memory; the next click loads it again.
  void closeCalculator(SiteTab tab) {
    _destroy(tab.id);
    tab
      ..opened = false
      ..url = tab.home
      ..title = ''
      ..loading = false
      ..canBack = false
      ..canForward = false;
    if (calculators.activeSite == tab.id) calculators.activeSite = null;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest({bool supported = true}) {
    _supported = supported;
    workspaces.clear();
    calculators
      ..tabs.clear()
      ..activeSite = null;
    current = null;
    _nextId = 0;
    _shown = null;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  /// Back to the standby list after a restart. Pages load when opened.
  @visibleForTesting
  void restoreForTest() => _restore();

  void _restore() {
    final raw = ServiceConfig.sharedPreferences?.getString(_prefKey);
    if (raw == null) return;
    try {
      for (final item in jsonDecode(raw) as List) {
        final workspace = AssetWorkspace(item['ticker'] as String)
          ..standby = true;
        for (final tab in item['tabs'] as List) {
          workspace.tabs.add(
            SiteTab(
              'tab${_nextId++}',
              tab['label'] as String,
              tab['url'] as String,
            ),
          );
        }
        workspaces.add(workspace);
      }
    } catch (e, st) {
      _logger.handle(e, st, 'Ignoring saved standby list');
    }
  }

  void _save() {
    ServiceConfig.sharedPreferences?.setString(
      _prefKey,
      jsonEncode([
        for (final workspace in inStandby)
          {
            'ticker': workspace.ticker,
            'tabs': [
              for (final tab in workspace.tabs)
                {'label': tab.label, 'url': tab.url},
            ],
          },
      ]),
    );
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'changed') return;
    final args = (call.arguments as Map).cast<String, dynamic>();
    for (final workspace in [...workspaces, calculators]) {
      final tab = workspace.tabs.where((t) => t.id == args['id']).firstOrNull;
      if (tab == null) continue;
      tab
        ..title = args['title'] as String? ?? ''
        ..loading = args['loading'] as bool? ?? false
        ..canBack = args['canBack'] as bool? ?? false
        ..canForward = args['canForward'] as bool? ?? false;
      final url = args['url'] as String?;
      if (url != null && url.isNotEmpty && url != tab.url) {
        tab.url = url;
        if (workspace.standby) _save();
      }
      notifyListeners();
      return;
    }
  }

  /// What the asset is: each kind has its own sites. Swapped in the tests.
  @visibleForTesting
  Future<AssetKind> Function(String ticker) kindLookup = resolveAssetKind;

  /// Goes to an asset's workspace, the one it already has if any, and loads its
  /// sites. The screen does not wait for them.
  Future<void> openAsset(String ticker) async {
    final workspace =
        workspaces.where((w) => w.ticker == ticker).firstOrNull ??
        (AssetWorkspace(ticker)..also(workspaces.add));
    current = workspace;
    notifyListeners();
    if (_supported) {
      await _loadSites(workspace);
    } else if (workspace.kind == null) {
      workspace.kind = await kindLookup(workspace.ticker);
      notifyListeners();
    }
  }

  /// Creates what is missing: nothing for a workspace already alive, and the
  /// pages of one restored from standby after a restart.
  Future<void> _loadSites(AssetWorkspace workspace) async {
    final kind = await kindLookup(workspace.ticker);
    if (!workspaces.contains(workspace)) return; // closed meanwhile
    workspace.kind = kind;
    final links = assetLinks(
      workspace.ticker,
      cryptoNames[workspace.ticker] ?? StockCompany.of(workspace.ticker)?.name,
      kind: kind,
    );
    // The sites follow the list of today: one that left it is closed (a
    // workspace saved before keeps its old tabs), and the order is the list's.
    // A tab whose address moved to another part of its site (a link fixed in
    // a new version) opens again from the new address.
    bool samePlace(SiteTab tab, AssetLink link) {
      final saved = Uri.tryParse(tab.url);
      final now = link.url;
      final section = (Uri u) => u.pathSegments.isEmpty ? '' : u.pathSegments.first;
      return saved != null &&
          saved.host == now.host &&
          section(saved) == section(now);
    }

    final kept = {
      for (final tab in workspace.tabs)
        if (links.any(
          (link) => link.label == tab.label && samePlace(tab, link),
        ))
          tab.label: tab,
    };
    for (final tab in workspace.tabs) {
      if (kept[tab.label] == tab) continue;
      _destroy(tab.id);
      if (workspace.activeSite == tab.id) workspace.activeSite = null;
    }
    workspace.tabs
      ..clear()
      ..addAll([
        for (final link in links)
          kept[link.label] ??
              SiteTab('tab${_nextId++}', link.label, link.url.toString()),
      ]);
    workspace.standby = true;
    _save();
    for (final tab in workspace.tabs) {
      _call('load', {'id': tab.id, 'url': tab.url});
    }
    notifyListeners();
  }

  void showFicha(AssetWorkspace workspace) {
    workspace.activeSite = null;
    notifyListeners();
  }

  void showSite(AssetWorkspace workspace, String id) {
    workspace.activeSite = id;
    notifyListeners();
  }

  /// Back to the search: it stays in standby. Without web views it holds nothing
  /// (what was written in the Ficha is already saved).
  void leave(AssetWorkspace workspace) {
    if (workspace.tabs.isEmpty) {
      close(workspace);
      return;
    }
    if (current == workspace) current = null;
    notifyListeners();
  }

  void close(AssetWorkspace workspace) {
    for (final tab in workspace.tabs) {
      _destroy(tab.id);
    }
    workspaces.remove(workspace);
    if (current == workspace) current = null;
    _save();
    notifyListeners();
  }

  /// Puts the page over [rect] (window coordinates).
  void show(SiteTab tab, Rect rect) {
    final x = rect.left.round();
    final y = rect.top.round();
    final width = rect.width.round();
    final height = rect.height.round();
    // Rebuilds are frequent (every title change) and this is a native call.
    final shown = '${tab.id}|$x|$y|$width|$height';
    if (shown == _shown) return;
    _shown = shown;
    _call('show', {
      'id': tab.id,
      'url': tab.url,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
  }

  void hide() {
    if (_shown == null) return;
    _shown = null;
    _call('hide');
  }

  /// Each tab hides only its own page: both ask for it at every rebuild, and
  /// the other one may have just put a page on screen.
  void hideAssetPages() {
    if (!(_shown?.startsWith('calc') ?? true)) hide();
  }

  void hideCalculatorPages() {
    if (_shown?.startsWith('calc') ?? false) hide();
  }

  void pageBack(SiteTab tab) => _call('back', {'id': tab.id});
  void pageForward(SiteTab tab) => _call('forward', {'id': tab.id});
  void pageReload(SiteTab tab) => _call('reload', {'id': tab.id});

  void _destroy(String id) {
    if (_shown?.startsWith('$id|') ?? false) _shown = null;
    _call('close', {'id': id});
  }

  void _call(String method, [Map<String, Object?>? args]) {
    if (!_supported) return;
    _channel
        .invokeMethod<void>(method, args)
        .catchError((Object e) => _logger.warning('$method failed: $e'));
  }
}

extension _Also<T> on T {
  T also(void Function(T value) action) {
    action(this);
    return this;
  }
}
