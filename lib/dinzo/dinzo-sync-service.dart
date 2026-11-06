import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:aupp/components/known-tags.dart';
import 'package:aupp/demo/demo-mode.dart';
import 'package:aupp/helpers/datetime-utility-functions.dart';
import 'package:aupp/investments/investments-cache.dart';
import 'package:aupp/models/category-type.dart';
import 'package:aupp/models/category.dart';
import 'package:aupp/models/record.dart';
import 'package:aupp/services/database/sqlite-database.dart';
import 'package:aupp/services/logger.dart';
import 'package:aupp/services/service-config.dart';
import 'package:aupp/settings/constants/preferences-keys.dart';
import 'package:timezone/timezone.dart' as tz;

import 'dinzo-api.dart';
import 'dinzo-config.dart';
import 'dinzo-models.dart';
import 'dinzo-taxes.dart';
import 'daily-money.dart';
import 'dinzo-sync-engine.dart';
import 'dinzo-sync-log.dart';

/// Everything fetched for one sync, ready for the merge screen.
class DinzoPreparedSync {
  DinzoSyncPlan plan;
  final List<DinzoTransaction> transactions;
  final List<Record> linkedRecords;
  final DateTime from;
  final DateTime to;
  final DinzoSyncEngine engine;
  final DinzoBalances balances;
  final List<DinzoCategory> categories;
  final List<String> connectionsNeedingAttention;

  /// Everything since the start date and the investments were read.
  final bool full;

  /// Investment positions with movements (income tax, Investments tab).
  final List<DinzoInvestment> investments;
  final List<Map<String, dynamic>> investmentHistory;
  final List<Map<String, dynamic>> investmentIncome;

  DinzoPreparedSync({
    required this.plan,
    required this.transactions,
    required this.linkedRecords,
    required this.from,
    required this.to,
    required this.engine,
    required this.balances,
    required this.categories,
    required this.connectionsNeedingAttention,
    this.full = true,
    this.investments = const [],
    this.investmentHistory = const [],
    this.investmentIncome = const [],
  });

  /// Recomputes the plan after the config changed (a remembered rule, an
  /// ignored transaction...).
  void replan() {
    plan = engine.plan(
      transactions: transactions,
      linkedRecords: linkedRecords,
      from: from,
      to: to,
    );
  }
}

class DinzoApplyResult {
  int created = 0;
  int updated = 0;
  int removed = 0;

  /// One line per record touched, for the sync history.
  final List<String> items = [];

  /// "3 novos, 1 atualizado, 0 removidos".
  String get summary =>
      '$created novos, $updated atualizados, $removed removidos';
}

/// Pulls from Dinzo and applies the user's merge decisions to the database.
/// Nothing happens without an explicit [prepare] + [apply] from the UI.
class DinzoSyncService {
  static final _logger = Logger.withClass(DinzoSyncService);

  /// Tag every hand-entered record carries (and cannot drop), so records that
  /// exist only in AUPP are easy to tell apart from Dinzo imports.
  static const String manualTag = 'Manual';

  /// Tag of hand-entered moves between wallets (caixinhas): money only set
  /// aside on paper, nothing happened at the bank.
  static const String virtualTag = 'Virtual';

  /// Tag of estimate patterns: forecast entries (salary, average monthly
  /// costs, a known future expense) that show up in future months but never
  /// become real records; each occurrence vanishes when its day arrives.
  static const String estimateTag = 'Estimativa';

  /// Tag of money paid in cash (paper money). A new hand-entered record
  /// starts with it, unless it is an estimate, a transfer or a Pix / boleto.
  static const String cashTag = 'Dinheiro';

