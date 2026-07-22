import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/entry.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/models/session.dart';
import 'package:pachi_kaiten/models/store.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/machine_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/store_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

const _machine = Machine(
  id: 'umi5sp',
  name: 'P大海物語5スペシャル',
  probability: 319.6,
  border40: 16.5,
  border357: 18.0,
);

void main() {
  late Database db;
  late SessionService service;
  late SessionRepository sessionRepo;
  late EntryRepository entryRepo;
  late StoreRepository storeRepo;
  late MachineRepository machineRepo;

  // 時刻を固定して created_at / date を決定的にする。
  var t = DateTime(2026, 7, 22, 10, 0, 0);
  DateTime clock() => t;

  setUp(() async {
    db = await openTestDb();
    sessionRepo = SessionRepository(db);
    entryRepo = EntryRepository(db);
    storeRepo = StoreRepository(db);
    machineRepo = MachineRepository(db);
    service = SessionService(
      sessions: sessionRepo,
      entries: entryRepo,
      clock: clock,
    );
    t = DateTime(2026, 7, 22, 10, 0, 0);
    await machineRepo.upsertAll([_machine]);
  });

  tearDown(() async => db.close());

  Future<Store> seedStore({double rate = 4.0, double ball = 4.0}) {
    return storeRepo.insert(
      Store(name: 'テスト店', exchangeRate: rate, ballPrice: ball),
    );
  }

  test('start でセッションと start イベントが即時に書かれる', () async {
    final store = await seedStore();
    final s = await service.start(
      store: store,
      machine: _machine,
      startCounter: 100,
    );
    expect(s.id, isNotNull);
    expect(s.state, SessionState.active);
    expect(s.exchangeRate, 4.0);
    expect(s.date, '2026-07-22');

    final ev = await entryRepo.bySession(s.id!);
    expect(ev.length, 1);
    expect(ev.first.type, EntryType.start);
    expect(ev.first.counter, 100);

    // 復帰カード用: active が取得できる
    final active = await sessionRepo.active();
    expect(active!.id, s.id);
  });

  test('決定タップは即時書き込み、cash は投資自動加算', () async {
    final store = await seedStore();
    final s = await service.start(
      store: store,
      machine: _machine,
      startCounter: 0,
    );
    await service.recordCount(s, counter: 20, mode: EntryMode.cash);
    await service.recordCount(s, counter: 41, mode: EntryMode.cash);

    final stats = await service.stats(s, _machine);
    expect(stats.cashInvest, 2000);
    expect(stats.cashRotations, 41);
    expect(stats.rotationRate, closeTo(20.5, 1e-9));
  });

  test('大当り→復帰でモードが ball に切り替わり、rebase は回転に数えない', () async {
    final store = await seedStore();
    final s = await service.start(
      store: store,
      machine: _machine,
      startCounter: 0,
    );
    await service.recordCount(s, counter: 20, mode: EntryMode.cash);
    await service.recordRebase(s, counter: 500);

    expect(await service.currentMode(s.id!), EntryMode.ball);

    await service.recordCount(s, counter: 530, mode: EntryMode.ball);
    final stats = await service.stats(s, _machine);
    expect(stats.totalRotations, 50);
    expect(stats.cashRotations, 20);
    expect(stats.cashInvest, 1000);
    expect(stats.bonusCount, 1);
  });

  test('1つ戻すは直前の count のみ削除、start / rebase は戻せない', () async {
    final store = await seedStore();
    final s = await service.start(
      store: store,
      machine: _machine,
      startCounter: 0,
    );
    await service.recordCount(s, counter: 20, mode: EntryMode.cash);

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

  test('close で closed になり回収額が入る', () async {
    final store = await seedStore();
    final s = await service.start(
      store: store,
      machine: _machine,
      startCounter: 0,
    );
    await service.recordCount(s, counter: 20, mode: EntryMode.cash);
    final closed = await service.close(s, recovery: 3000);

    expect(closed.state, SessionState.closed);
    expect(closed.recovery, 3000);
    expect(closed.closedAt, isNotNull);
    expect(await sessionRepo.active(), isNull);

    final reloaded = await sessionRepo.byId(s.id!);
    expect(reloaded!.state, SessionState.closed);
    expect(reloaded.recovery, 3000);
  });

  test('店舗を後から編集しても過去セッションの換金率は変わらない', () async {
    var store = await seedStore(rate: 4.0);
    final s = await service.start(
      store: store,
      machine: _machine,
      startCounter: 0,
    );
    // 店舗の換金率を変更
    await storeRepo.update(store.copyWith(exchangeRate: 3.3));

    final reloaded = await sessionRepo.byId(s.id!);
    expect(reloaded!.exchangeRate, 4.0); // コピーされた値のまま
  });

  test('recentMachineIds は最近使った順', () async {
    final store = await seedStore();
    await machineRepo.upsertAll([
      _machine,
      const Machine(
        id: 'eva',
        name: 'エヴァ',
        probability: 319.7,
        border40: 16.2,
      ),
    ]);
    await service.start(store: store, machine: _machine, startCounter: 0);
    t = t.add(const Duration(minutes: 10));
    await service.start(
      store: store,
      machine: const Machine(
        id: 'eva',
        name: 'エヴァ',
        probability: 319.7,
        border40: 16.2,
      ),
      startCounter: 0,
    );

    final recent = await sessionRepo.recentMachineIds();
    expect(recent.first, 'eva'); // 直近が先頭
    expect(recent.contains('umi5sp'), isTrue);
  });
}
