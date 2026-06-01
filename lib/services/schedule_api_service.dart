import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:http/http.dart' as http;

const int defaultScheduleUserId = 1;

class ScheduleApiService {
  ScheduleApiService({
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  // Windows 데스크톱에서 같은 PC의 FastAPI 서버에 접속하는 주소
  static const String _baseUrl = 'http://127.0.0.1:8010';

  // Android 에뮬레이터에서 실행할 때는 위 주소 대신 아래 주소 사용
  // static const String _baseUrl = 'http://10.0.2.2:8010';

  Future<ScheduleUser> createUser({
    required String displayName,
  }) async {
    final uri = Uri.parse('$_baseUrl/users');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'display_name': displayName,
      }),
    );

    _checkResponse(response, '사용자 생성 실패');

    return ScheduleUser.fromJson(_decodeMap(response));
  }

  Future<List<ScheduleTripSummary>> fetchUserTrips(int userId) async {
    final uri = Uri.parse('$_baseUrl/users/$userId/trips');

    final response = await _client.get(uri);

    _checkResponse(response, '사용자 일정 목록 조회 실패');

    final data = _decode(response);

    if (data is List) {
      return data
          .map((item) => ScheduleTripSummary.fromJson(_asMap(item)))
          .toList(growable: false);
    }

    if (data is Map<String, dynamic> && data['trips'] is List) {
      return (data['trips'] as List)
          .map((item) => ScheduleTripSummary.fromJson(_asMap(item)))
          .toList(growable: false);
    }

    throw Exception('사용자 일정 목록 응답 형식이 올바르지 않습니다.');
  }

  Future<ScheduleTripSummary> createTrip({
    required int userId,
    required String title,
    required String area,
  }) async {
    final uri = Uri.parse('$_baseUrl/users/$userId/trips');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'area': area,
      }),
    );

    _checkResponse(response, '여행 일정 생성 실패');

    return ScheduleTripSummary.fromJson(_decodeMap(response));
  }

  Future<ScheduleTripDay> createDay({
    required int tripId,
    required String label,
    required String title,
    required String area,
    required String totalTime,
    required String walkingDistance,
  }) async {
    final uri = Uri.parse('$_baseUrl/trips/$tripId/days');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'label': label,
        'title': title,
        'area': area,
        'total_time': totalTime,
        'walking_distance': walkingDistance,
      }),
    );

    _checkResponse(response, '여행 날짜 생성 실패');

    return ScheduleTripDay.fromJson(_decodeMap(response));
  }

  Future<SchedulePlace> createPlace({
    required int dayId,
    required String category,
    required String name,
    required String note,
    String? move,
    String? address,
    String? link,
    double? latitude,
    double? longitude,
    String? thumbnailUrl,
    String? imageUrl,
  }) async {
    final uri = Uri.parse('$_baseUrl/days/$dayId/places');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'category': category,
        'name': name,
        'note': note,
        'move': move,
        'address': address,
        'link': link,
        'latitude': latitude,
        'longitude': longitude,
        'thumbnail_url': thumbnailUrl,
        'image_url': imageUrl,
      }),
    );

    _checkResponse(response, '장소 생성 실패');

    return SchedulePlace.fromJson(_decodeMap(response));
  }

  Future<ScheduleTripDetail> fetchTrip(int tripId) async {
    final uri = Uri.parse('$_baseUrl/trips/$tripId');

    final response = await _client.get(uri);

    _checkResponse(response, '여행 일정 상세 조회 실패');

    return ScheduleTripDetail.fromJson(_decodeMap(response));
  }

  Future<void> deletePlace(int placeId) async {
    final uri = Uri.parse('$_baseUrl/places/$placeId');

    final response = await _client.delete(uri);

    _checkResponse(response, '장소 삭제 실패');
  }

  Future<List<ScheduledTripDestination>> fetchUserDestinations(
    int userId,
  ) async {
    final destinationDays = await fetchUserDestinationDays(userId);

    return destinationDays
        .expand((day) => day.destinations)
        .toList(growable: false);
  }

  Future<List<ScheduledTripDestinationDay>> fetchUserDestinationDays(
    int userId,
  ) async {
    final trips = await fetchUserTrips(userId);
    final result = <ScheduledTripDestinationDay>[];

    for (final trip in trips) {
      final detail = await fetchTrip(trip.id);

      for (final day in detail.days) {
        final destinations = <ScheduledTripDestination>[];

        for (final place in day.places) {
          if (place.latitude == null || place.longitude == null) {
            continue;
          }

          destinations.add(
            ScheduledTripDestination(
              id: 'place_${place.id}',
              name: place.name,
              description: place.note.isNotEmpty ? place.note : day.title,
              duration: place.move?.isNotEmpty == true
                  ? place.move!
                  : day.totalTime,
              position: NLatLng(place.latitude!, place.longitude!),
              icon: _iconForCategory(place.category),
            ),
          );
        }

        result.add(
          ScheduledTripDestinationDay(
            dayId: day.id,
            label: day.label,
            title: day.title,
            area: day.area,
            totalTime: day.totalTime,
            walkingDistance: day.walkingDistance,
            destinations: destinations,
          ),
        );
      }
    }

    return result;
  }

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }

    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final data = _decode(response);

    if (data is Map<String, dynamic>) {
      return data;
    }

    throw Exception('서버 응답 형식이 올바르지 않습니다.');
  }

  void _checkResponse(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$message: ${response.statusCode} ${response.body}');
    }
  }

  IconData _iconForCategory(String category) {
    if (category.contains('카페')) {
      return Icons.local_cafe_rounded;
    }

    if (category.contains('식사') ||
        category.contains('음식') ||
        category.contains('맛집')) {
      return Icons.restaurant_rounded;
    }

    if (category.contains('공원') || category.contains('산책')) {
      return Icons.park_rounded;
    }

    if (category.contains('역사') ||
        category.contains('문화') ||
        category.contains('궁')) {
      return Icons.account_balance_rounded;
    }

    if (category.contains('전망') || category.contains('야경')) {
      return Icons.landscape_rounded;
    }

    return Icons.place_rounded;
  }
}

