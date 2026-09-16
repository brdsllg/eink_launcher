import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
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

  testWidgets('study selectors and Save stay separate at enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(630, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const ReaderSettingsScreen(
            initialSettings: ReaderSettings(),
            format: DocFormat.epub,
            studySources: ['Commentary A'],
            studyTranslations: [
              StudyTranslationOption(
                id: 'long-edition',
                label: 'A very long translation title from this EPUB',
              ),
            ],
            primaryStudyTranslationId: 'long-edition',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Book default'), findsNothing);
    expect(
      find.text('A very long translation title from this EPUB'),
      findsOneWidget,
    );

    final save = tester.getRect(find.byKey(const Key('reader-settings-save')));
    final saveText = tester.getRect(find.text('Save'));
    expect(save.width, greaterThanOrEqualTo(88));
    expect(save.contains(saveText.center), isTrue);
    expect(saveText.height, lessThan(save.height));

    final selectors = find.byType(DropdownButtonFormField<String>);
    expect(selectors, findsNWidgets(2));
    final languageLabel = tester.getRect(find.text('Commentary language'));
    final translationLabel = tester.getRect(find.text('Main translation'));
    final languageField = tester.getRect(selectors.at(0));
    final translationField = tester.getRect(selectors.at(1));
    expect(languageLabel.bottom, lessThan(languageField.top));
    expect(languageField.bottom, lessThan(translationLabel.top));
    expect(translationLabel.bottom, lessThan(translationField.top));
  });
}
