import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziggo_app/core/services/app_version_service.dart';
import 'package:ziggo_app/core/widgets/app_version_text.dart';

void main() {
  tearDown(() {
    AppVersionService.setLoaderForTesting(null);
  });

  test('normalize trims whitespace, leading v, and build metadata', () {
    expect(AppVersionService.normalize(' 1.1.5 '), '1.1.5');
    expect(AppVersionService.normalize('v1.2.0+40'), '1.2.0');
    expect(AppVersionService.normalize('V2.0.1'), '2.0.1');
    expect(AppVersionService.normalize(''), '');
  });

  testWidgets('AppVersionText updates dynamically for customer and driver formats',
      (WidgetTester tester) async {
    AppVersionService.setLoaderForTesting(() async => '1.1.5');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppVersionText(prefix: 'Ziggo • v', fallbackText: 'Ziggo'),
              AppVersionText(prefix: 'Version '),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ziggo • v1.1.5'), findsOneWidget);
    expect(find.text('Version 1.1.5'), findsOneWidget);

    AppVersionService.setLoaderForTesting(() async => '1.2.0');

    await tester.pumpWidget(
      const MaterialApp(
        key: ValueKey('updated'),
        home: Scaffold(
          body: Column(
            children: [
              AppVersionText(prefix: 'Ziggo • v', fallbackText: 'Ziggo'),
              AppVersionText(prefix: 'Version '),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ziggo • v1.2.0'), findsOneWidget);
    expect(find.text('Version 1.2.0'), findsOneWidget);
  });

  testWidgets('AppVersionText falls back cleanly when version is unavailable',
      (WidgetTester tester) async {
    AppVersionService.setLoaderForTesting(
      () async => throw Exception('unavailable'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppVersionText(prefix: 'Ziggo • v', fallbackText: 'Ziggo'),
              AppVersionText(prefix: 'Version '),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ziggo'), findsOneWidget);
    expect(find.textContaining('Version'), findsNothing);
  });
}
