import 'package:sqflite/sqflite.dart';

import '../models/machine.dart';

/// 機種マスタ。JSON 同期は UPSERT、UI からはインクリメンタル検索で引く。
class MachineRepository {
  final Database db;
  MachineRepository(this.db);

  Future<List<Machine>> all() async {
    final rows = await db.query('machines', orderBy: 'name ASC');
    return rows.map(Machine.fromMap).toList();
  }

  Future<Machine?> byId(String id) async {
    final rows = await db.query('machines', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Machine.fromMap(rows.first);
  }

  /// 機種名の部分一致検索(大文字小文字無視)。空クエリは全件。
  Future<List<Machine>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return all();
    final rows = await db.query(
      'machines',
      where: 'name LIKE ?',
      whereArgs: ['%$q%'],
      orderBy: 'name ASC',
    );
    return rows.map(Machine.fromMap).toList();
  }

  /// machines.json 由来のリストを UPSERT する(既存 id は上書き)。
  Future<void> upsertAll(List<Machine> machines) async {
    final batch = db.batch();
    for (final m in machines) {
      batch.insert('machines', m.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// マスタを丸ごと [machines] に置き換える(全削除→挿入。トランザクション)。
  /// 同梱アセット更新時のミラー用。旧マスタの取りこぼしを残さない。
  Future<void> replaceAll(List<Machine> machines) async {
    await db.transaction((txn) async {
      await txn.delete('machines');
      final batch = txn.batch();
      for (final m in machines) {
        batch.insert('machines', m.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int> count() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM machines');
    return (rows.first['c'] as num).toInt();
  }
}
