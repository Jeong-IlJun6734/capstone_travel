import 'package:flutter/material.dart';

import '../models/page_section.dart';
import 'indoor_navigation_page.dart';
import 'schedule_management_page.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.section});

  final PageSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(section.title),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: section.accent,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(section.icon, color: Colors.white, size: 32),
                  const SizedBox(height: 16),
                  Text(
                    section.category,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    section.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    section.subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (section.actions.isNotEmpty) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: section.actions.map((label) {
                  return FilledButton(
                    onPressed: () => _handleActionTap(context, label),
                    style: FilledButton.styleFrom(
                      backgroundColor: section.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    child: Text(label),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              '상세 내용',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: section.bullets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: section.accent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Text('${index + 1}'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            section.bullets[index],
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleActionTap(BuildContext context, String label) {
    if (label.contains('길찾기')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const IndoorNavigationPage()),
      );
      return;
    }

    if (label.contains('일정')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ScheduleManagementPage()),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label 기능은 아직 준비 중입니다.')));
  }
}
