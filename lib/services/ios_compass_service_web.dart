import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:async';
import 'package:web/web.dart' as web;

/// Web implementation using modern package:web and dart:js_interop
/// This targets the DeviceOrientationEvent.requestPermission() API on iOS 13+
Future<String> requestIOSCompassPermission() async {
  // Define helper JS function to safely call requestPermission
  // This avoids complexity with checking undefined properties on the window/DeviceOrientationEvent object type in Dart
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
  web.document.body!.appendChild(script);

  try {
    final promise = _callRequestCompassPermission();
    final resultAny = await promise.toDart;
    
    // Result is JSAny? (which is actually a String from JS)
    if (resultAny != null) {
       // Safe conversion
       return (resultAny as JSString).toDart; 
    }
    return 'unknown';
    
  } catch (e) {
    print('Error requesting compass permission: $e');
    return 'error';
  }
}

// Define external function to call the JS global we just injected
@JS('_requestCompassPermission')
external JSPromise _callRequestCompassPermission();

/// Fallback: Get raw compass stream using direct JS event listener
/// This bypasses flutter_compass if it fails to pick up the permission change.
Stream<double?> getIOSWebCompassStream() {
  final controller = StreamController<double?>.broadcast();
  
  void onOrientation(web.Event event) {
     final deviceOrientation = event as web.DeviceOrientationEvent;
     
     // Check for webkitCompassHeading (iOS specific) using js_interop_unsafe
     // deviceOrientation is a JSObject wrapper in package:web
     final jsObj = deviceOrientation as JSObject;
     
     if (jsObj.has('webkitCompassHeading')) {
        final heading = jsObj['webkitCompassHeading'];
        if (heading != null) {
           // heading is a JSNumber
           controller.add((heading as JSNumber).toDartDouble);
           return;
        }
     }
     
     // Fallback to standard alpha if visible (often null on desktop, dependent on absolute layout)
     if (deviceOrientation.alpha != null) {
       // Convert alpha to double? Alpha is usually degrees
       controller.add(deviceOrientation.alpha);
     } else {
       controller.add(null);
     }
  }

  // Subscribe using standard addEventListener
  final callback = onOrientation.toJS;
  web.window.addEventListener('deviceorientation', callback);
  
  controller.onCancel = () {
    web.window.removeEventListener('deviceorientation', callback);
  };
  
  return controller.stream;
}

