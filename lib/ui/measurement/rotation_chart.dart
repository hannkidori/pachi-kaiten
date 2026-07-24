import 'package:flutter/material.dart';

import '../../logic/rotation_calc.dart';
import '../../theme/app_theme.dart';

// グラフの色ルール(確定済み区間はボーダー判定色)。
// 判定ルール: ボーダー以上=ティール / 未満=赤。最新(右端)の棒はシアン。
const Color chartBarAbove = Color(0x6656D9F0); // ボーダー以上(ティール)
const Color chartBarBelow = Color(0x52F06A5D); // ボーダー未満(赤)
const Color chartBarLatest = AppColors.accent; // 最新の棒(シアン)
const Color chartBarNeutral = Color(0x29FFFFFF); // クイック計測(判定なし)
const Color chartLabelAbove = Color(0xFF5A7A82);
const Color chartLabelBelow = AppColors.downDim;

/// 確定済み区間の棒色。ボーダー以上=ティール / 未満=赤。
Color chartBarColor(double ratePer1000, double border) {
  return ratePer1000 < border ? chartBarBelow : chartBarAbove;
}

/// 確定済み区間の数値ラベル色(現金・持ち玉共通)。
Color chartLabelColor(double ratePer1000, double border) =>
    ratePer1000 < border ? chartLabelBelow : chartLabelAbove;

/// 「千円ごとの回転」グラフ。
///
/// 与えられた高さ制約に必ず収まる(オーバーフローしない)ことを保証する:
/// ヘッダ・余白・ラベル・棒・破線の合計が LayoutBuilder の maxHeight を超えない
/// よう、上から順に「入るぶんだけ」確保する。棒の余地が無ければラベルごと隠す。
/// ボーダー破線はスクロールせず、領域の可視全幅に固定表示する。
class RotationChart extends StatelessWidget {
  final RotationStats stats;
  final ScrollController? controller;

  const RotationChart({super.key, required this.stats, this.controller});

  static const double _header = 14;
  static const double _headerGap = 5;
  static const double _label = 15;
  static const double _barGap = 3;
  static const double _maxBar = 48;

  /// 設計上の理想の高さ(これ以上は与えられても使わない)。
  static const double maxTotal =
      _header + _headerGap + _barGap + _label + _maxBar;

