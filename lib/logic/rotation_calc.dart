import '../models/entry.dart';

/// 1 本の区間(count イベント 1 回)を表す。グラフ描画に使う。
class RotationSegment {
  final int rotations; // この区間の回転数(差分)
  final int yen; // この区間で消化した金額(円 = 加算単位)

  const RotationSegment({
    required this.rotations,
    required this.yen,
  });

  /// 千円あたりの回転率(棒の高さ用)。
  double get ratePer1000 => yen > 0 ? rotations * 1000.0 / yen : 0;
}

/// セッションの計測結果。純粋計算の出力。
class RotationStats {
  /// 総回転数(全 count 区間の合計)。
  final int totalRotations;

  /// 消化した総額(円)。ヘッダーの「消化」表示・P/L の基準に使う。
  final int consumedYen;

  /// 回転率 R = 総回転 / (消化額 / 1000)。消化 0 なら null。
  final double? rotationRate;

  /// 判定ボーダー B(ユーザーが入力した機種スロットのボーダーそのまま)。
  /// 0 はボーダー未設定(クイック計測)。
  final double border;

  /// ボーダーがあるか(クイック計測は false)。
  bool get hasBorder => border > 0;

  /// ボーダー比 = R − B。R が null / ボーダー未設定のときは null。
  final double? borderDiff;

  /// 期待値 EV(円、10円単位丸め)。R が null / 0、または B が 0 のときは null。
  final double? expectedValue;

  /// count イベントごとの区間(グラフ用、時系列順)。
  final List<RotationSegment> segments;

  /// 大当り回数(rebase イベントの数)。
  final int bonusCount;

  /// グラフ用の大当りマーカー位置。各要素は「その rebase までに現れた
  /// 区間(グラフに描く棒)の本数」。グラフはこの位置に◆を差し込む。
  /// 棒ではないので高さ・集計には影響しない。
  final List<int> rebaseMarkers;

  const RotationStats({
    required this.totalRotations,
    required this.consumedYen,
    required this.rotationRate,
    required this.border,
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
/// - start / rebase は起点を付け替えるだけで、それ自体は回転・消化に加算しない。
/// - 消化額(円): count の yen(= 加算単位 1000/500)をそのまま足す。
/// - R = 総回転 / (消化額 / 1000)。
/// - EV = 消化額 × (R − B) / B(10円単位丸め)。
///
/// [border] はユーザーが入力した機種スロットのボーダー(補正せずそのまま使う)。
/// 0 はボーダー未設定(クイック計測)= 判定・EV を出さない。
RotationStats computeStats({
  required List<Entry> entries,
  required double border,
}) {
  int total = 0;
  int consumed = 0;
  int bonusCount = 0;
  int barCount = 0; // これまでに描いた棒の本数(マーカー位置用)
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
        rebaseMarkers.add(barCount); // ここまでの棒の本数=挿入位置
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
        consumed += e.yen;

        segments.add(RotationSegment(rotations: diff, yen: e.yen));
        barCount++;
        break;
    }
  }

  final double? r = consumed > 0 ? total / (consumed / 1000.0) : null;

  final bool hasBorder = border > 0;
  final double? borderDiff =
      (r == null || !hasBorder) ? null : r - border;

  double? ev;
  if (r != null && r > 0 && hasBorder) {
    final raw = consumed * (r - border) / border;
    ev = (raw / 10).round() * 10.0; // 10円単位丸め
  }

  return RotationStats(
    totalRotations: total,
    consumedYen: consumed,
    rotationRate: r,
    border: border,
    borderDiff: borderDiff,
    expectedValue: ev,
    segments: segments,
    bonusCount: bonusCount,
    rebaseMarkers: rebaseMarkers,
  );
}