  /// Icons for the Dinzo top-level categories, used when the sync creates
  /// them in AUPP.
  static final Map<String, IconData> categoryIcons = {
    'Alimentação': FontAwesomeIcons.burger.data,
    'Assinaturas/Serviços': FontAwesomeIcons.receipt.data,
    'Compras': FontAwesomeIcons.bagShopping.data,
    'Cuidado Pessoal': FontAwesomeIcons.handsBubbles.data,
    'Dívidas/Empréstimos': FontAwesomeIcons.fileInvoiceDollar.data,
    'Educação': FontAwesomeIcons.graduationCap.data,
    'Impostos/Taxas': FontAwesomeIcons.landmark.data,
    'Investimentos': FontAwesomeIcons.coins.data,
    'Lazer/Hobbies': FontAwesomeIcons.faceLaughBeam.data,
    'Moradia': FontAwesomeIcons.house.data,
    'Outros': FontAwesomeIcons.tag.data,
    'Pets': FontAwesomeIcons.paw.data,
    'Salário': FontAwesomeIcons.moneyBillWave.data,
    'Saúde': FontAwesomeIcons.stethoscope.data,
    'Supermercado': FontAwesomeIcons.cartShopping.data,
    'Transporte': FontAwesomeIcons.car.data,
    'Vestuário': FontAwesomeIcons.socks.data,
    'Viagens': FontAwesomeIcons.planeDeparture.data,
    'Sem categoria': FontAwesomeIcons.question.data,
  };

