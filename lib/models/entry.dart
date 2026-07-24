/// 計測イベントの種別。
/// - [start]  : セッション開始。差分計算の起点となるカウンタ値。
/// - [count]  : 決定タップ。直前イベントとの差分が回転数。1 単位(1000/500円分)消化。
/// - [rebase] : 大当り復帰。差分計算の起点を付け替える(このイベント自体は
///              回転・消化に加算しない)。復帰後は通常状態に戻る。
enum EntryType { start, count, rebase }

/// 計測イベント(追記専用。UPDATE せず、取消は直前 1 件の物理 DELETE のみ)。
///
/// 現金/持ち玉の区別は持たない。決定は常に「1 単位(1000/500円分)消化した」の
/// 申告であり、[yen] にその単位額を記録する(持ち玉消費の千円換算はユーザーが
/// 頭の中で行い、決定として押す)。
class Entry {
  final int? id;
  final int sessionId;
  final EntryType type;
  final int counter; // 台のカウンタ値(入力生値)
  final int yen; // count: このイベントで消化した金額(円 = 加算単位 1000/500)
  final String createdAt;

  const Entry({
    this.id,
    required this.sessionId,
    required this.type,
    required this.counter,
    this.yen = 0,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'type': type.name,
      'counter': counter,
      'yen': yen,
      'created_at': createdAt,
    };
  }

  factory Entry.fromMap(Map<String, Object?> map) {
    return Entry(
      id: map['id'] as int?,
      sessionId: (map['session_id'] as num).toInt(),
      type: EntryType.values.byName(map['type'] as String),
      counter: (map['counter'] as num).toInt(),
      yen: (map['yen'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] as String,
    );
  }
}
