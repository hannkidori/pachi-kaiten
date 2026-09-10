import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// テンキーの左列に置く主役ボタン(決定 / 計測スタート)の指定。
///
/// 左手の親指が届く位置に確定操作を置くための構成で、テンキーの一部として
/// 同じグリッドに収める(別ボタンとして下に置かない)。
class NumpadCommit {
  final String label;
  final String? sub; // 「+1000円」など label の下に置く小さい行
  final VoidCallback onTap;
  final bool enabled;

  /// 大当り復帰の入力中はアンバーに切り替える。
  final bool hit;

  const NumpadCommit({
    required this.label,
    required this.onTap,
    this.sub,
    this.enabled = true,
    this.hit = false,
  });
}

/// 左手配置テンキー(4 列 × 4 行)。
///
/// - 左列: 上 2 行が ⌫、下 2 行が [commit](主役ボタン)。
///   [commit] が無い画面では ⌫ が 4 行を占める(空きマスを作らない)。
/// - 右 3 列: 1 2 3 / 4 5 6 / 7 8 9 / 00 0 C。
///
/// [onKey] に渡すキーは '0'〜'9' / '00' / 'C'(全消去) / '⌫'。
class Numpad extends StatelessWidget {
  final void Function(String key) onKey;
  final NumpadCommit? commit;
  final double keyHeight;
  final double spacing;

  const Numpad({
    super.key,
    required this.onKey,
    this.commit,
    this.keyHeight = 52,
    this.spacing = 8,
  });

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['00', '0', 'C'],
  ];

  @override
  Widget build(BuildContext context) {
    final left = commit == null
        ? _digit('⌫', height: keyHeight * 4 + spacing * 3)
        : Column(
            children: [
              SizedBox(
                height: keyHeight * 2 + spacing,
                child: _digit('⌫'),
              ),
              SizedBox(height: spacing),
              SizedBox(
                height: keyHeight * 2 + spacing,
                child: _commitKey(commit!),
              ),
            ],
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: spacing),
        // 数字は右 3 列。左列と同じ幅になるよう flex を 3 にする。
        Expanded(
          flex: 3,
          child: Column(
            children: [
              for (var r = 0; r < _rows.length; r++) ...[
                if (r > 0) SizedBox(height: spacing),
                SizedBox(
                  height: keyHeight,
                  child: Row(
                    children: [
                      for (var c = 0; c < 3; c++) ...[
                        if (c > 0) SizedBox(width: spacing),
                        Expanded(child: _digit(_rows[r][c])),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _digit(String label, {double? height}) {
    final isBack = label == '⌫';
    final isClear = label == 'C';
    final key = SizedBox(
      height: height,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onKey(label);
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          // ⌫(U+232B)は同梱フォントに無いため Material アイコンで描画する。
          child: isBack
              ? const Icon(Icons.backspace_outlined,
                  size: 20, color: AppColors.muted)
              : Text(
                  label,
                  style: AppTheme.mono(
                    size: isClear ? 13 : (label == '00' ? 20 : 24),
                    weight: FontWeight.w500,
                    color: isClear ? AppColors.muted : AppColors.text,
                  ),
                ),
        ),
      ),
    );
    return key;
  }

  Widget _commitKey(NumpadCommit c) {
    final on = c.enabled;
    final accent = c.hit ? AppColors.hit : AppColors.accent;
    return GestureDetector(
      onTap: on ? c.onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: on
              ? (c.hit ? const Color(0xFF2A1E06) : AppColors.accentFill)
              : AppColors.surfaceAlt,
          border:
              Border.all(color: on ? accent : AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.label,
                textAlign: TextAlign.center,
                style: AppTheme.sans(
                    size: 15,
                    weight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: 0.1 * 15,
                    color: on ? AppColors.text : AppColors.mutedDark)),
            if (c.sub != null) ...[
              const SizedBox(height: 4),
              Text(c.sub!,
                  style: AppTheme.mono(
                      size: 11,
                      weight: FontWeight.w600,
                      color: on ? accent : AppColors.faint)),
            ],
          ],
        ),
      ),
    );
  }
}

/// テンキー入力文字列を扱う小さなヘルパ(最大桁でクランプ)。
String applyKey(String current, String key, {int maxLen = 6}) {
  if (key == '⌫') {
    return current.isEmpty ? current : current.substring(0, current.length - 1);
  }
  if (key == 'C') return '';
  final next = current + key;
  return next.length > maxLen ? next.substring(0, maxLen) : next;
}
