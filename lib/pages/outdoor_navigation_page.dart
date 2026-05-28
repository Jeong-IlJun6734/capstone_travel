import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../models/tmap_route.dart';
import '../services/naver_map_config.dart';
import '../services/tmap_config.dart';
import '../services/tmap_route_service.dart';
import '../theme/route_in_palette.dart';
import 'package:geolocator/geolocator.dart';

class OutdoorNavigationPage extends StatefulWidget {
  const OutdoorNavigationPage({super.key});

  @override
  State<OutdoorNavigationPage> createState() => _OutdoorNavigationPageState();
}

class _OutdoorNavigationPageState extends State<OutdoorNavigationPage> {
  static const _destinations = [
    _TravelDestination(
      id: 'destination_1',
      name: '여행지 1',
      description: '광화문 광장에서 여행을 시작합니다.',
      duration: '2분',
      position: NLatLng(37.572376, 126.976859),
      icon: Icons.photo_camera_outlined,
    ),
    _TravelDestination(
      id: 'destination_2',
      name: '여행지 2',
      description: '청계천을 따라 다음 장소로 이동합니다.',
      duration: '12분',
      position: NLatLng(37.569023, 126.978739),
      icon: Icons.park_outlined,
    ),
    _TravelDestination(
      id: 'destination_3',
      name: '여행지 3',
      description: '서울 시청 근처에서 일정을 마칩니다.',
      duration: '9분',
      position: NLatLng(37.566614, 126.978388),
      icon: Icons.flag_outlined,
    ),
  ];

  String? _guidedDestinationId;

  @override
  Widget build(BuildContext context) {
    final guidedDestination = _findDestination(_guidedDestinationId);

    return Scaffold(
      backgroundColor: RouteInPalette.white,
      appBar: AppBar(title: const Text('실외 길찾기')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: _OutdoorMap(
                key: ValueKey(_guidedDestinationId ?? 'planned_trip'),
                destinations: _destinations,
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
                                ? '오늘의 여행지'
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
                          ? '목적지를 누르면 현재 위치부터 안내를 시작합니다.'
                          : '지도에서 선택한 여행지까지 이동 경로를 확인하세요.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RouteInPalette.navy,
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final destination in _destinations) ...[
                      _DestinationTile(
                        destination: destination,
                        isGuiding: destination.id == _guidedDestinationId,
                        onTap: () => _confirmNavigation(destination),
                      ),
                      if (destination != _destinations.last)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _TravelDestination? _findDestination(String? id) {
    if (id == null) return null;

    for (final destination in _destinations) {
      if (destination.id == id) return destination;
    }

    return null;
  }

  Future<void> _confirmNavigation(_TravelDestination destination) async {
    final shouldStart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: RouteInPalette.white,
        title: Text(destination.name),
        content: const Text('현재 위치에서부터 경로 안내를 시작합니다'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (!mounted || shouldStart != true) return;

    setState(() => _guidedDestinationId = destination.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _OutdoorGuidancePage(destination: destination),
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
        child: !NaverMapConfig.supportsMobileMap
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
    final routeCoords = destinations.map((destination) {
      return destination.position;
    }).toList();

    await controller.addOverlayAll({
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

    await controller.updateCamera(
      NCameraUpdate.fitBounds(
        NLatLngBounds.from(routeCoords),
        padding: const EdgeInsets.all(42),
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
                  Icon(
                    isGuiding
                        ? Icons.navigation_rounded
                        : Icons.chevron_right_rounded,
                    color: isGuiding
                        ? RouteInPalette.coral
                        : RouteInPalette.navy,
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

class _OutdoorGuidancePage extends StatefulWidget {
  const _OutdoorGuidancePage({required this.destination});

  final _TravelDestination destination;

  @override
  State<_OutdoorGuidancePage> createState() => _OutdoorGuidancePageState();
}

class _OutdoorGuidancePageState extends State<_OutdoorGuidancePage> {
  final TmapRouteService _routeService = TmapRouteService();

  NaverMapController? _mapController;
  NLatLng? _currentPosition;
  TmapRouteMode _routeMode = TmapRouteMode.car;
  TmapRoute? _route;
  String? _routeError;
  bool _isLoadingRoute = false;

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

    if (!mounted) return;

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
    if (!mounted) return;

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

class _TravelDestination {
  const _TravelDestination({
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
