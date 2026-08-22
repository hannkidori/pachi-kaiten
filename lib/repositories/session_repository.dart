import 'package:sqflite/sqflite.dart';

import '../models/session.dart';

/// セッションの永続化。開始・終了(回収額確定)・復帰カード用のアクティブ取得を担う。
/// 履歴は履歴ログ(traces)側に集約したため、集計系クエリはここには持たない。
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
    await db.update(
      'sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
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

  /// 最近使った機種 id を新しい順に(重複除去)。機種検索の先頭表示用。
  /// クイック計測(machine_id = NULL)は機種を持たないため対象外にする。
  Future<List<int>> recentMachineIds({int limit = 8}) async {
    final rows = await db.rawQuery(
      'SELECT machine_id, MAX(started_at) AS last FROM sessions '
      'WHERE machine_id IS NOT NULL '
      'GROUP BY machine_id ORDER BY last DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) => (r['machine_id'] as num).toInt()).toList();
  }

  Future<void> delete(int id) async {
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }
}
