import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/backup_service.dart';
import 'package:pachi_kaiten/logic/session_service.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/machine_repository.dart';
import 'package:pachi_kaiten/repositories/session_repository.dart';
import 'package:pachi_kaiten/repositories/settings_repository.dart';
import 'package:pachi_kaiten/repositories/trace_repository.dart';
import 'package:pachi_kaiten/ui/start/machine_sheets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

void main() {
  group('オンボーディング表示フラグ', () {
    late Database db;
    late SettingsRepository settings;

    setUp(() async {
      db = await openTestDb();
      settings = SettingsRepository(db);
    });
    tearDown(() async => db.close());

    test('初期は未表示。set で表示済みになる', () async {
      // 初期(フラグ未設定)は未表示。
      expect(await settings.onbCounterDone(), isFalse);

      await settings.setOnbCounterDone();
      expect(await settings.onbCounterDone(), isTrue);
    });
  });
  group('機種スロット — 育つマスタ(自動換算なし)', () {
    late Database db;
    late MachineRepository repo;

    setUp(() async {
      db = await openTestDb();
      repo = MachineRepository(db);
    });
    tearDown(() async => db.close());

    test('borderFor は貸玉に応じたスロットを返す', () {
      const m = Machine(id: 1, name: 'X', border4: 16.5, border1: 66.0);
      expect(m.borderFor(4.0), 16.5);
      expect(m.borderFor(1.0), 66.0);
    });

    test('未入力スロットは null(自動換算しない)', () {
      const m = Machine(id: 1, name: 'X', border4: 16.5);
      expect(m.borderFor(4.0), 16.5);
      expect(m.borderFor(1.0), isNull); // ×4 などしない
    });

    test('applyBorder は該当スロットのみ書き込み、他スロットは不変', () {
      const m = Machine(id: 1, name: 'X', border4: 16.5);
      final m1 = applyBorder(m, 1.0, 70.0, 'stamp');
      expect(m1.border4, 16.5); // 4円は不変
      expect(m1.border1, 70.0); // 1円だけ入る
    });

    test('登録→再選択→スロット上書きが往復する', () async {
      // 4円ボーダーだけで登録。
      final saved = await repo.insert(
          applyBorder(const Machine(name: 'ハネデリ'), 4.0, 18.3, 's'));
      expect(saved.id, isNotNull);
      var reloaded = await repo.byId(saved.id!);
      expect(reloaded!.border4, 18.3);
      expect(reloaded.border1, isNull);

      // 1円で計測しようとした想定 → 1円スロットを入力して保存(育つ)。
      await repo.update(applyBorder(reloaded, 1.0, 72.0, 's'));
      reloaded = await repo.byId(saved.id!);
      expect(reloaded!.border4, 18.3); // 4円は保持
      expect(reloaded.border1, 72.0);
    });
  });

  group('エクスポート', () {
    late Database db;

    setUp(() async => db = await openTestDb());
    tearDown(() async => db.close());

    test('エクスポート JSON は machines と traces を含む', () async {
      final machines = MachineRepository(db);
      await machines.insert(const Machine(name: 'X', border4: 16.5));

      final service = SessionService(
        sessions: SessionRepository(db),
        entries: EntryRepository(db),
        traces: TraceRepository(db),
      );
      const m = Machine(id: 1, name: 'X', border4: 16.5);
      final s = await service.start(machine: m, ballPrice: 4.0, startCounter: 0);
      await service.recordCount(s, counter: 20);
      await service.endAndLog(s, m, recovery: 3000);

      final data = await BackupService(db).exportData();
      expect(data['app'], 'pachi_kaiten');
      expect((data['machines'] as List), isNotEmpty);
      expect((data['traces'] as List).length, 1);
    });
  });

  group('ネットワーク非依存', () {
    test('pubspec.yaml に http / file_picker 依存が無い', () {
      final text = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'^\s*http:', multiLine: true).hasMatch(text), isFalse,
          reason: 'http 依存が残っている(通信ゼロを担保)');
      expect(RegExp(r'^\s*file_picker:', multiLine: true).hasMatch(text),
          isFalse,
          reason: 'file_picker 依存が残っている(インポート廃止)');
    });
  });
}