  /// Icons for Dinzo subcategories; any other subcategory uses its parent's.
  static final Map<String, IconData> subcategoryIcons = {
    'Restaurante': FontAwesomeIcons.pizzaSlice.data,
    'Delivery': FontAwesomeIcons.motorcycle.data,
    'Cafeteria': FontAwesomeIcons.mugHot.data,
    'Padaria': FontAwesomeIcons.breadSlice.data,
    'Streamings': FontAwesomeIcons.circlePlay.data,
    'Televisão': FontAwesomeIcons.tv.data,
    'Telefone/Celular': FontAwesomeIcons.phone.data,
    'Jogos': FontAwesomeIcons.gamepad.data,
    'Aplicativos': FontAwesomeIcons.mobileScreen.data,
    'Cabeleireiro/Barbeiro': FontAwesomeIcons.scissors.data,
    'Higiene Pessoal': FontAwesomeIcons.pumpSoap.data,
    'Manicure': FontAwesomeIcons.handSparkles.data,
    'Maquiagem': FontAwesomeIcons.wandMagicSparkles.data,
    'Cartão de Crédito': FontAwesomeIcons.creditCard.data,
    'Cheque Especial': FontAwesomeIcons.moneyCheck.data,
    'Consórcio': FontAwesomeIcons.peopleGroup.data,
    'Empréstimo': FontAwesomeIcons.handHoldingDollar.data,
    'Empréstimo Consignado': FontAwesomeIcons.fileSignature.data,
    'Encargos': FontAwesomeIcons.percent.data,
    'Financiamento': FontAwesomeIcons.sackDollar.data,
    'Renegociação': FontAwesomeIcons.handshake.data,
    'Cursos': FontAwesomeIcons.chalkboardUser.data,
    'Escola': FontAwesomeIcons.school.data,
    'Faculdade': FontAwesomeIcons.userGraduate.data,
    'Materiais e Livros': FontAwesomeIcons.book.data,
    'Anuidade Cartão': FontAwesomeIcons.calendarDays.data,
    'Imposto de Renda': FontAwesomeIcons.fileInvoice.data,
    'Tarifa Bancária': FontAwesomeIcons.buildingColumns.data,
    'Tributos': FontAwesomeIcons.scaleBalanced.data,
    'Aplicação': FontAwesomeIcons.arrowTrendUp.data,
    'Juros': FontAwesomeIcons.percent.data,
    'Proventos': FontAwesomeIcons.moneyBillTrendUp.data,
    'Retirada': FontAwesomeIcons.arrowTrendDown.data,
    'Bares': FontAwesomeIcons.beerMugEmpty.data,
    'Cinema': FontAwesomeIcons.film.data,
    'Esportes': FontAwesomeIcons.futbol.data,
    'Parques': FontAwesomeIcons.tree.data,
    'Shows e Eventos': FontAwesomeIcons.music.data,
    'Teatro': FontAwesomeIcons.masksTheater.data,
    'Aluguel/Prestação': FontAwesomeIcons.key.data,
    'Condomínio': FontAwesomeIcons.building.data,
    'Diarista': FontAwesomeIcons.broom.data,
    'Eletrodomésticos': FontAwesomeIcons.blender.data,
    'Gás': FontAwesomeIcons.fire.data,
    'IPTU': FontAwesomeIcons.landmark.data,
    'Internet': FontAwesomeIcons.wifi.data,
    'Luz': FontAwesomeIcons.lightbulb.data,
    'Móveis': FontAwesomeIcons.couch.data,
    'Reformas': FontAwesomeIcons.hammer.data,
    'Seguro Residencial': FontAwesomeIcons.houseLock.data,
    'Água': FontAwesomeIcons.faucet.data,
    'Presentes/Doações': FontAwesomeIcons.gift.data,
    'Transferência': FontAwesomeIcons.rightLeft.data,
    'Acessórios Pet': FontAwesomeIcons.bone.data,
    'Alimentação Pet': FontAwesomeIcons.bowlFood.data,
    'Banho/Tosa': FontAwesomeIcons.shower.data,
    'Medicamentos': FontAwesomeIcons.prescriptionBottleMedical.data,
    'Veterinário': FontAwesomeIcons.userDoctor.data,
    '13° Salário': FontAwesomeIcons.calendarPlus.data,
    'Aposentadoria': FontAwesomeIcons.personCane.data,
    'Comissão': FontAwesomeIcons.percent.data,
    'Férias': FontAwesomeIcons.umbrellaBeach.data,
    'Hora extra': FontAwesomeIcons.clock.data,
    'Trabalho': FontAwesomeIcons.briefcase.data,
    'Vale alimentação': FontAwesomeIcons.cartShopping.data,
    'Academia': FontAwesomeIcons.dumbbell.data,
    'Consultas': FontAwesomeIcons.userDoctor.data,
    'Dentista': FontAwesomeIcons.tooth.data,
    'Exames': FontAwesomeIcons.syringe.data,
    'Farmácia': FontAwesomeIcons.pills.data,
    'Plano Odontológico': FontAwesomeIcons.teeth.data,
    'Plano de Saúde': FontAwesomeIcons.heartPulse.data,
    'Seguro de Vida': FontAwesomeIcons.shieldHalved.data,
    'Combustível': FontAwesomeIcons.gasPump.data,
    'Estacionamento': FontAwesomeIcons.squareParking.data,
    'IPVA': FontAwesomeIcons.idCard.data,
    'Lavação': FontAwesomeIcons.sprayCanSparkles.data,
    'Licenciamento': FontAwesomeIcons.fileContract.data,
    'Manutenção': FontAwesomeIcons.wrench.data,
    'Multa': FontAwesomeIcons.triangleExclamation.data,
    'Pedágio': FontAwesomeIcons.road.data,
    'Prestação': FontAwesomeIcons.carSide.data,
    'Seguro do Carro': FontAwesomeIcons.carBurst.data,
    'Taxi/Uber': FontAwesomeIcons.taxi.data,
    'Transporte Público': FontAwesomeIcons.bus.data,
    'Acessórios': FontAwesomeIcons.glasses.data,
    'Calçados': FontAwesomeIcons.shoePrints.data,
    'Roupas': FontAwesomeIcons.shirt.data,
    'Hotel': FontAwesomeIcons.bed.data,
    'Passagem': FontAwesomeIcons.ticket.data,
    'Passeio': FontAwesomeIcons.mountainSun.data,
  };