class ScheduleUser {
  const ScheduleUser({
    required this.id,
    required this.displayName,
    required this.createdAt,
  });

  factory ScheduleUser.fromJson(Map<String, dynamic> json) {
    return ScheduleUser(
      id: _asInt(json['id']),
      displayName: json['display_name'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  final int id;
  final String displayName;
  final String createdAt;
}

class ScheduleTripSummary {
  const ScheduleTripSummary({
    required this.id,
    required this.userId,
    required this.title,
    required this.area,
    required this.createdAt,
  });

  factory ScheduleTripSummary.fromJson(Map<String, dynamic> json) {
    return ScheduleTripSummary(
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      title: json['title'] as String? ?? '',
      area: json['area'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  final int id;
  final int userId;
  final String title;
  final String area;
  final String createdAt;
}

class ScheduleTripDetail {
  const ScheduleTripDetail({
    required this.id,
    required this.userId,
    required this.title,
    required this.area,
    required this.createdAt,
    required this.days,
  });

  factory ScheduleTripDetail.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];

    return ScheduleTripDetail(
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      title: json['title'] as String? ?? '',
      area: json['area'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      days: rawDays is List
          ? rawDays
              .map((item) => ScheduleTripDay.fromJson(_asMap(item)))
              .toList(growable: false)
          : const [],
    );
  }

  final int id;
  final int userId;
  final String title;
  final String area;
  final String createdAt;
  final List<ScheduleTripDay> days;
}

class ScheduleTripDay {
  const ScheduleTripDay({
    required this.id,
    required this.tripId,
    required this.label,
    required this.title,
    required this.area,
    required this.totalTime,
    required this.walkingDistance,
    required this.sortOrder,
    required this.places,
  });

  factory ScheduleTripDay.fromJson(Map<String, dynamic> json) {
    final rawPlaces = json['places'];

    return ScheduleTripDay(
      id: _asInt(json['id']),
      tripId: _asInt(json['trip_id']),
      label: json['label'] as String? ?? '',
      title: json['title'] as String? ?? '',
      area: json['area'] as String? ?? '',
      totalTime: json['total_time'] as String? ?? '',
      walkingDistance: json['walking_distance'] as String? ?? '',
      sortOrder: _asInt(json['sort_order']),
      places: rawPlaces is List
          ? rawPlaces
              .map((item) => SchedulePlace.fromJson(_asMap(item)))
              .toList(growable: false)
          : const [],
    );
  }

  final int id;
  final int tripId;
  final String label;
  final String title;
  final String area;
  final String totalTime;
  final String walkingDistance;
  final int sortOrder;
  final List<SchedulePlace> places;
}

class SchedulePlace {
  const SchedulePlace({
    required this.id,
    required this.dayId,
    required this.category,
    required this.name,
    required this.note,
    required this.sortOrder,
    this.move,
    this.address,
    this.link,
    this.latitude,
    this.longitude,
    this.thumbnailUrl,
    this.imageUrl,
  });

  factory SchedulePlace.fromJson(Map<String, dynamic> json) {
    return SchedulePlace(
      id: _asInt(json['id']),
      dayId: _asInt(json['day_id']),
      category: json['category'] as String? ?? '',
      name: json['name'] as String? ?? '',
      note: json['note'] as String? ?? '',
      move: json['move'] as String?,
      address: json['address'] as String?,
      link: json['link'] as String?,
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      thumbnailUrl: json['thumbnail_url'] as String?,
      imageUrl: json['image_url'] as String?,
      sortOrder: _asInt(json['sort_order']),
    );
  }

  final int id;
  final int dayId;
  final String category;
  final String name;
  final String note;
  final String? move;
  final String? address;
  final String? link;
  final double? latitude;
  final double? longitude;
  final String? thumbnailUrl;
  final String? imageUrl;
  final int sortOrder;
}

class ScheduledTripDestinationDay {
  const ScheduledTripDestinationDay({
    required this.dayId,
    required this.label,
    required this.title,
    required this.area,
    required this.totalTime,
    required this.walkingDistance,
    required this.destinations,
  });

  final int dayId;
  final String label;
  final String title;
  final String area;
  final String totalTime;
  final String walkingDistance;
  final List<ScheduledTripDestination> destinations;
}

class ScheduledTripDestination {
  const ScheduledTripDestination({
    required this.id,
    required this.name,
    required this.description,
    required this.duration,
    required this.position,
    required this.icon,
  });

  final String id;
  final String name;
  final String description;
  final String duration;
  final NLatLng position;
  final IconData icon;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map(
      (key, mapValue) => MapEntry(key.toString(), mapValue),
    );
  }

  throw Exception('서버 응답 항목 형식이 올바르지 않습니다.');
}

int _asInt(dynamic value) {
  if (value == null) {
    return 0;
  }

  if (value is int) {
    return value;
  }

  if (value is double) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value) ?? 0;
  }

  return 0;
}

double? _asDouble(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is double) {
    return value;
  }

  if (value is int) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value);
  }

  return null;
}