import 'package:flutter_test/flutter_test.dart';

import 'package:demo_app/main.dart';

void main() {
  testWidgets('opens indoor navigation split page and switches tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const FocusFlowApp());

    expect(find.text('Focus Flow'), findsOneWidget);
    expect(find.text('1번 페이지'), findsOneWidget);

    await tester.tap(find.text('1번 페이지').first);
    await tester.pumpAndSettle();

    expect(find.text('실내 길찾기'), findsOneWidget);
    expect(find.text('일정관리'), findsOneWidget);

    await tester.tap(find.text('실내 길찾기'));
    await tester.pumpAndSettle();

    expect(find.text('카메라'), findsOneWidget);
    expect(find.text('이미지'), findsOneWidget);
    expect(find.text('카메라 프리뷰'), findsOneWidget);
    expect(find.text('이미지 뷰'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('2번'));
    await tester.pumpAndSettle();
    expect(find.text('2번 페이지 모음'), findsOneWidget);

    await tester.tap(find.text('3번'));
    await tester.pumpAndSettle();
    expect(find.text('3번 페이지 모음'), findsOneWidget);
  });
}
