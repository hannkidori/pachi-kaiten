import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/backup_service.dart';
import 'package:pachi_kaiten/logic/machine_sync.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/models/store.dart';
import 'package:pachi_kaiten/repositories/machine_repository.dart';
import 'package:pachi_kaiten/repositories/settings_repository.dart';
import 'package:pachi_kaiten/repositories/store_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

String machinesJson(String version, List<Map<String, Object?>> machines) =>
    jsonEncode({'version': version, 'machines': machines});

Map<String, Object?> mj(String id, String name, {bool dropProb = false}) => {
      'id': id,
      'name': name,
      if (!dropProb) 'probability': 319.6,
      'borders': {'4.0': 16.5, '3.57': 18.0},
      'type': 'ミドル',
    };

void main() {
  group('MachineSync — 配信ミス耐性', () {
    late Database db;
    late MachineRepository machineRepo;
    late SettingsRepository settings;
    late MachineSync sync;

    setUp(() async {
      db = await openTestDb();
      machineRepo = MachineRepository(db);
      settings = SettingsRepository(db);
      sync = MachineSync(machineRepo, settings: settings);
      // 初期状態: umi = 旧名、version 2026-07-22。
      await machineRepo.upsertAll([Machine.fromJson(mj('umi', '旧・海物語'))]);
      await settings.setMachinesVersion('2026-07-22');
    });
    tearDown(() async => db.close());

    Fetcher fixed(String body) => (_) async => body;
    Fetcher throwing() => (_) async => throw const SocketException('no net');

    test('新しい version は UPSERT される', () async {
      final res = await sync.syncFromRemote('u',
          fetch: fixed(machinesJson('2026-07-23', [
            mj('umi', '新・海物語'),
            mj('eva', 'エヴァ'),
          ])));
      expect(res.outcome, SyncOutcome.applied);
      expect((await machineRepo.byId('umi'))!.name, '新・海物語');
      expect(await machineRepo.byId('eva'), isNotNull);
      expect(await settings.machinesVersion(), '2026-07-23');
    });

    test('同じ version は UPSERT しない', () async {
      final res = await sync.syncFromRemote('u',
          fetch: fixed(machinesJson('2026-07-22', [mj('umi', '別名')])));
      expect(res.outcome, SyncOutcome.upToDate);
      expect((await machineRepo.byId('umi'))!.name, '旧・海物語'); // 不変
    });

    test('古い version は UPSERT しない', () async {
      final res = await sync.syncFromRemote('u',
          fetch: fixed(machinesJson('2026-07-01', [mj('umi', '別名')])));
      expect(res.outcome, SyncOutcome.upToDate);
      expect((await machineRepo.byId('umi'))!.name, '旧・海物語');
    });

    test('壊れた JSON でも既存マスタは無傷', () async {
      final res = await sync.syncFromRemote('u', fetch: fixed('<<not json>>'));
      expect(res.outcome, SyncOutcome.failed);
      expect((await machineRepo.byId('umi'))!.name, '旧・海物語');
      expect(await machineRepo.count(), 1);
      expect(await settings.machinesVersion(), '2026-07-22');
    });

    test('必須フィールド欠落でも既存マスタは無傷(部分適用しない)', () async {
      // umi は正常だが eva に probability が無い → 全体を破棄。
      final res = await sync.syncFromRemote('u',
          fetch: fixed(machinesJson('2026-07-30', [
            mj('umi', '新名'),
            mj('eva', 'エヴァ', dropProb: true),
          ])));
      expect(res.outcome, SyncOutcome.failed);
      // umi も更新されていない(途中適用が無い)。
      expect((await machineRepo.byId('umi'))!.name, '旧・海物語');
      expect(await machineRepo.byId('eva'), isNull);
      expect(await settings.machinesVersion(), '2026-07-22');
    });

    test('ネットワーク例外でも既存マスタは無傷', () async {
      final res = await sync.syncFromRemote('u', fetch: throwing());
      expect(res.outcome, SyncOutcome.failed);
      expect(await machineRepo.count(), 1);
    });
  });

  group('BackupService — バックアップ/復元', () {
    late Database db;
    late StoreRepository storeRepo;
    late BackupService backup;

    setUp(() async {
      db = await openTestDb();
      storeRepo = StoreRepository(db);
      backup = BackupService(db);
      await MachineRepository(db)
          .upsertAll([Machine.fromJson(mj('umi', '海物語'))]);
      await storeRepo
          .insert(const Store(name: 'A', exchangeRate: 3.57, ballPrice: 4.0));
    });
    tearDown(() async => db.close());

    test('エクスポート→インポートで往復復元できる', () async {
      final exported = await backup.exportData();
      // シリアライズ相当(ファイル経由を模擬)。
      final roundTripped =
          (jsonDecode(jsonEncode(exported)) as Map).cast<String, Object?>();

      // DB を変更(店舗を追加)。
      await storeRepo
          .insert(const Store(name: 'B', exchangeRate: 4.0, ballPrice: 4.0));
      expect((await storeRepo.all()).length, 2);

      // インポートで元に戻る。
      await backup.applyImport(roundTripped);
      final stores = await storeRepo.all();
      expect(stores.length, 1);
      expect(stores.single.name, 'A');
    });

    test('不正なインポートデータは弾かれ DB は無傷', () async {
      final before = await storeRepo.all();
      // entries テーブルが欠けている不正データ。
      final bad = {
        'app': 'pachi_kaiten',
        'schema': 2,
        'stores': [],
        'machines': [],
        'sessions': [],
        'settings': [],
      };
      expect(() => backup.applyImport(bad), throwsFormatException);
      expect((await storeRepo.all()).length, before.length);
      expect((await storeRepo.all()).single.name, 'A');
    });

    test('別アプリのバックアップは弾く', () async {
      expect(
        () => backup.applyImport({'app': 'other'}),
        throwsFormatException,
      );
    });

    test('importWithBackup は上書き前に現データをバックアップする', () async {
      Map<String, Object?>? captured;
      final incoming = {
        'app': 'pachi_kaiten',
        'schema': 2,
        'stores': [
          {
            'id': 9,
            'name': 'B',
            'exchange_rate': 4.0,
            'ball_price': 4.0,
            'sort_order': 0
          }
        ],
        'machines': [],
        'sessions': [],
        'entries': [],
        'settings': [],
      };

      await backup.importWithBackup(
        incoming,
        writeBackup: (snap) async {
          captured = snap;
        },
      );

      // バックアップは「上書き前」の状態(店舗 A)を含む。
      expect(captured, isNotNull);
      final backedStores = (captured!['stores'] as List).cast<Map>();
      expect(backedStores.length, 1);
      expect(backedStores.single['name'], 'A');

      // 実データは incoming(店舗 B)に置き換わっている。
      final stores = await storeRepo.all();
      expect(stores.single.name, 'B');
    });

    test('インポート失敗時はバックアップを取らず DB も無傷', () async {
      var backupCalled = false;
      final bad = {'app': 'other'}; // 検証で弾かれる
      await expectLater(
        backup.importWithBackup(bad,
            writeBackup: (_) async => backupCalled = true),
        throwsFormatException,
      );
      expect(backupCalled, isFalse); // 上書きが起きないのでバックアップ不要
      expect((await storeRepo.all()).single.name, 'A');
    });
  });
}

/// テスト内でネットワーク例外を模すための最小 SocketException。
class SocketException implements Exception {
  final String message;
  const SocketException(this.message);
}
