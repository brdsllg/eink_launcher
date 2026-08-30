import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/screens/reader_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSettings(
    WidgetTester tester,
    PdfFitMode fitMode, {
    bool allowZoomOutBeyondFit = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: ReaderSettingsScreen(
          initialSettings: ReaderSettings(
            fitMode: fitMode,
            allowZoomOutBeyondFit: allowZoomOutBeyondFit,
          ),
        ),
      ),
    );
  }

  testWidgets('fit height shows only the crop control', (tester) async {
    await pumpSettings(tester, PdfFitMode.fitHeight);

    // Fit mode itself lives in the reader menu overlay; repeating it here
    // was pure duplication.
    expect(find.text('Page fit'), findsNothing);
    expect(find.text('Fit height'), findsNothing);
    expect(find.text('Zoom / scroll'), findsNothing);

    expect(find.text('Automatic margin crop'), findsOneWidget);
    expect(find.text('Fit-width overlap'), findsNothing);
    expect(find.byKey(const Key('reader-settings-zoom-out')), findsNothing);

    await tester.tap(find.byKey(const Key('reader-settings-crop')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('reader-settings-crop')),
        matching: find.text('Disabled'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('fit width adds the overlap control', (tester) async {
    await pumpSettings(tester, PdfFitMode.fitWidth);

    expect(find.text('Automatic margin crop'), findsOneWidget);
    expect(find.text('Fit-width overlap'), findsOneWidget);
    expect(find.text('6%'), findsOneWidget);
    expect(find.byKey(const Key('reader-settings-zoom-out')), findsNothing);

    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.add));
    await tester.pump();
    expect(find.text('7%'), findsOneWidget);
  });

  testWidgets('zoom / scroll offers zoom-out only, defaulting to on', (
    tester,
  ) async {
    await pumpSettings(tester, PdfFitMode.zoom);

    expect(find.text('Automatic margin crop'), findsNothing);
    expect(find.byKey(const Key('reader-settings-crop')), findsNothing);
    expect(find.text('Fit-width overlap'), findsNothing);
    expect(find.text('Continuous pages'), findsNothing);
    expect(find.text('Page by page'), findsNothing);
    expect(find.text('Continuous-scroll momentum'), findsNothing);

    expect(
      find.descendant(
        of: find.byKey(const Key('reader-settings-zoom-out')),
        matching: find.text('Enabled'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('reader-settings-zoom-out')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('reader-settings-zoom-out')),
        matching: find.text('Disabled'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('reader-settings-save')));
    await tester.pump();
  });

  test('zoom-out setting drives the pinch floor', () {
    const on = ReaderSettings(fitMode: PdfFitMode.zoom);
    const off = ReaderSettings(
      fitMode: PdfFitMode.zoom,
      allowZoomOutBeyondFit: false,
    );

    expect(on.allowZoomOutBeyondFit, isTrue, reason: 'default is on');
    expect(on.minZoomScale, lessThan(1.0));
    expect(off.minZoomScale, 1.0);

    // Round-trips through library.json.
    expect(
      ReaderSettings.fromJson(off.toJson()).allowZoomOutBeyondFit,
      isFalse,
    );
    // Documents saved before the setting existed default to on.
    final legacy = on.toJson()..remove('allowZoomOutBeyondFit');
    expect(ReaderSettings.fromJson(legacy).allowZoomOutBeyondFit, isTrue);
  });
}
