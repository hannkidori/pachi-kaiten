import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/rotation_calc.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/entry.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/models/store.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/store_repository.dart';
import 'package:pachi_kaiten/ui/start/start_screen.dart';
import 'package:pachi_kaiten/util/format.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

Machine _m(String id, String name) =>
    Machine(id: id, name: name, probability: 319.6, border40: 16.5);

void main() {
  group('orderMachines', () {
    final all = [
      _m('umi', 'P大海物語5'),
      _m('eva', 'Pエヴァ15'),
      _m('hokuto', 'P北斗の拳'),
    ];

    test('クエリ空: 最近使った機種が先頭、残りは名前順', () {
      final r = orderMachines(all: all, recentIds: ['hokuto'], query: '');
      expect(r.first.id, 'hokuto');
      // 残りは名前順(コードユニット比較で 'Pエヴァ' < 'P大海')
      expect(r.sublist(1).map((m) => m.id), ['eva', 'umi']);
    });

    test('クエリあり: 名前部分一致でフィルタ', () {
      final r = orderMachines(all: all, recentIds: [], query: 'エヴァ');
      expect(r.map((m) => m.id), ['eva']);
    });

    test('存在しない recentId は無視される', () {
      final r = orderMachines(all: all, recentIds: ['ghost'], query: '');
      expect(r.length, 3);
    });
  });

  group('SessionService / SessionRepository', () {
    late Database db;
    late SessionService service;
    late SessionRepository sessionRepo;
    late EntryRepository entryRepo;
    late StoreRepository storeRepo;

    const machine = Machine(
        id: 'umi', name: 'P大海物語5', probability: 319.6, border40: 16.5);

    setUp(() async {
      db = await openTestDb();
      sessionRepo = SessionRepository(db);
      entryRepo = EntryRepository(db);
      storeRepo = StoreRepository(db);
      service = SessionService(sessions: sessionRepo, entries: entryRepo);
    });
    tearDown(() async => db.close());

    test('discard はセッションとイベントを物理削除する', () async {
      final store = await storeRepo
          .insert(const Store(name: '店', exchangeRate: 3.57, ballPrice: 4.0));
      final session =
          await service.start(store: store, machine: machine, startCounter: 0);
      await service.recordCount(session, counter: 20, mode: EntryMode.cash);

      await service.discard(session.id!);

      expect(await sessionRepo.byId(session.id!), isNull);
      expect(await entryRepo.bySession(session.id!), isEmpty);
      expect(await sessionRepo.active(), isNull);
    });

    test('計測開始→即クラッシュ→再起動で 0k・0回転の active が復帰する', () async {
      final store = await storeRepo
          .insert(const Store(name: '店', exchangeRate: 3.57, ballPrice: 4.0));
      // 計測開始(session + start イベントを同期書き込み)。この直後に
      // アプリが殺されても確定済みデータは残っている。
      final started =
          await service.start(store: store, machine: machine, startCounter: 26143);

      // 「再起動」= 新しいリポジトリ群で同じ DB を読み直す。
      final freshSessions = SessionRepository(db);
      final freshEntries = EntryRepository(db);

      final active = await freshSessions.active();
      expect(active, isNotNull);
      expect(active!.id, started.id);

      final entries = await freshEntries.bySession(active.id!);
      expect(entries.length, 1); // start のみ
      expect(entries.single.type, EntryType.start);
      expect(entries.single.counter, 26143);

      // 復帰カードに出る値: 投資 0.0k / 0回転
      final stats = computeStats(
        entries: entries,
        catalogBorder: machine.borderForRate(active.exchangeRate),
        ballPrice: active.ballPrice,
      );
      expect(stats.cashInvest, 0);
      expect(stats.totalRotations, 0);
      expect(fmtK(stats.cashInvest), '0.0k');
    });

    test('recentStoreId は直近セッションの店舗を返す', () async {
      final a = await storeRepo
          .insert(const Store(name: 'A', exchangeRate: 4.0, ballPrice: 4.0));
      final b = await storeRepo
          .insert(const Store(name: 'B', exchangeRate: 3.3, ballPrice: 4.0));
      await service.start(store: a, machine: machine, startCounter: 0);
      final s2 =
          await service.start(store: b, machine: machine, startCounter: 0);

      expect(await sessionRepo.recentStoreId(), s2.storeId);
      expect(s2.storeId, b.id);
    });

    test('店舗 CRUD 往復', () async {
      final saved = await storeRepo.insert(
          const Store(name: 'マイホール', exchangeRate: 3.57, ballPrice: 1.0));
      expect(saved.id, isNotNull);

      await storeRepo.update(saved.copyWith(name: '新名称', exchangeRate: 4.0));
      final reloaded = await storeRepo.byId(saved.id!);
      expect(reloaded!.name, '新名称');
      expect(reloaded.exchangeRate, 4.0);
      expect(reloaded.ballPrice, 1.0);

      await storeRepo.delete(saved.id!);
      expect(await storeRepo.byId(saved.id!), isNull);
    });
  });
}
