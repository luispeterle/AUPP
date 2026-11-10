import 'package:aupp/dinzo/dinzo-default-categories.dart';
import 'package:aupp/services/database/change-log.dart';
import 'package:sqflite/sqflite.dart';

import '../logger.dart';

class SqliteMigrationService {
  static final _logger = Logger.withClass(SqliteMigrationService);

  /// A database older than this is not opened: every device was past it when
  /// the migrations before it were removed.
  static const oldestSupported = 35;

  static const _categoriesTable = """
    CREATE TABLE categories (
        name  TEXT,
        color TEXT,
        icon INTEGER,
        category_type INTEGER,
        last_used INTEGER,
        record_count INTEGER DEFAULT 0,
        is_archived INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        icon_emoji TEXT,
        parent_name TEXT,
        PRIMARY KEY (name, category_type)
    )""";

  static const _recordsTable = """
    CREATE TABLE records (
        id          INTEGER  PRIMARY KEY AUTOINCREMENT,
        datetime    INTEGER,
        timezone    TEXT,
        value       REAL,
        title       TEXT,
        description TEXT,
        category_name TEXT,
        category_type INTEGER,
        recurrence_id TEXT,
        wallet_id   INTEGER,
        transfer_wallet_id INTEGER,
        dinzo_id TEXT,
        dinzo_snapshot TEXT,
        estimate_link TEXT,
        refund_link TEXT
    )""";

  static const _walletsTable = """
    CREATE TABLE wallets (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT,
        color         TEXT,
        icon          INTEGER,
        icon_emoji    TEXT,
        initial_amount REAL DEFAULT 0,
        is_archived   INTEGER DEFAULT 0,
        is_default    INTEGER DEFAULT 0,
        is_predefined INTEGER DEFAULT 0,
        sort_order    INTEGER DEFAULT 0,
        kind          TEXT NOT NULL DEFAULT 'normal'
    )""";

  static const _patternsTable = """
    CREATE TABLE recurrent_record_patterns (
        id          TEXT  PRIMARY KEY,
        datetime    INTEGER,
        timezone    TEXT,
        value       REAL,
        title       TEXT,
        description TEXT,
        category_name TEXT,
        category_type INTEGER,
        last_update INTEGER,
        recurrent_period INTEGER,
        recurrence_id TEXT,
        date_str TEXT,
        tags TEXT,
        end_date INTEGER,
        wallet_id INTEGER,
        transfer_wallet_id INTEGER,
        custom_interval_value INTEGER,
        custom_interval_unit INTEGER,
        payment_codes TEXT
    )""";

  static const _recordsTagsTable = """
    CREATE TABLE records_tags (
       record_id INTEGER NOT NULL,
       tag_name TEXT NOT NULL,
       PRIMARY KEY (record_id, tag_name)
    )""";

  /// Tags that exist before any record uses them: the payment methods,
  /// always, and the banks the Dinzo sync finds (see ForkTags).
  static const _forkTagsTable =
      'CREATE TABLE fork_tags (name TEXT PRIMARY KEY)';

  static const _recordsIndex =
      'CREATE INDEX IF NOT EXISTS idx_records_dinzo_id ON records(dinzo_id)';

  static Future<void> _createRecordTriggers(DatabaseExecutor db) async {
    await db.execute("""
      CREATE TRIGGER update_category_usage
      AFTER INSERT ON records
      FOR EACH ROW
      BEGIN
          UPDATE categories
          SET record_count = record_count + 1,
              last_used = strftime('%s', 'now') * 1000
          WHERE name = NEW.category_name AND category_type = NEW.category_type;
      END""");
    await db.execute("""
      CREATE TRIGGER update_category_usage_on_update
      AFTER UPDATE OF category_name, category_type ON records
      FOR EACH ROW
      WHEN NEW.category_name IS NOT OLD.category_name
        OR NEW.category_type IS NOT OLD.category_type
      BEGIN
          UPDATE categories
          SET record_count = record_count + 1,
              last_used = strftime('%s', 'now') * 1000
          WHERE name = NEW.category_name AND category_type = NEW.category_type;
          UPDATE categories
          SET record_count = record_count - 1
          WHERE name = OLD.category_name AND category_type = OLD.category_type;
      END""");
    await db.execute("""
      CREATE TRIGGER update_category_usage_on_delete
      AFTER DELETE ON records
      FOR EACH ROW
      BEGIN
          UPDATE categories
          SET record_count = record_count - 1
          WHERE name = OLD.category_name AND category_type = OLD.category_type;
      END""");
    await db.execute("""
      CREATE TRIGGER delete_record_tags
      AFTER DELETE ON records
      FOR EACH ROW
      BEGIN
          DELETE FROM records_tags WHERE record_id = OLD.id;
      END""");
  }

  static const defaultWalletName = 'Conta corrente';

  /// Payment methods every install starts with (names match KnownTag).
  static const defaultForkTags = [
    'Pix',
    'Crédito',
    'Débito',
    'Boleto',
    'Transferência',
  ];

  /// Every device is on the current schema: a database from before it is
  /// not converted.
  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    throw StateError('Banco de dados antigo demais (versão $oldVersion)');
  }

  static Future<void> onCreate(Database db, int version) async {
    _logger.info('Creating new database (version $version)');
    await db.execute(_categoriesTable);
    await db.execute(_recordsTable);
    await db.execute(_recordsTagsTable);
    await db.execute(_patternsTable);
    await db.execute(_walletsTable);
    await db.execute(_forkTagsTable);
    await db.execute(ChangeLog.createTable);
    await db.execute(_recordsIndex);
    await _createRecordTriggers(db);

    final batch = db.batch();
    for (final category in dinzoDefaultCategories()) {
      batch.insert('categories', category.toMap());
    }
    for (final tag in defaultForkTags) {
      batch.insert('fork_tags', {'name': tag});
    }
    await batch.commit(noResult: true);

    await db.rawInsert(
      "INSERT INTO wallets (name, is_default, sort_order) VALUES (?, 1, 0)",
      [defaultWalletName],
    );
  }
}
