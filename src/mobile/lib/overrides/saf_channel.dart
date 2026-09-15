import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SafChannel {
  static const _channel = MethodChannel('music_anti_blur/saf');

  static Future<bool> takePersistable(String uri) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    if (!uri.startsWith('content://')) {
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('takePersistable', {'uri': uri});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
