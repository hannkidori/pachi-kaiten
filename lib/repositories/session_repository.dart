import 'package:sqflite/sqflite.dart';

import '../models/session.dart';

/// セッションの永続化。開始・終了(回収額確定)・復帰カード用のアクティブ取得・
/// 履歴(月別/日別)取得を担う。
class SessionRepository {
  final Database db;
  SessionRepository(this.db);

  /// 挿入して採番された id つきの [Session] を返す。
  Future<Session> insert(Session session) async {
    final id = await db.insert('sessions', session.toMap()..remove('id'));
    return session.copyWith(id: id);
  }

  Future<void> update(Session session) async {
    assert(session.id != null, 'update には id が必要');
    await db.update('sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  Future<Session?> byId(int id) async {
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Session.fromMap(rows.first);
  }

  /// 計測中(state='active')のセッション。復帰カードの判定に使う。
  /// 通常 1 件のはずだが、保険として最新の 1 件を返す。
  Future<Session?> active() async {
    final rows = await db.query(
      'sessions',
      where: "state = 'active'",
      orderBy: 'started_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Session.fromMap(rows.first);
  }

  /// 終了済みセッションを開始日の新しい順に。
  Future<List<Session>> allClosed() async {
    final rows = await db.query(
      'sessions',
      where: "state = 'closed'",
      orderBy: 'date DESC, started_at DESC',
    );
    return rows.map(Session.fromMap).toList();
  }

  /// 指定月(YYYY-MM)の終了済みセッション。
  Future<List<Session>> closedByMonth(String yyyyMm) async {
    final rows = await db.query(
      'sessions',
      where: "state = 'closed' AND date LIKE ?",
      whereArgs: ['$yyyyMm-%'],
      orderBy: 'date DESC, started_at DESC',
    );
    return rows.map(Session.fromMap).toList();
  }

  /// 記録のある月(YYYY-MM)を新しい順に。履歴の月チップ用。
  Future<List<String>> months() async {
    final rows = await db.rawQuery(
      "SELECT DISTINCT substr(date, 1, 7) AS ym FROM sessions "
      "WHERE state = 'closed' ORDER BY ym DESC",
    );
    return rows.map((r) => r['ym'] as String).toList();
  }

  /// 直近セッションの店舗 id(スタート画面の「前回値」デフォルト用)。無ければ null。
  Future<int?> recentStoreId() async {
    final rows = await db.query('sessions',
        columns: ['store_id'],
        orderBy: 'started_at DESC, id DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['store_id'] as num).toInt();
  }

  /// 最近使った機種 id を新しい順に(重複除去)。機種検索の先頭表示用。
  Future<List<String>> recentMachineIds({int limit = 8}) async {
    final rows = await db.rawQuery(
      'SELECT machine_id, MAX(started_at) AS last FROM sessions '
      'GROUP BY machine_id ORDER BY last DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['machine_id'] as String).toList();
  }

  Future<void> delete(int id) async {
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }
}
