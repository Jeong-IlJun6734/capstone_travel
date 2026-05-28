import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

abstract final class NaverMapConfig {
  static const clientId = 'lb8l7xq5sp';
  static var _isReady = false;

  static bool get hasClientId => clientId.isNotEmpty;

  static bool get isReady => _isReady;

  static bool get supportsMobileMap {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<void> initialize() async {
    if (!supportsMobileMap || !hasClientId) {
      return;
    }

    await FlutterNaverMap().init(clientId: clientId);
    _isReady = true;
  }
}
