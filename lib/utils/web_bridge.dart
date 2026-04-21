import 'web_bridge_stub.dart' if (dart.library.html) 'web_bridge_web.dart';

class WebBridgeInterface {
  static void listenForOfflineEvent(Function() onOffline) {
    WebBridge.listenForOfflineEvent(onOffline);
  }

  static void listenForOnlineEvent(Function() onOnline) {
    WebBridge.listenForOnlineEvent(onOnline);
  }
}
