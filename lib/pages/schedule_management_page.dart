import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../services/naver_map_config.dart';
import '../services/schedule_api_service.dart';
import '../theme/route_in_palette.dart';
import 'add_place_page.dart';

class ScheduleManagementPage extends StatefulWidget {
  const ScheduleManagementPage({
    super.key,
    this.userId = defaultScheduleUserId,
  });

  final int userId;

  @override
  State<ScheduleManagementPage> createState() => _ScheduleManagementPageState();
}

class _ScheduleManagementPageState extends State<ScheduleManagementPage> {
  int _selectedDayIndex = 0;
  List<_TripDay> _days = const [];
  Future<void>? _loadFuture;
  String? _loadError;

  final ScheduleApiService _scheduleApiService = ScheduleApiService();

  int _nextPlaceId = 1;

  int get _serverUserId => widget.userId;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadScheduleFromServer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('일정관리'),
        backgroundColor: RouteInPalette.white,
        actions: [
          IconButton(
            onPressed: _reloadSchedule,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '서버 일정 새로고침',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _days.isEmpty ? null : _openAddPlacePage,
        backgroundColor: RouteInPalette.navy,
        foregroundColor: RouteInPalette.white,
        icon: const Icon(Icons.add),
        label: const Text('일정 추가'),
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_loadError != null) {
            return _ScheduleLoadError(
              message: _loadError!,
              onRetry: _reloadSchedule,
            );
          }

          if (_days.isEmpty) {
            return _ScheduleLoadError(
              message: '서버에 저장된 일정 데이터가 없습니다.',
              onRetry: _reloadSchedule,
            );
          }

          final safeIndex = _selectedDayIndex.clamp(0, _days.length - 1);
          final day = _days[safeIndex];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              _MapPreviewSection(day: day),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '여행 일정',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openAddPlacePage,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('추가'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _days.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = _days[index];
                    final isSelected = index == _selectedDayIndex;

                    return ChoiceChip(
                      label: Text(item.label),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedDayIndex = index;
                        });
                      },
                      labelStyle: TextStyle(
                        color: isSelected
                            ? RouteInPalette.white
                            : RouteInPalette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                      selectedColor: RouteInPalette.navy,
                      backgroundColor: RouteInPalette.white,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              _DaySummaryCard(day: day),
              const SizedBox(height: 12),
              Text(
                '카드를 길게 눌러 순서를 바꿀 수 있습니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: RouteInPalette.ink,
                ),
              ),
              const SizedBox(height: 12),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: day.places.length,
                onReorder: _reorderPlaces,
                itemBuilder: (context, index) {
                  final place = day.places[index];

                  return Padding(
                    key: ValueKey(place.id),
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _PlaceTimelineCard(
                      index: index,
                      place: place,
                      onDelete: () => _removePlace(place.id),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadScheduleFromServer() async {
    setState(() {
      _loadError = null;
    });

    try {
      final trips = await _scheduleApiService.fetchUserTrips(_serverUserId);

      if (!mounted) return;

      if (trips.isEmpty) {
        setState(() {
          _days = const [];
          _selectedDayIndex = 0;
          _nextPlaceId = 1;
        });
        return;
      }

      final detail = await _scheduleApiService.fetchTrip(trips.first.id);

      if (!mounted) return;

      final loadedDays = detail.days
          .map(_tripDayFromServer)
          .toList(growable: false);

      setState(() {
        _days = loadedDays;
        _selectedDayIndex = 0;
        _nextPlaceId = _calculateNextPlaceId(loadedDays);
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loadError = '$error';
      });
    }
  }

  int _calculateNextPlaceId(List<_TripDay> days) {
    final maxId = days
        .expand((day) => day.places)
        .map((place) => place.id)
        .fold<int>(0, (maxId, id) => id > maxId ? id : maxId);

    return maxId + 1;
  }

  _TripDay _tripDayFromServer(ScheduleTripDay day) {
    return _TripDay(
      serverDayId: day.id,
      label: day.label,
      title: day.title,
      area: day.area,
      totalTime: day.totalTime,
      walkingDistance: day.walkingDistance,
      places: day.places.map(_tripPlaceFromServer).toList(growable: true),
    );
  }

  _TripPlace _tripPlaceFromServer(SchedulePlace place) {
    return _TripPlace(
      id: place.id,
      serverPlaceId: place.id,
      category: place.category,
      name: place.name,
      note: place.note,
      move: place.move,
      address: place.address,
      link: place.link,
      latitude: place.latitude,
      longitude: place.longitude,
      thumbnailUrl: place.thumbnailUrl,
      imageUrl: place.imageUrl,
    );
  }

  void _reloadSchedule() {
    setState(() {
      _loadFuture = _loadScheduleFromServer();
    });
  }

  void _reorderPlaces(int oldIndex, int newIndex) {
    setState(() {
      final places = _days[_selectedDayIndex].places;

      if (newIndex > oldIndex) {
        newIndex -= 1;
      }

      final item = places.removeAt(oldIndex);
      places.insert(newIndex, item);
    });

    // 서버에 순서 저장 API가 있다면 여기에서 호출하면 됩니다.
    // 예: _scheduleApiService.updatePlaceOrder(...)
  }

  Future<void> _openAddPlacePage() async {
    final draft = await Navigator.of(context).push<AddedTripPlaceDraft>(
      MaterialPageRoute(
        builder: (_) => AddPlacePage(nextPlaceId: _nextPlaceId),
      ),
    );

    if (draft == null || !mounted) {
      return;
    }

    final day = _days[_selectedDayIndex];

    if (day.serverDayId == null) {
      _showSnackBar('서버 일정 ID가 없어 장소를 추가할 수 없습니다.');
      return;
    }

    try {
      final savedPlace = await _scheduleApiService.createPlace(
        dayId: day.serverDayId!,
        category: draft.category,
        name: draft.name,
        note: draft.note,
        move: draft.move,
        address: draft.address,
        link: draft.link,
        latitude: draft.latitude,
        longitude: draft.longitude,
        thumbnailUrl: draft.thumbnailUrl,
        imageUrl: draft.imageUrl,
      );

      if (!mounted) return;

      setState(() {
        _days[_selectedDayIndex].places.add(
          _TripPlace(
            id: savedPlace.id,
            serverPlaceId: savedPlace.id,
            category: savedPlace.category,
            name: savedPlace.name,
            note: savedPlace.note,
            move: savedPlace.move,
            address: savedPlace.address,
            link: savedPlace.link,
            latitude: savedPlace.latitude,
            longitude: savedPlace.longitude,
            thumbnailUrl: savedPlace.thumbnailUrl,
            imageUrl: savedPlace.imageUrl,
          ),
        );

        _nextPlaceId = savedPlace.id + 1;
      });
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('장소 추가 실패: $error');
    }
  }

  void _removePlace(int placeId) {
    final day = _days[_selectedDayIndex];

    final target = day.places
        .where((place) => place.id == placeId)
        .firstOrNull;

    if (target == null) {
      return;
    }

    setState(() {
      day.places.removeWhere((place) => place.id == placeId);
    });

    final serverPlaceId = target.serverPlaceId;
    if (serverPlaceId != null) {
      unawaited(_deletePlaceFromServer(serverPlaceId));
    }
  }

  Future<void> _deletePlaceFromServer(int placeId) async {
    try {
      await _scheduleApiService.deletePlace(placeId);
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('서버 장소 삭제 실패: $error');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _MapPreviewSection extends StatelessWidget {
  const _MapPreviewSection({required this.day});

  final _TripDay day;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 250,
        width: double.infinity,
        child: _ScheduleNaverMap(day: day),
      ),
    );
  }
}

class _ScheduleNaverMap extends StatelessWidget {
  const _ScheduleNaverMap({required this.day});

  final _TripDay day;

  @override
  Widget build(BuildContext context) {
    final routePlaces = day.places
        .where((place) => place.latitude != null && place.longitude != null)
        .toList(growable: false);

    if (routePlaces.isEmpty) {
      return _ScheduleMapFallback(
        title: '좌표가 있는 장소를 추가하면 지도가 표시됩니다.',
        day: day,
      );
    }

    if (!NaverMapConfig.supportsMobileMap) {
      return _ScheduleMapFallback(
        title: '모바일 지도 전용입니다.',
        day: day,
      );
    }

    if (!NaverMapConfig.hasClientId) {
      return _ScheduleMapFallback(
        title: '네이버 지도 키가 필요합니다.',
        day: day,
      );
    }

    if (!NaverMapConfig.isReady) {
      return _ScheduleMapFallback(
        title: '네이버 지도를 준비하는 중입니다.',
        day: day,
      );
    }

    return NaverMap(
      key: ValueKey('${day.label}_${routePlaces.length}'),
      options: NaverMapViewOptions(
        mapType: NMapType.basic,
        initialCameraPosition: NCameraPosition(
          target: NLatLng(
            routePlaces.first.latitude!,
            routePlaces.first.longitude!,
          ),
          zoom: 13,
        ),
      ),
      onMapReady: (controller) => _addScheduleOverlays(
        controller,
        routePlaces,
      ),
    );
  }

  Future<void> _addScheduleOverlays(
    NaverMapController controller,
    List<_TripPlace> routePlaces,
  ) async {
    final coords = routePlaces
        .map((place) => NLatLng(place.latitude!, place.longitude!))
        .toList(growable: false);

    await controller.addOverlayAll({
      if (coords.length > 1)
        NPathOverlay(
          id: 'schedule_route_${day.label}',
          coords: coords,
          width: 6,
          color: RouteInPalette.denim,
          outlineWidth: 2,
          outlineColor: RouteInPalette.white,
        ),
      for (var index = 0; index < routePlaces.length; index++)
        NMarker(
          id: 'schedule_${day.label}_${routePlaces[index].id}',
          position: coords[index],
          iconTintColor: index == 0
              ? RouteInPalette.coral
              : RouteInPalette.navy,
          caption: NOverlayCaption(
            text: '${index + 1}. ${routePlaces[index].name}',
          ),
        ),
    });

    if (coords.length > 1) {
      await controller.updateCamera(
        NCameraUpdate.fitBounds(
          NLatLngBounds.from(coords),
          padding: const EdgeInsets.all(42),
        ),
      );
    }
  }
}

class _ScheduleMapFallback extends StatelessWidget {
  const _ScheduleMapFallback({
    required this.title,
    required this.day,
  });

  final String title;
  final _TripDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: RouteInPalette.sky,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _MapPlaceholderPainter()),
          Center(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RouteInPalette.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.map_outlined,
                    color: RouteInPalette.navy,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: RouteInPalette.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.label} · ${day.area}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: RouteInPalette.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.day});

