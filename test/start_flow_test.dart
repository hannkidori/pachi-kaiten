import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/rotation_calc.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/entry.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/trace_repository.dart';
import 'package:pachi_kaiten/ui/start/start_screen.dart';
import 'package:pachi_kaiten/util/format.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

Machine _m(int id, String name) => Machine(id: id, name: name, border4: 16.5);

void main() {
  group('orderMachines', () {
    final all = [
      _m(1, 'P大海物語5'),
      _m(2, 'Pエヴァ15'),
      _m(3, 'P北斗の拳'),
    ];

    test('クエリ空: 最近使った機種が先頭、残りは名前順', () {
      final r = orderMachines(all: all, recentIds: [3], query: '');
      expect(r.first.id, 3);
      // 残りは名前順(コードユニット比較で 'Pエヴァ' < 'P大海')
      expect(r.sublist(1).map((m) => m.id), [2, 1]);
    });

    test('クエリあり: 名前部分一致でフィルタ', () {
      final r = orderMachines(all: all, recentIds: [], query: 'エヴァ');
      expect(r.map((m) => m.id), [2]);
    });

    test('存在しない recentId は無視される', () {
      final r = orderMachines(all: all, recentIds: [99], query: '');
      expect(r.length, 3);
    });
  });

  group('SessionService / SessionRepository', () {
    late Database db;
    late SessionService service;
    late SessionRepository sessionRepo;
    late EntryRepository entryRepo;

    const machine = Machine(id: 1, name: 'P大海物語5', border4: 16.5);

    setUp(() async {
      db = await openTestDb();
      sessionRepo = SessionRepository(db);
      entryRepo = EntryRepository(db);
      service = SessionService(
        sessions: sessionRepo,
        entries: entryRepo,
        traces: TraceRepository(db),
      );
    });
    tearDown(() async => db.close());

    test('discard はセッションとイベントを物理削除する', () async {
      final session =
          await service.start(machine: machine, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(session, counter: 20);

      await service.discard(session.id!);

      expect(await sessionRepo.byId(session.id!), isNull);
      expect(await entryRepo.bySession(session.id!), isEmpty);
      expect(await sessionRepo.active(), isNull);
    });

    test('計測開始→即クラッシュ→再起動で 0k・0回転の active が復帰する', () async {
      // 計測開始(session + start イベントを同期書き込み)。この直後に
      // アプリが殺されても確定済みデータは残っている。
      final started = await service.start(
          machine: machine, ballPrice: 4.0, startCounter: 26143);

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

      // 復帰カードに出る値: 計測 0円分 / 0回転
      final stats = computeStats(
        entries: entries,
        border: machine.borderFor(active.ballPrice) ?? 0,
      );
      expect(stats.consumedYen, 0);
      expect(stats.totalRotations, 0);
      expect(fmtYen(stats.consumedYen), '0円');
    });
  });
}
