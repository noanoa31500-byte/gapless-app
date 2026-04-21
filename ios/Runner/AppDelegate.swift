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
      let messenger = controller.binaryMessenger

      // BLE ペリフェラル (アドバタイズ) ネイティブチャンネルを登録
      BlePeripheralManager.register(with: messenger)

      // バックグラウンド実行時間延長チャンネル
      let bgChannel = FlutterMethodChannel(name: "gapless/bg_task", binaryMessenger: messenger)
      bgChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "begin":
          var taskId: UIBackgroundTaskIdentifier = .invalid
          taskId = UIApplication.shared.beginBackgroundTask(withName: "GapLess BLE exchange") {
            UIApplication.shared.endBackgroundTask(taskId)
          }
          result(NSNumber(value: taskId.rawValue))
        case "end":
          if let rawId = call.arguments as? Int {
            let id = UIBackgroundTaskIdentifier(rawValue: rawId)
            if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
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
