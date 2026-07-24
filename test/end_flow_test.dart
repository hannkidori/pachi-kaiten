import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/entry.dart';
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

  test('台移動: endAndLog(旧) → start(新) が途切れなく繋がる', () async {
    final s1 = await service.start(machine: _a, ballPrice: 4.0, startCounter: 100);
    await service.recordCount(s1, counter: 118);

    // 旧セッションを足跡に記録して終了。
    final trace = await service.endAndLog(s1, _a, recovery: 0);
    expect(trace, isNotNull);
    expect(trace!.plYen, 0 - 1000); // 回収0 - 消化1000

    // 同じ貸玉で新機種のセッションを開始。
    final s2 = await service.start(
        machine: _b, ballPrice: 4.0, startCounter: 0, addUnit: s1.addUnit);

    // 旧: closed で確定
    expect((await sessionRepo.byId(s1.id!))!.state, SessionState.closed);
    // 新: これが唯一の active
    final active = await sessionRepo.active();
    expect(active!.id, s2.id);
    expect(active.machineId, 2);
    // 新セッションには start イベントがある(打ち始め0)
    final ev = await entryRepo.bySession(s2.id!);
    expect(ev.single.type, EntryType.start);
    expect(ev.single.counter, 0);
  });
}
