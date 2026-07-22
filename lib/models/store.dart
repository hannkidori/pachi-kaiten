/// 店舗プロファイル。
///
/// [exchangeRate] は換金率(4.0=等価 / 3.57 / 3.3 / 3.03)、
/// [ballPrice] は貸玉単価(4.0円 / 1.0円)。
class Store {
  final int? id;
  final String name;
  final double exchangeRate;
  final double ballPrice;
  final int sortOrder;

  const Store({
    this.id,
    required this.name,
    required this.exchangeRate,
    this.ballPrice = 4.0,
    this.sortOrder = 0,
  });

  Store copyWith({
    int? id,
    String? name,
    double? exchangeRate,
    double? ballPrice,
    int? sortOrder,
  }) {
    return Store(
      id: id ?? this.id,
      name: name ?? this.name,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      ballPrice: ballPrice ?? this.ballPrice,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'exchange_rate': exchangeRate,
      'ball_price': ballPrice,
      'sort_order': sortOrder,
    };
  }

  factory Store.fromMap(Map<String, Object?> map) {
    return Store(
      id: map['id'] as int?,
      name: map['name'] as String,
      exchangeRate: (map['exchange_rate'] as num).toDouble(),
      ballPrice: (map['ball_price'] as num).toDouble(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
