/// アプリ全体の定数。
class AppConfig {
  AppConfig._();

  /// 機種マスタ配信元(GitHub raw)。空文字なら同期はスキップされる。
  static const machinesUrl =
      'https://raw.githubusercontent.com/hannkidori/pachi-kaiten/main/data/machines.json';
}
