/// 決定タップ時の異常値判定。
///
/// 回転数が増えていない(差分 0 以下)、または消化単位あたりの回転数が上限を
/// 超えたときに種別を返し、確認シートを表示するトリガーとする。
enum AnomalyKind { none, negative, tooHigh }

/// [diff]    : 今回の差分回転数(新カウンタ − 直前カウンタ)。
/// [addUnit] : 決定 1 回の消化額(1000 / 500)。上限のスケールに使う。
///
/// 判定は **常に** 行う(start / rebase 直後の最初の入力も対象)。
/// 台のカウンタは減らないので差分が 0 以下なら打ち間違い、1000 円で 40 回転超も
/// 打ち間違いの可能性が高い。かつては最初の入力を素通しにしていたが、
/// 打ち始め値の打ち間違いがそのまま記録され、総回転が 0 や負になったセッションが
/// 終了時に黙って破棄される事故につながっていた。
///
/// 上限は 1000 円区間で 40 回転(500 円区間で 20 回転)。
///   threshold = 40 × addUnit / 1000
AnomalyKind detectAnomaly({
  required int diff,
  required int addUnit,
}) {
  if (diff <= 0) return AnomalyKind.negative;
  final threshold = (40 * addUnit) / 1000.0;
  if (diff > threshold) return AnomalyKind.tooHigh;
  return AnomalyKind.none;
}
