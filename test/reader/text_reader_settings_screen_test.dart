import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/screens/reader_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('text settings expose discrete typography controls', (
    tester,
  ) async {
    ReaderSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => OutlinedButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<ReaderSettings>(
                MaterialPageRoute(
                  builder: (_) => const ReaderSettingsScreen(
                    initialSettings: ReaderSettings(),
                    format: DocFormat.epub,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Text settings'), findsOneWidget);
    expect(find.text('Latin font'), findsOneWidget);
    expect(
      find.byKey(const Key('reader-settings-font-larger')),
      findsOneWidget,
    );
    expect(find.text('Page fit'), findsNothing);

    await tester.tap(find.byKey(const Key('reader-settings-font-larger')));
    await tester.tap(find.byKey(const Key('reader-settings-save')));
    await tester.pumpAndSettle();

    expect(saved?.fontSizeStep, 4);
  });
}
