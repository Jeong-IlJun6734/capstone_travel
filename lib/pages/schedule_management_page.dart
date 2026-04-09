import 'package:flutter/material.dart';

class ScheduleManagementPage extends StatefulWidget {
  const ScheduleManagementPage({super.key});

  @override
  State<ScheduleManagementPage> createState() => _ScheduleManagementPageState();
}

class _ScheduleManagementPageState extends State<ScheduleManagementPage> {
  int _selectedDayIndex = 0;
  late final List<_TripDay> _days;
  int _nextPlaceId = 1;

  static const List<_TripDay> _seedDays = [
    _TripDay(
      label: 'DAY 1',
      title: '난바 먹방 루트',
      area: '도톤보리 - 구로몬 시장',
      totalTime: '6시간 20분',
      walkingDistance: '1.3km',
      places: [
        _TripPlace(
          id: 1,
          category: '관광',
          name: '도톤보리',
          note: '네온사인 거리에서 여행 시작, 사진 스팟 체크',
          move: '도보 7분',
        ),
        _TripPlace(
          id: 2,
          category: '식당',
          name: '오코노미야키 런치',
          note: '대기 줄이 짧은 점심 타임에 방문',
          move: '도보 9분',
        ),
        _TripPlace(
          id: 3,
          category: '시장',
          name: '구로몬 시장',
          note: '간식, 해산물, 기념품까지 한 번에 보기',
          move: '도보 12분',
        ),
        _TripPlace(
          id: 4,
          category: '바',
          name: '우라 난바 이자카야',
          note: '저녁 마무리, 예약 여부 확인 필요',
        ),
      ],
    ),
    _TripDay(
      label: 'DAY 2',
      title: '카페거리와 빈티지 샵',
      area: '나카자키초',
      totalTime: '5시간 10분',
      walkingDistance: '1.0km',
      places: [
        _TripPlace(
          id: 5,
          category: '산책',
          name: '나카자키초 골목',
          note: '오픈 전 조용한 거리 먼저 둘러보기',
          move: '도보 5분',
        ),
        _TripPlace(
          id: 6,
          category: '쇼핑',
          name: '빈티지 소품샵',
          note: '문 여는 시간 11:00 체크',
          move: '도보 4분',
        ),
        _TripPlace(
          id: 7,
          category: '카페',
          name: '디저트 카페',
          note: '브레이크 타임 전에 방문',
          move: '도보 8분',
        ),
        _TripPlace(
          id: 8,
          category: '포토',
          name: '감성 골목 사진 코스',
          note: '해질녘 촬영 추천',
        ),
      ],
    ),
    _TripDay(
      label: 'DAY 3',
      title: '우메다 쇼핑 데이',
      area: '우메다 - 신사이바시',
      totalTime: '7시간 00분',
      walkingDistance: '2.1km',
      places: [
        _TripPlace(
          id: 9,
          category: '브런치',
          name: '우동 브런치',
          note: '아침 줄이 짧을 때 입장',
          move: '지하철 18분',
        ),
        _TripPlace(
          id: 10,
          category: '쇼핑',
          name: '헵파이브',
          note: '관람차와 쇼핑 동선 함께 잡기',
          move: '도보 11분',
        ),
        _TripPlace(
          id: 11,
          category: '전망대',
          name: '공중정원 전망대',
          note: '야경 시간대 입장권 확보',
          move: '지하철 15분',
        ),
        _TripPlace(
          id: 12,
          category: '카페',
          name: '신사이바시 커피 스톱',
          note: '쇼핑 중간 휴식 포인트',
        ),
      ],
    ),
    _TripDay(
      label: 'DAY 4',
      title: '텐마 먹거리 산책',
      area: '텐진바시스지',
      totalTime: '4시간 40분',
      walkingDistance: '0.9km',
      places: [
        _TripPlace(
          id: 13,
          category: '시장',
          name: '텐진바시스지 상점가',
          note: '기념품 마지막 구매 추천',
          move: '도보 6분',
        ),
        _TripPlace(
          id: 14,
          category: '식당',
          name: '스시 점심',
          note: '오픈 시간 맞춰 방문',
          move: '도보 3분',
        ),
        _TripPlace(
          id: 15,
          category: '디저트',
          name: '와라비모찌 카페',
          note: '포장 가능 여부 확인',
          move: '도보 5분',
        ),
        _TripPlace(
          id: 16,
          category: '휴식',
          name: '마무리 티타임',
          note: '공항 이동 전 짐 정리 체크',
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _days = _seedDays.map((day) => day.copy()).toList();
    _nextPlaceId =
        _days
            .expand((day) => day.places)
            .map((place) => place.id)
            .fold<int>(0, (maxId, id) => id > maxId ? id : maxId) +
        1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = _days[_selectedDayIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('일정관리'),
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPlaceDialog,
        backgroundColor: const Color(0xFF1B1B1B),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('일정 추가'),
      ),
      body: ListView(
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
                onPressed: _showAddPlaceDialog,
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
                    color: isSelected ? Colors.white : const Color(0xFF1B1B1B),
                    fontWeight: FontWeight.w700,
                  ),
                  selectedColor: const Color(0xFF1B1B1B),
                  backgroundColor: Colors.white,
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
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
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
      ),
    );
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
  }

  Future<void> _showAddPlaceDialog() async {
    final categoryController = TextEditingController();
    final nameController = TextEditingController();
    final noteController = TextEditingController();
    final moveController = TextEditingController();

    final created = await showDialog<_TripPlace>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('일정 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: '카테고리'),
                ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '장소 이름'),
                ),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: '메모'),
                  maxLines: 2,
                ),
                TextField(
                  controller: moveController,
                  decoration: const InputDecoration(
                    labelText: '이동 정보',
                    hintText: '예: 도보 8분',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final category = categoryController.text.trim();
                final name = nameController.text.trim();
                final note = noteController.text.trim();
                final move = moveController.text.trim();

                if (category.isEmpty || name.isEmpty || note.isEmpty) {
                  return;
                }

                Navigator.of(dialogContext).pop(
                  _TripPlace(
                    id: _nextPlaceId,
                    category: category,
                    name: name,
                    note: note,
                    move: move.isEmpty ? null : move,
                  ),
                );
              },
              child: const Text('추가'),
            ),
          ],
        );
      },
    );

    categoryController.dispose();
    nameController.dispose();
    noteController.dispose();
    moveController.dispose();

    if (created == null || !mounted) {
      return;
    }

    setState(() {
      _days[_selectedDayIndex].places.add(created);
      _nextPlaceId += 1;
    });
  }

  void _removePlace(int placeId) {
    setState(() {
      _days[_selectedDayIndex].places.removeWhere(
        (place) => place.id == placeId,
      );
    });
  }
}

