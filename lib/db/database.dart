import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// アプリの sqflite データベース。スキーマ定義と接続の入口のみを担う。
/// クエリは各リポジトリ層(machine_repo など)から [db] を通して行う。
///
/// リリース前のためスキーマは v1 に採番し直している(マイグレーション履歴を
/// 積まない)。既存端末はアンインストール→再インストールで作り直す前提。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'pachi_kaiten.db';
  static const _dbVersion = 1;

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
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final stmt in createStatements) {
      batch.execute(stmt);
    }
    await batch.commit(noResult: true);
  }

  /// スキーマ生成 SQL 群(テスト用インメモリ DB からも参照できるよう公開)。
  static const List<String> createStatements = [
    // 機種マスタ = ユーザー登録機種の保存先(育つマスタ)。
    // ボーダーは 4円用 / 1円用の 2 スロット(どちらも任意・最低 1 つ)。
    // 自動換算はしない — 1パチのボーダーは 4パチの単純 4 倍にならないため。
    '''
    CREATE TABLE machines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      border_4 REAL,
      border_1 REAL,
      updated_at TEXT
    )
    ''',
    // セッション = 1 台の計測単位。ball_price はグローバル貸玉設定の開始時コピー。
    '''
    CREATE TABLE sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      machine_id INTEGER NOT NULL,
      ball_price REAL NOT NULL,
      add_unit INTEGER NOT NULL DEFAULT 1000,
      state TEXT NOT NULL DEFAULT 'active',
      recovery INTEGER,
      started_at TEXT NOT NULL,
      closed_at TEXT
    )
    ''',
    // 決定は常に「1 単位(1000/500円分)消化」の申告。現金/持ち玉の区別は持たない。
    '''
    CREATE TABLE entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      counter INTEGER NOT NULL,
      yen INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
    ''',
    // 足跡ログ = セッション終了時に自動保存する確定スナップショット。
    // 機種名などをデノーマライズ保存し、機種の削除・改名の影響を受けない。
    '''
    CREATE TABLE traces (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      machine_name TEXT NOT NULL,
      rotation_rate REAL,
      total_rotations INTEGER NOT NULL,
      ev_yen INTEGER,
      consumed_yen INTEGER NOT NULL,
      bonus_count INTEGER NOT NULL,
      pl_yen INTEGER,
      created_at TEXT NOT NULL
    )
    ''',
    _settingsTable,
    'CREATE INDEX idx_entries_session ON entries(session_id, id)',
    'CREATE INDEX idx_sessions_state ON sessions(state)',
    'CREATE INDEX idx_traces_date ON traces(date DESC, id DESC)',
  ];

  static const _settingsTable = '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''';
}
