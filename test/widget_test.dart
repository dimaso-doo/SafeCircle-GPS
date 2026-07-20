import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:safe_circle_gps/app/app.dart';

void main() {
  setUpAll(() async {
    dotenv.testLoad(fileInput: 'SAFE_CIRCLE_DEMO_MODE=true');
  });

  testWidgets('SafeCircle app widget can be built', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SafeCircleApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
