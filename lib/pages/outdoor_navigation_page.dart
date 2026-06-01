import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';

import '../models/tmap_route.dart';
import '../services/naver_map_config.dart';
import '../services/naver_move_time_cache_service.dart';
import '../services/schedule_api_service.dart';
import '../services/tmap_config.dart';
import '../services/tmap_route_service.dart';
import '../theme/route_in_palette.dart';

class OutdoorNavigationPage extends StatefulWidget {
  const OutdoorNavigationPage({super.key, this.userId = defaultScheduleUserId});

  final int userId;

  @override
  State<OutdoorNavigationPage> createState() => _OutdoorNavigationPageState();
}

class _OutdoorNavigationPageState extends State<OutdoorNavigationPage> {
  final ScheduleApiService _scheduleApiService = ScheduleApiService();
  final NaverMoveTimeCacheService _moveTimeCache =
      NaverMoveTimeCacheService.instance;

  late Future<List<ScheduledTripDestinationDay>> _destinationDaysFuture;

  int _selectedDayIndex = 0;
  String? _guidedDestinationId;
  final Map<int, List<_TravelDestination>> _moveTimeDestinationCache =
      <int, List<_TravelDestination>>{};
  final Set<int> _moveTimeLoadingDayIndexes = <int>{};

  @override
  void initState() {
    super.initState();
    _destinationDaysFuture = _loadDestinationDays();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ScheduledTripDestinationDay>>(
      future: _destinationDaysFuture,
      builder: (context, snapshot) {
        final destinationDays =
            snapshot.data ?? const <ScheduledTripDestinationDay>[];

        final safeDayIndex = destinationDays.isEmpty
            ? 0
            : _selectedDayIndex.clamp(0, destinationDays.length - 1).toInt();

        final selectedDay = destinationDays.isEmpty
            ? null
            : destinationDays[safeDayIndex];

        final destinations = selectedDay == null
            ? const <_TravelDestination>[]
            : _moveTimeDestinationCache[safeDayIndex] ??
                  selectedDay.destinations
                      .map(_TravelDestination.fromScheduled)
                      .toList(growable: false);

        final guidedDestination = _findDestination(
          _guidedDestinationId,
          destinations,
        );

        return Scaffold(
          backgroundColor: RouteInPalette.white,
          appBar: AppBar(
            title: const Text('실외 길찾기'),
            actions: [
              IconButton(
                onPressed: _refreshDestinations,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '서버 일정 새로고침',
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  child: _OutdoorMap(
                    key: ValueKey(
                      '${selectedDay?.dayId ?? 'empty'}_${_guidedDestinationId ?? 'planned_trip'}_${destinations.length}',
                    ),
                    destinations: destinations,
                    guidedDestination: guidedDestination,
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: RouteInPalette.sky),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                guidedDestination == null
                                    ? '내 일정 장소'
                                    : '${guidedDestination.name} 안내 중',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            const Icon(
                              Icons.route_rounded,
                              color: RouteInPalette.navy,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          guidedDestination == null
                              ? '일정관리에서 추가한 장소를 날짜별로 확인하고 현재 위치 기준으로 안내합니다.'
                              : '지도에서 선택한 여행지까지 이동 경로를 확인하세요.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: RouteInPalette.navy),
                        ),
                        const SizedBox(height: 14),
                        if (snapshot.connectionState != ConnectionState.done)
                          const _ScheduleServerNotice(
                            icon: Icons.sync_rounded,
                            text: '서버에서 사용자 일정을 불러오는 중입니다.',
                          )
                        else if (snapshot.hasError)
                          _ScheduleServerNotice(
                            icon: Icons.cloud_off_rounded,
                            text: '서버 일정을 불러오지 못했습니다.',
                            detail: '${snapshot.error}',
                          )
                        else if (destinationDays.isEmpty)
                          const _NoScheduleDestinationCard()
                        else ...[
                          _DaySelector(
                            days: destinationDays,
                            selectedIndex: _selectedDayIndex,
                            onSelected: (index) {
                              setState(() {
                                _selectedDayIndex = index;
                                _guidedDestinationId = null;
                              });
                              unawaited(
                                _ensureMoveTimesForDay(index, destinationDays),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          if (selectedDay != null)
                            _OutdoorDaySummary(day: selectedDay),
                          const SizedBox(height: 14),
                          if (destinations.isEmpty)
                            const _ScheduleServerNotice(
                              icon: Icons.event_busy_rounded,
                              text: '선택한 날짜에 좌표가 있는 장소가 없습니다.',
                            )
                          else
                            for (final destination in destinations) ...[
                              _DestinationTile(
                                destination: destination,
                                isGuiding:
                                    destination.id == _guidedDestinationId,
                                onTap: () => _confirmNavigation(destination),
                              ),
                              if (destination != destinations.last)
                                const SizedBox(height: 12),
                            ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<ScheduledTripDestinationDay>> _loadDestinationDays() async {
    final days = await _scheduleApiService.fetchUserDestinationDays(
      widget.userId,
    );
    unawaited(_ensureMoveTimesForDay(0, days));
    return days;
  }

  void _refreshDestinations() {
    setState(() {
      _selectedDayIndex = 0;
      _guidedDestinationId = null;
      _moveTimeDestinationCache.clear();
      _moveTimeLoadingDayIndexes.clear();
      _destinationDaysFuture = _loadDestinationDays();
    });
  }

  Future<void> _ensureMoveTimesForDay(
    int dayIndex,
    List<ScheduledTripDestinationDay> days,
  ) async {
    if (dayIndex < 0 || dayIndex >= days.length) {
      return;
    }

    if (_moveTimeDestinationCache.containsKey(dayIndex) ||
        _moveTimeLoadingDayIndexes.contains(dayIndex)) {
      return;
    }

    final scheduledDestinations = days[dayIndex].destinations
        .map(_TravelDestination.fromScheduled)
        .toList(growable: false);

    if (scheduledDestinations.isEmpty) {
      _moveTimeDestinationCache[dayIndex] = scheduledDestinations;
      return;
    }

    _moveTimeLoadingDayIndexes.add(dayIndex);
    final currentPosition = await _loadCurrentPositionForMoveTimes();
    final updatedDestinations = <_TravelDestination>[];

    for (var index = 0; index < scheduledDestinations.length; index++) {
      final destination = scheduledDestinations[index];
      final start = index == 0
          ? currentPosition
          : scheduledDestinations[index - 1].position;

      if (start == null) {
        updatedDestinations.add(destination);
        continue;
      }

      try {
        final moveTime = await _moveTimeCache.drivingMoveTime(
          startLatitude: start.latitude,
          startLongitude: start.longitude,
          endLatitude: destination.position.latitude,
          endLongitude: destination.position.longitude,
        );
        updatedDestinations.add(destination.copyWith(duration: moveTime));
      } catch (error) {
        debugPrint('Outdoor Naver Directions move time failed: $error');
        updatedDestinations.add(destination);
      }
    }

    if (!mounted) {
      _moveTimeLoadingDayIndexes.remove(dayIndex);
      return;
    }

    setState(() {
      _moveTimeLoadingDayIndexes.remove(dayIndex);
      _moveTimeDestinationCache[dayIndex] = updatedDestinations;
    });
  }

  Future<NLatLng?> _loadCurrentPositionForMoveTimes() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Outdoor move time skipped: location service off');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Outdoor move time skipped: location denied');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return NLatLng(position.latitude, position.longitude);
    } catch (error) {
      debugPrint('Outdoor current location failed: $error');
      return null;
    }
  }

  _TravelDestination? _findDestination(
    String? id,
    List<_TravelDestination> destinations,
  ) {
    if (id == null) {
      return null;
    }

    for (final destination in destinations) {
      if (destination.id == id) {
        return destination;
      }
    }

    return null;
  }

  Future<void> _confirmNavigation(_TravelDestination destination) async {
    final routeMode = await Navigator.of(context).push<TmapRouteMode>(
      MaterialPageRoute<TmapRouteMode>(
        builder: (_) => _OutdoorRoutePrepPage(destination: destination),
      ),
    );

    if (!mounted || routeMode == null) {
      return;
    }

    setState(() {
      _guidedDestinationId = destination.id;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _OutdoorGuidancePage(
          destination: destination,
          initialRouteMode: routeMode,
        ),
      ),
    );
  }
}

class _OutdoorMap extends StatelessWidget {
  const _OutdoorMap({
    super.key,
    required this.destinations,
    required this.guidedDestination,
  });

  final List<_TravelDestination> destinations;
  final _TravelDestination? guidedDestination;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 310,
        width: double.infinity,
        child: destinations.isEmpty
            ? const _MapUnavailableState(
                icon: Icons.event_note_rounded,
                title: '선택한 날짜에 표시할 장소가 없습니다.',
                description: '좌표가 저장된 장소가 있으면 지도에 표시됩니다.',
              )
            : !NaverMapConfig.supportsMobileMap
            ? const _MapUnavailableState(
                icon: Icons.phone_android_rounded,
                title: '모바일에서 지도를 확인하세요.',
                description: '네이버 지도 화면은 Android와 iOS에서 표시됩니다.',
              )
            : !NaverMapConfig.hasClientId
            ? const _MapUnavailableState(
                icon: Icons.key_rounded,
                title: '네이버 지도 키가 필요합니다.',
                description: 'NAVER_MAP_CLIENT_ID를 넣어 앱을 실행하면 경로 지도가 표시됩니다.',
              )
            : !NaverMapConfig.isReady
            ? const _MapUnavailableState(
                icon: Icons.map_outlined,
                title: '네이버 지도를 준비 중입니다.',
                description: '앱 초기화가 끝나면 여행 경로가 지도에 표시됩니다.',
              )
            : NaverMap(
                options: NaverMapViewOptions(
                  initialCameraPosition: NCameraPosition(
                    target: destinations.first.position,
                    zoom: 15,
                  ),
                ),
                onMapReady: (controller) => _addRoute(controller),
              ),
      ),
    );
  }

  Future<void> _addRoute(NaverMapController controller) async {
    final routeCoords = destinations
        .map((destination) => destination.position)
        .toList(growable: false);

    await controller.addOverlayAll({
      if (routeCoords.length > 1)
        NPathOverlay(
          id: 'planned_trip_route',
          coords: routeCoords,
          width: 6,
          color: RouteInPalette.denim,
          outlineWidth: 2,
          outlineColor: RouteInPalette.white,
          passedColor: RouteInPalette.coral,
          passedOutlineColor: RouteInPalette.white,
          progress: guidedDestination == null ? 0 : 0.34,
        ),
      for (final destination in destinations)
        NMarker(
          id: destination.id,
          position: destination.position,
          iconTintColor: destination == guidedDestination
              ? RouteInPalette.coral
              : RouteInPalette.denim,
          caption: NOverlayCaption(text: destination.name),
        ),
    });

    if (routeCoords.length > 1) {
      await controller.updateCamera(
        NCameraUpdate.fitBounds(
          NLatLngBounds.from(routeCoords),
          padding: const EdgeInsets.all(42),
        ),
      );
    } else {
      await controller.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: routeCoords.first, zoom: 15),
      );
    }
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ScheduledTripDestinationDay> days;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final day = days[index];
          final isSelected = index == selectedIndex;

          return ChoiceChip(
            label: Text(day.label.isEmpty ? 'DAY ${index + 1}' : day.label),
            selected: isSelected,
            onSelected: (_) => onSelected(index),
            selectedColor: RouteInPalette.navy,
            backgroundColor: RouteInPalette.white,
            side: BorderSide.none,
            labelStyle: TextStyle(
              color: isSelected ? RouteInPalette.white : RouteInPalette.ink,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          );
        },
      ),
    );
  }
}

class _OutdoorDaySummary extends StatelessWidget {
  const _OutdoorDaySummary({required this.day});

  final ScheduledTripDestinationDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final summaryText = [
      if (day.area.isNotEmpty) day.area,
      if (day.totalTime.isNotEmpty) day.totalTime,
      if (day.walkingDistance.isNotEmpty) day.walkingDistance,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: RouteInPalette.denim,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: RouteInPalette.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.title.isEmpty ? day.label : day.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (summaryText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    summaryText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: RouteInPalette.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${day.destinations.length}곳',
            style: theme.textTheme.labelLarge?.copyWith(
              color: RouteInPalette.coral,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.destination,
    required this.isGuiding,
    required this.onTap,
  });

  final _TravelDestination destination;
  final bool isGuiding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: RouteInPalette.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: Key('outdoor-${destination.id}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: isGuiding ? RouteInPalette.coral : RouteInPalette.white,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isGuiding
                      ? RouteInPalette.coral
                      : RouteInPalette.denim,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  destination.icon,
                  color: RouteInPalette.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      destination.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: RouteInPalette.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  Text(
                    destination.duration,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: RouteInPalette.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    key: Key('outdoor-start-${destination.id}'),
                    onPressed: onTap,
                    icon: Icon(
                      isGuiding
                          ? Icons.navigation_rounded
                          : Icons.chevron_right_rounded,
                    ),
                    color: isGuiding
                        ? RouteInPalette.coral
                        : RouteInPalette.navy,
                    tooltip: '경로 안내 준비',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutdoorRoutePrepPage extends StatefulWidget {
  const _OutdoorRoutePrepPage({required this.destination});

  final _TravelDestination destination;

  @override
  State<_OutdoorRoutePrepPage> createState() => _OutdoorRoutePrepPageState();
}

class _OutdoorRoutePrepPageState extends State<_OutdoorRoutePrepPage> {
  TmapRouteMode _routeMode = TmapRouteMode.car;
  Position? _position;
  String? _positionError;
  bool _isLoadingPosition = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadUserPosition();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = _position;

    return Scaffold(
      backgroundColor: RouteInPalette.white,
      appBar: AppBar(title: const Text('경로 안내 준비')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _RoutePrepHero(destination: widget.destination),
            const SizedBox(height: 18),
            Text(
              '사용자 정보',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            _UserLocationCard(
              position: position,
              error: _positionError,
              isLoading: _isLoadingPosition,
              onRetry: _loadUserPosition,
            ),
            const SizedBox(height: 18),
            Text(
              '경로 옵션',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<TmapRouteMode>(
              segments: const [
                ButtonSegment<TmapRouteMode>(
                  value: TmapRouteMode.transit,
                  enabled: TmapConfig.isTransitRouteEnabled,
                  icon: Icon(Icons.directions_transit_rounded),
                  label: Text('대중교통'),
                ),
                ButtonSegment<TmapRouteMode>(
                  value: TmapRouteMode.car,
                  icon: Icon(Icons.directions_car_filled_rounded),
                  label: Text('자동차'),
                ),
              ],
              selected: {_routeMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _routeMode = selection.first);
              },
            ),
            const SizedBox(height: 14),
            _RoutePrepInfoGrid(
              destination: widget.destination,
              position: position,
              routeMode: _routeMode,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: FilledButton.icon(
            onPressed: _position == null
                ? null
                : () => Navigator.of(context).pop(_routeMode),
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('이 정보로 안내 시작'),
          ),
        ),
      ),
    );
  }

  Future<void> _loadUserPosition() async {
    setState(() {
      _isLoadingPosition = true;
      _positionError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const TmapRouteException('기기의 위치 서비스가 꺼져 있습니다.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw const TmapRouteException('위치 권한이 필요합니다.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw const TmapRouteException('설정에서 위치 권한을 허용해 주세요.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _position = position;
        _isLoadingPosition = false;
      });
    } on TmapRouteException catch (error) {
      _setPositionError(error.message);
    } catch (error) {
      _setPositionError('현재 위치 확인 실패: $error');
    }
  }

  void _setPositionError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _position = null;
      _positionError = message;
      _isLoadingPosition = false;
    });
  }
}

class _RoutePrepHero extends StatelessWidget {
  const _RoutePrepHero({required this.destination});

  final _TravelDestination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RouteInPalette.denim,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: RouteInPalette.sky,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(destination.icon, color: RouteInPalette.navy, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: RouteInPalette.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  destination.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: RouteInPalette.white,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserLocationCard extends StatelessWidget {
  const _UserLocationCard({
    required this.position,
    required this.error,
    required this.isLoading,
    required this.onRetry,
  });

  final Position? position;
  final String? error;
  final bool isLoading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RouteInPalette.sky.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error == null
                ? Icons.my_location_rounded
                : Icons.location_disabled_rounded,
            color: error == null ? RouteInPalette.denim : RouteInPalette.coral,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoading
                      ? '현재 위치 확인 중'
                      : error == null
                      ? '현재 위치 확인 완료'
                      : '현재 위치 확인 필요',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                if (isLoading)
                  const LinearProgressIndicator()
                else if (error != null)
                  Text(
                    error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: RouteInPalette.navy,
                    ),
                  )
                else
                  Text(
                    _formatPosition(position!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: RouteInPalette.navy,
                    ),
                  ),
              ],
            ),
          ),
          if (!isLoading)
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '현재 위치 다시 확인',
            ),
        ],
      ),
    );
  }

  static String _formatPosition(Position position) {
    final lat = position.latitude.toStringAsFixed(6);
    final lng = position.longitude.toStringAsFixed(6);
    final accuracy = position.accuracy.toStringAsFixed(0);
    return '위도 $lat · 경도 $lng · 정확도 약 ${accuracy}m';
  }
}

