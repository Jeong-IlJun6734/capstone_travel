import 'package:flutter/material.dart';

import '../models/page_section.dart';
import '../theme/route_in_palette.dart';
import '../widgets/metric_chip.dart';
import '../widgets/section_card.dart';
import 'detail_page.dart';

class FeatureListPage extends StatelessWidget {
  const FeatureListPage({
    super.key,
    required this.heading,
    required this.description,
    required this.sections,
    this.showHeroCard = false,
  });

  final String heading;
  final String description;
  final List<PageSection> sections;
  final bool showHeroCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
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
                      heading,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: RouteInPalette.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: RouteInPalette.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.wb_sunny_outlined),
              ),
            ],
          ),
        ),
        if (showHeroCard)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [RouteInPalette.navy, RouteInPalette.denim],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '페이지 이동 데모',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: RouteInPalette.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '각 카드 탭 시 체크 대신 전용 상세 페이지로 이동합니다.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: RouteInPalette.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      MetricChip(label: 'Pages', value: '${sections.length}'),
                      const MetricChip(label: 'Type', value: 'Push'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            itemCount: sections.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final section = sections[index];
              return SectionCard(
                section: section,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DetailPage(section: section),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
