import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/history_aggregation.dart';
import 'package:pachi_kaiten/logic/rotation_calc.dart';
import 'package:pachi_kaiten/models/session.dart';

SessionAggregate _agg({
  required String date,
  required String machineId,
  required int invest,
  required int recovery,
  double ev = 0,
}) {
  final session = Session(
    id: null,
    date: date,
    storeId: 1,
    machineId: machineId,
    exchangeRate: 4.0,
    ballPrice: 4.0,
    state: SessionState.closed,
    recovery: recovery,
    startedAt: '${date}T10:00:00',
  );
  final stats = RotationStats(
    totalRotations: 0,
    cashRotations: 0,
    cashInvest: invest,
    measuredRotations: 0,
    measuredInvest: invest,
    rotationRate: null,
    effectiveBorder: 16.5,
    borderDiff: null,
    expectedValue: ev,
    segments: const [],
    bonusCount: 0,
  );
  return SessionAggregate(session: session, stats: stats);
}

void main() {
  test('profit = recovery - invest', () {
    final a = _agg(date: '2026-07-22', machineId: 'm', invest: 10000, recovery: 15000);
    expect(a.profit, 5000);
  });

  group('groupByDay', () {
    test('同日をまとめ、日付降順、日収支を合算', () {
      final items = [
        _agg(date: '2026-07-20', machineId: 'a', invest: 5000, recovery: 3000),
        _agg(date: '2026-07-22', machineId: 'b', invest: 4000, recovery: 10000),
        _agg(date: '2026-07-22', machineId: 'c', invest: 6000, recovery: 2000),
      ];
      final days = groupByDay(items);
      expect(days.map((d) => d.date).toList(), ['2026-07-22', '2026-07-20']);

      final d22 = days.first;
      expect(d22.sessionCount, 2);
      expect(d22.totalInvest, 10000);
      expect(d22.totalRecovery, 12000);
      expect(d22.dayProfit, 2000);
    });
  });

  group('groupByMachine', () {
    test('機種別集計と回収率', () {
      final items = [
        _agg(date: '2026-07-22', machineId: 'umi', invest: 10000, recovery: 12000),
        _agg(date: '2026-07-21', machineId: 'umi', invest: 10000, recovery: 8000),
        _agg(date: '2026-07-20', machineId: 'eva', invest: 5000, recovery: 5000),
      ];
      final byMachine = groupByMachine(items);
      // 投資額の多い umi が先頭
      expect(byMachine.first.machineId, 'umi');

      final umi = byMachine.first;
      expect(umi.totalInvest, 20000);
      expect(umi.totalRecovery, 20000);
      expect(umi.recoveryRate, closeTo(100.0, 1e-9));

      final eva = byMachine[1];
      expect(eva.recoveryRate, closeTo(100.0, 1e-9));
    });

    test('投資0の機種は回収率 null', () {
      final byMachine = groupByMachine([
        _agg(date: '2026-07-22', machineId: 'x', invest: 0, recovery: 0),
      ]);
      expect(byMachine.first.recoveryRate, isNull);
    });
  });

  group('dayWinRate', () {
    test('±0円の日は母数から除外', () {
      final days = groupByDay([
        _agg(date: '2026-07-22', machineId: 'a', invest: 1000, recovery: 5000), // +勝
        _agg(date: '2026-07-21', machineId: 'a', invest: 5000, recovery: 1000), // -負
        _agg(date: '2026-07-20', machineId: 'a', invest: 3000, recovery: 3000), // ±0 除外
      ]);
      // 勝1 / 勝負2 = 50%
      expect(dayWinRate(days), closeTo(50.0, 1e-9));
    });

    test('勝負のある日が無ければ null', () {
      final days = groupByDay([
        _agg(date: '2026-07-22', machineId: 'a', invest: 3000, recovery: 3000),
      ]);
      expect(dayWinRate(days), isNull);
    });
  });
}
