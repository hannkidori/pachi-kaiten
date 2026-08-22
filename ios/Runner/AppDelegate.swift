import Flutter
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // アプリ内レビュー依頼(App Store の星評価ダイアログ)を Dart から呼べるようにする。
    // 表示されたか / 星を付けたか / 閉じたかは OS が握っていて取得できないため、
    // 戻り値は「OS に依頼を投げた」ことだけを表す。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PachiKaitenReview") {
      let channel = FlutterMethodChannel(
        name: "pachi_kaiten/review",
        binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "requestReview" else {
          result(FlutterMethodNotImplemented)
          return
        }
        if #available(iOS 14.0, *) {
          // 前面のウィンドウシーンに紐づけて出す(iOS 14+ の作法)。
          let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
          guard let scene = scene else {
            result(false)
            return
          }
          SKStoreReviewController.requestReview(in: scene)
        } else {
          SKStoreReviewController.requestReview()
        }
        result(true)
      }

      // 設定画面の「作者の他のアプリ」から App Store のページを開く。
      // url_launcher を足さずに済ませるための最小の橋渡し。
      let linkChannel = FlutterMethodChannel(
        name: "pachi_kaiten/links",
        binaryMessenger: registrar.messenger())
      linkChannel.setMethodCallHandler { call, result in
        guard call.method == "open" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: Any],
              let raw = args["url"] as? String,
              let url = URL(string: raw) else {
          result(FlutterError(code: "bad_url", message: "url が不正です", details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          result(opened)
        }
      }
    }
  }
}
