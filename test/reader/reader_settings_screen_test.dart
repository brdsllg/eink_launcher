import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/screens/reader_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PDF settings use discrete controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderSettingsScreen(initialSettings: ReaderSettings()),
      ),
    );

    expect(find.text('Fit height'), findsOneWidget);
    expect(find.text('6%'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-settings-crop')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('reader-settings-crop')),
        matching: find.text('Disabled'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.add));
    await tester.pump();
    expect(find.text('7%'), findsOneWidget);
  });
}