  /// A category as the sync creates it: a subcategory takes a shade of its
  /// parent's colour (so the pie chart groups visually) and, without an icon
  /// of its own, the parent's icon.
  static Category categoryFromDinzo(
    String name,
    CategoryType type, {
    Category? parent,
    String? colorHex,
  }) {
    final color = parent?.color != null
        ? _shade(parent!.color!, name)
        : _parseColor(colorHex) ?? Colors.blueGrey;
    final iconCodePoint =
        subcategoryIcons[name]?.codePoint ??
        categoryIcons[name]?.codePoint ??
        parent?.iconCodePoint;
    return Category(
      name,
      categoryType: type,
      color: color,
      iconCodePoint: iconCodePoint,
      parentName: parent?.name,
    );
  }

  /// Deterministic lighter/darker variant of [base], picked by [name].
  static Color _shade(Color base, String name) {
    final step = name.codeUnits.fold<int>(0, (a, b) => a + b) % 5 - 2;
    final hsl = HSLColor.fromColor(base);
    final lightness = (hsl.lightness + step * 0.08).clamp(0.2, 0.8);
    return hsl.withLightness(lightness.toDouble()).toColor();
  }

  static String? get apiKey =>
      ServiceConfig.sharedPreferences?.getString(PreferencesKeys.dinzoApiKey);

  static Future<void> setApiKey(String? key) async {
    final prefs = ServiceConfig.sharedPreferences!;
    if (key == null || key.trim().isEmpty) {
      await prefs.remove(PreferencesKeys.dinzoApiKey);
    } else {
      await prefs.setString(PreferencesKeys.dinzoApiKey, key.trim());
    }
  }

  static DinzoConfig loadConfig() => DinzoConfig.fromJsonString(
    ServiceConfig.sharedPreferences?.getString(PreferencesKeys.dinzoConfig),
  );

  static Future<void> saveConfig(DinzoConfig config) async {
    await ServiceConfig.sharedPreferences!.setString(
      PreferencesKeys.dinzoConfig,
      config.toJsonString(),
    );
  }

  static DateTime? get lastSync => DateTime.tryParse(
    ServiceConfig.sharedPreferences?.getString(PreferencesKeys.dinzoLastSync) ??
        '',
  );

  /// Days a quick sync looks back. Older records stay as they are.
  static const int quickWindowDays = 30;