class _RoutePrepInfoGrid extends StatelessWidget {
  const _RoutePrepInfoGrid({
    required this.destination,
    required this.position,
    required this.routeMode,
  });

  final _TravelDestination destination;
  final Position? position;
  final TmapRouteMode routeMode;

  @override
  Widget build(BuildContext context) {
    final straightDistance = position == null
        ? null
        : Geolocator.distanceBetween(
            position!.latitude,
            position!.longitude,
            destination.position.latitude,
            destination.position.longitude,
          );

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _PrepMetricTile(
          icon: Icons.route_rounded,
          label: '경로 모드',
          value: routeMode.label,
        ),
        _PrepMetricTile(
          icon: Icons.place_outlined,
          label: '목적지',
          value: destination.name,
        ),
        _PrepMetricTile(
          icon: Icons.social_distance_rounded,
          label: '직선 거리',
          value: straightDistance == null
              ? '위치 확인 후 표시'
              : _formatDistance(straightDistance),
        ),
        _PrepMetricTile(
          icon: Icons.schedule_rounded,
          label: '목록 예상',
          value: destination.duration,
        ),
      ],
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }

    return '${meters.round()} m';
  }
}

class _PrepMetricTile extends StatelessWidget {
  const _PrepMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        border: Border.all(color: RouteInPalette.mist),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: RouteInPalette.denim),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: RouteInPalette.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutdoorGuidancePage extends StatefulWidget {
  const _OutdoorGuidancePage({
    required this.destination,
    required this.initialRouteMode,
  });

  final _TravelDestination destination;
  final TmapRouteMode initialRouteMode;

  @override
  State<_OutdoorGuidancePage> createState() => _OutdoorGuidancePageState();
}