  @override
  Widget build(BuildContext context) {
    // 各 count 区間を棒にする。
    final segs = stats.segments;
    final border = stats.border;
    final hasBorder = stats.hasBorder;
    final barVals = segs.map((s) => s.ratePer1000).toList();
    final maxV = [if (hasBorder) border + 3, 1.0, ...barVals]
        .reduce((a, b) => a > b ? a : b);
    final linePct = (border / maxV).clamp(0.0, 0.96);

    return LayoutBuilder(
      builder: (context, constraints) {
        final avail =
            (constraints.maxHeight.isFinite ? constraints.maxHeight : maxTotal)
                .clamp(0.0, maxTotal);

        // 上から順に、入るぶんだけ確保する(合計は avail を超えない)。
        final header = _header.clamp(0.0, avail);
        final afterHeader = avail - header;
        final headerGap =
            (header > 0 ? _headerGap : 0.0).clamp(0.0, afterHeader);
        final bodyH = (afterHeader - headerGap).clamp(0.0, afterHeader);
        final label = _label.clamp(0.0, bodyH);
        final barGap = _barGap.clamp(0.0, bodyH - label);
        final barArea = (bodyH - label - barGap).clamp(0.0, bodyH);
        // header + headerGap + barArea + barGap + label == avail

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header > 0)
              SizedBox(
                height: header,
                child: ClipRect(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('千円分ごとの回転',
                          style: AppTheme.sans(
                              size: 9, color: AppColors.mutedDark)),
                      if (hasBorder)
                        Text('B=${border.toStringAsFixed(1)}',
                            style: AppTheme.mono(
                                size: 9, color: AppColors.mutedDark)),
                    ],
                  ),
                ),
              ),
            if (headerGap > 0) SizedBox(height: headerGap),
            SizedBox(
              height: bodyH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 破線: 可視全幅に固定(スクロールしない)。棒領域内の border 位置。
                  // クイック計測(ボーダー未設定)では出さない。
                  if (hasBorder)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: barArea * (1 - linePct),
                      child: const _DashedLine(),
                    ),
                  // 棒とラベルは横スクロール。棒の余地が無ければ描かない
                  // (「棒が無くラベルだけ」を避ける)。
                  if (segs.isNotEmpty && barArea > 0)
                    SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      child: _Bars(
                        segs: segs,
                        barVals: barVals,
                        border: border,
                        hasBorder: hasBorder,
                        maxV: maxV,
                        barArea: barArea,
                        labelH: label,
                        barGap: barGap,
                        markers: stats.rebaseMarkers,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Bars extends StatelessWidget {
  final List<RotationSegment> segs;
  final List<double> barVals;
  final double border;
  final bool hasBorder;
  final double maxV;
  final double barArea;
  final double labelH;
  final double barGap;

  /// 大当りマーカーの位置(その rebase までに現れた区間の本数)。
  final List<int> markers;

  const _Bars({
    required this.segs,
    required this.barVals,
    required this.border,
    required this.hasBorder,
    required this.maxV,
    required this.barArea,
    required this.labelH,
    required this.barGap,
    required this.markers,
  });

  static const double _barW = 22;
  static const double _markerW = 14;

  @override
  Widget build(BuildContext context) {
    // 棒列とラベル列を並行に組み立てる(列を揃えるためラベル側にも同じ幅の
    // マーカー枠を入れる)。位置 p では「マーカー(◆)→ 棒」の順に並べる。
    final barCells = <Widget>[];
    final labelCells = <Widget>[];
    var first = true;
    void add(Widget bar, Widget label) {
      if (!first) {
        barCells.add(const SizedBox(width: 5));
        labelCells.add(const SizedBox(width: 5));
      }
      first = false;
      barCells.add(bar);
      labelCells.add(label);
    }

    for (var p = 0; p <= segs.length; p++) {
      for (final m in markers) {
        if (m == p) {
          add(_marker(), const SizedBox(width: _markerW));
        }
      }
      if (p < segs.length) {
        add(_bar(barVals[p], isLatest: p == segs.length - 1), _label(p));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: barArea,
          child:
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: barCells),
        ),
        SizedBox(height: barGap),
        // ラベル。高さは labelH に固定され、収まらなければ Text が自然にクリップ
        // される(RenderFlex オーバーフローは起きない)。
        SizedBox(
          height: labelH,
          child: ClipRect(child: Row(children: labelCells)),
        ),
      ],
    );
  }

  Widget _bar(double val, {required bool isLatest}) {
    final h = (val / maxV * barArea).clamp(0.0, barArea);
    // 最新の棒は常にシアン。それ以外は hasBorder なら判定色、クイックはニュートラル。
    final Color color = isLatest
        ? chartBarLatest
        : (hasBorder ? chartBarColor(val, border) : chartBarNeutral);
    return Container(
      width: _barW,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
    );
  }

  Widget _label(int i) {
    // ラベル色: hasBorder なら判定色、クイックはニュートラル。
    final color = hasBorder
        ? chartLabelColor(barVals[i], border)
        : AppColors.mutedDark;
    return SizedBox(
      width: _barW,
      child: Text(
        '${segs[i].rotations}',
        textAlign: TextAlign.center,
        maxLines: 1,
        style: AppTheme.mono(size: 10, color: color),
      ),
    );
  }

  /// 大当り(rebase)位置の区切り記号。棒ではないので高さ・集計に影響しない。
  Widget _marker() {
    return SizedBox(
      width: _markerW,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Text('◆',
            style: AppTheme.mono(size: 9, color: AppColors.hit)),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const dash = 4.0, gap = 4.0;
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
      final count = (w / (dash + gap)).floor().clamp(0, 200);
      return Row(
        children: List.generate(
          count,
          (_) => Container(
            width: dash,
            height: 1,
            margin: const EdgeInsets.only(right: gap),
            color: const Color(0x47FFFFFF),
          ),
        ),
      );
    });
  }
}