  /// Fetches from Dinzo and computes the plan. [full] reads everything Dinzo
  /// has ([DinzoConfig.startDate]) plus the investments (slow: ~60 requests and a
  /// long wait for the banks); otherwise only the last [quickWindowDays]
  /// days are read and compared. [refreshBanks] first asks every bank
  /// connection to sync.
  static Future<DinzoPreparedSync> prepare({
    bool full = false,
    bool refreshBanks = true,
    void Function(String step)? onProgress,
  }) async {
    final key = apiKey;
    if (key == null) {
      throw DinzoApiException(
        null,
        'missing_key',
        'Chave da API não configurada',
      );
    }
    final config = loadConfig();
    // The first sync brings the whole history.
    if (!full && !await DailyMoney.started()) full = true;
    final api = DinzoApi(key);
    try {
      var needsAttention = <String>[];
      if (refreshBanks) {
        onProgress?.call('Atualizando bancos…');
        needsAttention = await api.refreshConnections();
        await api.waitForConnections(
          timeout: Duration(seconds: full ? 90 : 25),
        );
      }
      onProgress?.call('Buscando contas e categorias…');
      final accounts = await api.accounts();
      final categories = await api.categories();
      final balances = DailyMoney.balances(
        accounts,
        await InvestmentsCache.withBrokers(api, await api.investmentsNow()),
      );

      final now = DateTime.now();
      final quickFrom = DateTime(
        now.year,
        now.month,
        now.day - quickWindowDays,
      );
      // Also covers last month from its start, so its yield can still be
      // completed with transactions that reached Dinzo late, and everything
      // since the last sync (minus a margin for late transactions), so a
      // long pause never leaves a gap.
      var quickStart = DateTime(now.year, now.month - 1, 0);
      if (quickFrom.isBefore(quickStart)) quickStart = quickFrom;
      final last = lastSync;
      if (last != null) {
        final sinceLast = DateTime(last.year, last.month, last.day - 10);
        if (sinceLast.isBefore(quickStart)) quickStart = sinceLast;
      }
      final from = full || quickStart.isBefore(config.startDate)
          ? config.startDate
          : quickStart;
      final to = DateTime(now.year, now.month, now.day + 45);
      onProgress?.call(
        full
            ? 'Buscando todos os lançamentos…'
            : 'Buscando lançamentos dos últimos $quickWindowDays dias…',
      );
      final transactions = await api.transactions(from, to);
      // Investments (Investments tab cache) only on a full sync: the tab
      // refreshes them on its own.
      var investments = <DinzoInvestment>[];
      var investmentHistory = <Map<String, dynamic>>[];
      var investmentIncome = <Map<String, dynamic>>[];
      if (full) {
        onProgress?.call('Buscando investimentos…');
        investmentHistory = await api.investmentSnapshots();
        investments = await InvestmentsCache.fetch(api);
        investmentIncome = await api.investmentIncome(
          DateTime(now.year - 1, now.month, now.day),
          now,
        );
      }

      final defaultWallet = await ServiceConfig.database.getDefaultWallet();
      final engine = DinzoSyncEngine(
        config: config,
        accounts: accounts,
        categories: categories,
        defaultWalletId: defaultWallet?.id,
      );
      final linked = await linkedRecords();
      final plan = engine.plan(
        transactions: transactions,
        linkedRecords: linked,
        from: from,
        to: to,
      );
      _logger.info(
        'Dinzo plan: ${transactions.length} transactions, '
        '${plan.ofKind(DinzoPlanKind.create).length} new, '
        '${plan.ofKind(DinzoPlanKind.update).length} updated, '
        '${plan.ofKind(DinzoPlanKind.conflict).length} conflicts, '
        '${plan.ofKind(DinzoPlanKind.remove).length} removed',
      );
      return DinzoPreparedSync(
        plan: plan,
        transactions: transactions,
        linkedRecords: linked,
        from: from,
        to: to,
        engine: engine,
        balances: balances,
        categories: categories,
        connectionsNeedingAttention: needsAttention,
        full: full,
        investments: investments,
        investmentHistory: investmentHistory,
        investmentIncome: investmentIncome,
      );
    } finally {
      api.close();
    }
  }

  /// Every record imported from Dinzo, with its category and tags.
  static Future<List<Record>> linkedRecords() async {
    final db = (await SqliteDatabase.instance.database)!;
    final maps = await db.rawQuery("""
      SELECT m.*, c.name, c.color, c.category_type, c.icon, c.icon_emoji,
             c.is_archived, GROUP_CONCAT(rt.tag_name) AS tags
      FROM records AS m
      LEFT JOIN categories AS c
          ON m.category_name = c.name AND m.category_type = c.category_type
      LEFT JOIN records_tags AS rt ON m.id = rt.record_id
      WHERE m.dinzo_id IS NOT NULL AND m.dinzo_id NOT LIKE '$syntheticPrefix%'
      GROUP BY m.id
    """);
    return maps.map((m) {
      final row = Map<String, dynamic>.from(m);
      row['category'] = Category.fromNullableMap(row);
      return Record.fromMap(row);
    }).toList();
  }

