/// 計測イベントの種別。
/// - [start]  : セッション開始。差分計算の起点となるカウンタ値。
/// - [count]  : 決定タップ。直前イベントとの差分が回転数。
/// - [rebase] : 大当り復帰。差分計算の起点を付け替える(このイベント自体は
///              回転・投資に加算しない)。以降の [mode] は 'ball' になる。
enum EntryType { start, count, rebase }

/// 投資モード。cash=現金、ball=持ち玉。
enum EntryMode { cash, ball }

/// 計測イベント(追記専用。UPDATE せず、取消は直前 1 件の物理 DELETE のみ)。
class Entry {
  final int? id;
  final int sessionId;
  final EntryType type;
  final int counter; // 台のカウンタ値(入力生値)
  final EntryMode mode;
  final int investAdded; // cash: このイベントで加算された現金投資額(円)
  final int ballsAdded; // ball: このイベントで消費した持ち玉数(玉)。0=計測外(旧データ)
  final String createdAt;

  const Entry({
    this.id,
    required this.sessionId,
    required this.type,
    required this.counter,
    required this.mode,
    this.investAdded = 0,
    this.ballsAdded = 0,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'type': type.name,
      'counter': counter,
      'mode': mode.name,
      'invest_added': investAdded,
      'balls_added': ballsAdded,
      'created_at': createdAt,
    };
  }

  factory Entry.fromMap(Map<String, Object?> map) {
    return Entry(
      id: map['id'] as int?,
      sessionId: (map['session_id'] as num).toInt(),
      type: EntryType.values.byName(map['type'] as String),
      counter: (map['counter'] as num).toInt(),
      mode: (map['mode'] as String) == 'ball' ? EntryMode.ball : EntryMode.cash,
      investAdded: (map['invest_added'] as num?)?.toInt() ?? 0,
      ballsAdded: (map['balls_added'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] as String,
    );
  }
}
