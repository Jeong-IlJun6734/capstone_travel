import 'package:flutter_test/flutter_test.dart';

import 'package:demo_app/main.dart';

void main() {
  testWidgets('renders dashboard and adds a task', (tester) async {
    await tester.pumpWidget(const FocusFlowApp());

    expect(find.text('Focus Flow'), findsOneWidget);
    expect(find.text('오늘 일정 0/3 완료'), findsOneWidget);
    expect(find.text('작업 추가'), findsOneWidget);

    await tester.tap(find.text('작업 추가'));
    await tester.pumpAndSettle();

    expect(find.text('오늘 일정 0/4 완료'), findsOneWidget);
  });
}
