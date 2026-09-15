import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/screens/reader_settings_screen.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';

void main() {
  test(
    'responsive pagination preserves complete synchronous page geometry',
    () async {
      final blocks = List.generate(
        320,
        (i) => ContentBlock(
          type: BlockType.paragraph,
          runs: [
            InlineRun(
              text: 'Verse $i with commentary spanning multiple lines. ' * 3,
            ),
          ],
        ),
      );
      const paginator = EpubPaginatorService();
      const settings = ReaderSettings();
      const size = Size(260, 350);
      final expected = paginator.paginateSpine(
        spineIndex: 0,
        blocks: blocks,
        contentSize: size,
        settings: settings,
      );
      var updates = 0;
      final actual = await paginator.paginateSpineResponsive(
        spineIndex: 0,
        blocks: blocks,
        contentSize: size,
        settings: settings,
        isCancelled: () => false,
        onProgress: (_) => updates++,
      );
      expect(updates, greaterThan(1));
      expect(actual.length, expected.length);
      for (var i = 0; i < actual.length; i++) {
        expect(actual[i].start, expected[i].start);
        expect(actual[i].end, expected[i].end);
        expect(
          actual[i].slices.map(
            (s) => [s.blockIndex, s.startCharOffset, s.endCharOffset, s.height],
          ),
          expected[i].slices.map(
            (s) => [s.blockIndex, s.startCharOffset, s.endCharOffset, s.height],
          ),
        );
      }
    },
  );

  test(
    'link hit-testing uses run boundaries and rejects surrounding whitespace',
    () {
      const block = ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'Open note', href: '#note')],
      );
      const settings = ReaderSettings(justify: false, hyphenate: false);
      final painter = TextBlockLayout.createPainter(block, settings, 300);
      final box = painter
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 9),
          )
          .first;
      expect(
        TextBlockLayout.linkAtOffset(block, settings, 300, box.toRect().center),
        '#note',
      );
      expect(
        TextBlockLayout.linkAtOffset(
          block,
          settings,
          300,
          const Offset(290, 10),
        ),
        isNull,
      );
      painter.dispose();
    },
  );

  testWidgets(
    'study controls fit a narrow reader and persist selected settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: ReaderSettingsScreen(
            initialSettings: ReaderSettings(),
            format: DocFormat.epub,
            studySources: ['Rashi on Genesis', 'Other'],
            studyTranslations: ['Default', 'Alternate'],
          ),
        ),
      );
      expect(find.text('Inline commentary'), findsOneWidget);
      await tester.tap(find.text('Commentary sources'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Rashi on Genesis')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rashi on Genesis'));
      await tester.pumpAndSettle();
      final choice = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('Rashi on Genesis'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(choice.value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
