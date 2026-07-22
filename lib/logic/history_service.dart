import '../repositories/entry_repository.dart';
import '../repositories/machine_repository.dart';
import '../repositories/session_repository.dart';
import 'history_aggregation.dart';
import 'rotation_calc.dart';

/// 指定月の履歴データ(集計単位 + 機種名の解決)。
class MonthData {
  final List<SessionAggregate> aggregates;
  final Map<String, String> machineNames; // machineId -> 表示名

  const MonthData({required this.aggregates, required this.machineNames});
}

/// 履歴・収支の読み込み。セッションごとに entries を集約して統計を計算する。
class HistoryService {
  final SessionRepository sessions;
  final EntryRepository entries;
  final MachineRepository machines;

  HistoryService({
    required this.sessions,
    required this.entries,
    required this.machines,
  });

  /// 記録のある月(YYYY-MM)を新しい順に。
  Future<List<String>> months() => sessions.months();

  /// 指定月(YYYY-MM)の集計。
  Future<MonthData> load(String yyyyMm) async {
    final ss = await sessions.closedByMonth(yyyyMm);
    return _aggregate(ss);
  }

  /// 全期間の集計(機種別サマリー用)。
  Future<MonthData> loadAll() async {
    final ss = await sessions.allClosed();
    return _aggregate(ss);
  }

  Future<MonthData> _aggregate(List ss) async {
    final names = <String, String>{};
    final borderCache = <String, double>{};
    final aggregates = <SessionAggregate>[];

    for (final session in ss) {
      // 機種名・ボーダーをキャッシュしつつ解決(削除済み機種にも耐える)。
      if (!names.containsKey(session.machineId)) {
        final m = await machines.byId(session.machineId);
        names[session.machineId] = m?.name ?? session.machineId;
        borderCache[session.machineId] =
            m?.borderForRate(session.exchangeRate) ?? 16.5;
      }
      final ev = await entries.bySession(session.id!);
      final stats = computeStats(
        entries: ev,
        catalogBorder: borderCache[session.machineId]!,
        ballPrice: session.ballPrice,
      );
      aggregates.add(SessionAggregate(session: session, stats: stats));
    }
    return MonthData(aggregates: aggregates, machineNames: names);
  }
}
