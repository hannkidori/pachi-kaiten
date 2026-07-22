import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/rotation_calc.dart';
import 'package:pachi_kaiten/models/entry.dart';

/// テスト用 Entry ビルダー。cash は [invest](円)、ball は [balls](玉)。
Entry _e(
  EntryType type,
  int counter, {
  EntryMode mode = EntryMode.cash,
  int invest = 0,
  int balls = 0,
  int seq = 0,
}) {
  return Entry(
    sessionId: 1,
    type: type,
    counter: counter,
    mode: mode,
    investAdded: invest,
    ballsAdded: balls,
    createdAt: '2026-07-22T10:00:${seq.toString().padLeft(2, '0')}',
  );
}

void main() {
  group('effectiveBorder', () {
    test('4円貸しはカタログ値そのまま', () {
      expect(effectiveBorder(16.5, 4.0), 16.5);
    });
    test('1円貸しは4倍', () {
      expect(effectiveBorder(16.5, 1.0), closeTo(66.0, 1e-9));
    });
    test('ball_price 0 はフォールバックでカタログ値', () {
      expect(effectiveBorder(16.5, 0), 16.5);
    });
  });

  group('computeStats — 現金のみ', () {
    test('R と borderDiff と EV', () {
      final entries = [
        _e(EntryType.start, 100, seq: 0),
        _e(EntryType.count, 120, mode: EntryMode.cash, invest: 1000, seq: 1),
        _e(EntryType.count, 141, mode: EntryMode.cash, invest: 1000, seq: 2),
      ];
      final s = computeStats(
          entries: entries, catalogBorder: 16.5, ballPrice: 4.0);

      expect(s.totalRotations, 41);
      expect(s.cashRotations, 41);
      expect(s.cashInvest, 2000);
      expect(s.measuredRotations, 41);
      expect(s.measuredInvest, 2000);
      expect(s.rotationRate, closeTo(20.5, 1e-9));
      expect(s.effectiveBorder, 16.5);
      expect(s.borderDiff, closeTo(4.0, 1e-9));
      expect(s.expectedValue, closeTo(484.848484, 1e-4));
      expect(s.bonusCount, 0);
      expect(s.segments.map((e) => e.rotations).toList(), [20, 21]);
    });

    test('未計測(投資0)は R / borderDiff / EV が null', () {
      final s = computeStats(
          entries: [_e(EntryType.start, 100)],
          catalogBorder: 16.5,
          ballPrice: 4.0);
      expect(s.rotationRate, isNull);
      expect(s.borderDiff, isNull);
      expect(s.expectedValue, isNull);
      expect(s.totalRotations, 0);
    });

    test('500円加算単位でも R が正しい', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 10, mode: EntryMode.cash, invest: 500, seq: 1),
        _e(EntryType.count, 21, mode: EntryMode.cash, invest: 500, seq: 2),
      ];
      final s = computeStats(
          entries: entries, catalogBorder: 16.5, ballPrice: 4.0);
      expect(s.cashInvest, 1000);
      expect(s.rotationRate, closeTo(21.0, 1e-9));
    });
  });

  group('computeStats — 持ち玉も算入(新仕様)', () {
    test('現金+持ち玉の混在。250玉=1000円相当で R に算入', () {
      // 現金1000円で20回転、持ち玉250玉(=1000円相当)で30回転。
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 20, mode: EntryMode.cash, invest: 1000, seq: 1),
        _e(EntryType.rebase, 500, mode: EntryMode.ball, seq: 2),
        _e(EntryType.count, 530, mode: EntryMode.ball, balls: 250, seq: 3),
      ];
      final s = computeStats(
          entries: entries, catalogBorder: 16.5, ballPrice: 4.0);

      expect(s.totalRotations, 50);
      expect(s.cashRotations, 20);
      expect(s.cashInvest, 1000); // 「投資」表示は現金のみ
      // 計測: 現金20 + 持ち玉30 = 50回転、投資相当 1000 + 250×4=1000 = 2000円
      expect(s.measuredRotations, 50);
      expect(s.measuredInvest, 2000);
      expect(s.rotationRate, closeTo(25.0, 1e-9)); // 50 / 2
      expect(s.borderDiff, closeTo(25.0 - 16.5, 1e-9));
      // EV = 計測回転 × (1000/B − 1000/R) = 50×(1000/16.5 − 1000/25)
      expect(s.expectedValue, closeTo(1030.303030, 1e-3));
      expect(s.bonusCount, 1);
      // グラフは現金・持ち玉の両区間を棒にする。
      expect(s.segments.map((e) => e.mode).toList(),
          [EntryMode.cash, EntryMode.ball]);
      expect(s.segments[1].measured, isTrue);
    });

    test('rebase 直後の最初の持ち玉決定も計測に算入される', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 18, mode: EntryMode.cash, invest: 1000, seq: 1),
        _e(EntryType.rebase, 400, mode: EntryMode.ball, seq: 2),
        // 復帰直後の最初の入力(持ち玉)。250玉で17回転。
        _e(EntryType.count, 417, mode: EntryMode.ball, balls: 250, seq: 3),
      ];
      final s = computeStats(
          entries: entries, catalogBorder: 16.5, ballPrice: 4.0);
      // 持ち玉の17回転が R に含まれる。
      expect(s.measuredRotations, 18 + 17);
      expect(s.measuredInvest, 1000 + 1000);
      expect(s.rotationRate, closeTo(35 / 2.0, 1e-9));
    });

    test('消費玉0の持ち玉区間(旧データ)は計測外', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 20, mode: EntryMode.cash, invest: 1000, seq: 1),
        _e(EntryType.rebase, 500, mode: EntryMode.ball, seq: 2),
        _e(EntryType.count, 530, mode: EntryMode.ball, seq: 3), // balls=0
      ];
      final s = computeStats(
          entries: entries, catalogBorder: 16.5, ballPrice: 4.0);
      expect(s.totalRotations, 50); // 表示上の総回転には入る
      expect(s.measuredRotations, 20); // 計測は現金のみ
      expect(s.measuredInvest, 1000);
      expect(s.rotationRate, closeTo(20.0, 1e-9));
      expect(s.segments[1].measured, isFalse);
    });

    test('1円パチンコ: 1000玉=1000円相当。ボーダー4倍で評価', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 60, mode: EntryMode.cash, invest: 1000, seq: 1),
        _e(EntryType.rebase, 300, mode: EntryMode.ball, seq: 2),
        _e(EntryType.count, 340, mode: EntryMode.ball, balls: 1000, seq: 3),
      ];
      final s = computeStats(
          entries: entries, catalogBorder: 16.5, ballPrice: 1.0);
      expect(s.effectiveBorder, closeTo(66.0, 1e-9));
      // 計測: 100回転 / (2000円/1000) = 50
      expect(s.measuredRotations, 100);
      expect(s.measuredInvest, 2000); // 1000円 + 1000玉×1円
      expect(s.rotationRate, closeTo(50.0, 1e-9));
      expect(s.borderDiff, closeTo(50.0 - 66.0, 1e-9)); // 下
    });
  });

  group('computeStats — rebase / マーカー', () {
    test('rebase イベント自体は回転・投資に加算しない', () {
      final entries = [
        _e(EntryType.start, 100, seq: 0),
        _e(EntryType.count, 120, mode: EntryMode.cash, invest: 1000, seq: 1),
        _e(EntryType.rebase, 500, mode: EntryMode.ball, seq: 2), // 起点付替のみ
      ];
      final s = computeStats(
          entries: entries, catalogBorder: 16.5, ballPrice: 4.0);
      expect(s.totalRotations, 20);
      expect(s.measuredRotations, 20);
      expect(s.bonusCount, 1);
    });

    test('rebaseMarkers は各大当りまでの計測区間の本数', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 20, mode: EntryMode.cash, invest: 1000, seq: 1),
        _e(EntryType.count, 40, mode: EntryMode.cash, invest: 1000, seq: 2),
        _e(EntryType.rebase, 500, mode: EntryMode.ball, seq: 3), // 計測2本後
        _e(EntryType.count, 530, mode: EntryMode.ball, balls: 250, seq: 4),
        _e(EntryType.count, 552, mode: EntryMode.cash, invest: 1000, seq: 5),
        _e(EntryType.rebase, 800, mode: EntryMode.ball, seq: 6), // 計測4本後
      ];
      final s = computeStats(
          entries: entries, catalogBorder: 16.5, ballPrice: 4.0);
      expect(s.bonusCount, 2);
      expect(s.rebaseMarkers, [2, 4]);
    });
  });
}
