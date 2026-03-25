import 'package:flutter/material.dart';

void main() {
  runApp(const FocusFlowApp());
}

class FocusFlowApp extends StatelessWidget {
  const FocusFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const canvas = Color(0xFFF4F1EA);
    const ink = Color(0xFF1B1B1B);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Focus Flow',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFCC5A2B),
          brightness: Brightness.light,
          surface: canvas,
        ),
        scaffoldBackgroundColor: canvas,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
      ),
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  final List<DemoTask> _tasks = [
    DemoTask(
      title: '와이어프레임 정리',
      category: 'Design',
      time: '09:00',
      accent: const Color(0xFFCC5A2B),
    ),
    DemoTask(
      title: 'API 연결 테스트',
      category: 'Dev',
      time: '11:30',
      accent: const Color(0xFF2F6B5F),
    ),
    DemoTask(
      title: '발표 자료 초안',
      category: 'Docs',
      time: '16:00',
      accent: const Color(0xFF355C9A),
    ),
  ];

  int _selectedIndex = 0;

  int get _completedCount => _tasks.where((task) => task.isDone).length;

  void _toggleTask(DemoTask task) {
    setState(() {
      task.isDone = !task.isDone;
    });
  }

  void _addTask() {
    setState(() {
      final index = _tasks.length + 1;
      _tasks.add(
        DemoTask(
          title: '새 작업 $index',
          category: 'Quick',
          time: '${8 + index}:15',
          accent: const Color(0xFF7A4B8E),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Focus Flow',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '오늘 일정 $_completedCount/${_tasks.length} 완료',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.wb_sunny_outlined),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B1B1B), Color(0xFF3C332C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deep Work Session',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '집중 시간 72분 확보. 가장 중요한 작업부터 처리하세요.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _MetricChip(label: 'Tasks', value: '${_tasks.length}'),
                        const SizedBox(width: 12),
                        _MetricChip(label: 'Done', value: '$_completedCount'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                itemBuilder: (context, index) {
                  final task = _tasks[index];
                  return _TaskCard(task: task, onTap: () => _toggleTask(task));
                },
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemCount: _tasks.length,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTask,
        backgroundColor: const Color(0xFFCC5A2B),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('작업 추가'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});

  final DemoTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 72,
                decoration: BoxDecoration(
                  color: task.accent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.category,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: task.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: task.isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.time,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: task.isDone ? task.accent : Colors.black12,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  task.isDone ? Icons.check : Icons.circle_outlined,
                  color: task.isDone ? Colors.white : Colors.black45,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DemoTask {
  DemoTask({
    required this.title,
    required this.category,
    required this.time,
    required this.accent,
    this.isDone = false,
  });

  final String title;
  final String category;
  final String time;
  final Color accent;
  bool isDone;
}
