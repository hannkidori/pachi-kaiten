import 'package:sqflite/sqflite.dart';

/// バックアップ(エクスポート/インポート)。全テーブルを JSON 化する。
///
/// インポートは「上書き前に必ず現 DB のスナップショットを取ってから」実行する。
/// 間違ったファイル選択やインポート中断からの復旧経路を残すため。
class BackupService {
  final Database db;
  BackupService(this.db);

  static const _tables = ['stores', 'machines', 'sessions', 'entries', 'settings'];
  static const schemaVersion = 2;

  /// 全テーブルを 1 つの Map にエクスポートする。
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

  /// インポートデータの形を検証する(不正なら例外)。DB には触れない。
  static void validate(Map<String, Object?> data) {
    if (data['app'] != 'pachi_kaiten') {
      throw const FormatException('このアプリのバックアップではありません');
    }
    for (final t in _tables) {
      final v = data[t];
      if (v is! List) {
        throw FormatException('テーブル "$t" がありません');
      }
      for (final row in v) {
        if (row is! Map) {
          throw FormatException('テーブル "$t" の行が不正です');
        }
      }
    }
  }

  /// 検証済みデータでトランザクション上書きする(全消し→挿入、失敗時ロールバック)。
  Future<void> applyImport(Map<String, Object?> data) async {
    validate(data);
    await db.transaction((txn) async {
      for (final t in _tables) {
        await txn.delete(t);
        final rows = (data[t] as List).cast<Map>();
        for (final row in rows) {
          await txn.insert(t, row.cast<String, Object?>(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  /// 上書き前に現 DB を [writeBackup] へ渡してバックアップさせてから取り込む。
  ///
  /// 手順: (1) 取り込みデータを検証 → 不正なら中断(DB 無傷、バックアップ不要)
  ///       (2) 現 DB のスナップショットを取り [writeBackup] で保存
  ///       (3) トランザクションで上書き(失敗時はロールバック)
  Future<void> importWithBackup(
    Map<String, Object?> incoming, {
    required Future<void> Function(Map<String, Object?> snapshot) writeBackup,
    String? backupStamp,
  }) async {
    // (1) 先に検証。ここで失敗すれば上書きは起きない。
    validate(incoming);
    // (2) 現状のスナップショットをバックアップ。
    final snapshot = await exportData(exportedAt: backupStamp);
    await writeBackup(snapshot);
    // (3) 上書き。
    await applyImport(incoming);
  }
}
