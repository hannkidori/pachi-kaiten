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

const _machine = Machine(
  id: 1,
  name: 'P大海物語5スペシャル',
  border4: 16.5,
  border1: 66.0,
);

void main() {
  late Database db;
  late SessionService service;
  late SessionRepository sessionRepo;
  late EntryRepository entryRepo;

  // 時刻を固定して created_at / date を決定的にする。
  var t = DateTime(2026, 7, 22, 10, 0, 0);
  DateTime clock() => t;

  setUp(() async {
    db = await openTestDb();
    sessionRepo = SessionRepository(db);
    entryRepo = EntryRepository(db);
    service = SessionService(
      sessions: sessionRepo,
      entries: entryRepo,
      traces: TraceRepository(db),
      clock: clock,
    );
    t = DateTime(2026, 7, 22, 10, 0, 0);
  });

  tearDown(() async => db.close());

  test('start でセッションと start イベントが即時に書かれる', () async {
    final s = await service.start(
      machine: _machine,
      ballPrice: 4.0,
      startCounter: 100,
    );
    expect(s.id, isNotNull);
    expect(s.state, SessionState.active);
    expect(s.ballPrice, 4.0);
    expect(s.machineId, 1);
    expect(s.date, '2026-07-22');

    final ev = await entryRepo.bySession(s.id!);
    expect(ev.length, 1);
    expect(ev.first.type, EntryType.start);
    expect(ev.first.counter, 100);

    // 復帰カード用: active が取得できる
    final active = await sessionRepo.active();
    expect(active!.id, s.id);
  });

  test('決定タップは即時書き込み、消化は自動加算', () async {
    final s = await service.start(machine: _machine, ballPrice: 4.0, startCounter: 0);
    await service.recordCount(s, counter: 20);
    await service.recordCount(s, counter: 41);

    final stats = await service.stats(s, _machine);
    expect(stats.consumedYen, 2000);
    expect(stats.totalRotations, 41);
    expect(stats.rotationRate, closeTo(20.5, 1e-9));
  });

  test('大当り→復帰で rebase は回転に数えず、以降の決定は算入される', () async {
    final s = await service.start(machine: _machine, ballPrice: 4.0, startCounter: 0);
    await service.recordCount(s, counter: 20);
    await service.recordRebase(s, counter: 500);
    await service.recordCount(s, counter: 530);

    final stats = await service.stats(s, _machine);
    expect(stats.totalRotations, 50);
    expect(stats.consumedYen, 2000);
    expect(stats.bonusCount, 1);
  });

  test('1つ戻すは直前の count のみ削除、start / rebase は戻せない', () async {
    final s = await service.start(machine: _machine, ballPrice: 4.0, startCounter: 0);
    await service.recordCount(s, counter: 20);

    expect(await service.undoLastCount(s.id!), isTrue);
    var ev = await entryRepo.bySession(s.id!);
    expect(ev.length, 1); // start だけ残る

    // start は戻せない
    expect(await service.undoLastCount(s.id!), isFalse);

    // rebase も戻せない
    await service.recordRebase(s, counter: 300);
    expect(await service.undoLastCount(s.id!), isFalse);
    ev = await entryRepo.bySession(s.id!);
    expect(ev.last.type, EntryType.rebase);
  });

  test('close で closed になり回収額が入る(任意)', () async {
    final s = await service.start(machine: _machine, ballPrice: 4.0, startCounter: 0);
    await service.recordCount(s, counter: 20);
    final closed = await service.close(s, recovery: 3000);

    expect(closed.state, SessionState.closed);
    expect(closed.recovery, 3000);
    expect(closed.closedAt, isNotNull);
    expect(await sessionRepo.active(), isNull);

    final reloaded = await sessionRepo.byId(s.id!);
    expect(reloaded!.state, SessionState.closed);
    expect(reloaded.recovery, 3000);
  });

  test('close は回収額なし(スキップ)でも closed にできる', () async {
    final s = await service.start(machine: _machine, ballPrice: 4.0, startCounter: 0);
    await service.recordCount(s, counter: 20);
    final closed = await service.close(s);
    expect(closed.state, SessionState.closed);
    expect(closed.recovery, isNull);
  });

  test('discard はセッションとイベントを物理削除する', () async {
    final s = await service.start(machine: _machine, ballPrice: 4.0, startCounter: 0);
    await service.recordCount(s, counter: 20);

    await service.discard(s.id!);
    expect(await sessionRepo.byId(s.id!), isNull);
    expect(await entryRepo.bySession(s.id!), isEmpty);
    expect(await sessionRepo.active(), isNull);
  });

  test('recentMachineIds は最近使った順', () async {
    const eva = Machine(id: 2, name: 'エヴァ', border4: 16.2);
    await service.start(machine: _machine, ballPrice: 4.0, startCounter: 0);
    t = t.add(const Duration(minutes: 10));
    await service.start(machine: eva, ballPrice: 4.0, startCounter: 0);

    final recent = await sessionRepo.recentMachineIds();
    expect(recent.first, 2); // 直近が先頭
    expect(recent.contains(1), isTrue);
  });
}
