import 'package:sqflite/sqflite.dart';

/// アプリ設定(key-value)。加算単位デフォルト・スリープ防止・機種マスタ版など。
class SettingsRepository {
  final Database db;
  SettingsRepository(this.db);

  static const kAddUnit = 'add_unit_default';
  static const kKeepAwake = 'keep_awake';
  static const kMachinesVersion = 'machines_version';

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

  Future<String?> machinesVersion() => getString(kMachinesVersion);

  Future<void> setMachinesVersion(String version) =>
      setString(kMachinesVersion, version);
}
