/// 機種マスタ。ボーダーは各換金率ごとに保持する(等価=[border40] は必須)。
class Machine {
  final String id;
  final String name;
  final double probability; // 大当り確率の分母(319.6 など)
  final double border40; // 4.0円(等価)ボーダー
  final double? border357; // 3.57円
  final double? border33; // 3.3円
  final double? border303; // 3.03円
  final String? type; // ミドル / ライト / 甘 など
  final String? updatedAt;

  const Machine({
    required this.id,
    required this.name,
    required this.probability,
    required this.border40,
    this.border357,
    this.border33,
    this.border303,
    this.type,
    this.updatedAt,
  });

  /// 換金率に対応するカタログ上のボーダー(千円あたり回転数、4円貸し基準)。
  ///
  /// 該当換金率のボーダーが未登録の場合は等価([border40])にフォールバックする。
  double borderForRate(double exchangeRate) {
    if (exchangeRate >= 3.99) return border40;
    if (exchangeRate >= 3.5) return border357 ?? border40;
    if (exchangeRate >= 3.15) return border33 ?? border357 ?? border40;
    return border303 ?? border33 ?? border357 ?? border40;
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'probability': probability,
      'border_40': border40,
      'border_357': border357,
      'border_33': border33,
      'border_303': border303,
      'type': type,
      'updated_at': updatedAt,
    };
  }

  factory Machine.fromMap(Map<String, Object?> map) {
    return Machine(
      id: map['id'] as String,
      name: map['name'] as String,
      probability: (map['probability'] as num).toDouble(),
      border40: (map['border_40'] as num).toDouble(),
      border357: (map['border_357'] as num?)?.toDouble(),
      border33: (map['border_33'] as num?)?.toDouble(),
      border303: (map['border_303'] as num?)?.toDouble(),
      type: map['type'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  /// machines.json の 1 エントリ({ "borders": { "4.0": .. } } 形式)から生成。
  factory Machine.fromJson(Map<String, Object?> json, {String? version}) {
    final borders = (json['borders'] as Map).cast<String, Object?>();
    double? b(String key) => (borders[key] as num?)?.toDouble();
    return Machine(
      id: json['id'] as String,
      name: json['name'] as String,
      probability: (json['probability'] as num).toDouble(),
      border40: b('4.0')!,
      border357: b('3.57'),
      border33: b('3.3'),
      border303: b('3.03'),
      type: json['type'] as String?,
      updatedAt: version,
    );
  }
}
