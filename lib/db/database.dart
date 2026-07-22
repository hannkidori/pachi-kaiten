import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// アプリの sqflite データベース。スキーマ定義と接続の入口のみを担う。
/// クエリは各リポジトリ層(store_repo など)から [db] を通して行う。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'pachi_kaiten.db';
  static const _dbVersion = 3;

  Database? _db;

  Future<Database> get db async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final stmt in createStatements) {
      batch.execute(stmt);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute(_settingsTable);
    }
    if (from < 3) {
      // 持ち玉消費(玉数)。既存 ball イベントは 0 のまま=計測外として扱う。
      await db.execute(
          'ALTER TABLE entries ADD COLUMN balls_added INTEGER NOT NULL DEFAULT 0');
    }
  }

  static const _settingsTable = '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''';

  /// スキーマ生成 SQL 群(テスト用インメモリ DB からも参照できるよう公開)。
  static const List<String> createStatements = [
    '''
    CREATE TABLE stores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      exchange_rate REAL NOT NULL,
      ball_price REAL NOT NULL DEFAULT 4.0,
      sort_order INTEGER DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE machines (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      probability REAL NOT NULL,
      border_40 REAL NOT NULL,
      border_357 REAL,
      border_33 REAL,
      border_303 REAL,
      type TEXT,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      store_id INTEGER NOT NULL,
      machine_id TEXT NOT NULL,
      exchange_rate REAL NOT NULL,
      ball_price REAL NOT NULL,
      add_unit INTEGER NOT NULL DEFAULT 1000,
      state TEXT NOT NULL DEFAULT 'active',
      recovery INTEGER,
      started_at TEXT NOT NULL,
      closed_at TEXT
    )
    ''',
    '''
    CREATE TABLE entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      counter INTEGER NOT NULL,
      mode TEXT NOT NULL,
      invest_added INTEGER NOT NULL DEFAULT 0,
      balls_added INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
    ''',
    _settingsTable,
    'CREATE INDEX idx_entries_session ON entries(session_id, id)',
    'CREATE INDEX idx_sessions_state ON sessions(state)',
    'CREATE INDEX idx_sessions_date ON sessions(date)',
  ];
}
