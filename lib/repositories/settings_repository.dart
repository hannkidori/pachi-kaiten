import 'package:sqflite/sqflite.dart';

/// アプリ設定(key-value)。加算単位デフォルト・貸玉・スリープ防止など。
class SettingsRepository {
  final Database db;
  SettingsRepository(this.db);

  static const kAddUnit = 'add_unit_default';
  static const kKeepAwake = 'keep_awake';
  static const kBallPrice = 'ball_price'; // グローバル貸玉(4.0 / 1.0)
  static const kReviewStage = 'review_stage'; // レビュー依頼を出した回数(0..3)
  static const kReviewWaited = 'review_waited'; // 好条件待ちで見送った計測回数

  Future<String?> getString(String key) async {
    final rows =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setString(String key, String value) async {
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> addUnitDefault() async {
    final v = await getString(kAddUnit);
    return int.tryParse(v ?? '') ?? 1000;
  }

  Future<void> setAddUnitDefault(int unit) =>
      setString(kAddUnit, unit.toString());

  Future<bool> keepAwake() async {
    final v = await getString(kKeepAwake);
    return v == null ? true : v == '1'; // デフォルト ON
  }

  Future<void> setKeepAwake(bool on) =>
      setString(kKeepAwake, on ? '1' : '0');

  /// グローバル貸玉単価(4.0 / 1.0)。既定 4.0。
  Future<double> ballPrice() async {
    final v = await getString(kBallPrice);
    return double.tryParse(v ?? '') ?? 4.0;
  }

  Future<void> setBallPrice(double price) =>
      setString(kBallPrice, price.toString());

  /// レビュー依頼を出した回数。しきい値を消化した段数として使う。既定 0。
  Future<int> reviewStage() async {
    final v = await getString(kReviewStage);
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<void> setReviewStage(int stage) =>
      setString(kReviewStage, stage.toString());

  /// 資格を得たあと、好条件が来ないまま見送った計測の回数。既定 0。
  Future<int> reviewWaited() async {
    final v = await getString(kReviewWaited);
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<void> setReviewWaited(int n) =>
      setString(kReviewWaited, n.toString());
}
