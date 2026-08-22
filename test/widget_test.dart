import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:pachi_kaiten/ui/measurement/end_sheets.dart';
import 'package:pachi_kaiten/ui/measurement/measurement_screen.dart';
import 'package:pachi_kaiten/ui/measurement/rotation_chart.dart';
import 'package:pachi_kaiten/ui/settings/settings_screen.dart';
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
      expect(entries.last.yen, 1000); // 1 単位消化
      expect(c.stats.rotationRate, closeTo(25.0, 1e-9)); // 25回転 / 1k
      expect(c.typed, isEmpty);
    });

    test('負差分で異常確認シート(negative)が立つ', () async {
      final c = await startController();
      // 打ち始め 0 → 20 回転(正常)を確定
      type(c, '20');
      await c.commit();
      expect(c.confirm, isNull);

      type(c, '10'); // 差分 -10
      await c.commit();
      expect(c.confirm, isNotNull);
      expect(c.confirm!.kind, AnomalyKind.negative);
      // シート表示中はまだ書き込まれていない
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.length, 2); // start + 20 のみ
    });

    test('決定の二度押しでも count は1件だけ(消化額の二重計上を防ぐ)', () async {
      // 1 回目の DB 書き込み中に 2 回目が走ると、同じ入力がもう 1 件書かれ、
      // 回転は増えないのに消化額だけ倍 = 回転率が半減していた。
      final c = await startController();
      type(c, '20');
      final first = c.commit();
      final second = c.commit(); // await せずに二度押し
      await Future.wait([first, second]);

      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.where((e) => e.type == EntryType.count).length, 1);
      expect(c.stats.consumedYen, 1000); // 2000 にならない
      expect(c.stats.rotationRate, closeTo(20.0, 1e-9));
    });

    test('大当り復帰値に 0 を入力できる(カウンタが 0 に戻る台)', () async {
      final c = await startController();
      type(c, '20');
      await c.commit();

      c.startHit();
      type(c, '0');
      await c.commit();
      expect(c.isHit, isFalse); // 弾かれずに確定する
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.type, EntryType.rebase);
      expect(entries.last.counter, 0);
    });

    test('最初の入力も検証される(打ち始めの打ち間違いを素通ししない)', () async {
      final c = await startController(); // 打ち始め 0
      type(c, '500'); // 1000円で 500 回転はあり得ない
      await c.commit();
      expect(c.confirm, isNotNull);
      expect(c.confirm!.kind, AnomalyKind.tooHigh);
      // 確認前は書き込まれない(start のみ)
      expect((await entryRepo.bySession(c.session.id!)).length, 1);
    });

    test('確定する(force)でそのまま追記される', () async {
      final c = await startController();
      type(c, '20');
      await c.commit();
      type(c, '70'); // 差分 +50 は 1000円で上限超
      await c.commit();
      expect(c.confirm!.kind, AnomalyKind.tooHigh);

      await c.confirmForce();
      expect(c.confirm, isNull);
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.counter, 70);
    });

    test('大当り→復帰で rebase が書かれ、通常状態に戻る', () async {
      final c = await startController();
      type(c, '100');
      await c.commit();

      c.startHit();
      expect(c.isHit, isTrue);
      type(c, '500');
      await c.commit();

      expect(c.isHit, isFalse);
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.type, EntryType.rebase);
      expect(entries.last.counter, 500);
      expect(c.stats.bonusCount, 1);
    });

    test('大当り→復帰→決定→再度大当り でも rebase が書き込まれる', () async {
      // 復帰後(rebase 起点)からも次の大当り→rebase が成立する(検出漏れ防止)。
      final c = await startController();
      type(c, '100');
      await c.commit(); // count
      c.startHit();
      type(c, '300');
      await c.commit(); // rebase
      type(c, '330');
      await c.commit(); // count(復帰後の最初の決定も算入)

      c.startHit();
      expect(c.isHit, isTrue);
      type(c, '800');
      await c.commit();

      expect(c.isHit, isFalse);
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.type, EntryType.rebase);
      expect(entries.last.counter, 800);
      expect(c.stats.bonusCount, 2); // 大当り 2 回
    });

    test('フィードバック: コミット種別ごとに lastFeedback が立つ', () async {
      final c = await startController();

      type(c, '20');
      await c.commit(); // count
      expect(c.lastFeedback, CommitFeedback.commit);
      final t1 = c.feedbackTick;
      expect(t1, greaterThan(0));

      c.startHit();
      type(c, '300');
      await c.commit(); // rebase
      expect(c.lastFeedback, CommitFeedback.rebase);
      expect(c.feedbackTick, greaterThan(t1));

      type(c, '330');
      await c.commit(); // count
      expect(c.lastFeedback, CommitFeedback.commit);
    });

    test('復帰後の決定でヘッダー総回転(stats.totalRotations)が更新される', () async {
      final c = await startController();
      type(c, '20');
      await c.commit(); // total 20
      c.startHit();
      type(c, '300');
      await c.commit(); // rebase(total は増えない)
      final before = c.stats.totalRotations;
      expect(before, 20);

      type(c, '330');
      await c.commit(); // +30
      // 表示元の stats が即座に更新されている(古い値が残らない)。
      expect(c.stats.totalRotations, before + 30);
    });

    test('加算単位トグルは +1000 ↔ +500', () async {
      final c = await startController();
      expect(c.unit, 1000);
      expect(c.unitChipLabel, '+1000');
      expect(c.commitSubLabel, '+1000円分');

      c.cycleUnit();
      expect(c.unit, 500);
      expect(c.unitChipLabel, '+500');
      expect(c.commitSubLabel, '+500円分');

      // 500円単位の決定は yen=500 で記録される。
      type(c, '10');
      await c.commit();
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.last.yen, 500);
      c.cycleUnit();
      expect(c.unit, 1000);
    });

    test('1つ戻すは直前の count のみ削除する', () async {
      final c = await startController();
      type(c, '20');
      await c.commit();
      type(c, '40');
      await c.commit();
      expect((await entryRepo.bySession(c.session.id!)).length, 3);

      await c.undo();
      final entries = await entryRepo.bySession(c.session.id!);
      expect(entries.length, 2);
      expect(entries.last.counter, 20);
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
    expect(find.text('+1000'), findsOneWidget); // 加算単位チップ
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

    test('未完成の棒はボーダー判定色を適用しない(半透明ニュートラル+減光ラベル)', () {
      const border = 16.5;
      const partial = ChartBar(rotations: 10, complete: false);
      final barC = barColorFor(partial, hasBorder: true, border: border);
      expect(barC, chartBarPartial);
      expect(barC, isNot(chartBarAbove));
      expect(barC, isNot(chartBarBelow));
      final labelC = labelColorFor(partial, hasBorder: true, border: border);
      expect(labelC, chartLabelPartial);
      expect(labelC, isNot(chartLabelAbove));
      expect(labelC, isNot(chartLabelBelow));
    });

    test('完成棒は最新/それ以外を問わずボーダー判定色(超過=ティール / 未満=赤)', () {
      const border = 16.5;
      const above = ChartBar(rotations: 20, complete: true);
      const below = ChartBar(rotations: 15, complete: true);
      // 最新かどうかで色は変えない(シアンのハイライトは廃止)。
      expect(barColorFor(above, hasBorder: true, border: border), chartBarAbove);
      expect(barColorFor(below, hasBorder: true, border: border), chartBarBelow);
    });
  });

  // ---- チャート単体の崩壊安全性(ラベル+棒+破線の合計 <= 親制約) ----
  testWidgets('RotationChart は小さい高さ×scale1.3 でも溢れない', (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;

    // 実データのある stats を作る(区間 4 本)。
    final entries = <Entry>[
      const Entry(
          sessionId: 1, type: EntryType.start, counter: 0, createdAt: 't0'),
      for (var i = 0; i < 4; i++)
        Entry(
            sessionId: 1, type: EntryType.count, counter: (i + 1) * 18,
            yen: 1000, createdAt: 't${i + 1}'),
    ];
    final stats = computeStats(entries: entries, border: 16.5);

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
          sessionId: 1, type: EntryType.start, counter: 0, createdAt: 't0'),
      const Entry(
          sessionId: 1, type: EntryType.count, counter: 20,
          yen: 1000, createdAt: 't1'),
      const Entry(
          sessionId: 1, type: EntryType.rebase, counter: 500, createdAt: 't2'),
      const Entry(
          sessionId: 1, type: EntryType.count, counter: 530,
          yen: 1000, createdAt: 't3'),
    ];
    final stats = computeStats(entries: entries, border: 16.5);
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
        await service.recordCount(c.session, counter: counter);
      }
      await c.load();
    });

    // 667/568 は iOS 13 対応で残る小画面(iPhone 8 / SE 第1世代)。
    for (final h in <double>[844, 812, 780, 667, 568]) {
      for (final scale in <double>[1.0, 1.3]) {
        tester.view.physicalSize = Size(375, h);
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
    await tester.tap(find.text('★ 大当り'));
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

  testWidgets('大当り後にテンキー入力が反映される', (tester) async {
    late MeasurementController c;
    await tester.runAsync(() async {
      c = await startController();
      await service.recordCount(c.session, counter: 20);
      await c.load();
    });
    await expectHitInputReflects(tester, c);
  });

  testWidgets('復帰後(継続中)でも大当り入力が反映される', (tester) async {
    late MeasurementController c;
    await tester.runAsync(() async {
      c = await startController();
      await service.recordCount(c.session, counter: 20);
      await service.recordRebase(c.session, counter: 300);
      await service.recordCount(c.session, counter: 330);
      await c.load();
    });
    await expectHitInputReflects(tester, c);
  });

  // ---- リセットシートの選択肢表示(DB非依存なので通常の testWidgets) ----
  Future<void> openResetSheet(WidgetTester tester, bool isQuick) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showResetSheet(context,
                  machineName: 'P大海物語5', isQuick: isQuick),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('リセットシート: 機種計測中は3択(主役=機種名のままリセット)', (tester) async {
    await openResetSheet(tester, false);
    expect(find.text('P大海物語5のままリセット'), findsOneWidget); // 主役
    expect(find.text('機種を変えてリセット'), findsOneWidget); // 従
    expect(find.text('機種なしでリセット'), findsOneWidget); // 従(小)
    expect(find.text('ここまでの計測は履歴に残ります'), findsOneWidget);
  });

  testWidgets('リセットシート: クイック中は2択(「機種なしでリセット」を出さない)', (tester) async {
    await openResetSheet(tester, true);
    expect(find.text('カウントをリセット'), findsOneWidget); // 主役
    expect(find.text('機種を変えてリセット'), findsOneWidget); // 従
    expect(find.text('機種なしでリセット'), findsNothing); // 主役と同義のため非表示
  });

  // ---- 設定: 作者の他のアプリ(iOS のみ) ----
  group('設定の他アプリ紹介欄', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(services: services)));
      // 設定は initState で DB(ffi)を読む。スピナーが回っている間は settle しない
      // ので、runAsync で実時間を進めてから 1 フレーム描く。
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    testWidgets('iOS では 2 件が説明付きで並び、はみ出さない', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpSettings(tester);

        expect(find.text('作者の他のアプリ'), findsOneWidget);
        expect(find.text('ハナジャグ'), findsOneWidget);
        expect(find.text('コヤカン'), findsOneWidget);
        expect(find.text('ハナハナ・ジャグラー専用の設定推測とデータ記録'), findsOneWidget);
        expect(find.text('縦横対応の小役カウンター'), findsOneWidget);
        // 削除済みの旧文言が残っていないこと
        expect(find.textContaining('広告なし'), findsNothing);
        expect(tester.takeException(), isNull); // オーバーフローなし
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android では節ごと出さない(開けないリンクを見せない)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pumpSettings(tester);

        expect(find.text('作者の他のアプリ'), findsNothing);
        expect(find.text('ハナジャグ'), findsNothing);
        // 版数表示は残る(数字は feature_test の pubspec 一致テストで担保)
        expect(find.textContaining('パチ回転計 v'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