  final _TripDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RouteInPalette.sky,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            day.area,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: RouteInPalette.ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: '예상 소요',
                  value: day.totalTime,
                  icon: Icons.schedule_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: '도보 거리',
                  value: day.walkingDistance,
                  icon: Icons.directions_walk_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlaceTimelineCard extends StatelessWidget {
  const _PlaceTimelineCard({
    required this.index,
    required this.place,
    required this.onDelete,
  });

  final int index;
  final _TripPlace place;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: RouteInPalette.navy,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: RouteInPalette.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (place.move != null && place.move!.isNotEmpty)
                Container(
                  width: 2,
                  height: 48,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: RouteInPalette.mist,
                ),
            ],
          ),
          const SizedBox(width: 14),
          _PlaceThumbnail(url: place.thumbnailUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: RouteInPalette.mist,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        place.category,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.drag_handle,
                          color: RouteInPalette.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                      color: RouteInPalette.ink,
                      tooltip: '삭제',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  place.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (place.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    place.note,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: RouteInPalette.ink,
                      height: 1.4,
                    ),
                  ),
                ],
                if (place.address != null && place.address!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: RouteInPalette.denim,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          place.address!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: RouteInPalette.denim,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (place.move != null && place.move!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.route_outlined,
                        size: 18,
                        color: RouteInPalette.coral,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '다음 장소까지 ${place.move}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: RouteInPalette.coral,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceThumbnail extends StatelessWidget {
  const _PlaceThumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 72,
        height: 72,
        child: imageUrl == null || imageUrl.isEmpty
            ? Container(
                color: RouteInPalette.denim,
                child: const Icon(
                  Icons.place_outlined,
                  color: RouteInPalette.white,
                ),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: RouteInPalette.denim,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: RouteInPalette.white,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ScheduleLoadError extends StatelessWidget {
  const _ScheduleLoadError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: RouteInPalette.denim,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              '서버 일정 연결이 필요합니다.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: RouteInPalette.navy,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 불러오기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: RouteInPalette.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: RouteInPalette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
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

class _MapPlaceholderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = RouteInPalette.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final routePaint = Paint()
      ..color = RouteInPalette.navy
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.55,
        size.width * 0.36,
        size.height * 0.60,
      )
      ..quadraticBezierTo(
        size.width * 0.56,
        size.height * 0.68,
        size.width * 0.74,
        size.height * 0.42,
      )
      ..quadraticBezierTo(
        size.width * 0.84,
        size.height * 0.28,
        size.width * 0.92,
        size.height * 0.34,
      );

    for (var i = 1; i < 4; i++) {
      final dx = size.width * i / 4;
      canvas.drawLine(
        Offset(dx, 0),
        Offset(dx, size.height),
        linePaint,
      );
    }

    for (var i = 1; i < 4; i++) {
      final dy = size.height * i / 4;
      canvas.drawLine(
        Offset(0, dy),
        Offset(size.width, dy),
        linePaint,
      );
    }

    canvas.drawPath(path, routePaint);

    final points = [
      Offset(size.width * 0.18, size.height * 0.62),
      Offset(size.width * 0.48, size.height * 0.64),
      Offset(size.width * 0.78, size.height * 0.40),
    ];

    for (final point in points) {
      canvas.drawCircle(
        point,
        10,
        Paint()..color = RouteInPalette.coral,
      );
      canvas.drawCircle(
        point,
        4,
        Paint()..color = RouteInPalette.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TripDay {
  const _TripDay({
    this.serverDayId,
    required this.label,
    required this.title,
    required this.area,
    required this.totalTime,
    required this.walkingDistance,
    required this.places,
  });

  final int? serverDayId;
  final String label;
  final String title;
  final String area;
  final String totalTime;
  final String walkingDistance;
  final List<_TripPlace> places;
}

class _TripPlace {
  const _TripPlace({
    required this.id,
    required this.category,
    required this.name,
    required this.note,
    this.move,
    this.address,
    this.link,
    this.latitude,
    this.longitude,
    this.thumbnailUrl,
    this.imageUrl,
    this.serverPlaceId,
  });

  final int id;
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
  final int? serverPlaceId;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;

    if (iterator.moveNext()) {
      return iterator.current;
    }

    return null;
  }
}