class _OutdoorGuidancePageState extends State<_OutdoorGuidancePage> {
  final TmapRouteService _routeService = TmapRouteService();

  NaverMapController? _mapController;
  NLatLng? _currentPosition;
  late TmapRouteMode _routeMode;
  TmapRoute? _route;
  String? _routeError;
  bool _isLoadingRoute = false;

  @override
  void initState() {
    super.initState();
    _routeMode = widget.initialRouteMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RouteInPalette.white,
      appBar: AppBar(title: const Text('현재 위치 안내')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _GuidanceMap(
                destination: widget.destination,
                onMapReady: _rememberMapController,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              decoration: const BoxDecoration(color: RouteInPalette.sky),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: RouteInPalette.denim,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: RouteInPalette.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.destination.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '현재 위치를 따라 목적지까지 안내합니다.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: RouteInPalette.navy),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('종료'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<TmapRouteMode>(
                      key: const Key('outdoor-route-mode'),
                      segments: const [
                        ButtonSegment<TmapRouteMode>(
                          value: TmapRouteMode.transit,
                          enabled: TmapConfig.isTransitRouteEnabled,
                          icon: Icon(Icons.directions_transit_rounded),
                          label: Text('대중교통 경로'),
                        ),
                        ButtonSegment<TmapRouteMode>(
                          value: TmapRouteMode.car,
                          icon: Icon(Icons.directions_car_filled_rounded),
                          label: Text('자동차 경로'),
                        ),
                      ],
                      selected: {_routeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: _isLoadingRoute
                          ? null
                          : (selection) {
                              _requestRoute(selection.first);
                            },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _routeStatus,
                      key: const Key('outdoor-route-status'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _routeError == null
                            ? RouteInPalette.navy
                            : RouteInPalette.ink,
                        fontWeight: _routeError == null
                            ? FontWeight.w700
                            : FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _routeStatus {
    if (_isLoadingRoute) {
      return '${_routeMode.label}를 불러오는 중입니다.';
    }

    if (_routeError != null) {
      return _routeError!;
    }

    final route = _route;
    if (route == null) {
      return '경로 종류를 선택하면 TMAP 경로를 지도에 표시합니다.';
    }

    final minutes = (route.totalTimeSeconds / 60).ceil();
    final distance = route.totalDistanceMeters >= 1000
        ? '${(route.totalDistanceMeters / 1000).toStringAsFixed(1)} km'
        : '${route.totalDistanceMeters} m';
    final transfer = route.transferCount == null
        ? ''
        : ' · 환승 ${route.transferCount}회';

    return '${route.mode.label} · 약 $minutes분 · $distance$transfer';
  }

  void _rememberMapController(NaverMapController controller) {
    _mapController = controller;
  }

  Future<void> _requestRoute(TmapRouteMode mode) async {
    setState(() {
      _routeMode = mode;
      _isLoadingRoute = true;
      _routeError = null;
    });

    if (mode == TmapRouteMode.transit && !TmapConfig.isTransitRouteEnabled) {
      setState(() {
        _routeMode = TmapRouteMode.car;
        _isLoadingRoute = false;
        _routeError = 'Tmap transit route API is temporarily disabled.';
      });
      return;
    }

    if (!TmapConfig.hasAppKey) {
      setState(() {
        _isLoadingRoute = false;
        _routeError = 'TMAP 앱 키가 필요합니다.';
      });
      return;
    }

    final controller = _mapController;
    if (controller == null) {
      setState(() {
        _isLoadingRoute = false;
        _routeError = '지도가 준비되면 경로를 다시 선택해 주세요.';
      });
      return;
    }

    late final NLatLng currentPosition;

    try {
      currentPosition = await _loadCurrentPosition(controller);
    } on TmapRouteException catch (error) {
      _setRouteError('현재 위치 확인 실패: ${error.message}');
      return;
    } catch (error) {
      _setRouteError('현재 위치 확인 실패: $error');
      return;
    }

    late final TmapRoute route;

    try {
      route = await _routeService.fetchRoute(
        mode: mode,
        startLatitude: currentPosition.latitude,
        startLongitude: currentPosition.longitude,
        endLatitude: widget.destination.position.latitude,
        endLongitude: widget.destination.position.longitude,
        destinationName: widget.destination.name,
      );
    } on TmapRouteException catch (error) {
      _setRouteError('TMAP 경로 요청 실패: ${error.message}');
      return;
    } catch (error) {
      _setRouteError('TMAP 경로 요청 실패: $error');
      return;
    }

    try {
      await _drawRoute(controller, route);
    } catch (error) {
      _setRouteError('지도 경로 표시 실패: $error');
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _route = route;
      _isLoadingRoute = false;
    });
  }

  Future<NLatLng> _loadCurrentPosition(NaverMapController controller) async {
    final cached = _currentPosition;
    if (cached != null) {
      return cached;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const TmapRouteException('기기의 위치 서비스가 꺼져 있습니다.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const TmapRouteException('위치 권한이 필요합니다.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw const TmapRouteException('설정에서 위치 권한을 허용해 주세요.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    final currentPosition = NLatLng(position.latitude, position.longitude);

    _currentPosition = currentPosition;

    await controller.updateCamera(
      NCameraUpdate.scrollAndZoomTo(target: currentPosition, zoom: 16),
    );

    controller.setLocationTrackingMode(NLocationTrackingMode.face);

    return currentPosition;
  }

  Future<void> _drawRoute(
    NaverMapController controller,
    TmapRoute route,
  ) async {
    await controller.clearOverlays(type: NOverlayType.pathOverlay);

    await controller.addOverlayAll({
      for (final segment in route.segments)
        NPathOverlay(
          id: segment.id,
          coords: segment.coordinates.map((coordinate) {
            return NLatLng(coordinate.latitude, coordinate.longitude);
          }).toList(),
          width: segment.mode == TmapRouteSegmentMode.walk ? 5 : 7,
          color: switch (segment.mode) {
            TmapRouteSegmentMode.walk => RouteInPalette.coral,
            TmapRouteSegmentMode.transit => RouteInPalette.denim,
            TmapRouteSegmentMode.car => RouteInPalette.navy,
          },
          outlineWidth: 2,
          outlineColor: RouteInPalette.white,
          passedColor: RouteInPalette.coral,
          passedOutlineColor: RouteInPalette.white,
        ),
    });

    final routeBounds = route.allCoordinates
        .map((coordinate) {
          return NLatLng(coordinate.latitude, coordinate.longitude);
        })
        .toList(growable: false);

    if (routeBounds.length > 1) {
      await controller.updateCamera(
        NCameraUpdate.fitBounds(
          NLatLngBounds.from(routeBounds),
          padding: const EdgeInsets.all(44),
        ),
      );
    }
  }

  void _setRouteError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingRoute = false;
      _routeError = message;
    });
  }
}

class _GuidanceMap extends StatelessWidget {
  const _GuidanceMap({required this.destination, required this.onMapReady});

  final _TravelDestination destination;
  final ValueChanged<NaverMapController> onMapReady;

  @override
  Widget build(BuildContext context) {
    if (!NaverMapConfig.supportsMobileMap) {
      return const _MapUnavailableState(
        icon: Icons.phone_android_rounded,
        title: '모바일에서 위치 안내를 시작하세요.',
        description: '현재 위치 추적은 Android와 iOS 지도 화면에서 동작합니다.',
      );
    }

    if (!NaverMapConfig.hasClientId) {
      return const _MapUnavailableState(
        icon: Icons.key_rounded,
        title: '네이버 지도 키가 필요합니다.',
        description: 'NAVER_MAP_CLIENT_ID를 넣어야 현재 위치 안내를 시작할 수 있습니다.',
      );
    }

    if (!NaverMapConfig.isReady) {
      return const _MapUnavailableState(
        icon: Icons.map_outlined,
        title: '네이버 지도를 준비 중입니다.',
        description: '지도 초기화가 끝나면 현재 위치 추적을 시작합니다.',
      );
    }

    return NaverMap(
      options: NaverMapViewOptions(
        mapType: NMapType.navi,
        locationButtonEnable: true,
        initialCameraPosition: NCameraPosition(
          target: destination.position,
          zoom: 16,
        ),
      ),
      onMapReady: _startGuidance,
    );
  }

  Future<void> _startGuidance(NaverMapController controller) async {
    onMapReady(controller);

    await controller.addOverlay(
      NMarker(
        id: 'guided_${destination.id}',
        position: destination.position,
        iconTintColor: RouteInPalette.coral,
        caption: NOverlayCaption(text: destination.name),
      ),
    );

    controller.setLocationTrackingMode(NLocationTrackingMode.face);
  }
}

class _MapUnavailableState extends StatelessWidget {
  const _MapUnavailableState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: RouteInPalette.mist,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: RouteInPalette.navy, size: 44),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RouteInPalette.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleServerNotice extends StatelessWidget {
  const _ScheduleServerNotice({
    required this.icon,
    required this.text,
    this.detail,
  });

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final detailText = detail;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: RouteInPalette.denim),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detailText == null || detailText.isEmpty
                  ? text
                  : '$text\n$detailText',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: RouteInPalette.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoScheduleDestinationCard extends StatelessWidget {
  const _NoScheduleDestinationCard();

  @override
  Widget build(BuildContext context) {
    return const _ScheduleServerNotice(
      icon: Icons.event_busy_rounded,
      text: '서버에 저장된 일정 장소가 없습니다. 일정관리에서 장소를 추가해 주세요.',
    );
  }
}

class _TravelDestination {
  const _TravelDestination({
    required this.id,
    required this.name,
    required this.description,
    required this.duration,
    required this.position,
    required this.icon,
  });

  factory _TravelDestination.fromScheduled(
    ScheduledTripDestination destination,
  ) {
    return _TravelDestination(
      id: destination.id,
      name: destination.name,
      description: destination.description,
      duration: destination.duration,
      position: destination.position,
      icon: destination.icon,
    );
  }

  final String id;
  final String name;
  final String description;
  final String duration;
  final NLatLng position;
  final IconData icon;

  _TravelDestination copyWith({String? duration}) {
    return _TravelDestination(
      id: id,
      name: name,
      description: description,
      duration: duration ?? this.duration,
      position: position,
      icon: icon,
    );
  }
}
