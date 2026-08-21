import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/repositories/machine_repository.dart';
import 'package:pachi_kaiten/repositories/settings_repository.dart';
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
  group('ボーダー入力の検証(parseBorder)', () {
    test('Infinity / NaN / 0以下 / 上限超 は弾く', () {
      // double.tryParse('Infinity') は Infinity を返す。> 0 だけの検査では
      // 素通りし、期待値計算が NaN になって計測画面とホームが落ちていた。
      expect(parseBorder('Infinity'), isNull);
      expect(parseBorder('1e999'), isNull); // これも Infinity になる
      expect(parseBorder('NaN'), isNull);
      expect(parseBorder('0'), isNull);
      expect(parseBorder('-5'), isNull);
      expect(parseBorder(''), isNull);
      expect(parseBorder('abc'), isNull);
      expect(parseBorder('${kBorderMax + 1}'), isNull);
    });

    test('現実的な値は通す', () {
      expect(parseBorder('18.3'), closeTo(18.3, 1e-9));
      expect(parseBorder(' 66 '), closeTo(66.0, 1e-9)); // 前後の空白は無視
      expect(parseBorder('$kBorderMax'), closeTo(kBorderMax, 1e-9)); // 上限は可
    });
  });

  group('機種名の重複チェック(isDuplicateName)', () {
    const existing = ['P大海物語5', 'Pエヴァ15'];

    test('同名(前後空白・大小文字の違いを無視)は重複', () {
      expect(isDuplicateName('P大海物語5', existing), isTrue);
      expect(isDuplicateName('  P大海物語5  ', existing), isTrue);
      expect(isDuplicateName('pエヴァ15'.toUpperCase(), ['PエヴァSP']), isFalse);
      expect(isDuplicateName('pエヴァ15', ['Pエヴァ15']), isTrue);
    });

    test('別名・空文字は重複でない', () {
      expect(isDuplicateName('P北斗の拳', existing), isFalse);
      expect(isDuplicateName('', existing), isFalse);
      expect(isDuplicateName('   ', existing), isFalse);
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
