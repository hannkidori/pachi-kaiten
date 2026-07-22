import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pachi_kaiten/logic/rotation_calc.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/entry.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/models/session.dart';
import 'package:pachi_kaiten/models/store.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/store_repository.dart';
import 'package:pachi_kaiten/ui/measurement/end_sheets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

const _a = Machine(id: 'a', name: 'P大海物語5', probability: 319.6, border40: 16.5);
const _b = Machine(id: 'b', name: 'Pエヴァ15', probability: 319.9, border40: 17.0);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('終了 / 台移動フロー(サービス層)', () {
    late Database db;
    late SessionService service;
    late SessionRepository sessionRepo;
    late EntryRepository entryRepo;
    late StoreRepository storeRepo;

    setUp(() async {
      db = await openTestDb();
      sessionRepo = SessionRepository(db);
      entryRepo = EntryRepository(db);
      storeRepo = StoreRepository(db);
      service = SessionService(sessions: sessionRepo, entries: entryRepo);
    });
    tearDown(() async => db.close());

    test('終了: close で回収額が入りサマリー材料が揃う', () async {
      final store = await storeRepo
          .insert(const Store(name: '店', exchangeRate: 3.57, ballPrice: 4.0));
      final s1 = await service.start(store: store, machine: _a, startCounter: 0);
      await service.recordCount(s1, counter: 20, mode: EntryMode.cash);
      await service.recordCount(s1, counter: 40, mode: EntryMode.cash);

      final closed = await service.close(s1, recovery: 5000);
      final stats = await service.stats(closed, _a);
      final summary =
          SessionSummary(session: closed, machine: _a, stats: stats);

      expect(summary.invest, 2000);
      expect(summary.recovery, 5000);
      expect(summary.profit, 3000); // 実収支
      expect(summary.stats.totalRotations, 40);
      expect(summary.ev, isNotNull); // 期待値表示可能
    });

    test('台移動: 旧セッション closed と新セッション start が途切れなく繋がる', () async {
      final store = await storeRepo
          .insert(const Store(name: '店', exchangeRate: 3.57, ballPrice: 4.0));
      final s1 = await service.start(store: store, machine: _a, startCounter: 100);
      await service.recordCount(s1, counter: 118, mode: EntryMode.cash);

      // 回収額を入れて旧セッションを記録(台移動の回収ステップ相当)。
      final closed = await service.close(s1, recovery: 0); // ¥0 ワンタップ相当
      // 同じ店舗で新機種のセッションを開始。
      final s2 = await service.start(
          store: store, machine: _b, startCounter: 0, addUnit: s1.addUnit);

      // 旧: closed かつ回収0 で確定
      expect(closed.state, SessionState.closed);
      expect(closed.recovery, 0);
      // 新: これが唯一の active
      final active = await sessionRepo.active();
      expect(active!.id, s2.id);
      expect(active.machineId, 'b');
      // 旧は履歴に残る
      final history = await sessionRepo.allClosed();
      expect(history.map((s) => s.id), contains(s1.id));
      // 新セッションには start イベントがある(打ち始め0)
      final ev = await entryRepo.bySession(s2.id!);
      expect(ev.single.type, EntryType.start);
      expect(ev.single.counter, 0);
    });
  });

  group('サマリーシート描画', () {
    testWidgets('主要な値が表示される', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = Session(
        id: 1,
        date: '2026-07-22',
        storeId: 1,
        machineId: 'a',
        exchangeRate: 3.57,
        ballPrice: 4.0,
        state: SessionState.closed,
        recovery: 5000,
        startedAt: '2026-07-22T10:00:00',
      );
      const stats = RotationStats(
        totalRotations: 40,
        cashRotations: 40,
        cashInvest: 2000,
        measuredRotations: 40,
        measuredInvest: 2000,
        rotationRate: 20.0,
        effectiveBorder: 16.5,
        borderDiff: 3.5,
        expectedValue: 848.0,
        segments: [],
        bonusCount: 0,
      );
      final sum =
          SessionSummary(session: session, machine: _a, stats: stats);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showSummarySheet(ctx, sum),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('セッションサマリー'), findsOneWidget);
      expect(find.text('実収支'), findsOneWidget);
      expect(find.text('期待値'), findsOneWidget);
      expect(find.text('閉じる'), findsOneWidget);
    });
  });
}
