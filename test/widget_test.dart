import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eink_launcher/main.dart';

void main() {
  testWidgets('File browser renders its app bar', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // The app always renders the Home (top-left) icon — present whether or not
    // storage permission has been granted yet.
    expect(find.byIcon(Icons.home), findsOneWidget);
  });
}

