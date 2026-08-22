import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 画面背景 = ベース(#08090b)の上に、上端(または指定位置)から広がる薄いシアンの
/// グローを重ねた 2 層構造。CSS の `radial-gradient(rx% ry% at cx% cy%, ...)` を
/// 楕円(幅≠高さ)のまま再現する。
///
/// 画面ごとに強度([alpha])と広がり([radiusXFrac]/[radiusYFrac])・中心・減衰([stop])
/// だけ変える(計測画面は稼働中を暗示するため α を強めに)。
class GlowBackground extends StatelessWidget {
  final Widget child;

  /// グローの不透明度(シアン #56D9F0 に乗る 0..1)。
  final double alpha;

  /// 楕円の水平半径 = 画面幅の [radiusXFrac] 倍(CSS の 1 つ目, 例 1.25)。
  final double radiusXFrac;

  /// 楕円の垂直半径 = 画面高の [radiusYFrac] 倍(CSS の 2 つ目, 例 0.5)。
  final double radiusYFrac;

  /// 中心 X = 画面幅の [centerXFrac](例 0.5 = 50%)。
  final double centerXFrac;

  /// 中心 Y = 画面高の [centerYFrac](例 0.0 = 上辺, 0.82 = 下端寄り)。
  final double centerYFrac;

  /// 完全に透明になる位置(半径に対する割合, 例 0.58)。
  final double stop;

  const GlowBackground({
    super.key,
    required this.child,
    required this.alpha,
    required this.radiusXFrac,
    required this.radiusYFrac,
    this.centerXFrac = 0.5,
    this.centerYFrac = 0.0,
    required this.stop,
  });

  /// 計測画面(稼働中を暗示するため α 強め)。
  const GlowBackground.measurement({super.key, required this.child})
      : alpha = 0.11,
        radiusXFrac = 1.25,
        radiusYFrac = 0.5,
        centerXFrac = 0.5,
        centerYFrac = 0.0,
        stop = 0.58;

  /// スタート画面(機種選択)。
  const GlowBackground.start({super.key, required this.child})
      : alpha = 0.08,
        radiusXFrac = 1.2,
        radiusYFrac = 0.4,
        centerXFrac = 0.5,
        centerYFrac = 0.0,
        stop = 0.55;

  /// 履歴 / 設定(一覧系)。
  const GlowBackground.list({super.key, required this.child})
      : alpha = 0.07,
        radiusXFrac = 1.2,
        radiusYFrac = 0.4,
        centerXFrac = 0.5,
        centerYFrac = 0.0,
        stop = 0.55;

  /// ホーム(下端寄り = スタートボタンの後光)。
  const GlowBackground.home({super.key, required this.child})
      : alpha = 0.10,
        radiusXFrac = 0.9,
        radiusYFrac = 0.42,
        centerXFrac = 0.5,
        centerYFrac = 0.82,
        stop = 0.65;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlowPainter(
        alpha: alpha,
        rxFrac: radiusXFrac,
        ryFrac: radiusYFrac,
        cxFrac: centerXFrac,
        cyFrac: centerYFrac,
        stop: stop,
      ),
      child: child,
    );
  }
}

class _GlowPainter extends CustomPainter {
  final double alpha;
  final double rxFrac;
  final double ryFrac;
  final double cxFrac;
  final double cyFrac;
  final double stop;

  _GlowPainter({
    required this.alpha,
    required this.rxFrac,
    required this.ryFrac,
    required this.cxFrac,
    required this.cyFrac,
    required this.stop,
  });

  static const _cyan = Color(0xFF56D9F0);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // ベース。
    canvas.drawRect(rect, Paint()..color = AppColors.bg);

    final rx = rxFrac * size.width;
    final ry = ryFrac * size.height;
    if (rx <= 0 || ry <= 0 || alpha <= 0) return;

    final center = Offset(cxFrac * size.width, cyFrac * size.height);
    // 半径 ry の円を、中心 center.dx まわりに X 方向へ rx/ry 倍して楕円にする。
    // x' = k·x + cx·(1−k)。setEntry(row, col, value) で直接組む(deprecated API 回避)。
    final k = rx / ry;
    final m = Matrix4.identity()
      ..setEntry(0, 0, k)
      ..setEntry(0, 3, center.dx * (1 - k));
    final shader = ui.Gradient.radial(
      center,
      ry,
      [_cyan.withValues(alpha: alpha), _cyan.withValues(alpha: 0)],
      [0.0, stop.clamp(0.001, 1.0)],
      TileMode.clamp,
      m.storage,
    );
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.alpha != alpha ||
      old.rxFrac != rxFrac ||
      old.ryFrac != ryFrac ||
      old.cxFrac != cxFrac ||
      old.cyFrac != cyFrac ||
      old.stop != stop;
}
