import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/models/trace.dart';
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

  group('endAndLog — 履歴の自動保存', () {
    test('終了(回収入力あり): 履歴が1件保存され P/L を含む', () async {
      final s = await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(s, counter: 20);
      await service.recordCount(s, counter: 40); // 消化2000

      final trace =
          await service.endAndLog(s, _a, invest: 2000, recovery: 5000);
      expect(trace, isNotNull);

      final all = await traceRepo.allDesc();
      expect(all.length, 1);
      final t = all.single;
      expect(t.machineName, 'P大海物語5');
      expect(t.consumedYen, 2000);
      expect(t.totalRotations, 40);
      expect(t.investYen, 2000);
      expect(t.plYen, 3000); // 回収5000 - 投資2000(消化額は基準にしない)
      expect(t.rotationRate, closeTo(20.0, 1e-9));
      expect(t.borderDiff, closeTo(20.0 - 16.5, 1e-9)); // ホームの前回比用


      // セッションは closed に、active は無くなる。
      expect((await sessionRepo.byId(s.id!))!.state, SessionState.closed);
      expect(await sessionRepo.active(), isNull);
    });

    test('終了(収支スキップ): 投資・P/L とも null', () async {
      final s = await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(s, counter: 30);

      final trace = await service.endAndLog(s, _a); // 投資・回収とも省略=スキップ
      expect(trace, isNotNull);
      expect(trace!.investYen, isNull);
      expect(trace.plYen, isNull);
      expect((await traceRepo.allDesc()).single.plYen, isNull);
    });

    test('片方だけの入力では収支を出さない(両方揃ったときだけ)', () async {
      final s1 = await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(s1, counter: 30);
      final onlyInvest = await service.endAndLog(s1, _a, invest: 3000);
      expect(onlyInvest!.plYen, isNull);

      final s2 = await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(s2, counter: 30);
      final onlyRecovery = await service.endAndLog(s2, _a, recovery: 3000);
      expect(onlyRecovery!.plYen, isNull);
    });

    test('収支は消化額ではなく投資額との差(持ち玉で回しても歪まない)', () async {
      // 現金 1 万円だけ入れ、持ち玉で 2 万円分回した想定(消化 3 万円)。
      final s = await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      for (var i = 1; i <= 30; i++) {
        await service.recordCount(s, counter: i * 20);
      }
      final trace =
          await service.endAndLog(s, _a, invest: 10000, recovery: 0);
      expect(trace!.consumedYen, 30000); // 消化は持ち玉分も含む
      expect(trace.plYen, -10000); // 収支は実際に入れた現金の分だけ
    });

    test('クイック計測(機種なし): 履歴は machineName=null・ボーダー差なしで保存', () async {
      // 機種を選ばず計測 → machineId null・ボーダーなし。
      final s = await service.start(
          machine: null, ballPrice: 4.0, startCounter: 0);
      expect(s.machineId, isNull);
      await service.recordCount(s, counter: 20);
      await service.recordCount(s, counter: 41);

      final trace =
          await service.endAndLog(s, null, invest: 2000, recovery: 3000);
      expect(trace, isNotNull);
      expect(trace!.machineName, isNull); // クイックは機種名なし
      expect(trace.rotationRate, closeTo(20.5, 1e-9)); // 回転率は出る
      expect(trace.borderDiff, isNull); // ボーダーなし=差分も出ない
      expect(trace.plYen, 3000 - 2000); // 収支は機種の有無に関係なく出る

      // 履歴(時系列)に 1 件だけ残る。
      final all = await traceRepo.allDesc();
      expect(all.length, 1);
      expect(all.single.machineName, isNull);
    });

    test('終了3経路(終了/リセット/復帰終了)は同じ endAndLog を通り各1件残す', () async {
      // UI 上の 3 経路(終了ボタン / リセット / 復帰カード終了)は全て endAndLog に
      // 集約される。3 セッションを順に終了すると履歴が 3 件たまる。
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

    test('count 0件のセッションは履歴を残さず破棄される', () async {
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
  group('リセット3択: endAndLog(履歴保存)→新セッションの機種引き継ぎ', () {
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
      // 旧は closed、履歴に 1 件。
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

    test('クイック中の同条件リセット: 履歴は machineName null のまま', () async {
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

    test('count 0件のリセットは履歴を残さず破棄して次へ', () async {
      final s1 =
          await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      // 1 度も決定せずリセット → endAndLog は破棄(履歴なし)。
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

  // ---------- 空セッションは履歴を作らない(実機バグ #1 の回帰防止) ----------
  group('空セッションは3経路とも履歴を作らない', () {
    // 終了 / リセット / 復帰カード終了 は全て endAndLog に集約されるため、
    // endAndLog が空セッションを破棄することで 3 経路すべてが担保される。

    /// endAndLog が破棄(null)し、履歴もセッションも残らないことを検証。
    Future<void> expectDiscarded(Session s, Machine? machine) async {
      final t = await service.endAndLog(s, machine);
      expect(t, isNull);
      expect(await traceRepo.allDesc(), isEmpty);
      expect(await sessionRepo.byId(s.id!), isNull);
      expect(await sessionRepo.active(), isNull);
    }

    test('決定を一度も押していない(count 0件)→ 履歴なし', () async {
      final s =
          await service.start(machine: _a, ballPrice: 4.0, startCounter: 100);
      await expectDiscarded(s, _a);
    });

    test('打ち始め値と同値で1回だけ決定(count有・総回転0)→ 履歴なし', () async {
      // 最初の決定は異常値判定をスキップするため delta 0 の count が作られるが、
      // 総回転 0 なので空セッションとして破棄される。
      final s =
          await service.start(machine: _a, ballPrice: 4.0, startCounter: 100);
      await service.recordCount(s, counter: 100); // delta 0
      await expectDiscarded(s, _a);
    });

    test('クイック計測でも総回転0なら履歴なし(実機で見えた 計測 0.0回/k の再現)', () async {
      final s =
          await service.start(machine: null, ballPrice: 4.0, startCounter: 50);
      await service.recordCount(s, counter: 50); // delta 0
      await expectDiscarded(s, null);
    });

    test('1回でも正の回転があれば履歴は残る(境界の確認)', () async {
      final s =
          await service.start(machine: _a, ballPrice: 4.0, startCounter: 100);
      await service.recordCount(s, counter: 101); // delta 1
      final t = await service.endAndLog(s, _a);
      expect(t, isNotNull);
      expect(t!.totalRotations, 1);
    });
  });

  group('TraceRepository.deleteEmpty(旧不正レコードの一掃)', () {
    test('総回転0以下の履歴だけを削除する', () async {
      // 正常な履歴を1件作る。
      final s =
          await service.start(machine: _a, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(s, counter: 20);
      await service.endAndLog(s, _a);
      // 旧バグ相当の空履歴を直接1件差し込む。
      await traceRepo.insert(Trace(
        date: '2026-07-28',
        machineName: null,
        rotationRate: 0,
        totalRotations: 0,
        consumedYen: 0,
        bonusCount: 0,
        createdAt: '2026-07-28T00:00:00',
      ));
      expect((await traceRepo.allDesc()).length, 2);

      final removed = await traceRepo.deleteEmpty();
      expect(removed, 1);
      final all = await traceRepo.allDesc();
      expect(all.length, 1);
      expect(all.single.totalRotations, greaterThan(0));
    });
  });
}
