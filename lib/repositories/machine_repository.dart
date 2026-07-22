import 'package:sqflite/sqflite.dart';

import '../models/machine.dart';

/// 機種マスタ(ユーザー登録型)の CRUD。UI からはインクリメンタル検索で引く。
class MachineRepository {
  final Database db;
  MachineRepository(this.db);

  Future<List<Machine>> all() async {
    final rows = await db.query('machines', orderBy: 'name ASC');
    return rows.map(Machine.fromMap).toList();
  }

  Future<Machine?> byId(int id) async {
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

  /// 新規登録して採番された id つきの [Machine] を返す。
  Future<Machine> insert(Machine machine) async {
    final id = await db.insert('machines', machine.toMap()..remove('id'));
    return machine.copyWith(id: id);
  }

  Future<void> update(Machine machine) async {
    assert(machine.id != null, 'update には id が必要');
    await db.update('machines', machine.toMap(),
        where: 'id = ?', whereArgs: [machine.id]);
  }

  Future<void> delete(int id) async {
    await db.delete('machines', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM machines');
    return (rows.first['c'] as num).toInt();
  }
}
