import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 打ち始め入力・計測画面で共有するカウンタ入力欄(再設計版)。
///
/// 左2:右8。左は「前回値=参照専用」(枠なし・一段暗い・タップ不能)、右が入力欄(主役)。
/// 「カウンタ」ラベルは持たない。3 状態:
/// - 初回(打ち始め): [prevCounter] が null → 前回「—」。
/// - 通常: [prevCounter] を「前回」として左に表示。
/// - 大当り復帰([rebase] true): 前回値を消しアンバーの文脈表示に切替、入力欄もアンバー。
class CounterField extends StatelessWidget {
  final String typed;
  final int? prevCounter; // null=初回(前回「—」)
  final bool rebase;
  final bool error; // 異常値: 枠を赤に
  final String placeholder;
  final double height;

  const CounterField({
    super.key,
    required this.typed,
    this.prevCounter,
    this.rebase = false,
    this.error = false,
    this.placeholder = '台の数字',
    this.height = 58,
  });

  @override
  Widget build(BuildContext context) {
    final Color boxBorder = error
        ? const Color(0xCCF06A5D)
        : rebase
            ? const Color(0x8CD9A85C)
            : const Color(0x5956D9F0);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左: 参照専用(枠なし・タップ不能)。
          Expanded(flex: 2, child: _reference()),
          const SizedBox(width: 12),
          // 右: 入力欄(主役)。
          Expanded(
            flex: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                border: Border.all(color: boxBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: typed.isEmpty
                          ? Text(placeholder,
                              style: AppTheme.sans(
                                  size: 14, color: AppColors.faint))
                          : Text(typed,
                              style: AppTheme.mono(
                                  size: 30, weight: FontWeight.w700)),
                    ),
                  ),
                  _Cursor(color: rebase ? AppColors.hit : AppColors.accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reference() {
    if (rebase) {
      // 前回値との連続性が切れるため数値は出さず、アンバーの文脈表示に切替。
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('大当り',
              style: AppTheme.sans(
                  size: 9,
                  weight: FontWeight.w600,
                  color: AppColors.hit,
                  letterSpacing: 0.1 * 9)),
          const SizedBox(height: 3),
          Text('復帰後の\n値を入力',
              style: AppTheme.sans(
                  size: 11, color: AppColors.hitText, height: 1.25)),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('前回',
            style: AppTheme.sans(
                size: 9, color: AppColors.muted, letterSpacing: 0.1 * 9)),
        const SizedBox(height: 3),
        Text(prevCounter?.toString() ?? '—',
            style: AppTheme.mono(size: 16, color: AppColors.mutedDark)),
      ],
    );
  }
}

/// 点滅カーソル(1.1s)。色は状態で切替(通常=シアン / 復帰=アンバー)。
class _Cursor extends StatefulWidget {
  final Color color;
  const _Cursor({required this.color});

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Opacity(
        opacity: _ctrl.value < 0.5 ? 1 : 0,
        child: Container(
          width: 2,
          height: 26,
          margin: const EdgeInsets.only(left: 3),
          color: widget.color,
        ),
      ),
    );
  }
}
