/// 決定タップ時の異常値判定。
///
/// 差分が負、または投資単位あたりの回転数が上限を超えたとき true を返し、
/// 確認シートを表示するトリガーとする。
enum AnomalyKind { none, negative, tooHigh }

/// [diff]      : 今回の差分回転数(新カウンタ − 直前カウンタ)。
/// [addUnit]   : 決定 1 回の投資加算額(1000 / 500)。上限のスケールに使う。
/// [isFirstAfterOrigin] : start / rebase 直後の最初の入力なら true(判定スキップ)。
///
/// 上限は 1000 円区間で 40 回転(500 円区間で 20 回転)。
///   threshold = 40 × addUnit / 1000
AnomalyKind detectAnomaly({
  required int diff,
  required int addUnit,
  required bool isFirstAfterOrigin,
}) {
  if (isFirstAfterOrigin) return AnomalyKind.none;
  if (diff < 0) return AnomalyKind.negative;
  final threshold = (40 * addUnit) / 1000.0;
  if (diff > threshold) return AnomalyKind.tooHigh;
  return AnomalyKind.none;
}
