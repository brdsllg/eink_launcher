import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/screens/reader_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PDF settings only show controls relevant to the selected mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderSettingsScreen(initialSettings: ReaderSettings()),
      ),
    );

    expect(find.text('Fit height'), findsOneWidget);
    expect(find.text('Zoom / scroll'), findsOneWidget);
    expect(find.text('Automatic margin crop'), findsOneWidget);
    expect(find.text('Fit-width overlap'), findsNothing);
    expect(find.text('Continuous pages'), findsNothing);
    expect(find.text('Page by page'), findsNothing);
    expect(find.text('Continuous-scroll momentum'), findsNothing);

    await tester.tap(find.byKey(const Key('reader-settings-crop')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('reader-settings-crop')),
        matching: find.text('Disabled'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Zoom / scroll'));
    await tester.pump();
    expect(find.text('Automatic margin crop'), findsNothing);
    expect(find.text('Fit-width overlap'), findsNothing);

    await tester.tap(find.text('Fit width'));
    await tester.pump();
    expect(find.text('Automatic margin crop'), findsOneWidget);
    expect(find.text('Fit-width overlap'), findsOneWidget);
    expect(find.text('6%'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.add));
    await tester.pump();
    expect(find.text('7%'), findsOneWidget);
  });
}
