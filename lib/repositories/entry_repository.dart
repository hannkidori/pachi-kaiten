import 'package:sqflite/sqflite.dart';

import '../models/entry.dart';

/// 計測イベントの永続化。追記専用で、取消は直前の count 1 件の物理 DELETE のみ。
class EntryRepository {
  final Database db;
  EntryRepository(this.db);

  /// 追記して採番された id を返す。決定タップの瞬間に同期的に呼ぶ。
  Future<int> insert(Entry entry) async {
    return db.insert('entries', entry.toMap()..remove('id'));
  }

  /// セッションのイベントを追記順(id 昇順)に取得。
  Future<List<Entry>> bySession(int sessionId) async {
    final rows = await db.query(
      'entries',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(Entry.fromMap).toList();
  }

  /// セッションの最新イベント(1 件)。
  Future<Entry?> last(int sessionId) async {
    final rows = await db.query(
      'entries',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Entry.fromMap(rows.first);
  }

  /// 種別ごとの累計件数(全セッション通算)。レビュー依頼のしきい値判定に使う。
  /// 破棄されたセッションのイベントは削除済みなので数に入らない。
  Future<int> countOfType(EntryType type) async {
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM entries WHERE type = ?', [type.name]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 直前の 1 件が count のときだけ削除する(start / rebase は戻せない)。
  /// 削除したら true。
  Future<bool> deleteLastIfCount(int sessionId) async {
    final e = await last(sessionId);
    if (e == null || e.type != EntryType.count) return false;
    await db.delete('entries', where: 'id = ?', whereArgs: [e.id]);
    return true;
  }

  Future<void> deleteBySession(int sessionId) async {
    await db.delete('entries', where: 'session_id = ?', whereArgs: [sessionId]);
  }
}
