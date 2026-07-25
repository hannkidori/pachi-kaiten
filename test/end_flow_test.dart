import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/models/session.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/trace_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

const _a = Machine(id: 1, name: 'P大海物語5', border4: 16.5);
const _b = Machine(id: 2, name: 'Pエヴァ15', border4: 17.0);

void main() {
  late Database db;
  late SessionService service;
  late SessionRepository sessionRepo;
  late EntryRepository entryRepo;
  late TraceRepository traceRepo;

  setUp(() async {
    db = await openTestDb();
    sessionRepo = SessionRepository(db);
    entryRepo = EntryRepository(db);
    traceRepo = TraceRepository(db);
    service = SessionService(
        sessions: sessionRepo, entries: entryRepo, traces: traceRepo);
  });
  tearDown(() async => db.close());

  group('endAndLog — 足跡の自動保存', () {
    test('終了(回収入力あり): 足跡が1件保存され P/L を含む', () async {
      final s = await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(s, counter: 20);
      await service.recordCount(s, counter: 40); // 消化2000

      final trace = await service.endAndLog(s, _a, recovery: 5000);
      expect(trace, isNotNull);

      final all = await traceRepo.allDesc();
      expect(all.length, 1);
      final t = all.single;
      expect(t.machineName, 'P大海物語5');
      expect(t.consumedYen, 2000);
      expect(t.totalRotations, 40);
      expect(t.plYen, 3000); // 回収5000 - 消化2000
      expect(t.rotationRate, closeTo(20.0, 1e-9));
      expect(t.borderDiff, closeTo(20.0 - 16.5, 1e-9)); // ホームの前回比用


      // セッションは closed に、active は無くなる。
      expect((await sessionRepo.byId(s.id!))!.state, SessionState.closed);
      expect(await sessionRepo.active(), isNull);
    });

    test('終了(回収スキップ): P/L は null', () async {
      final s = await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(s, counter: 30);

      final trace = await service.endAndLog(s, _a); // recovery 省略=スキップ
      expect(trace, isNotNull);
      expect(trace!.plYen, isNull);
      expect((await traceRepo.allDesc()).single.plYen, isNull);
    });

    test('クイック計測(機種なし): 足跡は machineName=null・EV=null で保存', () async {
      // 機種を選ばず計測 → machineId null・ボーダーなし。
      final s = await service.start(
          machine: null, ballPrice: 4.0, startCounter: 0);
      expect(s.machineId, isNull);
      await service.recordCount(s, counter: 20);
      await service.recordCount(s, counter: 41);

      final trace = await service.endAndLog(s, null, recovery: 3000);
      expect(trace, isNotNull);
      expect(trace!.machineName, isNull); // クイックは機種名なし
      expect(trace.rotationRate, closeTo(20.5, 1e-9)); // 回転率は出る
      expect(trace.evYen, isNull); // ボーダーなし=EVなし
      expect(trace.borderDiff, isNull); // ボーダー差分も出ない
      expect(trace.plYen, 3000 - 2000); // 回収-消化 は出る

      // 足跡(時系列)に 1 件だけ残り、EV は null のまま。
      final all = await traceRepo.allDesc();
      expect(all.length, 1);
      expect(all.single.machineName, isNull);
      expect(all.single.evYen, isNull);
    });

    test('終了3経路(終了/リセット/復帰終了)は同じ endAndLog を通り各1件残す', () async {
      // UI 上の 3 経路(終了ボタン / リセット / 復帰カード終了)は全て endAndLog に
      // 集約される。3 セッションを順に終了すると足跡が 3 件たまる。
      for (var i = 0; i < 3; i++) {
        final s =
            await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
        await service.recordCount(s, counter: 20 + i);
        final t = await service.endAndLog(s, _a);
        expect(t, isNotNull);
      }
      expect((await traceRepo.allDesc()).length, 3);
      expect(await sessionRepo.active(), isNull); // 進行中は残らない
    });

    test('count 0件のセッションは足跡を残さず破棄される', () async {
      final s = await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      // count を 1 件も打たずに終了。
      final trace = await service.endAndLog(s, _a, recovery: 1000);
      expect(trace, isNull);
      expect(await traceRepo.allDesc(), isEmpty);
      // セッションごと破棄されている(closed でもない)。
      expect(await sessionRepo.byId(s.id!), isNull);
      expect(await sessionRepo.active(), isNull);
    });
  });

  // ---------- リセット(次の台へ急ぐ出口。回収額は聞かない) ----------
  group('リセット3択: endAndLog(足跡保存)→新セッションの機種引き継ぎ', () {
    // リセットは回収額を聞かない=常に recovery なし。3 択それぞれの「新セッションの
    // machine_id」を検証する。UI の差は「次に開始する machine」だけなので、
    // service レベルで endAndLog→start の連結として検証する。

    /// 旧を計測して endAndLog(回収なし)し、指定 machine で新セッションを開始する。
    Future<Session> resetTo(Machine old, Machine? next) async {
      final s1 =
          await service.start(machine: old, ballPrice: 4.0, startCounter: 100);
      await service.recordCount(s1, counter: 118);
      final trace = await service.endAndLog(s1, old); // recovery なし
      expect(trace, isNotNull);
      expect(trace!.plYen, isNull); // リセットは P/L を記録しない
      // 旧は closed、足跡に 1 件。
      expect((await sessionRepo.byId(s1.id!))!.state, SessionState.closed);
      return service.start(
          machine: next, ballPrice: 4.0, startCounter: 0, addUnit: s1.addUnit);
    }

    test('同条件(機種そのまま): 新セッションは同じ machine_id', () async {
      final s2 = await resetTo(_a, _a);
      final active = await sessionRepo.active();
      expect(active!.id, s2.id);
      expect(active.machineId, _a.id); // 同じ機種を引き継ぐ
      expect((await traceRepo.allDesc()).length, 1);
    });

    test('機種を変えて: 新セッションは別の machine_id', () async {
      final s2 = await resetTo(_a, _b);
      final active = await sessionRepo.active();
      expect(active!.id, s2.id);
      expect(active.machineId, _b.id); // 変更後の機種
      expect((await traceRepo.allDesc()).length, 1);
    });

    test('機種なしで: 新セッションは machine_id null(クイック)', () async {
      final s2 = await resetTo(_a, null);
      final active = await sessionRepo.active();
      expect(active!.id, s2.id);
      expect(active.machineId, isNull); // クイックに切替
      expect((await traceRepo.allDesc()).length, 1);
    });

    test('クイック中の同条件リセット: 足跡は machineName null のまま', () async {
      final s2 = await resetTo(_a, null);
      // s2(クイック)を計測して更にリセット(同条件=クイックのまま)。
      await service.recordCount(s2, counter: 20);
      await service.endAndLog(s2, null); // クイックの終了(recovery なし)
      final s3 = await service.start(
          machine: null, ballPrice: 4.0, startCounter: 0);
      expect((await sessionRepo.active())!.id, s3.id);
      final quickTrace = (await traceRepo.allDesc()).first;
      expect(quickTrace.machineName, isNull);
    });

    test('count 0件のリセットは足跡を残さず破棄して次へ', () async {
      final s1 =
          await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      // 1 度も決定せずリセット → endAndLog は破棄(足跡なし)。
      final trace = await service.endAndLog(s1, _a);
      expect(trace, isNull);
      expect(await traceRepo.allDesc(), isEmpty);
      expect(await sessionRepo.byId(s1.id!), isNull); // 破棄
      // その後、新セッションは問題なく開始できる。
      final s2 =
          await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      expect((await sessionRepo.active())!.id, s2.id);
    });
  });
}
