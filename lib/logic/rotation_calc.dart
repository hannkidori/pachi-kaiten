import '../models/entry.dart';

/// 1 本の区間(count イベント 1 回)を表す。グラフ描画に使う。
class RotationSegment {
  final int rotations; // この区間の回転数(差分)
  final int yen; // この区間で消化した金額(円 = 加算単位)

  const RotationSegment({
    required this.rotations,
    required this.yen,
  });
}

/// グラフ表示用の棒(1 本 = 1000 円分)。加算単位 500 円のときは決定 2 回で 1 本になる。
/// 500 円分だけ入力された未完成の棒は complete=false(半透明・判定なし)で描く。
class ChartBar {
  /// この棒の回転数。完成 = 1000 円分(500 円×2 は合計)、未完成 = 500 円 1 回分の生値。
  final int rotations;

  /// true = 1000 円分に到達した完成棒 / false = 500 円分だけの未完成棒。
  final bool complete;

  const ChartBar({required this.rotations, required this.complete});
}

/// グラフ描画用データ(棒列 + 大当りマーカー位置)。
class ChartData {
  final List<ChartBar> bars;

  /// bars 上の◆挿入位置(その位置の棒の前に入る)。
  final List<int> markers;

  const ChartData({required this.bars, required this.markers});
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
    required this.segments,
    required this.bonusCount,
    this.rebaseMarkers = const [],
  });

  /// グラフ表示用データ(1 本 = 1000 円分にまとめ、大当りマーカーも棒基準へ変換)。
  /// 計算値(総回転・R・EV)には一切影響しない、純粋な表示変換。
  ChartData get chartData => buildChartData(segments, rebaseMarkers);
}

/// 追記順(created_at / id 昇順)に並んだ [entries] からセッション統計を計算する。
///
/// - 回転数 = count イベントの counter と直前イベントの counter の差分。
/// - start / rebase は起点を付け替えるだけで、それ自体は回転・消化に加算しない。
/// - 消化額(円): count の yen(= 加算単位 1000/500)をそのまま足す。
/// - R = 総回転 / (消化額 / 1000)。
///
/// 期待値(円)は出さない。円換算には交換率と持ち玉比率の前提が要るが、アプリは
/// どちらも持たないため、ボーダー比 R − B までを事実として示すに留める。
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

  return RotationStats(
    totalRotations: total,
    consumedYen: consumed,
    rotationRate: r,
    border: border,
    borderDiff: borderDiff,
    segments: segments,
    bonusCount: bonusCount,
    rebaseMarkers: rebaseMarkers,
  );
}

/// count 区間([segments])を「1 本 = 1000 円分」の棒列にまとめる(表示専用)。
///
/// - 1000 円分の count は 1 本の完成棒。
/// - 500 円分の count は 2 回連続で 1 本の完成棒(回転数は 2 回分の合計)。
/// - 500 円分が 1 回だけ残った状態は未完成棒(complete=false)。
/// - 未完成のまま 1000 円分の count が来た場合、その未完成棒はそのまま確定し、
///   1000 円分は新しい完成棒として始まる(単位切替時の半端棒がそのまま記録になる)。
///
/// [rebaseMarkers](= count 本数基準の◆位置)は、まとめた後の棒本数基準へ変換する。
ChartData buildChartData(List<RotationSegment> segments, List<int> rebaseMarkers) {
  final bars = <ChartBar>[];
  // boundary[k] = 先頭 k 区間が占める棒スロット数(未完成の保留も 1 スロットとして数える)。
  // マーカー位置(count 本数基準)を棒本数基準へ変換するために使う。
  final boundary = <int>[0];
  int finalized = 0; // 確定済みの棒本数
  int? pending; // 未完成(500 円分)の回転数。null = 保留なし。
  for (final seg in segments) {
    if (seg.yen >= 1000) {
      if (pending != null) {
        // 半端な 500 円分はそのまま未完成棒として確定させる。
        bars.add(ChartBar(rotations: pending, complete: false));
        finalized++;
        pending = null;
      }
      bars.add(ChartBar(rotations: seg.rotations, complete: true));
      finalized++;
    } else {
      if (pending == null) {
        pending = seg.rotations;
      } else {
        // 2 回目の 500 円分で 1000 円分に到達 → 合計して完成棒。
        bars.add(ChartBar(rotations: pending + seg.rotations, complete: true));
        finalized++;
        pending = null;
      }
    }
    boundary.add(finalized + (pending != null ? 1 : 0));
  }
  if (pending != null) {
    bars.add(ChartBar(rotations: pending, complete: false));
  }
  final markers = <int>[
    for (final m in rebaseMarkers)
      (m >= 0 && m < boundary.length) ? boundary[m] : bars.length,
  ];
  return ChartData(bars: bars, markers: markers);
}
