// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'package:web/web.dart' as web;

class WebBridge {
  static void listenForOfflineEvent(Function() onOffline) {
    // Listen for standard offline event
    web.window.addEventListener(
        'offline',
        (web.Event event) {
          onOffline();
        }.toJS);

    // Listen for custom forced event (if triggered by script)
    web.window.addEventListener(
        'force_disaster_mode',
        (web.Event event) {
          onOffline();
        }.toJS);
  }

  static void listenForOnlineEvent(Function() onOnline) {
    // Listen for standard online event
    web.window.addEventListener(
        'online',
        (web.Event event) {
          onOnline();
        }.toJS);
  }
}
