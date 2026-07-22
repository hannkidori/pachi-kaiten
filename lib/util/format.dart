import 'package:intl/intl.dart';

final _grouped = NumberFormat('#,###');

/// マイナス記号は U+2212(−)を使い、等幅で桁が揃うようにする。
const _minus = '−';

/// 符号つき円。例: +2,840円 / −1,960円。
String fmtYenSigned(num v) {
  final n = v.round();
  final sign = n >= 0 ? '+' : _minus;
  return '$sign${_grouped.format(n.abs())}円';
}

/// 符号なし円(カンマ区切り)。例: 12,000円。
String fmtYen(num v) => '${_grouped.format(v.round())}円';

/// 符号つき数値(単位なし)。例: +2,840 / −1,960。足跡の EV 表示など。
String fmtSignedNum(num v) {
  final n = v.round();
  final sign = n >= 0 ? '+' : _minus;
  return '$sign${_grouped.format(n.abs())}';
}

/// 千円単位。例: 12.0k。
String fmtK(num yen) => '${(yen / 1000).toStringAsFixed(1)}k';

/// 回転率など小数1桁。null は "--.-"。
String fmtRate(double? v) => v == null ? '--.-' : v.toStringAsFixed(1);

/// 符号つきボーダー比。例: +1.7 / −0.8。null は空。
String fmtDiff(double? v) {
  if (v == null) return '';
  final sign = v >= 0 ? '+' : _minus;
  return '$sign${v.abs().toStringAsFixed(1)}';
}

/// 足跡の短い日付。'2026-07-22' → '7/22'。
String fmtShortDate(String yyyyMmDd) {
  final d = DateTime.tryParse(yyyyMmDd);
  if (d == null) return yyyyMmDd;
  return '${d.month}/${d.day}';
}

const _weekdayJp = ['月', '火', '水', '木', '金', '土', '日'];

/// 月チップのラベル。'2026-07' → '7月'。
String fmtMonthChip(String yyyyMm) {
  final mm = int.tryParse(yyyyMm.substring(5, 7)) ?? 0;
  return '$mm月';
}

/// 月見出し。'2026-07' → '7月収支'。
String fmtMonthTitle(String yyyyMm) => '${fmtMonthChip(yyyyMm)}収支';

/// 日ラベル。'2026-07-22' → '7/22 火'。
String fmtDayLabel(String yyyyMmDd) {
  final d = DateTime.tryParse(yyyyMmDd);
  if (d == null) return yyyyMmDd;
  final w = _weekdayJp[(d.weekday - 1) % 7];
  return '${d.month}/${d.day} $w';
}
