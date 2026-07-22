import '../models/entry.dart';

/// 実質ボーダー B を求める。
///
/// [catalogBorder] はカタログ(4 円貸し基準)の該当換金率ボーダー、
/// [ballPrice] は貸玉単価。1 円パチンコは千円あたりの玉数が 4 倍のため
/// ボーダーも 4 倍になる。
///
///   B = catalogBorder × (4.0 / ballPrice)
double effectiveBorder(double catalogBorder, double ballPrice) {
  if (ballPrice <= 0) return catalogBorder;
  return catalogBorder * (4.0 / ballPrice);
}

/// 1 本の区間(count イベント 1 回)を表す。グラフ描画に使う。
class RotationSegment {
  final int rotations; // この区間の回転数(差分)
  final EntryMode mode;

  /// この区間の投資相当額(円)。cash=現金投資額、ball=消費玉数×貸玉単価。
  /// 0 は計測外(旧データの持ち玉区間)。
  final int moneyYen;

  const RotationSegment({
    required this.rotations,
    required this.mode,
    this.moneyYen = 0,
  });

  /// 計測対象(投資相当が正)か。
  bool get measured => moneyYen > 0;

  /// 千円あたりの回転率(棒の高さ用)。計測外(moneyYen=0)は null。
  double? get ratePer1000 =>
      moneyYen > 0 ? rotations * 1000.0 / moneyYen : null;
}

/// セッションの計測結果。純粋計算の出力。
class RotationStats {
  /// 総回転数(cash + ball 全区間の合計。計測外の旧持ち玉も含む表示用)。
  final int totalRotations;

  /// 現金区間の総回転数。
  final int cashRotations;

  /// 現金投資額(円)。ヘッダーの「投資」表示に使う。
  final int cashInvest;

  /// 計測対象の総回転数(R / EV の分子)。cash + 計測対象 ball。
  final int measuredRotations;

  /// 計測対象の投資相当額(円)。cash 投資 + 持ち玉消費の円換算。
  final int measuredInvest;

  /// 回転率 R = 計測回転 / (計測投資相当 / 1000)。計測投資 0 なら null。
  final double? rotationRate;

  /// 実質ボーダー B。
  final double effectiveBorder;

  /// ボーダー比 = R − B。R が null のときは null。
  final double? borderDiff;

  /// 期待値 EV(円)。R が null / 0、または B が 0 のときは null。
  final double? expectedValue;

  /// count イベントごとの区間(グラフ用、時系列順、cash/ball 両方)。
  final List<RotationSegment> segments;

  /// 大当り回数(rebase イベントの数)。
  final int bonusCount;

  /// グラフ用の大当りマーカー位置。各要素は「その rebase までに現れた
  /// 計測対象区間(グラフに描く棒)の本数」。グラフはこの位置に◆を差し込む。
  /// 棒ではないので高さ・集計には影響しない。
  final List<int> rebaseMarkers;

  const RotationStats({
    required this.totalRotations,
    required this.cashRotations,
    required this.cashInvest,
    required this.measuredRotations,
    required this.measuredInvest,
    required this.rotationRate,
    required this.effectiveBorder,
    required this.borderDiff,
    required this.expectedValue,
    required this.segments,
    required this.bonusCount,
    this.rebaseMarkers = const [],
  });
}

/// 追記順(created_at / id 昇順)に並んだ [entries] からセッション統計を計算する。
///
/// - 回転数 = count イベントの counter と直前イベントの counter の差分。
/// - start / rebase は起点を付け替えるだけで、それ自体は回転・投資に加算しない。
/// - 投資相当(円): cash=invest_added、ball=balls_added × ballPrice。
///   持ち玉も回転率に算入する(250玉=1000円 at 4円 / 1000玉=1000円 at 1円)。
///   balls_added=0 の旧持ち玉区間は計測外(R/EV に含めない)。
/// - R = 計測回転 / (計測投資相当 / 1000)。
/// - EV = 計測回転 × (1000/B − 1000/R)。
///
/// [catalogBorder] はカタログの該当換金率ボーダー、[ballPrice] は貸玉単価。
RotationStats computeStats({
  required List<Entry> entries,
  required double catalogBorder,
  required double ballPrice,
}) {
  final border = effectiveBorder(catalogBorder, ballPrice);

  int total = 0;
  int cashRot = 0;
  int cashInvest = 0;
  int measuredRot = 0;
  int measuredYen = 0;
  int bonusCount = 0;
  int measuredCount = 0; // これまでに描いた計測対象の棒の本数(マーカー位置用)
  final segments = <RotationSegment>[];
  final rebaseMarkers = <int>[];

  int? prevCounter;

  for (final e in entries) {
    switch (e.type) {
      case EntryType.start:
        prevCounter = e.counter;
        break;
      case EntryType.rebase:
        prevCounter = e.counter;
        bonusCount++;
        rebaseMarkers.add(measuredCount); // ここまでの棒の本数=挿入位置
        break;
      case EntryType.count:
        if (prevCounter == null) {
          // start の無い count は起点を張るだけ(異常系の保険)。
          prevCounter = e.counter;
          break;
        }
        final diff = e.counter - prevCounter;
        prevCounter = e.counter;
        total += diff;

        // 投資相当(円)。cash は現金投資、ball は消費玉×貸玉単価。
        final int moneyYen = e.mode == EntryMode.cash
            ? e.investAdded
            : (e.ballsAdded * ballPrice).round();

        segments.add(RotationSegment(
          rotations: diff,
          mode: e.mode,
          moneyYen: moneyYen,
        ));

        if (e.mode == EntryMode.cash) {
          cashRot += diff;
          cashInvest += e.investAdded;
        }
        if (moneyYen > 0) {
          measuredRot += diff;
          measuredYen += moneyYen;
          measuredCount++;
        }
        break;
    }
  }

  final double? r =
      measuredYen > 0 ? measuredRot / (measuredYen / 1000.0) : null;

  final double? borderDiff = r == null ? null : r - border;

  double? ev;
  if (r != null && r > 0 && border > 0) {
    ev = measuredRot * (1000.0 / border - 1000.0 / r);
  }

  return RotationStats(
    totalRotations: total,
    cashRotations: cashRot,
    cashInvest: cashInvest,
    measuredRotations: measuredRot,
    measuredInvest: measuredYen,
    rotationRate: r,
    effectiveBorder: border,
    borderDiff: borderDiff,
    expectedValue: ev,
    segments: segments,
    bonusCount: bonusCount,
    rebaseMarkers: rebaseMarkers,
  );
}
