import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

/// 作者の他のアプリ 1 件(設定画面の紹介欄に並べる)。
class OtherApp {
  final String name;
  final String description;
  final String appStoreId; // App Store の数値 ID(id を除いた部分)

  const OtherApp({
    required this.name,
    required this.description,
    required this.appStoreId,
  });

  /// App Store のアプリページ URL。
  String get storeUrl => 'https://apps.apple.com/jp/app/id$appStoreId';
}

/// 紹介する他アプリ。並び順がそのまま表示順。
const List<OtherApp> kOtherApps = [
  OtherApp(
    name: 'ハナジャグ',
    description: 'ハナハナ・ジャグラー専用の設定推測とデータ記録',
    appStoreId: '6792313623',
  ),
  OtherApp(
    name: 'コヤカン',
    description: '縦横対応の小役カウンター',
    appStoreId: '6801049251',
  ),
];

/// 紹介欄を出すかどうか。iOS のみ。
/// Play ストアには出していないため、Android では節ごと隠す(開けないリンクを見せない)。
/// dart:io の Platform ではなく defaultTargetPlatform を見るのは、テストで
/// 上書きして実際に描画・検証できるようにするため(実機での判定結果は同じ)。
bool get showsOtherApps => defaultTargetPlatform == TargetPlatform.iOS;

/// App Store のページを開く。iOS 以外・失敗時は何もしない。
///
/// url_launcher を足さず、iOS 側の MethodChannel で UIApplication.open を呼ぶ。
class AppStoreLauncher {
  static const MethodChannel channel = MethodChannel('pachi_kaiten/links');

  static Future<bool> open(OtherApp app) async {
    if (!showsOtherApps) return false;
    try {
      final ok = await channel
          .invokeMethod<bool>('open', <String, Object?>{'url': app.storeUrl});
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
