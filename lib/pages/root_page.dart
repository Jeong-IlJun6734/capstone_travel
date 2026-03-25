import 'package:flutter/material.dart';

import '../data/page_sections.dart';
import 'feature_list_page.dart';
import 'overview_page.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const OverviewPage(sections: pageSections),
      FeatureListPage(
        heading: '2번 페이지 모음',
        description: '보조 기능별로 상세 페이지에 들어갈 수 있습니다.',
        sections: [pageSections[1]],
      ),
      FeatureListPage(
        heading: '3번 페이지 모음',
        description: '할 일 관련 상세 화면으로 이동할 수 있습니다.',
        sections: [pageSections[2]],
      ),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.looks_one_outlined),
            selectedIcon: Icon(Icons.looks_one),
            label: '1번',
          ),
          NavigationDestination(
            icon: Icon(Icons.looks_two_outlined),
            selectedIcon: Icon(Icons.looks_two),
            label: '2번',
          ),
          NavigationDestination(
            icon: Icon(Icons.looks_3_outlined),
            selectedIcon: Icon(Icons.looks_3),
            label: '3번',
          ),
        ],
      ),
    );
  }
}
