import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eink_launcher/main.dart';

void main() {
  testWidgets('File browser renders its app bar', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final messenger = tester.binding.defaultBinaryMessenger;
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    const battery = MethodChannel('eink_launcher/battery_events');
    messenger.setMockMethodCallHandler(
      permissions,
      (call) async => call.method == 'requestPermissions'
          ? {for (final permission in call.arguments as List) permission: 0}
          : 0,
    );
    messenger.setMockMethodCallHandler(battery, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(permissions, null);
      messenger.setMockMethodCallHandler(battery, null);
    });
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // The app always renders the Home (top-left) icon — present whether or not
    // storage permission has been granted yet.
    expect(find.byIcon(Icons.home), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
