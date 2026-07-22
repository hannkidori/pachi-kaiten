import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// 3 列テンキー。キーは '0'〜'9' / '00' / '⌫'(バックスペース)。
/// 計測画面・スタート画面・回収額入力で共有する。
class Numpad extends StatelessWidget {
  /// 押されたキー('0'〜'9' / '00' / '⌫')。
  final void Function(String key) onKey;
  final double keyHeight;
  final double spacing;

  const Numpad({
    super.key,
    required this.onKey,
    this.keyHeight = 48,
    this.spacing = 8,
  });

  static const _keys = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '⌫',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = (constraints.maxWidth - spacing * 2) / 3;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final k in _keys)
            SizedBox(width: w, height: keyHeight, child: _key(k)),
        ],
      );
    });
  }

  Widget _key(String label) {
    final isBack = label == '⌫';
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onKey(label);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: const Color(0x12FFFFFF)),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTheme.mono(
            size: label == '00' ? 18 : (isBack ? 19 : 24),
            weight: FontWeight.w500,
            color: isBack ? AppColors.muted : AppColors.text,
          ),
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
  final next = current + key;
  return next.length > maxLen ? next.substring(0, maxLen) : next;
}
