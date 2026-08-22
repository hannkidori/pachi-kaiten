/// 履歴ログ 1 行。セッション終了時に計測データから自動算出した確定スナップショット。
///
/// 機種名などをデノーマライズ保存しているため、機種を削除・改名しても履歴は不変。
/// [machineName] は null=クイック計測(機種を選ばず計測)の履歴。
/// [rotationRate] は未計測(消化 0)なら null。
/// [investYen] / [plYen] は投資・回収の両方を入力したときだけ入る(片方だけ・
/// スキップなら null)。収支は消化額ではなく実際の投資額との差なので、
/// 持ち玉で回した分に影響されない。
class Trace {
  final int? id;
  final String date; // YYYY-MM-DD
  final String? machineName; // null=クイック計測
  final double? rotationRate; // 回/k
  final double? borderDiff; // ボーダー差分 R−B。ボーダー不明/クイックは null
  final int totalRotations;
  final int consumedYen; // 消化した総額(円。持ち玉で回した分も含む)
  final int bonusCount;
  final int? investYen; // 実際に入れた現金(円)。未記録なら null
  final int? plYen; // 回収 - 投資(円)。未記録なら null
  final String createdAt;

  const Trace({
    this.id,
    required this.date,
    this.machineName,
    this.rotationRate,
    this.borderDiff,
    required this.totalRotations,
    required this.consumedYen,
    required this.bonusCount,
    this.investYen,
    this.plYen,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'date': date,
      'machine_name': machineName,
      'rotation_rate': rotationRate,
      'border_diff': borderDiff,
      'total_rotations': totalRotations,
      'consumed_yen': consumedYen,
      'bonus_count': bonusCount,
      'invest_yen': investYen,
      'pl_yen': plYen,
      'created_at': createdAt,
    };
  }

  factory Trace.fromMap(Map<String, Object?> map) {
    return Trace(
      id: (map['id'] as num?)?.toInt(),
      date: map['date'] as String,
      machineName: map['machine_name'] as String?,
      rotationRate: (map['rotation_rate'] as num?)?.toDouble(),
      borderDiff: (map['border_diff'] as num?)?.toDouble(),
      totalRotations: (map['total_rotations'] as num).toInt(),
      consumedYen: (map['consumed_yen'] as num).toInt(),
      bonusCount: (map['bonus_count'] as num).toInt(),
      investYen: (map['invest_yen'] as num?)?.toInt(),
      plYen: (map['pl_yen'] as num?)?.toInt(),
      createdAt: map['created_at'] as String,
    );
  }
}
