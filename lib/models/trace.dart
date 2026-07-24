/// 足跡ログ 1 行。セッション終了時に計測データから自動算出した確定スナップショット。
///
/// 機種名などをデノーマライズ保存しているため、機種を削除・改名しても足跡は不変。
/// [machineName] は null=クイック計測(機種を選ばず計測)の足跡。
/// [rotationRate] / [evYen] は未計測(消化 0)なら null。
/// [plYen] は回収額をスキップしたセッションでは null(P/L なし)。
class Trace {
  final int? id;
  final String date; // YYYY-MM-DD
  final String? machineName; // null=クイック計測
  final double? rotationRate; // 回/k
  final double? borderDiff; // ボーダー差分 R−B。ボーダー不明/クイックは null
  final int totalRotations;
  final int? evYen; // 期待値(円)
  final int consumedYen; // 消化した総額(円)
  final int bonusCount;
  final int? plYen; // 回収 - 消化(円)。回収スキップ時は null
  final String createdAt;

  const Trace({
    this.id,
    required this.date,
    this.machineName,
    this.rotationRate,
    this.borderDiff,
    required this.totalRotations,
    this.evYen,
    required this.consumedYen,
    required this.bonusCount,
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
      'ev_yen': evYen,
      'consumed_yen': consumedYen,
      'bonus_count': bonusCount,
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
      evYen: (map['ev_yen'] as num?)?.toInt(),
      consumedYen: (map['consumed_yen'] as num).toInt(),
      bonusCount: (map['bonus_count'] as num).toInt(),
      plYen: (map['pl_yen'] as num?)?.toInt(),
      createdAt: map['created_at'] as String,
    );
  }
}
