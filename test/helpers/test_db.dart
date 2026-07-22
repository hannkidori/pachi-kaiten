import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pachi_kaiten/db/database.dart';
import 'package:pachi_kaiten/logic/backup_service.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/machine_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/settings_repository.dart';
import 'package:pachi_kaiten/repositories/trace_repository.dart';
import 'package:pachi_kaiten/services/app_services.dart';

/// テスト用の DB から AppServices を組み立てる。
AppServices buildTestServices(Database db) {
  final machines = MachineRepository(db);
  final sessions = SessionRepository(db);
  final entries = EntryRepository(db);
  final traces = TraceRepository(db);
  final settings = SettingsRepository(db);
  return AppServices(
    machines: machines,
    sessions: sessions,
    entries: entries,
    traces: traces,
    settings: settings,
    sessionService: SessionService(
        sessions: sessions, entries: entries, traces: traces),
    backup: BackupService(db),
  );
}

/// テスト用のインメモリ DB を FFI で開き、本番と同じスキーマを流し込む。
Future<Database> openTestDb() async {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        final batch = db.batch();
        for (final stmt in AppDatabase.createStatements) {
          batch.execute(stmt);
        }
        await batch.commit(noResult: true);
      },
    ),
  );
  return db;
}