  /// Applies the selected plan items, then reconciles the free wallet.
  /// The config (merchant rules, ignored ids...) is saved too, since the
  /// merge screen edits it.
  static Future<DinzoApplyResult> apply(
    DinzoPreparedSync prepared, {
    String trigger = 'manual',
  }) async {
    final firstSync = !await DailyMoney.started();
    final db = ServiceConfig.database;
    final result = DinzoApplyResult();
    await saveConfig(prepared.engine.config);

    final categories = <String, Category>{
      for (final c in await db.getAllCategories())
        if (c != null) '${c.name}|${c.categoryType?.index}': c,
    };
    final dinzoColors = {
      for (final c in prepared.categories)
        if (c.parentId == null && c.colorHex != null) c.title: c.colorHex!,
    };
    final parentTitles = prepared.engine.parentTitles;
    Future<Category?> categoryFor(String? name, CategoryType type) async {
      if (name == null) return null;
      final key = '$name|${type.index}';
      final parentName = parentTitles[name];
      final parent = parentName == null
          ? null
          : await categoryFor(parentName, type);
      final existing = categories[key];
      if (existing == null) {
        final created = categoryFromDinzo(
          name,
          type,
          parent: parent,
          colorHex: dinzoColors[name],
        );
        await db.addCategory(created);
        categories[key] = created;
      } else if (parent != null && existing.parentName != parent.name) {
        existing.parentName = parent.name;
        await db.updateCategory(name, type, existing);
      }
      return categories[key];
    }

    // Every connected bank has its tag, used or not.
    await SqliteDatabase.instance.addStandaloneTags({
      for (final a in prepared.engine.accounts.values)
        if (!a.archived && a.connectorName != null)
          KnownTag.bankIn(a.connectorName!)?.name ?? a.connectorName!,
    });

    final toCreate = <Record>[];
    final toDelete = <int>[];
    for (final item in prepared.plan.items) {
      switch (item.kind) {
        case DinzoPlanKind.create:
          if (!item.selected) break;
          final d = item.desired!;
          result.items.add(
            '+ ${d.date} ${_amount(d.value)} ${d.title} '
            '[${d.categoryName ?? 'sem categoria'}] '
            '(dinzo ${item.transaction!.id})',
          );
          toCreate.add(
            Record(
              d.value,
              d.title,
              await categoryFor(d.categoryName, item.categoryType!),
              _utcNoon(d.date),
              description: item.description,
              walletId: d.walletId,
              tags: d.tags.toSet(),
              dinzoId: item.transaction!.id,
              dinzoSnapshot: DinzoLink(item.source!, d).toJsonString(),
            ),
          );
          break;
        case DinzoPlanKind.update:
        case DinzoPlanKind.conflict:
          final record = item.existing!;
          if (!item.selected) {
            if (item.kind == DinzoPlanKind.conflict) {
              // Local wins: remember this Dinzo version so it is not offered
              // again, and keep the record as the user left it.
              final link = DinzoLink.fromJsonString(record.dinzoSnapshot);
              if (link != null) {
                record.dinzoSnapshot = DinzoLink(
                  item.source!,
                  link.applied,
                ).toJsonString();
                await db.updateRecordById(record.id, record);
              }
            }
            break;
          }
          final d = item.desired!;
          final before = DinzoSnapshot.ofRecord(
            record,
            syncedTags:
                DinzoLink.fromJsonString(record.dinzoSnapshot)?.applied.tags ??
                const [],
          );
          result.items.add(
            '~ ${d.date} ${d.title}: ${_changes(before, d)} '
            '(${item.kind == DinzoPlanKind.conflict ? 'conflito aceito, ' : ''}'
            'dinzo ${item.transaction!.id}, registro ${record.id})',
          );
          final previousTags =
              DinzoLink.fromJsonString(record.dinzoSnapshot)?.applied.tags ??
              const <String>[];
          record.tags
            ..removeAll(previousTags)
            ..addAll(d.tags);
          record
            ..value = d.value
            ..title = d.title
            ..category = await categoryFor(d.categoryName, item.categoryType!)
            ..walletId = d.walletId
            ..dinzoId = item.transaction!.id
            ..dinzoSnapshot = DinzoLink(item.source!, d).toJsonString();
          if (DinzoSnapshot.ofRecord(record).date != d.date) {
            record.utcDateTime = _utcNoon(d.date);
          }
          await db.updateRecordById(record.id, record);
          result.updated++;
          break;
        case DinzoPlanKind.remove:
          if (item.selected && item.existing?.id != null) {
            final r = item.existing!;
            result.items.add(
              '− ${DinzoSnapshot.ofRecord(r).date} ${_amount(r.value ?? 0)} '
              '${r.title} (dinzo ${r.dinzoId}, registro ${r.id})',
            );
            toDelete.add(r.id!);
          }
          break;
        case DinzoPlanKind.unchanged:
        case DinzoPlanKind.skipped:
          break;
      }
    }
    if (toCreate.isNotEmpty) {
      await db.addRecordsInBatchNoDuplicateCheck(toCreate);
      result.created = toCreate.length;
    }
    if (toDelete.isNotEmpty) {
      await db.deleteRecordsInBatch(toDelete);
      result.removed = toDelete.length;
    }

    final balances = prepared.balances;
    // Without every balance the money is wrong: the wallet to invest keeps
    // what it had until a sync sees them all.
    if (balances.complete) {
      await DailyMoney.reconcile(
        balances.money,
        spendable: firstSync ? balances.spendable : null,
      );
    }
    await DinzoSyncLog.add(
      DinzoSyncLogEntry(
        at: DateTime.now(),
        trigger: trigger,
        mode: prepared.full ? 'completo' : 'rápido',
        outcome: 'aplicado',
        summary: result.summary,
        warnings: [
          if (!balances.complete)
            'Sem saldo de ${balances.unknown.join(', ')}: o Investir não foi '
                'recalculado',
        ],
        items: [
          ...result.items,
          'Dinheiro ${balances.money.toStringAsFixed(2)} = bancos '
              '${balances.bank.toStringAsFixed(2)} + renda fixa '
              '${balances.fixedIncome.toStringAsFixed(2)} − cartões '
              '${balances.cardDebt.toStringAsFixed(2)}',
        ],
      ),
    );
    if (prepared.full) {
      await InvestmentsCache.save(
        InvestmentsSnapshot(
          investments: prepared.investments,
          history: prepared.investmentHistory,
          income: prepared.investmentIncome,
          bankBalance: balances.bank,
          cardDebt: balances.cardDebt,
          balancesComplete: balances.complete,
          fetchedAt: DateTime.now(),
        ),
      );
    }
    await ServiceConfig.sharedPreferences!.setString(
      PreferencesKeys.dinzoLastSync,
      DateTime.now().toIso8601String(),
    );
    _logger.info(
      'Dinzo sync applied: ${result.created} created, '
      '${result.updated} updated, ${result.removed} removed',
    );
    return result;
  }

