import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/db/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v6 時点の traces。invest_yen が無く、pl_yen は「回収 − 消化額」だった。
const _tracesV6 = '''
  CREATE TABLE traces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    machine_name TEXT,
    rotation_rate REAL,
    border_diff REAL,
    total_rotations INTEGER NOT NULL,
    ev_yen INTEGER,
    consumed_yen INTEGER NOT NULL,
    bonus_count INTEGER NOT NULL,
    pl_yen INTEGER,
    created_at TEXT NOT NULL
  )
''';

void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(_tracesV6);
  });
  tearDown(() async => db.close());

  group('v7: 収支を「回収 − 投資」に変更', () {
    Future<void> insertV6Row({int? plYen}) => db.insert('traces', {
          'date': '2026-08-01',
          'machine_name': 'P大海物語5',
          'rotation_rate': 20.5,
          'border_diff': 4.0,
          'total_rotations': 249,
          'ev_yen': 480,
          'consumed_yen': 30000,
          'bonus_count': 2,
          'pl_yen': plYen,
          'created_at': '2026-08-01T20:00:00.000',
        });

    test('履歴の行は消えず、意味の変わった pl_yen だけが落ちる', () async {
      await insertV6Row(plYen: -30000); // 旧定義(回収 − 消化額)の誤った値
      await AppDatabase.migrations[7]!(db);

      final rows = await db.query('traces');
      expect(rows.length, 1, reason: '履歴そのものは残す');
      expect(rows.single['total_rotations'], 249); // 計測データは無傷
      expect(rows.single['consumed_yen'], 30000);
      expect(rows.single['pl_yen'], isNull); // 旧収支は捨てる
      expect(rows.single['invest_yen'], isNull); // 新しい列は空で始まる
    });

    test('移行後は投資額を保存できる', () async {
      await AppDatabase.migrations[7]!(db);
      await db.insert('traces', {
        'date': '2026-08-23',
        'total_rotations': 100,
        'consumed_yen': 30000,
        'bonus_count': 0,
        'invest_yen': 10000,
        'pl_yen': -10000, // 回収 0 − 投資 10000
        'created_at': '2026-08-23T20:00:00.000',
      });
      final row = (await db.query('traces')).single;
      expect(row['invest_yen'], 10000);
      expect(row['pl_yen'], -10000);
    });

    test('手順が定義されている(未定義のまま _dbVersion を上げない)', () {
      expect(AppDatabase.migrations.containsKey(7), isTrue);
    });
  });
}
