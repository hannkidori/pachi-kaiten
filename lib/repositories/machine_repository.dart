import 'package:sqflite/sqflite.dart';

import '../models/machine.dart';

/// 機種マスタ(ユーザー登録型)の CRUD。UI からはインクリメンタル検索で引く。
class MachineRepository {
  final Database db;
  MachineRepository(this.db);

  Future<List<Machine>> all() async {
    // 並びは登録の新しい順。名前順は漢字がコード順に並んで探しにくいため使わない
    // (画面側で「最近使った順」を先頭に積む)。
    final rows = await db.query('machines', orderBy: 'id DESC');
    return rows.map(Machine.fromMap).toList();
  }

  Future<Machine?> byId(int id) async {
    final rows = await db.query('machines', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Machine.fromMap(rows.first);
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
}
