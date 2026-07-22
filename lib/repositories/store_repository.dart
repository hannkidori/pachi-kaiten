import 'package:sqflite/sqflite.dart';

import '../models/store.dart';

/// 店舗マスタの CRUD。
class StoreRepository {
  final Database db;
  StoreRepository(this.db);

  Future<List<Store>> all() async {
    final rows = await db.query('stores', orderBy: 'sort_order ASC, id ASC');
    return rows.map(Store.fromMap).toList();
  }

  Future<Store?> byId(int id) async {
    final rows = await db.query('stores', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Store.fromMap(rows.first);
  }

  /// 挿入して採番された id つきの [Store] を返す。
  Future<Store> insert(Store store) async {
    final id = await db.insert('stores', store.toMap()..remove('id'));
    return store.copyWith(id: id);
  }

  Future<void> update(Store store) async {
    assert(store.id != null, 'update には id が必要');
    await db.update('stores', store.toMap(),
        where: 'id = ?', whereArgs: [store.id]);
  }

  Future<void> delete(int id) async {
    await db.delete('stores', where: 'id = ?', whereArgs: [id]);
  }
}
