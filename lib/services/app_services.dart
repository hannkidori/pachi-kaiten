import '../db/database.dart';
import '../logic/session_service.dart';
import '../repositories/entry_repository.dart';
import '../repositories/machine_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/trace_repository.dart';

/// 簡易サービスロケータ。DB を開いてリポジトリ/サービスを束ねる。
/// 各画面はこれを受け取って永続化にアクセスする。
class AppServices {
  final MachineRepository machines;
  final SessionRepository sessions;
  final EntryRepository entries;
  final TraceRepository traces;
  final SettingsRepository settings;
  final SessionService sessionService;

  AppServices({
    required this.machines,
    required this.sessions,
    required this.entries,
    required this.traces,
    required this.settings,
    required this.sessionService,
  });

  static Future<AppServices> open() async {
    final db = await AppDatabase.instance.db;
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
    );
  }
}
