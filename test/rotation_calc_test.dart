import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/rotation_calc.dart';
import 'package:pachi_kaiten/models/entry.dart';

/// テスト用 Entry ビルダー。count は [yen](= 消化した加算単位)。
Entry _e(
  EntryType type,
  int counter, {
  int yen = 0,
  int seq = 0,
}) {
  return Entry(
    sessionId: 1,
    type: type,
    counter: counter,
    yen: yen,
    createdAt: '2026-07-22T10:00:${seq.toString().padLeft(2, '0')}',
  );
}

void main() {
  group('computeStats — 基本(単位統合モデル)', () {
    test('R と borderDiff と EV(10円丸め)', () {
      final entries = [
        _e(EntryType.start, 100, seq: 0),
        _e(EntryType.count, 120, yen: 1000, seq: 1),
        _e(EntryType.count, 141, yen: 1000, seq: 2),
      ];
      final s = computeStats(entries: entries, border: 16.5);

      expect(s.totalRotations, 41);
      expect(s.consumedYen, 2000);
      expect(s.rotationRate, closeTo(20.5, 1e-9)); // 41 / 2
      expect(s.border, 16.5);
      expect(s.hasBorder, isTrue);
      expect(s.borderDiff, closeTo(4.0, 1e-9));
      // EV = 消化 × (R − B) / B = 2000 × 4 / 16.5 = 484.8… → 480(10円丸め)
      expect(s.expectedValue, 480.0);
      expect(s.bonusCount, 0);
      expect(s.segments.map((e) => e.rotations).toList(), [20, 21]);
      expect(s.segments.map((e) => e.yen).toList(), [1000, 1000]);
    });

    test('未計測(消化0)は R / borderDiff / EV が null', () {
      final s = computeStats(entries: [_e(EntryType.start, 100)], border: 16.5);
      expect(s.rotationRate, isNull);
      expect(s.borderDiff, isNull);
      expect(s.expectedValue, isNull);
      expect(s.totalRotations, 0);
      expect(s.consumedYen, 0);
    });

    test('500円加算単位でも R が正しい', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 10, yen: 500, seq: 1),
        _e(EntryType.count, 21, yen: 500, seq: 2),
      ];
      final s = computeStats(entries: entries, border: 16.5);
      expect(s.consumedYen, 1000);
      expect(s.rotationRate, closeTo(21.0, 1e-9)); // 21 / 1
    });
  });

  group('computeStats — クイック計測(ボーダー未設定)', () {
    test('border=0 は R は出るが判定・EV は出ない', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 20, yen: 1000, seq: 1),
      ];
      final s = computeStats(entries: entries, border: 0);
      expect(s.hasBorder, isFalse);
      expect(s.rotationRate, closeTo(20.0, 1e-9));
      expect(s.borderDiff, isNull);
      expect(s.expectedValue, isNull);
    });
  });

  group('computeStats — rebase / マーカー', () {
    test('rebase 自体は加算しないが、以降の決定は通常どおり算入される', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 20, yen: 1000, seq: 1),
        _e(EntryType.rebase, 500, seq: 2), // 起点付替のみ
        _e(EntryType.count, 530, yen: 1000, seq: 3), // 復帰後の30回転も算入
      ];
      final s = computeStats(entries: entries, border: 16.5);
      expect(s.totalRotations, 50);
      expect(s.consumedYen, 2000);
      expect(s.rotationRate, closeTo(25.0, 1e-9)); // 50 / 2
      expect(s.bonusCount, 1);
    });

    test('rebase 直後の最初の決定も算入される', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 18, yen: 1000, seq: 1),
        _e(EntryType.rebase, 400, seq: 2),
        _e(EntryType.count, 417, yen: 1000, seq: 3), // 復帰直後の17回転
      ];
      final s = computeStats(entries: entries, border: 16.5);
      expect(s.totalRotations, 35);
      expect(s.consumedYen, 2000);
      expect(s.rotationRate, closeTo(17.5, 1e-9));
    });

    test('rebase のみ(復帰後の決定なし)は回転・消化に加算しない', () {
      final entries = [
        _e(EntryType.start, 100, seq: 0),
        _e(EntryType.count, 120, yen: 1000, seq: 1),
        _e(EntryType.rebase, 500, seq: 2),
      ];
      final s = computeStats(entries: entries, border: 16.5);
      expect(s.totalRotations, 20);
      expect(s.consumedYen, 1000);
      expect(s.bonusCount, 1);
    });

    test('rebaseMarkers は各大当りまでの区間の本数', () {
      final entries = [
        _e(EntryType.start, 0, seq: 0),
        _e(EntryType.count, 20, yen: 1000, seq: 1),
        _e(EntryType.count, 40, yen: 1000, seq: 2),
        _e(EntryType.rebase, 500, seq: 3), // 2本後
        _e(EntryType.count, 530, yen: 1000, seq: 4),
        _e(EntryType.count, 552, yen: 1000, seq: 5),
        _e(EntryType.rebase, 800, seq: 6), // 4本後
      ];
      final s = computeStats(entries: entries, border: 16.5);
      expect(s.bonusCount, 2);
      expect(s.rebaseMarkers, [2, 4]);
    });
  });
}
