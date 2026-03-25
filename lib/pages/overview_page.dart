import 'package:flutter/material.dart';

import '../models/page_section.dart';
import 'feature_list_page.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.sections});

  final List<PageSection> sections;

  @override
  Widget build(BuildContext context) {
    return FeatureListPage(
      heading: 'Focus Flow',
      description: '원하는 페이지를 눌러서 상세 화면으로 이동하세요.',
      sections: sections,
      showHeroCard: true,
    );
  }
}
