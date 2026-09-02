import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/models/entry.dart';
import 'package:pachi_kaiten/models/machine.dart';
import 'package:pachi_kaiten/repositories/entry_repository.dart';
import 'package:pachi_kaiten/repositories/machine_repository.dart';
import 'package:pachi_kaiten/repositories/settings_repository.dart';
import 'package:pachi_kaiten/services/other_apps.dart';
import 'package:pachi_kaiten/services/review_prompt.dart';
import 'package:pachi_kaiten/ui/start/machine_sheets.dart';
import 'package:pachi_kaiten/ui/widgets/counter_field.dart';
import 'package:pachi_kaiten/ui/widgets/numpad.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

void main() {
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

    test('all() は登録の新しい順(名前順ではない)', () async {
      // 名前順だと漢字がコード順に並んで探しにくいので登録順で固定している。
      await repo.insert(const Machine(name: 'ぱ機種')); // id 1
      await repo.insert(const Machine(name: 'あ機種')); // id 2
      await repo.insert(const Machine(name: 'A機種')); // id 3
      final list = await repo.all();
      expect(list.map((m) => m.name), ['A機種', 'あ機種', 'ぱ機種']);
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

  group('設定の初期値(新規インストール時)', () {
    late Database db;
    late SettingsRepository settings;

    setUp(() async {
      db = await openTestDb();
      settings = SettingsRepository(db);
    });
    tearDown(() async => db.close());

    test('貸玉は 4円 / 加算単位は1000 / スリープ防止はON', () async {
      expect(await settings.ballPrice(), 4.0); // 1円ではない
      expect(await settings.addUnitDefault(), 1000);
      expect(await settings.keepAwake(), isTrue);
    });

    test('1円に変えた後も 4円に戻せる', () async {
      await settings.setBallPrice(1.0);
      expect(await settings.ballPrice(), 1.0);
      await settings.setBallPrice(4.0);
      expect(await settings.ballPrice(), 4.0);
    });
  });

  group('レビュー依頼(iOS)', () {
    group('資格 — 決定の累計回数', () {
      test('しきい値は 50 / 500 / 1000 の 3 段(iOS の年3回上限に合わせる)', () {
        expect(kReviewMilestones, [50, 500, 1000]);
      });

      test('各段は到達した回数でだけ資格が立つ', () {
        expect(hasReviewQualification(count: 49, stage: 0), isFalse);
        expect(hasReviewQualification(count: 50, stage: 0), isTrue);
        // 1 段目を消化したら次は 500 まで立たない
        expect(hasReviewQualification(count: 499, stage: 1), isFalse);
        expect(hasReviewQualification(count: 500, stage: 1), isTrue);
        expect(hasReviewQualification(count: 999, stage: 2), isFalse);
        expect(hasReviewQualification(count: 1000, stage: 2), isTrue);
      });

      test('3 段消化後は何回入力しても資格は立たない(打ち止め)', () {
        expect(hasReviewQualification(count: 1000, stage: 3), isFalse);
        expect(hasReviewQualification(count: 999999, stage: 3), isFalse);
        expect(hasReviewQualification(count: 999999, stage: 99), isFalse);
      });
    });

    group('発火 — ボーダー超えで終えた直後', () {
      ReviewAction decide(double? diff, {int rotations = 300, int waited = 0}) =>
          decideAfterMeasurement(
              totalRotations: rotations, borderDiff: diff, waited: waited);

      test('ボーダー超え(R−B > 0)なら出す', () {
        expect(decide(0.1), ReviewAction.show);
        expect(decide(3.2), ReviewAction.show);
      });

      test('ボーダー割れ・同値・ボーダー不明では出さず次を待つ', () {
        expect(decide(-0.3), ReviewAction.wait); // 負けた直後に出さない
        expect(decide(0.0), ReviewAction.wait); // ちょうどは超えていない
        expect(decide(null), ReviewAction.wait); // クイック計測/ボーダー未登録
      });

      test('総回転が少なすぎる計測は待ち回数にも数えない', () {
        expect(decide(5.0, rotations: kReviewMinRotations - 1),
            ReviewAction.ignore);
        expect(decide(null, rotations: 0), ReviewAction.ignore);
        expect(decide(5.0, rotations: kReviewMinRotations), ReviewAction.show);
      });

      test('好条件が来ないまま 5 回終えたら妥協して出す', () {
        // 0,1,2,3 回目までは待つ / 5 回目(waited=4)で出す
        expect(decide(-1.0, waited: 0), ReviewAction.wait);
        expect(decide(-1.0, waited: 3), ReviewAction.wait);
        expect(decide(-1.0, waited: kReviewFallbackEnds - 1), ReviewAction.show);
      });
    });

    group('入力回数の数え方', () {
      late Database db;
      late EntryRepository entries;
      late SettingsRepository settings;

      setUp(() async {
        db = await openTestDb();
        entries = EntryRepository(db);
        settings = SettingsRepository(db);
      });
      tearDown(() async => db.close());

      Future<void> add(EntryType type) => entries.insert(Entry(
          sessionId: 1, type: type, counter: 0, createdAt: 's'));

      test('決定(count)だけを通算で数え、開始・大当り復帰は数えない', () async {
        expect(await entries.countOfType(EntryType.count), 0);
        await add(EntryType.start);
        await add(EntryType.count);
        await add(EntryType.rebase);
        await add(EntryType.count);
        expect(await entries.countOfType(EntryType.count), 2);
      });

      test('破棄されたセッションの入力は数から消える', () async {
        await add(EntryType.count);
        await add(EntryType.count);
        await entries.deleteBySession(1);
        expect(await entries.countOfType(EntryType.count), 0);
      });

      test('依頼済みの段数・待ち回数は保存され、既定は 0', () async {
        expect(await settings.reviewStage(), 0);
        expect(await settings.reviewWaited(), 0);
        await settings.setReviewStage(1);
        await settings.setReviewWaited(2);
        expect(await settings.reviewStage(), 1);
        expect(await settings.reviewWaited(), 2);
      });
    });
  });

  group('作者の他のアプリ(紹介欄)', () {
    test('ハナジャグ・コヤカンの 2 件を表示順に持つ', () {
      expect(kOtherApps.map((a) => a.name), ['ハナジャグ', 'コヤカン']);
    });

    test('App Store の ID が正しい', () {
      // リンク先を取り違えると別アプリに飛ぶので数値まで固定する。
      expect(kOtherApps[0].appStoreId, '6792313623'); // ハナジャグ
      expect(kOtherApps[1].appStoreId, '6801049251'); // コヤカン
    });

    test('URL は App Store のアプリページ形式', () {
      expect(kOtherApps[0].storeUrl,
          'https://apps.apple.com/jp/app/id6792313623');
      for (final app in kOtherApps) {
        expect(app.storeUrl, startsWith('https://apps.apple.com/'));
        expect(app.description, isNotEmpty);
      }
    });
  });

  group('輸出コンプライアンス', () {
    test('Info.plist に ITSAppUsesNonExemptEncryption=false がある', () {
      // 消えると App Store Connect で「暗号化書類」の回答を毎回求められる。
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final i = plist.indexOf('<key>ITSAppUsesNonExemptEncryption</key>');
      expect(i, greaterThan(-1), reason: 'キーが無い');
      expect(plist.substring(i).trimLeft(),
          contains(RegExp(r'ITSAppUsesNonExemptEncryption</key>\s*<false/>')));
    });
  });

  group('バージョン表記', () {
    test('設定画面の表示が pubspec.yaml と一致する', () {
      // 片方だけ上げ忘れると、ユーザーに古い版数を見せることになる。
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull, reason: 'pubspec.yaml に version が無い');
      final version = m!.group(1);
      final settings =
          File('lib/ui/settings/settings_screen.dart').readAsStringSync();
      expect(settings, contains("'パチ回転計 v$version'"));
    });
  });

  group('カウンタ入力の見せ方(displayCounter)', () {
    test('先頭の余分な 0 は表示しない', () {
      expect(displayCounter('05'), '5');
      expect(displayCounter('007'), '7');
      expect(displayCounter('0123'), '123');
    });

    test('0 単体・空はそのまま(0 は正当な入力)', () {
      expect(displayCounter('0'), '0');
      expect(displayCounter('00'), '0');
      expect(displayCounter('000'), '0');
      expect(displayCounter(''), '');
    });

    test('先頭が 0 でなければ何も変えない', () {
      expect(displayCounter('1'), '1');
      expect(displayCounter('105'), '105');
      expect(displayCounter('999999'), '999999');
    });

    test('数値としての解釈は変わらない(表示だけの整形)', () {
      for (final s in ['', '0', '00', '05', '007', '0123', '1', '105', '999999']) {
        expect(int.tryParse(displayCounter(s)) ?? 0, int.tryParse(s) ?? 0,
            reason: '「\$s」の値が変わってはいけない');
      }
    });

    test('applyKey は変えていない(桁数の上限も従来どおり)', () {
      // 表示だけを直す方針にしたので、入力文字列の作られ方は不変。
      expect(applyKey('', '0'), '0');
      expect(applyKey('0', '5'), '05'); // 文字列としては従来どおり
      expect(applyKey('12', '3'), '123');
      expect(applyKey('123456', '7'), '123456'); // 6桁でクランプ
      expect(applyKey('12', '⌫'), '1');
      expect(applyKey('', '⌫'), '');
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
