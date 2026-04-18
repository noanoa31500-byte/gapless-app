import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      // BLE ペリフェラル (アドバタイズ) ネイティブチャンネルを登録
      BlePeripheralManager.register(with: controller.binaryMessenger)

      // バックグラウンド実行時間延長チャンネル
      // GATT接続・交換（最大~12秒）が完了するまで iOS にサスペンドを猶予させる
      let bgChannel = FlutterMethodChannel(
        name: "gapless/bg_task",
        binaryMessenger: controller.binaryMessenger
      )
      bgChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "begin":
          var taskId: UIBackgroundTaskIdentifier = .invalid
          taskId = UIApplication.shared.beginBackgroundTask(withName: "GapLess BLE exchange") {
            // 期限切れハンドラ: OSが強制終了する直前に自動クリーンアップ
            UIApplication.shared.endBackgroundTask(taskId)
          }
          result(NSNumber(value: taskId.rawValue))

        case "end":
          if let rawId = call.arguments as? Int {
            let id = UIBackgroundTaskIdentifier(rawValue: rawId)
            if id != .invalid {
              UIApplication.shared.endBackgroundTask(id)
            }
          }
          result(nil)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
