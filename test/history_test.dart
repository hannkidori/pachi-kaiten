import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/history_aggregation.dart';
import 'package:pachi_kaiten/logic/history_service.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/entry.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/models/store.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/machine_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/store_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

const _a = Machine(id: 'a', name: 'P大海物語5', probability: 319.6, border40: 16.5);
const _b = Machine(id: 'b', name: 'Pエヴァ15', probability: 319.9, border40: 17.0);

void main() {
  late Database db;
  late SessionRepository sessionRepo;
  late EntryRepository entryRepo;
  late StoreRepository storeRepo;
  late MachineRepository machineRepo;
  late HistoryService history;

  DateTime clockNow = DateTime(2026, 7, 22, 10);
  late SessionService service;

  setUp(() async {
    db = await openTestDb();
    sessionRepo = SessionRepository(db);
    entryRepo = EntryRepository(db);
    storeRepo = StoreRepository(db);
    machineRepo = MachineRepository(db);
    await machineRepo.upsertAll([_a, _b]);
    service = SessionService(
        sessions: sessionRepo, entries: entryRepo, clock: () => clockNow);
    history = HistoryService(
        sessions: sessionRepo, entries: entryRepo, machines: machineRepo);
  });
  tearDown(() async => db.close());

  Future<void> playSession({
    required Store store,
    required Machine machine,
    required DateTime when,
    required int spins,
    required int invests, // 1000円 の投資回数
    required int recovery,
  }) async {
    clockNow = when;
    final s = await service.start(store: store, machine: machine, startCounter: 0);
    var counter = 0;
    for (var i = 0; i < invests; i++) {
      counter += (spins / invests).round();
      await service.recordCount(s, counter: counter, mode: EntryMode.cash);
    }
    await service.close(s, recovery: recovery);
  }

  test('months は記録のある月を新しい順に返す', () async {
    final store = await storeRepo
        .insert(const Store(name: '店', exchangeRate: 3.57, ballPrice: 4.0));
    await playSession(
        store: store, machine: _a, when: DateTime(2026, 7, 22, 10),
        spins: 40, invests: 2, recovery: 5000);
    await playSession(
        store: store, machine: _a, when: DateTime(2026, 6, 15, 10),
        spins: 40, invests: 2, recovery: 1000);

    expect(await history.months(), ['2026-07', '2026-06']);
  });

  test('月のロードで日別に集計され、機種名も解決される', () async {
    final store = await storeRepo
        .insert(const Store(name: '店', exchangeRate: 3.57, ballPrice: 4.0));
    // 7/22 に 2 台、7/20 に 1 台。
    await playSession(
        store: store, machine: _a, when: DateTime(2026, 7, 22, 10),
        spins: 40, invests: 2, recovery: 5000); // +3000
    await playSession(
        store: store, machine: _b, when: DateTime(2026, 7, 22, 14),
        spins: 30, invests: 3, recovery: 1000); // -2000
    await playSession(
        store: store, machine: _a, when: DateTime(2026, 7, 20, 10),
        spins: 20, invests: 1, recovery: 0); // -1000

    final data = await history.load('2026-07');
    expect(data.aggregates.length, 3);
    expect(data.machineNames['a'], 'P大海物語5');
    expect(data.machineNames['b'], 'Pエヴァ15');

    final days = groupByDay(data.aggregates);
    expect(days.map((d) => d.date), ['2026-07-22', '2026-07-20']);

    final d22 = days.first;
    expect(d22.sessionCount, 2);
    expect(d22.totalInvest, 2000 + 3000);
    expect(d22.totalRecovery, 5000 + 1000);
    expect(d22.dayProfit, (5000 + 1000) - (2000 + 3000)); // 1000

    final d20 = days[1];
    expect(d20.dayProfit, -1000);
  });

  test('機種別集計は回収率(回収/投資%)を主指標にする', () async {
    final store = await storeRepo
        .insert(const Store(name: '店', exchangeRate: 3.57, ballPrice: 4.0));
    await playSession(
        store: store, machine: _a, when: DateTime(2026, 7, 22, 10),
        spins: 40, invests: 2, recovery: 3000); // 投資2000 回収3000
    await playSession(
        store: store, machine: _a, when: DateTime(2026, 7, 20, 10),
        spins: 40, invests: 2, recovery: 1000); // 投資2000 回収1000

    final data = await history.loadAll();
    final byMachine = groupByMachine(data.aggregates);
    final umi = byMachine.firstWhere((m) => m.machineId == 'a');
    expect(umi.totalInvest, 4000);
    expect(umi.totalRecovery, 4000);
    expect(umi.recoveryRate, closeTo(100.0, 1e-9));
  });
}
