import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:route_in/main.dart';
import 'package:route_in/pages/overview_page.dart';

void main() {
  testWidgets('opens indoor navigation split page and switches tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const RouteInApp());

    expect(find.text('로그인'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'traveler@example.com',
    );
    await tester.enterText(find.byKey(const Key('login-password')), 'secret1');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('RouteIn'), findsOneWidget);
    expect(find.text('내 일정'), findsOneWidget);
    expect(find.text('일정 관리하기'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overview-indoor-navigation')));
    await tester.pumpAndSettle();

    expect(find.text('Indoor Navigation'), findsOneWidget);
    expect(find.text('Live Sensor Feed'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('2번'));
    await tester.pumpAndSettle();
    expect(find.text('2번 페이지 모음'), findsOneWidget);

    await tester.tap(find.text('3번'));
    await tester.pumpAndSettle();
    expect(find.text('3번 페이지 모음'), findsOneWidget);
  });

  testWidgets('offers schedule creation when overview has no schedule', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OverviewPage(schedules: [])),
      ),
    );

    expect(find.text('아직 만든 일정이 없습니다.'), findsOneWidget);
    expect(find.text('일정 만들기'), findsOneWidget);
  });
}
