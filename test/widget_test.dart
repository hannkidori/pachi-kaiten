import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pachi_kaiten/logic/anomaly.dart';
import 'package:pachi_kaiten/logic/rotation_calc.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/entry.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/trace_repository.dart';
import 'package:pachi_kaiten/services/app_services.dart';
import 'package:pachi_kaiten/state/measurement_controller.dart';
import 'package:pachi_kaiten/theme/app_theme.dart';
import 'package:pachi_kaiten/ui/measurement/measurement_screen.dart';
import 'package:pachi_kaiten/ui/measurement/rotation_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

const _machine = Machine(
  id: 1,
  name: 'P大海物語5スペシャル',
  border4: 16.5,
  border1: 66.0,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late Database db;
  late SessionService service;
  late EntryRepository entryRepo;
  late AppServices services;

  setUp(() async {
    db = await openTestDb();
    final sessionRepo = SessionRepository(db);
    entryRepo = EntryRepository(db);
    service = SessionService(
        sessions: sessionRepo, entries: entryRepo, traces: TraceRepository(db));
    services = buildTestServices(db);
  });

  tearDown(() async => db.close());

  Future<MeasurementController> startController() async {
    final session = await service.start(
        machine: _machine, ballPrice: 4.0, startCounter: 0);
    final c = MeasurementController(
        service: service, session: session, machine: _machine);
    await c.load();
    return c;
  }

  void type(MeasurementController c, String digits) {
    for (final d in digits.split('')) {
      c.tapKey(d);
    }
  }

  // ---- コントローラの挙動(実 async / ffi。UI から独立) ----
  group('MeasurementController', () {
    test('テンキー→決定で count が即時に書き込まれる', () async {
      final c = await startController();
      type(c, '25');
      await c.commit();

      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.length, 2); // start + count
      expect(entries.last.type, EntryType.count);
      expect(entries.last.counter, 25);
      expect(c.stats.rotationRate, closeTo(25.0, 1e-9)); // 25回転 / 1k
      expect(c.typed, isEmpty);
    });

    test('負差分で異常確認シート(negative)が立つ', () async {
      final c = await startController();
      // start 直後は判定スキップされるので、まず 100 を確定
      type(c, '100');
      await c.commit();
      expect(c.confirm, isNull);

      type(c, '90'); // 差分 -10
      await c.commit();
      expect(c.confirm, isNotNull);
      expect(c.confirm!.kind, AnomalyKind.negative);
      // シート表示中はまだ書き込まれていない
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.length, 2); // start + 100 のみ
    });

    test('確定する(force)でそのまま追記される', () async {
      final c = await startController();
      type(c, '100');
      await c.commit();
      type(c, '150'); // 差分 +50 は 1000円で上限超
      await c.commit();
      expect(c.confirm!.kind, AnomalyKind.tooHigh);

      await c.confirmForce();
      expect(c.confirm, isNull);
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.counter, 150);
    });

    test('大当り→復帰で rebase が書かれ ball モードになる', () async {
      final c = await startController();
      type(c, '100');
      await c.commit();

      c.startHit();
      expect(c.isHit, isTrue);
      type(c, '500');
      await c.commit();

      expect(c.isHit, isFalse);
      expect(c.isBall, isTrue);
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.type, EntryType.rebase);
      expect(entries.last.counter, 500);
      expect(c.stats.bonusCount, 1);
    });

    test('持ち玉モード中の 大当り→復帰→決定 でも rebase が書き込まれる', () async {
      // 持ち玉遊技中に次の当りを引く通常フロー。cash 起点だけでなく
      // ball 起点でも大当り→rebase が成立することを保証する(検出漏れ防止)。
      final c = await startController();
      type(c, '100');
      await c.commit(); // cash count
      c.startHit();
      type(c, '300');
      await c.commit(); // rebase → 持ち玉モード
      expect(c.isBall, isTrue);
      type(c, '330');
      await c.commit(); // ball count

      // ここで持ち玉モードのまま次の大当り。
      c.startHit();
      expect(c.isHit, isTrue);
      type(c, '800');
      await c.commit();

      expect(c.isHit, isFalse);
      expect(c.isBall, isTrue);
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.type, EntryType.rebase);
      expect(entries.last.counter, 800);
      expect(c.stats.bonusCount, 2); // 大当り 2 回
    });

    test('フィードバック: コミット種別ごとに lastFeedback と rebaseAnnounce が立つ', () async {
      final c = await startController();

      type(c, '20');
      await c.commit(); // cash
      expect(c.lastFeedback, CommitFeedback.cashCommit);
      final t1 = c.feedbackTick;
      expect(t1, greaterThan(0));

      c.startHit();
      type(c, '300');
      await c.commit(); // rebase
      expect(c.lastFeedback, CommitFeedback.rebase);
      expect(c.rebaseAnnounce, 300); // バナー告知値
      expect(c.feedbackTick, greaterThan(t1));

      type(c, '330');
      await c.commit(); // ball
      expect(c.lastFeedback, CommitFeedback.ballCommit);
    });

    test('持ち玉決定でヘッダー総回転(stats.totalRotations)が更新される', () async {
      final c = await startController();
      type(c, '20');
      await c.commit(); // cash: total 20
      c.startHit();
      type(c, '300');
      await c.commit(); // rebase → 持ち玉モード(total は増えない)
      final before = c.stats.totalRotations;
      expect(before, 20);

      type(c, '330');
      await c.commit(); // ball count: +30
      // 表示元の stats が即座に更新されている(古い値が残らない)。
      expect(c.stats.totalRotations, before + 30);
      expect(c.isBall, isTrue);
    });

    test('持ち玉単位は貸玉に連動(4円=250/500)し、決定で消費玉を記録', () async {
      final c = await startController(); // ballPrice 4.0
      type(c, '20');
      await c.commit(); // cash 20
      c.setMode(EntryMode.ball);
      expect(c.ballUnit, 250);
      expect(c.unitChipLabel, '250玉');
      expect(c.commitSubLabel, '250玉');
      expect(c.activeUnitYen, 1000); // 250玉 × 4円

      c.cycleUnit();
      expect(c.ballUnit, 500);
      expect(c.activeUnitYen, 2000);
      c.cycleUnit();
      expect(c.ballUnit, 250);

      type(c, '50'); // 差分 30
      await c.commit(); // ball
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.mode, EntryMode.ball);
      expect(entries.last.ballsAdded, 250);
      // 持ち玉も R に算入される。
      expect(c.stats.measuredRotations, 20 + 30);
      expect(c.stats.measuredInvest, 1000 + 250 * 4);
    });

    test('1円貸しは持ち玉単位 1000/2000', () async {
      final session = await service.start(
          machine: _machine, ballPrice: 1.0, startCounter: 0);
      final c = MeasurementController(
          service: service, session: session, machine: _machine);
      await c.load();
      c.setMode(EntryMode.ball);
      expect(c.ballUnit, 1000);
      expect(c.unitChipLabel, '1000玉');
      c.cycleUnit();
      expect(c.ballUnit, 2000);
    });

    test('1つ戻すは直前の count のみ削除する', () async {
      final c = await startController();
      type(c, '100');
      await c.commit();
      type(c, '120');
      await c.commit();
      expect((await entryRepo.bySession(c.session.id!)).length, 3);

      await c.undo();
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.length, 2);
      expect(entries.last.counter, 100);
    });
  });

  // ---- 描画スモークテスト ----
  // DB(ffi)は FakeAsync 外で回すため runAsync でセットアップする。
  testWidgets('計測画面が描画され、機種名と決定ボタンが出る', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late MeasurementController c;
    await tester.runAsync(() async {
      c = await startController();
    });

    await tester.pumpWidget(MaterialApp(
      home: MeasurementScreen(
          controller: c, services: services, keepAwake: false),
    ));
    await tester.pump();

    expect(find.text('P大海物語5スペシャル'), findsOneWidget);
    expect(find.text('決定'), findsOneWidget);
    expect(find.text('回転率'), findsOneWidget);
    expect(find.text('--.-'), findsOneWidget); // 未計測
  });

  // ---- グラフの色ルール ----
  group('グラフの色ルール(確定済みは判定色)', () {
    test('ボーダー以上はティール、未満は赤。シアン(accent)は使わない', () {
      const border = 16.5;
      expect(chartBarColor(20.0, border), chartBarAbove); // 以上=ティール
      expect(chartBarColor(16.5, border), chartBarAbove); // ちょうどは以上扱い
      expect(chartBarColor(15.0, border), chartBarBelow); // 未満=赤
      // 確定済みの棒がシアンのハイライトになることはない。
      expect(chartBarColor(20.0, border), isNot(AppColors.accent));
      expect(chartBarColor(15.0, border), isNot(AppColors.accent));
    });

    test('ラベル色も同じ判定に従う', () {
      const border = 16.5;
      expect(chartLabelColor(20.0, border), chartLabelAbove);
      expect(chartLabelColor(15.0, border), chartLabelBelow);
    });
  });

  // ---- チャート単体の崩壊安全性(ラベル+棒+破線の合計 <= 親制約) ----
  testWidgets('RotationChart は小さい高さ×scale1.3 でも溢れない', (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;

    // 実データのある stats を作る(現金区間 4 本)。
    final entries = <Entry>[
      const Entry(
          sessionId: 1, type: EntryType.start, counter: 0,
          mode: EntryMode.cash, createdAt: 't0'),
      for (var i = 0; i < 4; i++)
        Entry(
            sessionId: 1, type: EntryType.count, counter: (i + 1) * 18,
            mode: EntryMode.cash, investAdded: 1000, createdAt: 't${i + 1}'),
    ];
    final stats =
        computeStats(entries: entries, border: 16.5, ballPrice: 4.0);

    for (final h in <double>[4, 12, 20, 40, 60, 85]) {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: h,
              child: RotationChart(stats: stats),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'チャート高さ $h でオーバーフロー');
    }
  });

  // ---- 大当りマーカー ----
  testWidgets('RotationChart は大当り位置に ◆ マーカーを描く', (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;
    final entries = <Entry>[
      const Entry(
          sessionId: 1, type: EntryType.start, counter: 0,
          mode: EntryMode.cash, createdAt: 't0'),
      const Entry(
          sessionId: 1, type: EntryType.count, counter: 20,
          mode: EntryMode.cash, investAdded: 1000, createdAt: 't1'),
      const Entry(
          sessionId: 1, type: EntryType.rebase, counter: 500,
          mode: EntryMode.ball, createdAt: 't2'),
      const Entry(
          sessionId: 1, type: EntryType.count, counter: 530,
          mode: EntryMode.ball, createdAt: 't3'),
    ];
    final stats =
        computeStats(entries: entries, border: 16.5, ballPrice: 4.0);
    expect(stats.rebaseMarkers, [1]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
              width: 300, height: 70, child: RotationChart(stats: stats)),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('◆'), findsOneWidget);
  });

  // ---- 全画面: 複数の画面高さ × テキストスケールでオーバーフローしない ----
  testWidgets('計測画面が 780/812/844 × scale 1.0/1.3 で溢れない', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late MeasurementController c;
    await tester.runAsync(() async {
      c = await startController();
      var counter = 0;
      for (final diff in [18, 15, 20, 14, 22, 16, 19, 13]) {
        counter += diff;
        await service.recordCount(c.session,
            counter: counter, mode: EntryMode.cash);
      }
      await c.load();
    });

    for (final h in <double>[844, 812, 780]) {
      for (final scale in <double>[1.0, 1.3]) {
        tester.view.physicalSize = Size(390, h);
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            home: MeasurementScreen(
                controller: c, services: services, keepAwake: false),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: '画面高さ $h scale $scale でオーバーフロー');
        // テンキーと決定ボタンは常に画面内に収まっていること。
        expect(find.text('決定'), findsOneWidget);
      }
    }
  });

  // ---- 大当り後にテンキー入力が表示へ反映される ----
  Future<void> expectHitInputReflects(WidgetTester tester,
      MeasurementController c) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: MeasurementScreen(
          controller: c, services: services, keepAwake: false),
    ));
    await tester.pump();

    // 大当り → 復帰値入力状態
    await tester.tap(find.text('大当り'));
    await tester.pump();
    expect(c.isHit, isTrue);
    expect(find.textContaining('復帰値入力中'), findsOneWidget);

    // テンキーで 500 を入力 → カウンタ表示に反映される
    await tester.tap(find.text('5'));
    await tester.tap(find.text('0'));
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(c.typed, '500');
    expect(find.text('500'), findsOneWidget); // 画面に表示されている
  }

  testWidgets('現金モード: 大当り後にテンキー入力が反映される', (tester) async {
    late MeasurementController c;
    await tester.runAsync(() async {
      c = await startController();
      await service.recordCount(c.session, counter: 20, mode: EntryMode.cash);
      await c.load();
    });
    await expectHitInputReflects(tester, c);
  });

  testWidgets('持ち玉モード: 大当り後にテンキー入力が反映される', (tester) async {
    late MeasurementController c;
    await tester.runAsync(() async {
      c = await startController();
      await service.recordCount(c.session, counter: 20, mode: EntryMode.cash);
      await service.recordRebase(c.session, counter: 300); // → 持ち玉モード
      await service.recordCount(c.session, counter: 330, mode: EntryMode.ball);
      await c.load();
    });
    expect(c.isBall, isTrue); // 持ち玉モードから開始
    await expectHitInputReflects(tester, c);
  });

  testWidgets('持ち玉モードの表示: バナー「持ち玉計測中」/単位「250玉」/決定「250玉」',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late MeasurementController c;
    await tester.runAsync(() async {
      c = await startController();
      await service.recordCount(c.session, counter: 20, mode: EntryMode.cash);
      await service.recordRebase(c.session, counter: 300); // → 持ち玉モード
      await c.load();
    });
    expect(c.isBall, isTrue);

    await tester.pumpWidget(MaterialApp(
      home: MeasurementScreen(
          controller: c, services: services, keepAwake: false),
    ));
    await tester.pump();

    expect(find.text('持ち玉計測中'), findsOneWidget);
    expect(find.textContaining('計測から除外'), findsNothing); // 除外バナー廃止
    // 単位チップと決定ボタンのサブ表示に「250玉」。
    expect(find.text('250玉'), findsNWidgets(2));
  });
}