class _MapPreviewSection extends StatelessWidget {
  const _MapPreviewSection({required this.day});

  final _TripDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFFD8E6F2), Color(0xFFF0E6D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _MapPlaceholderPainter()),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'MAP AREA',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '실제 지도 자리',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${day.label} · ${day.area}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '이 영역은 이후 실제 지도와 장소 마커, 경로 선을 붙일 수 있도록 남겨둔 공간입니다.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
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

class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.day});

  final _TripDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE8DED0),
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
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.black54),
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
        color: Colors.white,
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
                  color: Color(0xFF1B1B1B),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (place.move != null)
                Container(
                  width: 2,
                  height: 48,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: const Color(0xFFE0D6C8),
                ),
            ],
          ),
          const SizedBox(width: 14),
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
                        color: const Color(0xFFF1ECE3),
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
                        child: Icon(Icons.drag_handle, color: Colors.black45),
                      ),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.black45,
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
                const SizedBox(height: 6),
                Text(
                  place.note,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                if (place.move != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.route_outlined,
                        size: 18,
                        color: Color(0xFF7C6A55),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '다음 장소까지 ${place.move}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF7C6A55),
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
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1B1B1B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
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
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final routePaint = Paint()
      ..color = const Color(0xFF1B1B1B)
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
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), linePaint);
    }

    for (var i = 1; i < 4; i++) {
      final dy = size.height * i / 4;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), linePaint);
    }

    canvas.drawPath(path, routePaint);

    final points = [
      Offset(size.width * 0.18, size.height * 0.62),
      Offset(size.width * 0.48, size.height * 0.64),
      Offset(size.width * 0.78, size.height * 0.40),
    ];

    for (final point in points) {
      canvas.drawCircle(point, 10, Paint()..color = const Color(0xFFFF7A59));
      canvas.drawCircle(point, 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TripDay {
  const _TripDay({
    required this.label,
    required this.title,
    required this.area,
    required this.totalTime,
    required this.walkingDistance,
    required this.places,
  });

  final String label;
  final String title;
  final String area;
  final String totalTime;
  final String walkingDistance;
  final List<_TripPlace> places;

  _TripDay copy() {
    return _TripDay(
      label: label,
      title: title,
      area: area,
      totalTime: totalTime,
      walkingDistance: walkingDistance,
      places: places.map((place) => place.copy()).toList(),
    );
  }
}

class _TripPlace {
  const _TripPlace({
    required this.id,
    required this.category,
    required this.name,
    required this.note,
    this.move,
  });

  final int id;
  final String category;
  final String name;
  final String note;
  final String? move;

  _TripPlace copy() {
    return _TripPlace(
      id: id,
      category: category,
      name: name,
      note: note,
      move: move,
    );
  }
}
