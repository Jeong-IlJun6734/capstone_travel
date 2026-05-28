import 'package:flutter/material.dart';

import '../theme/route_in_palette.dart';
import 'indoor_navigation_page.dart';
import 'outdoor_navigation_page.dart';
import 'schedule_management_page.dart';

const _defaultSchedulePreviews = [
  OverviewSchedulePreview(
    day: 'DAY 1',
    title: '난바 먹방 루트',
    area: '도톤보리 - 구로몬 시장',
    stops: ['도톤보리', '오코노미야키', '구로몬 시장'],
  ),
  OverviewSchedulePreview(
    day: 'DAY 2',
    title: '카페거리와 빈티지 샵',
    area: '나카자키초',
    stops: ['골목 산책', '빈티지 소품샵', '디저트 카페'],
  ),
  OverviewSchedulePreview(
    day: 'DAY 3',
    title: '우메다 쇼핑 데이',
    area: '우메다 - 신사이바시',
    stops: ['브런치', '헵파이브', '전망대'],
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
                      label: '여행중 문제 해결',
                      icon: Icons.support_agent_rounded,
                      onTap: () => _openComingSoon(context, '여행중 문제 해결'),
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

  void _openComingSoon(BuildContext context, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _ComingSoonPage(title: title)),
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
                child: Text(hasSchedule ? '전체 보기' : '일정 관리'),
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
            _ScheduleIllustrationCard(preview: schedules.first),
          ] else
            _EmptyScheduleCard(onCreateSchedule: onOpenSchedule),
        ],
      ),
    );
  }
}

class _ScheduleIllustrationCard extends StatelessWidget {
  const _ScheduleIllustrationCard({required this.preview});

  final OverviewSchedulePreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        border: Border.all(color: RouteInPalette.ink, width: 2),
        borderRadius: BorderRadius.circular(28),
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
          const SizedBox(height: 14),
          SizedBox(
            height: 118,
            width: double.infinity,
            child: CustomPaint(
              painter: const _TripRoutePainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    children: preview.stops.map((stop) {
                      return Expanded(
                        child: Text(
                          stop,
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
        borderRadius: BorderRadius.circular(28),
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
            '여행 동선을 그릴 일정을 먼저 만들어보세요.',
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
        borderRadius: BorderRadius.circular(28),
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
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
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
                  borderRadius: BorderRadius.circular(26),
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
    final branchPaint = Paint()
      ..color = RouteInPalette.denim
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final route = Path()
      ..moveTo(size.width * 0.12, size.height * 0.32)
      ..quadraticBezierTo(
        size.width * 0.32,
        size.height * 0.10,
        size.width * 0.50,
        size.height * 0.38,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.66,
        size.width * 0.86,
        size.height * 0.24,
      );
    final branch = Path()
      ..moveTo(size.width * 0.50, size.height * 0.38)
      ..quadraticBezierTo(
        size.width * 0.52,
        size.height * 0.08,
        size.width * 0.66,
        size.height * 0.10,
      );

    canvas.drawPath(route, routePaint);
    canvas.drawPath(branch, branchPaint);

    for (final point in [
      Offset(size.width * 0.12, size.height * 0.32),
      Offset(size.width * 0.50, size.height * 0.38),
      Offset(size.width * 0.86, size.height * 0.24),
    ]) {
      canvas.drawCircle(point, 12, Paint()..color = RouteInPalette.coral);
      canvas.drawCircle(point, 5, Paint()..color = RouteInPalette.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: RouteInPalette.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            '$title 기능을 준비하고 있습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
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
  final List<String> stops;
}
