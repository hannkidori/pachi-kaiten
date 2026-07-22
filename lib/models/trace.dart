/// 足跡ログ 1 行。セッション終了時に計測データから自動算出した確定スナップショット。
///
/// 機種名などをデノーマライズ保存しているため、機種を削除・改名しても足跡は不変。
/// [rotationRate] / [evYen] は未計測(投資 0)なら null。
/// [plYen] は回収額をスキップしたセッションでは null(P/L なし)。
class Trace {
  final int? id;
  final String date; // YYYY-MM-DD
  final String machineName;
  final double? rotationRate; // 回/k
  final int totalRotations;
  final int? evYen; // 期待値(円)
  final int investYen;
  final int bonusCount;
  final int? plYen; // 回収 - 投資(円)。回収スキップ時は null
  final String createdAt;

  const Trace({
    this.id,
    required this.date,
    required this.machineName,
    this.rotationRate,
    required this.totalRotations,
    this.evYen,
    required this.investYen,
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
      'total_rotations': totalRotations,
      'ev_yen': evYen,
      'invest_yen': investYen,
      'bonus_count': bonusCount,
      'pl_yen': plYen,
      'created_at': createdAt,
    };
  }

  factory Trace.fromMap(Map<String, Object?> map) {
    return Trace(
      id: (map['id'] as num?)?.toInt(),
      date: map['date'] as String,
      machineName: map['machine_name'] as String,
      rotationRate: (map['rotation_rate'] as num?)?.toDouble(),
      totalRotations: (map['total_rotations'] as num).toInt(),
      evYen: (map['ev_yen'] as num?)?.toInt(),
      investYen: (map['invest_yen'] as num).toInt(),
      bonusCount: (map['bonus_count'] as num).toInt(),
      plYen: (map['pl_yen'] as num?)?.toInt(),
      createdAt: map['created_at'] as String,
    );
  }
}
