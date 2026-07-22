/// 機種マスタ(ユーザー登録型)。
///
/// ボーダーは「4円用」「1円用」の 2 スロットを持つ(どちらも任意・最低 1 つ)。
/// 計測開始時、グローバル貸玉設定に応じて該当スロットの値をそのまま使う。
/// ×4 等の自動換算はしない — 1パチのボーダーは 4パチの単純 4 倍にならないため、
/// 両方ともユーザーの入力値が正。
class Machine {
  final int? id;
  final String name;
  final double? border4; // 4円貸し用ボーダー(回/k)
  final double? border1; // 1円貸し用ボーダー(回/k)
  final String? updatedAt;

  const Machine({
    this.id,
    required this.name,
    this.border4,
    this.border1,
    this.updatedAt,
  });

  /// 貸玉単価に対応するスロットのボーダー。未入力なら null。
  /// 1.5 円を境に 1円用 / 4円用を選ぶ(貸玉は 4.0 / 1.0 のみ)。
  double? borderFor(double ballPrice) => ballPrice <= 1.5 ? border1 : border4;

  Machine copyWith({
    int? id,
    String? name,
    double? border4,
    double? border1,
    String? updatedAt,
  }) {
    return Machine(
      id: id ?? this.id,
      name: name ?? this.name,
      border4: border4 ?? this.border4,
      border1: border1 ?? this.border1,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'border_4': border4,
      'border_1': border1,
      'updated_at': updatedAt,
    };
  }

  factory Machine.fromMap(Map<String, Object?> map) {
    return Machine(
      id: (map['id'] as num?)?.toInt(),
      name: map['name'] as String,
      border4: (map['border_4'] as num?)?.toDouble(),
      border1: (map['border_1'] as num?)?.toDouble(),
      updatedAt: map['updated_at'] as String?,
    );
  }
}
