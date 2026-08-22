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

  /// 現在のスキーマバージョン。
  /// v5: クイック計測対応で machine_id / machine_name を nullable 化。
  /// v6: 履歴にボーダー差分(border_diff)を追加(ホームの前回比ヒーロー用)。
  static const _dbVersion = 7;

  /// 「ここから先はデータを引き継ぐ」基準バージョン。
  ///
  /// これ未満(= リリース前の実験的スキーマ)からの更新だけは作り直しを許す。
  /// [_baselineVersion] 以降は必ず [migrations] に手順を書いて引き継ぐこと。
  /// ユーザーが育てた機種マスタと履歴を消さないための線引き。
  static const _baselineVersion = 6;

  /// バージョンごとのマイグレーション手順(v へ上げるときに実行する)。
  ///
  /// 例: 7 でカラムを足すなら
  ///   7: (db) async => db.execute('ALTER TABLE traces ADD COLUMN memo TEXT'),
  /// スキーマを変えたら _dbVersion を上げ、必ずここに追記する。
  /// (テストから直接適用して検証できるよう公開している)
  static final Map<int, Future<void> Function(Database db)> migrations = {
    // 収支を「回収 − 消化額」から「回収 − 投資」に変更(消化額は持ち玉で回した分も
    // 含むため、実際の現金収支と一致しなかった)。投資額の列を足し、意味の違う
    // 旧 pl_yen は誤った数字を残さないよう捨てる(履歴の行そのものは残る)。
    7: (db) async {
      await db.execute('ALTER TABLE traces ADD COLUMN invest_yen INTEGER');
      await db.execute('UPDATE traces SET pl_yen = NULL');
    },
  };

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
      // ダウングレード(古いアプリを入れ直した)は現行スキーマを読めないため
      // 作り直すしかない。通常運用では起こらない。
      onDowngrade: (db, _, _) => _recreate(db),
    );
  }

  /// バージョンを上げるときの処理。
  ///
  /// - [_baselineVersion] 未満から: リリース前の互換の無いスキーマなので作り直す。
  /// - それ以降: [migrations] を 1 段ずつ適用してデータを引き継ぐ。
  ///   手順が未定義のバージョンがあれば、黙って壊れないよう例外にする
  ///   (開発時に必ず気付ける)。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < _baselineVersion) {
      await _recreate(db);
      return;
    }
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      final step = migrations[v];
      if (step == null) {
        throw StateError('DB v$v のマイグレーションが未定義です'
            '(migrations に追記してください)');
      }
      await step(db);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final stmt in createStatements) {
      batch.execute(stmt);
    }
    await batch.commit(noResult: true);
  }

  /// 既存のユーザーテーブルを全て drop してスキーマを再生成する。
  /// リリース前のため旧データは保持しない(方針: スキーマ変更＝作り直し)。
  Future<void> _recreate(Database db) async {
    final tables = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name NOT LIKE 'sqlite_%' "
          "AND name NOT LIKE 'android_%'",
    );
    final batch = db.batch();
    for (final row in tables) {
      batch.execute('DROP TABLE IF EXISTS "${row['name']}"');
    }
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
      machine_id INTEGER,
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
    // 履歴ログ = セッション終了時に自動保存する確定スナップショット。
    // 機種名などをデノーマライズ保存し、機種の削除・改名の影響を受けない。
    '''
    CREATE TABLE traces (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      machine_name TEXT,
      rotation_rate REAL,
      border_diff REAL,
      total_rotations INTEGER NOT NULL,
      ev_yen INTEGER, -- 旧: 期待値。表示を廃止したので書き込まない(列だけ残す)
      consumed_yen INTEGER NOT NULL,
      bonus_count INTEGER NOT NULL,
      invest_yen INTEGER,
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