  /// Prefix of [Record.dinzoId] for records the app makes itself (a purchase's
  /// part paid with a caixinha, an investment buy, the food allowance). They
  /// are not Dinzo transactions.
  static const String syntheticPrefix = 'livre:';

  static bool isSynthetic(String? dinzoId) =>
      dinzoId?.startsWith(syntheticPrefix) ?? false;

  static String _amount(double v) => v.toStringAsFixed(2);

  /// "valor −40.00→−45.90; categoria A→B" for the sync history.
  static String _changes(DinzoSnapshot before, DinzoSnapshot after) {
    final parts = <String>[
      if (before.value != after.value)
        'valor ${_amount(before.value)}→${_amount(after.value)}',
      if (before.title != after.title)
        'nome "${before.title}"→"${after.title}"',
      if (before.categoryName != after.categoryName)
        'categoria ${before.categoryName}→${after.categoryName}',
      if (before.date != after.date) 'data ${before.date}→${after.date}',
      if (before.walletId != after.walletId)
        'carteira ${before.walletId}→${after.walletId}',
      if (before.tags.toSet().difference(after.tags.toSet()).isNotEmpty ||
          after.tags.toSet().difference(before.tags.toSet()).isNotEmpty)
        'tags ${before.tags.join(',')}→${after.tags.join(',')}',
    ];
    return parts.isEmpty ? 'sem mudança visível' : parts.join('; ');
  }

