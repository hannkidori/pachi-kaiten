/// セッション状態。
enum SessionState { active, closed }

/// セッション(= 1 台の計測単位)。
///
/// [ballPrice] は開始時点のグローバル貸玉設定(4.0 / 1.0)をコピーして固定する
/// (後から設定を変えても過去のセッションは変わらない)。ボーダーは機種側の
/// スロットを参照するため、セッションには持たない。
class Session {
  final int? id;
  final String date; // YYYY-MM-DD(開始日)
  final int machineId;
  final double ballPrice;
  final int addUnit; // 決定 1 回の投資加算額(1000 / 500)
  final SessionState state;
  final int? recovery; // 回収額(円)。任意(スキップ可)
  final String startedAt;
  final String? closedAt;

  const Session({
    this.id,
    required this.date,
    required this.machineId,
    required this.ballPrice,
    this.addUnit = 1000,
    this.state = SessionState.active,
    this.recovery,
    required this.startedAt,
    this.closedAt,
  });

  bool get isActive => state == SessionState.active;

  Session copyWith({
    int? id,
    String? date,
    int? machineId,
    double? ballPrice,
    int? addUnit,
    SessionState? state,
    int? recovery,
    String? startedAt,
    String? closedAt,
  }) {
    return Session(
      id: id ?? this.id,
      date: date ?? this.date,
      machineId: machineId ?? this.machineId,
      ballPrice: ballPrice ?? this.ballPrice,
      addUnit: addUnit ?? this.addUnit,
      state: state ?? this.state,
      recovery: recovery ?? this.recovery,
      startedAt: startedAt ?? this.startedAt,
      closedAt: closedAt ?? this.closedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'date': date,
      'machine_id': machineId,
      'ball_price': ballPrice,
      'add_unit': addUnit,
      'state': state.name,
      'recovery': recovery,
      'started_at': startedAt,
      'closed_at': closedAt,
    };
  }

  factory Session.fromMap(Map<String, Object?> map) {
    return Session(
      id: map['id'] as int?,
      date: map['date'] as String,
      machineId: (map['machine_id'] as num).toInt(),
      ballPrice: (map['ball_price'] as num).toDouble(),
      addUnit: (map['add_unit'] as num).toInt(),
      state: (map['state'] as String) == 'closed'
          ? SessionState.closed
          : SessionState.active,
      recovery: (map['recovery'] as num?)?.toInt(),
      startedAt: map['started_at'] as String,
      closedAt: map['closed_at'] as String?,
    );
  }
}
