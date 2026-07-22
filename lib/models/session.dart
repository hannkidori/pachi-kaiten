/// セッション状態。
enum SessionState { active, closed }

/// セッション(= 1 台の計測単位)。
///
/// [exchangeRate] / [ballPrice] は開始時点の店舗値をコピーして固定する
/// (後から店舗を編集しても過去のセッションは変わらない)。
class Session {
  final int? id;
  final String date; // YYYY-MM-DD(開始日)
  final int storeId;
  final String machineId;
  final double exchangeRate;
  final double ballPrice;
  final int addUnit; // 決定 1 回の投資加算額(1000 / 500)
  final SessionState state;
  final int? recovery; // 回収額(円)。closed 時に必須
  final String startedAt;
  final String? closedAt;

  const Session({
    this.id,
    required this.date,
    required this.storeId,
    required this.machineId,
    required this.exchangeRate,
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
    int? storeId,
    String? machineId,
    double? exchangeRate,
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
      storeId: storeId ?? this.storeId,
      machineId: machineId ?? this.machineId,
      exchangeRate: exchangeRate ?? this.exchangeRate,
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
      'store_id': storeId,
      'machine_id': machineId,
      'exchange_rate': exchangeRate,
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
      storeId: (map['store_id'] as num).toInt(),
      machineId: map['machine_id'] as String,
      exchangeRate: (map['exchange_rate'] as num).toDouble(),
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
