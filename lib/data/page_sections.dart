import 'package:flutter/material.dart';

import '../models/page_section.dart';

const List<PageSection> pageSections = [
  PageSection(
    title: '1번 페이지',
    category: 'PathFinding',
    subtitle: '길찾기 기능과 이동 동선을 확인합니다.',
    accent: Color(0xFFCC5A2B),
    icon: Icons.map_outlined,
    actions: ['실내 길찾기', '일정관리'],
    bullets: [
      '출발지와 도착지를 입력합니다.',
      '추천 경로와 이동 시간을 확인합니다.',
      '길안내 시작 버튼으로 다음 흐름을 연결합니다.',
    ],
  ),
  PageSection(
    title: '2번 페이지',
    category: 'Other Helps',
    subtitle: '부가 기능과 여행 보조 도구를 모아둔 화면입니다.',
    accent: Color(0xFF2F6B5F),
    icon: Icons.travel_explore_outlined,
    actions: [],
    bullets: [
      '주변 편의시설과 추천 장소를 표시합니다.',
      '여행 중 필요한 보조 기능 진입점을 제공합니다.',
      '자주 쓰는 기능을 빠르게 실행할 수 있습니다.',
    ],
  ),
  PageSection(
    title: '3번 페이지',
    category: 'Todo',
    subtitle: '할 일과 준비 항목을 정리하는 화면입니다.',
    accent: Color(0xFF355C9A),
    icon: Icons.checklist_outlined,
    actions: [],
    bullets: [
      '오늘 해야 할 항목을 정리합니다.',
      '우선순위가 높은 작업을 위쪽에 배치합니다.',
      '준비 완료 여부를 확인할 수 있습니다.',
    ],
  ),
];
