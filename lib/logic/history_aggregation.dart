import '../models/session.dart';
import 'rotation_calc.dart';

/// セッション 1 件に統計を束ねた集計単位。
class SessionAggregate {
  final Session session;
  final RotationStats stats;

  const SessionAggregate({required this.session, required this.stats});

  /// 投資額(円)= 現金投資の合計。
  int get invest => stats.cashInvest;

  /// 回収額(円)。未確定なら 0 扱い。
  int get recovery => session.recovery ?? 0;

  /// 収支(円)= 回収 − 投資。
  int get profit => recovery - invest;

  /// 期待値(円)。未計測なら 0 扱い。
  double get expectedValue => stats.expectedValue ?? 0;
}

/// 日別サマリー(履歴の日グルーピング)。
class DaySummary {
  final String date; // YYYY-MM-DD
  final List<SessionAggregate> sessions;

  const DaySummary({required this.date, required this.sessions});

  int get sessionCount => sessions.length;
  int get totalInvest => sessions.fold(0, (a, s) => a + s.invest);
  int get totalRecovery => sessions.fold(0, (a, s) => a + s.recovery);
  int get dayProfit => totalRecovery - totalInvest;
  double get evSum => sessions.fold(0.0, (a, s) => a + s.expectedValue);
}

/// 機種別サマリー。主指標は回収率(回収 / 投資 %)。
class MachineSummary {
  final String machineId;
  final List<SessionAggregate> sessions;

  const MachineSummary({required this.machineId, required this.sessions});

  int get sessionCount => sessions.length;
  int get totalInvest => sessions.fold(0, (a, s) => a + s.invest);
  int get totalRecovery => sessions.fold(0, (a, s) => a + s.recovery);
  int get profit => totalRecovery - totalInvest;

  /// 回収率(%)。投資 0 のときは null。
  double? get recoveryRate =>
      totalInvest > 0 ? totalRecovery / totalInvest * 100.0 : null;
}

/// 日別にグルーピングして日付の新しい順に返す。
List<DaySummary> groupByDay(List<SessionAggregate> items) {
  final map = <String, List<SessionAggregate>>{};
  for (final a in items) {
    map.putIfAbsent(a.session.date, () => []).add(a);
  }
  final days = map.entries
      .map((e) => DaySummary(date: e.key, sessions: e.value))
      .toList();
  days.sort((a, b) => b.date.compareTo(a.date));
  return days;
}

/// 機種別にグルーピングして投資額の多い順に返す。
List<MachineSummary> groupByMachine(List<SessionAggregate> items) {
  final map = <String, List<SessionAggregate>>{};
  for (final a in items) {
    map.putIfAbsent(a.session.machineId, () => []).add(a);
  }
  final list = map.entries
      .map((e) => MachineSummary(machineId: e.key, sessions: e.value))
      .toList();
  list.sort((a, b) => b.totalInvest.compareTo(a.totalInvest));
  return list;
}

/// 日別勝率(%)。±0 円の日は母数から除外する(既存収支アプリと同ルール)。
/// 勝敗のある日が無ければ null。
double? dayWinRate(List<DaySummary> days) {
  var wins = 0;
  var decided = 0;
  for (final d in days) {
    if (d.dayProfit == 0) continue;
    decided++;
    if (d.dayProfit > 0) wins++;
  }
  if (decided == 0) return null;
  return wins / decided * 100.0;
}
