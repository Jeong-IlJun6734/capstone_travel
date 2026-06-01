import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../services/naver_map_config.dart';
import '../theme/route_in_palette.dart';
import 'indoor_navigation_page.dart';
import 'outdoor_navigation_page.dart';
import 'realtime_help_page.dart';
import 'schedule_management_page.dart';

const _defaultSchedulePreviews = [
  OverviewSchedulePreview(
    day: 'DAY 1',
    title: '서울 고궁 산책 루트',
    area: '광화문 - 북촌',
    stops: [
      OverviewScheduleStop(
        name: '경복궁',
        position: NLatLng(37.579617, 126.977041),
      ),
      OverviewScheduleStop(
        name: '북촌한옥마을',
        position: NLatLng(37.582604, 126.983998),
      ),
      OverviewScheduleStop(
        name: '인사동길',
        position: NLatLng(37.574471, 126.984955),
      ),
    ],
  ),
  OverviewSchedulePreview(
    day: 'DAY 2',
    title: '남산 전망 코스',
    area: '명동 - 남산',
    stops: [
      OverviewScheduleStop(
        name: '명동성당',
        position: NLatLng(37.563177, 126.987015),
      ),
      OverviewScheduleStop(
        name: '남산골한옥마을',
        position: NLatLng(37.559106, 126.994459),
      ),
      OverviewScheduleStop(
        name: 'N서울타워',
        position: NLatLng(37.551169, 126.988227),
      ),
    ],
  ),
  OverviewSchedulePreview(
    day: 'DAY 3',
    title: '부산 바다 산책',
    area: '해운대 - 광안리',
    stops: [
      OverviewScheduleStop(
        name: '해운대해수욕장',
        position: NLatLng(35.158698, 129.160384),
      ),
      OverviewScheduleStop(
        name: '동백섬',
        position: NLatLng(35.152645, 129.152583),
      ),
      OverviewScheduleStop(
        name: '광안대교',
        position: NLatLng(35.153221, 129.118662),
      ),
    ],
  ),
];

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, this.schedules = _defaultSchedulePreviews});

  final List<OverviewSchedulePreview> schedules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            color: RouteInPalette.white,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Row(
              children: [
                const _HeaderIcon(icon: Icons.notifications_none_rounded),
                const SizedBox(width: 10),
                const _HeaderIcon(icon: Icons.tune_rounded),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Hi, Welcome Back',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: RouteInPalette.denim,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'RouteIn',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: RouteInPalette.navy,
                  foregroundColor: RouteInPalette.white,
                  child: Icon(Icons.person_rounded),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _ScheduleBoard(
            schedules: schedules,
            onOpenSchedule: () => _openSchedule(context),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '여행 도구',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: RouteInPalette.denim,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(color: RouteInPalette.sky, height: 1),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  children: [
                    _FeatureTile(
                      label: '일정 관리하기',
                      icon: Icons.edit_calendar_outlined,
                      onTap: () => _openSchedule(context),
                    ),
                    _FeatureTile(
                      key: const Key('overview-indoor-navigation'),
                      label: '실내 길찾기',
                      icon: Icons.directions_walk_rounded,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const IndoorNavigationPage(),
                        ),
                      ),
                    ),
                    _FeatureTile(
                      label: '실외 길찾기',
                      icon: Icons.map_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OutdoorNavigationPage(),
                        ),
                      ),
                    ),
                    _FeatureTile(
                      label: '실시간 문제 해결',
                      icon: Icons.support_agent_rounded,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RealtimeHelpPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openSchedule(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScheduleManagementPage()),
    );
  }
}

class _ScheduleBoard extends StatelessWidget {
  const _ScheduleBoard({required this.schedules, required this.onOpenSchedule});

  final List<OverviewSchedulePreview> schedules;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSchedule = schedules.isNotEmpty;

    return Container(
      color: RouteInPalette.sky,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '내 일정',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpenSchedule,
                child: const Text('일정 관리하기'),
              ),
            ],
          ),
          const Divider(color: RouteInPalette.ink, thickness: 2),
          const SizedBox(height: 14),
          if (hasSchedule) ...[
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: schedules.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return _DayPill(
                    preview: schedules[index],
                    selected: index == 0,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _ScheduleMapCard(preview: schedules.first),
          ] else
            _EmptyScheduleCard(onCreateSchedule: onOpenSchedule),
        ],
      ),
    );
  }
}

class _ScheduleMapCard extends StatelessWidget {
  const _ScheduleMapCard({required this.preview});

