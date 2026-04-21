import 'dart:async';
import 'dart:io';

class ConnectivityService {
  static Future<bool> isConnected() async {
    try {
      final result = await InternetAddress.lookup('connectivitycheck.gstatic.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Stream<bool> get onConnectivityChanged {
    return Stream.periodic(const Duration(seconds: 5))
        .asyncMap((_) => isConnected())
        .distinct();
  }
}
