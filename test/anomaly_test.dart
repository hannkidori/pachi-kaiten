import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/anomaly.dart';

void main() {
  group('detectAnomaly', () {
    test('差分が負なら negative', () {
      expect(
        detectAnomaly(diff: -5, addUnit: 1000, isFirstAfterOrigin: false),
        AnomalyKind.negative,
      );
    });

    test('1000円区間で40超なら tooHigh', () {
      expect(
        detectAnomaly(diff: 45, addUnit: 1000, isFirstAfterOrigin: false),
        AnomalyKind.tooHigh,
      );
    });

    test('1000円区間で40ちょうどは正常', () {
      expect(
        detectAnomaly(diff: 40, addUnit: 1000, isFirstAfterOrigin: false),
        AnomalyKind.none,
      );
    });

    test('500円区間で20超なら tooHigh', () {
      expect(
        detectAnomaly(diff: 21, addUnit: 500, isFirstAfterOrigin: false),
        AnomalyKind.tooHigh,
      );
    });

    test('500円区間で20ちょうどは正常', () {
      expect(
        detectAnomaly(diff: 20, addUnit: 500, isFirstAfterOrigin: false),
        AnomalyKind.none,
      );
    });

    test('start / rebase 直後の最初の入力は判定スキップ', () {
      expect(
        detectAnomaly(diff: 999, addUnit: 1000, isFirstAfterOrigin: true),
        AnomalyKind.none,
      );
      expect(
        detectAnomaly(diff: -50, addUnit: 1000, isFirstAfterOrigin: true),
        AnomalyKind.none,
      );
    });

    test('正常範囲は none', () {
      expect(
        detectAnomaly(diff: 18, addUnit: 1000, isFirstAfterOrigin: false),
        AnomalyKind.none,
      );
    });
  });
}
