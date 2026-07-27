import 'package:sqflite/sqflite.dart';

import '../models/trace.dart';

/// 足跡ログの永続化。セッション終了時に 1 行追記し、履歴は新しい順で読む。
/// 編集はできず、削除のみ(履歴画面の行タップ)。
class TraceRepository {
  final Database db;
  TraceRepository(this.db);

  /// 追記して採番された id を返す。
  Future<int> insert(Trace trace) async {
    return db.insert('traces', trace.toMap()..remove('id'));
  }

  /// 新しい順(日付降順→id 降順)に全件。履歴の時系列リスト用。
  Future<List<Trace>> allDesc() async {
    final rows = await db.query('traces', orderBy: 'date DESC, id DESC');
    return rows.map(Trace.fromMap).toList();
  }

  Future<void> delete(int id) async {
    await db.delete('traces', where: 'id = ?', whereArgs: [id]);
  }

  /// 総回転 0 以下の空足跡を削除する(旧バグで残った不正レコードの一掃)。
  /// 削除件数を返す。起動時に一度呼ぶ。
  Future<int> deleteEmpty() async {
    return db.delete('traces', where: 'total_rotations <= 0');
  }
}
