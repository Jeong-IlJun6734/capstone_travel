import 'package:flutter/foundation.dart';

import 'naver_directions_service.dart';

class NaverMoveTimeCacheService {
  NaverMoveTimeCacheService._();

  static final NaverMoveTimeCacheService instance =
      NaverMoveTimeCacheService._();

  final NaverDirectionsService _directionsService =
      const NaverDirectionsService();
  final Map<String, Future<String>> _moveTimeCache = <String, Future<String>>{};

  Future<String> drivingMoveTime({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    final key = _cacheKey(
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      endLatitude: endLatitude,
      endLongitude: endLongitude,
    );

    return _moveTimeCache.putIfAbsent(key, () async {
      final summary = await _directionsService.drivingSummary(
        startLatitude: startLatitude,
        startLongitude: startLongitude,
        endLatitude: endLatitude,
        endLongitude: endLongitude,
      );

      return _formatMoveSummary(summary);
    });
  }

  void clear() {
    _moveTimeCache.clear();
  }

  String _cacheKey({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    return [
      _roundCoordinate(startLatitude),
      _roundCoordinate(startLongitude),
      _roundCoordinate(endLatitude),
      _roundCoordinate(endLongitude),
    ].join('|');
  }

  String _roundCoordinate(double value) {
    return value.toStringAsFixed(5);
  }

  String _formatMoveSummary(NaverDirectionSummary summary) {
    final minutes = summary.durationMinutes;
    final distance = summary.distanceMeters >= 1000
        ? '${(summary.distanceMeters / 1000).toStringAsFixed(1)}km'
        : '${summary.distanceMeters}m';
    return '자동차 약 $minutes분 · $distance';
  }
}

@visibleForTesting
void clearNaverMoveTimeCacheForTests() {
  NaverMoveTimeCacheService.instance.clear();
}
