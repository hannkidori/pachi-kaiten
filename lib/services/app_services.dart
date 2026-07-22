import '../db/database.dart';
import '../logic/backup_service.dart';
import '../logic/history_service.dart';
import '../logic/machine_sync.dart';
import '../logic/session_service.dart';
import '../repositories/entry_repository.dart';
import '../repositories/machine_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/store_repository.dart';

/// 簡易サービスロケータ。DB を開いてリポジトリ/サービスを束ねる。
/// 各画面はこれを受け取って永続化にアクセスする。
class AppServices {
  final StoreRepository stores;
  final MachineRepository machines;
  final SessionRepository sessions;
  final EntryRepository entries;
  final SettingsRepository settings;
  final SessionService sessionService;
  final HistoryService history;
  final MachineSync machineSync;
  final BackupService backup;

  AppServices({
    required this.stores,
    required this.machines,
    required this.sessions,
    required this.entries,
    required this.settings,
    required this.sessionService,
    required this.history,
    required this.machineSync,
    required this.backup,
  });

  static Future<AppServices> open() async {
    final db = await AppDatabase.instance.db;
    final machines = MachineRepository(db);
    final settings = SettingsRepository(db);
    final machineSync = MachineSync(machines, settings: settings);
    // 空ならシード、同梱版が新しければ機種シートを同期(ミラー)。
    await machineSync.seedFromAsset();
    final sessions = SessionRepository(db);
    final entries = EntryRepository(db);
    return AppServices(
      stores: StoreRepository(db),
      machines: machines,
      sessions: sessions,
      entries: entries,
      settings: settings,
      sessionService: SessionService(sessions: sessions, entries: entries),
      history: HistoryService(
          sessions: sessions, entries: entries, machines: machines),
      machineSync: machineSync,
      backup: BackupService(db),
    );
  }
}
