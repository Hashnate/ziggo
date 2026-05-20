import 'package:flutter_test/flutter_test.dart';

import 'package:ziggo_app/main.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ZiggoApp());
    await tester.pump();
    expect(find.byType(ZiggoApp), findsOneWidget);
  });
}
