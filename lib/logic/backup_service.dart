import 'package:sqflite/sqflite.dart';

/// エクスポート専用。登録機種リストと足跡ログを JSON 化する(持ち出し用)。
///
/// v1 ではインポートは実装しない(受け入れは将来判断)。機種変更時に自分の
/// 育てたマスタと足跡を持ち出せることだけを担保する。
class BackupService {
  final Database db;
  BackupService(this.db);

  static const _tables = ['machines', 'traces'];
  static const schemaVersion = 3;

  /// machines + traces を 1 つの Map にエクスポートする。
  Future<Map<String, Object?>> exportData({String? exportedAt}) async {
    final data = <String, Object?>{
      'app': 'pachi_kaiten',
      'schema': schemaVersion,
      'exportedAt': ?exportedAt,
    };
    for (final t in _tables) {
      data[t] = await db.query(t);
    }
    return data;
  }
}
