import 'package:flutter/foundation.dart';
import 'dart:js_interop';
import 'dart:async';
import 'package:web/web.dart' as web;

// ============================================================================
// ① パーミッション要求 (iOS 13+ 必須 - ユーザーのジェスチャーから呼ぶこと)
// ============================================================================
Future<String> requestIOSCompassPermission() async {
  // JSスクリプトを注入してrequestPermission()を安全に呼び出す
  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.text = '''
    window._requestCompassPermission = function() {
      if (typeof DeviceOrientationEvent !== 'undefined' &&
          typeof DeviceOrientationEvent.requestPermission === 'function') {
        return DeviceOrientationEvent.requestPermission();
      }
      return Promise.resolve('not_supported');
    };
  ''';
  web.document.head?.appendChild(script);

  try {
    final promise = _jsRequestCompassPermission();
    final result = await promise.toDart;
    if (result != null) {
      return (result as JSString).toDart;
    }
    return 'unknown';
  } catch (e) {
    debugPrint('⚠️ requestIOSCompassPermission error: $e');
    return 'error';
  }
}

@JS('_requestCompassPermission')
external JSPromise _jsRequestCompassPermission();

// ============================================================================
// ② JSグローバル変数へのアクセサ
//    JS側でwindow._compassHeadingに最新の方位を保存し、Dartがポーリングする
// ============================================================================
@JS('window._compassHeading')
external JSNumber? get _jsCompassHeading;

// ============================================================================
// ③ JSリスナーセットアップ (一度だけ実行)
//    webkitCompassHeading (iOS) → 優先使用
//    360 - alpha (標準 / Android) → フォールバック
// ============================================================================
bool _jsListenerInitialized = false;

void _ensureJSCompassListenerSetup() {
  if (_jsListenerInitialized) return;
  _jsListenerInitialized = true;

  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.text = '''
    window._compassHeading = null;
    (function() {
      function onDeviceOrientation(event) {
        // iOS: webkitCompassHeading が最も正確
        if (typeof event.webkitCompassHeading === 'number' &&
            event.webkitCompassHeading >= 0) {
          window._compassHeading = event.webkitCompassHeading;
        } else if (event.absolute && typeof event.alpha === 'number') {
          // 標準 absolute orientation: 360 - alpha でコンパス方位に変換
          window._compassHeading = (360 - event.alpha) % 360;
        } else if (typeof event.alpha === 'number') {
          // 絶対方位でない場合も一応使う
          window._compassHeading = (360 - event.alpha) % 360;
        }
      }
      window.addEventListener('deviceorientation', onDeviceOrientation, true);
      window.addEventListener('deviceorientationabsolute', onDeviceOrientation, true);
    })();
  ''';
  web.document.head?.appendChild(script);
  debugPrint('🧭 JS compassリスナーを設定しました');
}

// ============================================================================
// ④ Dartストリーム (100msポーリング)
//    onOrientation.toJS は使わない → 信頼性の低いDart/JSコールバック変換を回避
// ============================================================================
Stream<double?> getIOSWebCompassStream() {
  // 最初にJSリスナーをセットアップ
  _ensureJSCompassListenerSetup();

  final controller = StreamController<double?>.broadcast();

  // 100msごとにJSグローバル変数をポーリング
  final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (controller.isClosed) return;
    try {
      final jsVal = _jsCompassHeading;
      if (jsVal != null) {
        final heading = jsVal.toDartDouble;
        if (heading >= 0 && heading <= 360) {
          controller.add(heading);
        }
      }
    } catch (e) {
      debugPrint('⚠️ コンパスポーリングエラー: $e');
    }
  });

  controller.onCancel = () {
    timer.cancel();
  };

  return controller.stream;
}
