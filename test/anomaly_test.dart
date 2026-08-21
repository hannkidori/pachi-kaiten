import 'package:flutter_test/flutter_test.dart';
import 'package:pachi_kaiten/logic/anomaly.dart';

void main() {
  group('detectAnomaly', () {
    test('差分が負なら negative', () {
      expect(detectAnomaly(diff: -5, addUnit: 1000), AnomalyKind.negative);
    });

    test('差分 0(回転が増えていない)も negative', () {
      // 1000円打って 0 回転は現実には起きない。打ち間違いとして確認させる。
      expect(detectAnomaly(diff: 0, addUnit: 1000), AnomalyKind.negative);
    });

    test('1000円区間で40超なら tooHigh', () {
      expect(detectAnomaly(diff: 45, addUnit: 1000), AnomalyKind.tooHigh);
    });

    test('1000円区間で40ちょうどは正常', () {
      expect(detectAnomaly(diff: 40, addUnit: 1000), AnomalyKind.none);
    });

    test('500円区間で20超なら tooHigh', () {
      expect(detectAnomaly(diff: 21, addUnit: 500), AnomalyKind.tooHigh);
    });

    test('500円区間で20ちょうどは正常', () {
      expect(detectAnomaly(diff: 20, addUnit: 500), AnomalyKind.none);
    });

    test('最初の入力でも判定する(スキップしない)', () {
      // 以前は start / rebase 直後を素通しにしており、打ち始めの打ち間違いが
      // そのまま記録され、総回転 0 や負のセッションが終了時に黙って破棄されていた。
      expect(detectAnomaly(diff: 999, addUnit: 1000), AnomalyKind.tooHigh);
      expect(detectAnomaly(diff: -50, addUnit: 1000), AnomalyKind.negative);
      expect(detectAnomaly(diff: 0, addUnit: 1000), AnomalyKind.negative);
    });

    test('正常範囲は none', () {
      expect(detectAnomaly(diff: 18, addUnit: 1000), AnomalyKind.none);
    });
  });
}