  final OverviewSchedulePreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        border: Border.all(color: RouteInPalette.ink, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  preview.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                preview.area,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: RouteInPalette.denim,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 170,
              width: double.infinity,
              child: _ScheduleNaverMap(preview: preview),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: preview.stops.map((stop) {
              return Expanded(
                child: Text(
                  stop.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: RouteInPalette.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ScheduleNaverMap extends StatelessWidget {
  const _ScheduleNaverMap({required this.preview});

  final OverviewSchedulePreview preview;

  @override
  Widget build(BuildContext context) {
    if (!NaverMapConfig.supportsMobileMap) {
      return _ScheduleMapFallback(preview: preview, title: '모바일 지도 전용');
    }
    if (!NaverMapConfig.hasClientId) {
      return _ScheduleMapFallback(preview: preview, title: '지도 키 필요');
    }
    if (!NaverMapConfig.isReady) {
      return _ScheduleMapFallback(preview: preview, title: '네이버 지도 준비 중');
    }

    return NaverMap(
      options: NaverMapViewOptions(
        mapType: NMapType.basic,
        initialCameraPosition: NCameraPosition(
          target: preview.stops.first.position,
          zoom: 14,
        ),
      ),
      onMapReady: (controller) => _addScheduleRoute(controller),
    );
  }

  Future<void> _addScheduleRoute(NaverMapController controller) async {
    final coords = preview.stops.map((stop) => stop.position).toList();

    await controller.addOverlayAll({
      NPathOverlay(
        id: 'overview_schedule_route',
        coords: coords,
        width: 6,
        color: RouteInPalette.denim,
        outlineWidth: 2,
        outlineColor: RouteInPalette.white,
      ),
      for (final stop in preview.stops)
        NMarker(
          id: 'overview_${stop.name}',
          position: stop.position,
          iconTintColor: RouteInPalette.coral,
          caption: NOverlayCaption(text: stop.name),
        ),
    });

    if (coords.length > 1) {
      await controller.updateCamera(
        NCameraUpdate.fitBounds(
          NLatLngBounds.from(coords),
          padding: const EdgeInsets.all(36),
        ),
      );
    }
  }
}

class _ScheduleMapFallback extends StatelessWidget {
  const _ScheduleMapFallback({required this.preview, required this.title});

  final OverviewSchedulePreview preview;
  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: RouteInPalette.mist),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: const _TripRoutePainter()),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: RouteInPalette.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: RouteInPalette.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyScheduleCard extends StatelessWidget {
  const _EmptyScheduleCard({required this.onCreateSchedule});

  final VoidCallback onCreateSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        border: Border.all(color: RouteInPalette.ink, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.route_outlined,
            color: RouteInPalette.denim,
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            '아직 만든 일정이 없습니다.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '여행 동선을 그리고 일정을 먼저 만들어보세요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RouteInPalette.navy,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreateSchedule,
            icon: const Icon(Icons.add_rounded),
            label: const Text('일정 만들기'),
          ),
        ],
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({required this.preview, required this.selected});

  final OverviewSchedulePreview preview;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? RouteInPalette.ink : RouteInPalette.sky,
        border: Border.all(color: RouteInPalette.ink, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            preview.day.substring(preview.day.length - 1),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: selected ? RouteInPalette.white : RouteInPalette.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            preview.day,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? RouteInPalette.white : RouteInPalette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: RouteInPalette.denim,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: RouteInPalette.sky,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: RouteInPalette.navy, size: 38),
              ),
              const SizedBox(height: 18),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: RouteInPalette.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        color: RouteInPalette.sky,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: RouteInPalette.navy),
    );
  }
}

class _TripRoutePainter extends CustomPainter {
  const _TripRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final routePaint = Paint()
      ..color = RouteInPalette.navy
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    final route = Path()
      ..moveTo(size.width * 0.16, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.16,
        size.width * 0.52,
        size.height * 0.42,
      )
      ..quadraticBezierTo(
        size.width * 0.70,
        size.height * 0.68,
        size.width * 0.86,
        size.height * 0.28,
      );

    canvas.drawPath(route, routePaint);

    for (final point in [
      Offset(size.width * 0.16, size.height * 0.62),
      Offset(size.width * 0.52, size.height * 0.42),
      Offset(size.width * 0.86, size.height * 0.28),
    ]) {
      canvas.drawCircle(point, 12, Paint()..color = RouteInPalette.coral);
      canvas.drawCircle(point, 5, Paint()..color = RouteInPalette.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OverviewSchedulePreview {
  const OverviewSchedulePreview({
    required this.day,
    required this.title,
    required this.area,
    required this.stops,
  });

  final String day;
  final String title;
  final String area;
  final List<OverviewScheduleStop> stops;
}

class OverviewScheduleStop {
  const OverviewScheduleStop({required this.name, required this.position});

  final String name;
  final NLatLng position;
}
