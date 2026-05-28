import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/tmap_route.dart';
import 'tmap_config.dart';

class TmapRouteService {
  TmapRouteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<TmapRoute> fetchRoute({
    required TmapRouteMode mode,
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
    required String destinationName,
  }) {
    return switch (mode) {
      TmapRouteMode.transit =>
        TmapConfig.isTransitRouteEnabled
            ? _fetchTransitRoute(
                startLatitude: startLatitude,
                startLongitude: startLongitude,
                endLatitude: endLatitude,
                endLongitude: endLongitude,
              )
            : throw const TmapRouteException(
                'Tmap transit route API is temporarily disabled.',
              ),
      TmapRouteMode.car => _fetchCarRoute(
        startLatitude: startLatitude,
        startLongitude: startLongitude,
        endLatitude: endLatitude,
        endLongitude: endLongitude,
        destinationName: destinationName,
      ),
    };
  }

  Future<TmapRoute> _fetchTransitRoute({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) async {
    final response = await _client.post(
      Uri.parse('https://apis.openapi.sk.com/transit/routes'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'startX': '$startLongitude',
        'startY': '$startLatitude',
        'endX': '$endLongitude',
        'endY': '$endLatitude',
        'count': 1,
        'lang': 0,
        'format': 'json',
      }),
    );
    final payload = _decodeResponse(response);
    final itineraries = _asList(
      _asMap(_asMap(payload['metaData'])['plan'])['itineraries'],
    );

    if (itineraries.isEmpty) {
      throw const TmapRouteException('대중교통 경로를 찾지 못했습니다.');
    }

    final itinerary = _asMap(itineraries.first);
    final segments = <TmapRouteSegment>[];
    var index = 0;

    for (final rawLeg in _asList(itinerary['legs'])) {
      final leg = _asMap(rawLeg);
      final mode = '${leg['mode'] ?? ''}'.toUpperCase();
      final coordinates = mode == 'WALK'
          ? _walkCoordinates(leg)
          : _transitCoordinates(leg);

      if (coordinates.length < 2) {
        continue;
      }

      segments.add(
        TmapRouteSegment(
          id: 'transit_segment_${index++}',
          mode: mode == 'WALK'
              ? TmapRouteSegmentMode.walk
              : TmapRouteSegmentMode.transit,
          coordinates: coordinates,
          label: mode == 'WALK' ? '도보' : '${leg['route'] ?? mode}',
        ),
      );
    }

    if (segments.isEmpty) {
      throw const TmapRouteException('표시할 대중교통 경로 좌표가 없습니다.');
    }

    return TmapRoute(
      mode: TmapRouteMode.transit,
      segments: segments,
      totalTimeSeconds: _asInt(itinerary['totalTime']),
      totalDistanceMeters: _asInt(itinerary['totalDistance']),
      transferCount: _asInt(itinerary['transferCount']),
    );
  }

  Future<TmapRoute> _fetchCarRoute({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
    required String destinationName,
  }) async {
    final response = await _client.post(
      Uri.parse('https://apis.openapi.sk.com/tmap/routes?version=1'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'startX': startLongitude,
        'startY': startLatitude,
        'endX': endLongitude,
        'endY': endLatitude,
        'reqCoordType': 'WGS84GEO',
        'resCoordType': 'WGS84GEO',
        'startName': '현재 위치',
        'endName': destinationName,
        'searchOption': 0,
        'trafficInfo': 'Y',
      }),
    );
    final payload = _decodeResponse(response);
    final segments = <TmapRouteSegment>[];
    var totalTimeSeconds = 0;
    var totalDistanceMeters = 0;
    var index = 0;

    for (final rawFeature in _asList(payload['features'])) {
      final feature = _asMap(rawFeature);
      final geometry = _asMap(feature['geometry']);
      final properties = _asMap(feature['properties']);

      if (totalTimeSeconds == 0) {
        totalTimeSeconds = _asInt(properties['totalTime']);
      }
      if (totalDistanceMeters == 0) {
        totalDistanceMeters = _asInt(properties['totalDistance']);
      }

      if (geometry['type'] != 'LineString') {
        continue;
      }

      final coordinates = _coordinatesFromPairs(
        _asList(geometry['coordinates']),
      );
      if (coordinates.length < 2) {
        continue;
      }

      segments.add(
        TmapRouteSegment(
          id: 'car_segment_${index++}',
          mode: TmapRouteSegmentMode.car,
          coordinates: coordinates,
          label: '${properties['name'] ?? '자동차 경로'}',
        ),
      );
    }

    if (segments.isEmpty) {
      throw const TmapRouteException('자동차 경로를 찾지 못했습니다.');
    }

    return TmapRoute(
      mode: TmapRouteMode.car,
      segments: segments,
      totalTimeSeconds: totalTimeSeconds,
      totalDistanceMeters: totalDistanceMeters,
    );
  }

  Map<String, String> get _jsonHeaders => {
    'accept': 'application/json',
    'content-type': 'application/json',
    'appKey': TmapConfig.appKey,
  };

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmapRouteException('TMAP 경로 요청에 실패했습니다. (${response.statusCode})');
    }

    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload is! Map<String, dynamic>) {
      throw const TmapRouteException('TMAP 응답 형식이 올바르지 않습니다.');
    }

    return payload;
  }

  List<TmapCoordinate> _walkCoordinates(Map<String, dynamic> leg) {
    return _asList(leg['steps'])
        .expand((rawStep) {
          return _parseLineString('${_asMap(rawStep)['linestring'] ?? ''}');
        })
        .toList(growable: false);
  }

  List<TmapCoordinate> _transitCoordinates(Map<String, dynamic> leg) {
    final passShape = _asMap(leg['passShape']);
    return _parseLineString('${passShape['linestring'] ?? ''}');
  }

  List<TmapCoordinate> _parseLineString(String lineString) {
    return lineString
        .trim()
        .split(RegExp(r'\s+'))
        .where((point) {
          return point.isNotEmpty;
        })
        .map((point) {
          final pair = point.split(',');
          if (pair.length < 2) {
            return null;
          }

          final longitude = double.tryParse(pair[0]);
          final latitude = double.tryParse(pair[1]);
          if (longitude == null || latitude == null) {
            return null;
          }

          return TmapCoordinate(latitude: latitude, longitude: longitude);
        })
        .whereType<TmapCoordinate>()
        .toList(growable: false);
  }

  List<TmapCoordinate> _coordinatesFromPairs(List<dynamic> coordinates) {
    return coordinates
        .map((rawPair) {
          final pair = _asList(rawPair);
          if (pair.length < 2) {
            return null;
          }

          final longitude = _asDouble(pair[0]);
          final latitude = _asDouble(pair[1]);
          if (longitude == null || latitude == null) {
            return null;
          }

          return TmapCoordinate(latitude: latitude, longitude: longitude);
        })
        .whereType<TmapCoordinate>()
        .toList(growable: false);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }

  List<dynamic> _asList(dynamic value) {
    return value is List ? value : const [];
  }

  int _asInt(dynamic value) {
    return switch (value) {
      int number => number,
      num number => number.round(),
      String text => int.tryParse(text) ?? 0,
      _ => 0,
    };
  }

  double? _asDouble(dynamic value) {
    return switch (value) {
      double number => number,
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
  }
}

class TmapRouteException implements Exception {
  const TmapRouteException(this.message);

  final String message;

  @override
  String toString() => message;
}
