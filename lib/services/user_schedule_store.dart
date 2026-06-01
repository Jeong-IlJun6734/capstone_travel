import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

const defaultRouteInUserId = 'demo-user';

class UserScheduleStore {
  UserScheduleStore._();

  static final UserScheduleStore instance = UserScheduleStore._();

  final Map<String, ValueNotifier<List<ScheduledTripDestination>>> _notifiers =
      {};

  ValueListenable<List<ScheduledTripDestination>> listenableForUser(
    String userId,
  ) {
    return _notifierForUser(userId);
  }

  List<ScheduledTripDestination> destinationsForUser(String userId) {
    return List.unmodifiable(_notifierForUser(userId).value);
  }

  void addDestination(String userId, ScheduledTripDestination destination) {
    final notifier = _notifierForUser(userId);
    final destinations = List<ScheduledTripDestination>.from(notifier.value);
    destinations.removeWhere((item) => item.id == destination.id);
    destinations.add(destination);
    notifier.value = List.unmodifiable(destinations);
  }

  void removeDestination(String userId, String destinationId) {
    final notifier = _notifierForUser(userId);
    notifier.value = List.unmodifiable(
      notifier.value.where((item) => item.id != destinationId),
    );
  }

  ValueNotifier<List<ScheduledTripDestination>> _notifierForUser(
    String userId,
  ) {
    return _notifiers.putIfAbsent(
      userId,
      () => ValueNotifier<List<ScheduledTripDestination>>(_seedDestinations),
    );
  }
}

class ScheduledTripDestination {
  const ScheduledTripDestination({
    required this.id,
    required this.name,
    required this.description,
    required this.duration,
    required this.position,
    required this.icon,
    required this.category,
  });

  final String id;
  final String name;
  final String description;
  final String duration;
  final NLatLng position;
  final IconData icon;
  final String category;
}

const _seedDestinations = [
  ScheduledTripDestination(
    id: 'seed_1',
    name: '경복궁',
    description: '서울 대표 고궁에서 여행을 시작합니다.',
    duration: '8분',
    position: NLatLng(37.579617, 126.977041),
    icon: Icons.photo_camera_outlined,
    category: '관광',
  ),
  ScheduledTripDestination(
    id: 'seed_2',
    name: '북촌한옥마을',
    description: '한옥 골목을 따라 다음 장소로 이동합니다.',
    duration: '15분',
    position: NLatLng(37.582604, 126.983998),
    icon: Icons.park_outlined,
    category: '산책',
  ),
  ScheduledTripDestination(
    id: 'seed_3',
    name: '인사동길',
    description: '전통 공예와 찻집이 있는 거리에서 일정을 마칩니다.',
    duration: '12분',
    position: NLatLng(37.574471, 126.984955),
    icon: Icons.flag_outlined,
    category: '문화',
  ),
];