  /// Renames the record's transaction in Dinzo, so its panel shows the same
  /// name, and records that both sides now agree on it.
  static Future<void> pushTitle(Record record) async {
    final key = apiKey;
    if (key == null) {
      throw DinzoApiException(
        null,
        'missing_key',
        'Chave da API não configurada',
      );
    }
    // Demo: the rename stays local (Dinzo is never called).
    if (!DemoMode.active) {
      final api = DinzoApi(key);
      try {
        await api.renameTransaction(record.dinzoId!, record.title!);
      } finally {
        api.close();
      }
    }
    final link = DinzoLink.fromJsonString(record.dinzoSnapshot);
    if (link != null) {
      record.dinzoSnapshot = DinzoLink(
        link.source.withTitle(record.title!),
        link.applied.withTitle(record.title!),
      ).toJsonString();
      await ServiceConfig.database.updateRecordById(record.id, record);
    }
  }

  /// Sets the record's category on its Dinzo transaction too, so Dinzo (and
  /// the next sync) agree with the change made here. The AUPP category is
  /// a Dinzo category title (the sync creates them that way); with several of
  /// the same name, the one under the same parent wins. "Sem categoria"
  /// clears it.
  static Future<void> pushCategory(Record record) async {
    final key = apiKey;
    if (key == null) {
      throw DinzoApiException(
        null,
        'missing_key',
        'Chave da API não configurada',
      );
    }
    final name = record.category?.name;
    // Demo: the change stays local (Dinzo is never called).
    if (!DemoMode.active) {
      final api = DinzoApi(key);
      try {
        String? categoryId;
        if (name != null && name != DinzoSyncEngine.uncategorized) {
          final all = await api.categories();
          final titles = {for (final c in all) c.id: c.title};
          final matches = all.where((c) => c.title == name).toList();
          if (matches.isEmpty) {
            throw DinzoApiException(
              null,
              'unknown_category',
              'a categoria "$name" não existe na Dinzo',
            );
          }
          final parent = record.category?.parentName;
          categoryId = matches
              .firstWhere(
                (c) => titles[c.parentId] == parent,
                orElse: () => matches.first,
              )
              .id;
        }
        await api.setTransactionCategory(record.dinzoId!, categoryId);
      } finally {
        api.close();
      }
    }
    final link = DinzoLink.fromJsonString(record.dinzoSnapshot);
    if (link != null) {
      record.dinzoSnapshot = DinzoLink(
        link.source.withCategory(name),
        link.applied.withCategory(name),
      ).toJsonString();
      await ServiceConfig.database.updateRecordById(record.id, record);
    }
  }

  /// Deleting an imported record means "não integrar": otherwise the next
  /// sync would bring it back.
  static Future<void> ignoreDeleted(Iterable<String> dinzoIds) async {
    if (dinzoIds.isEmpty) return;
    final config = loadConfig();
    config.ignoredIds.addAll(dinzoIds);
    await saveConfig(config);
  }

  static Color? _parseColor(String? hex) {
    final digits = hex?.replaceAll('#', '').replaceAll('`', '');
    if (digits == null || digits.length != 6) return null;
    final value = int.tryParse(digits, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  /// Dinzo dates are calendar days; store them at local noon so no timezone
  /// shift can move a record to the previous or next day.
  /// Noon of [day] in the local timezone, in UTC (how imports are dated).
  static DateTime utcNoon(String day) => _utcNoon(day);

  static DateTime _utcNoon(String day) {
    final d = DateTime.parse(day);
    final location = getLocation(ServiceConfig.localTimezone);
    return tz.TZDateTime(location, d.year, d.month, d.day, 12).toUtc();
  }
}
