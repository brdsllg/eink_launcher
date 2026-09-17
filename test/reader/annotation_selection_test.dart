import 'package:eink_launcher/reader/models/annotation.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/annotation_text_mapping.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/widgets/block_slice_view.dart';
import 'package:eink_launcher/reader/widgets/selection_toolbar.dart';
import 'package:eink_launcher/reader/widgets/tap_zone_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const settings = ReaderSettings(hyphenate: false, justify: false);
const block = ContentBlock(
  type: BlockType.paragraph,
  runs: [InlineRun(text: 'alpha beta gamma delta')],
);

Annotation annotation({int start = 6, int end = 10}) => Annotation(
  id: 'a',
  docId: 'book',
  createdAt: DateTime.utc(2026),
  spineIndex: 0,
  blockIndex: 0,
  startOffset: start,
  endOffset: end,
  text: 'beta',
);

void main() {
  test(
    'anchors survive prefixes, generated hyphens and typography changes',
    () {
      const source = ContentBlock(
        type: BlockType.listItem,
        runs: [
          InlineRun(text: 'Extraordinary '),
          InlineRun(text: 'internationalization'),
        ],
      );
      for (final options in [const ReaderSettings(hyphenate: true), settings]) {
        final map = AnnotationTextMapping(source, options);
        final a = annotation(start: 14, end: source.characterCount);
        final display = map.toDisplay(a)!;
        expect(
          map.toSource(display),
          TextSelection(baseOffset: 14, extentOffset: source.characterCount),
        );
        expect(map.sourceOffset(0), 0);
        expect(map.sourceOffset(10000), source.characterCount);
        expect(map.toDisplay(annotation(start: -1)), isNull);
        expect(map.toDisplay(annotation(end: 10000)), isNull);
      }
    },
  );

  testWidgets('toolbar exposes four accessible actions on a narrow screen', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: SelectionToolbar(
              onCopy: () => calls.add('copy'),
              onDictionary: () => calls.add('dictionary'),
              onAddNote: () => calls.add('note'),
              onUnderline: () => calls.add('underline'),
            ),
          ),
        ),
      ),
    );
    for (final name in ['copy', 'dictionary', 'note', 'underline']) {
      await tester.tap(find.byKey(Key('selection-$name')));
    }
    expect(calls, ['copy', 'dictionary', 'note', 'underline']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'handles anchor to text and dragging clamps to block boundaries',
    (tester) async {
      final painter = TextBlockLayout.createPainter(block, settings, 360);
      addTearDown(painter.dispose);
      final word = painter
          .getBoxesForSelection(
            const TextSelection(baseOffset: 6, extentOffset: 10),
          )
          .first;
      TextSelection? saved;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpBlock(tester, onAnnotate: (range, _, _) async => saved = range);
      await tester.longPressAt(word.toRect().center);
      await tester.pump();
      expect(
        tester.getTopRight(find.byKey(const Key('selection-start-handle'))),
        Offset(word.start, word.bottom),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('selection-end-handle'))),
        Offset(word.end, word.bottom),
      );
      await tester.drag(
        find.byKey(const Key('selection-end-handle')),
        const Offset(600, 300),
      );
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('selection-start-handle')),
        const Offset(-600, -300),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('selection-underline')));
      await tester.pump();
      expect(saved, const TextSelection(baseOffset: 0, extentOffset: 22));
      await tester.longPressAt(word.toRect().center);
      await tester.pump();
      await tester.tap(find.byKey(const Key('selection-copy')));
      await tester.pump();
      expect(copied, 'beta');
      expect(find.byType(SelectionToolbar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'underline paints, intercepts its own taps and disappears after deletion',
    (tester) async {
      final a = annotation();
      Annotation? opened;
      var turns = 0;
      final painter = TextBlockLayout.createPainter(block, settings, 360);
      addTearDown(painter.dispose);
      final box = painter
          .getBoxesForSelection(
            const TextSelection(baseOffset: 6, extentOffset: 10),
          )
          .first;
      await pumpBlock(
        tester,
        annotations: [a],
        onOpen: (a) => opened = a,
        onTurn: () => turns++,
      );
      final painted = find
          .descendant(
            of: find.byType(BlockSliceView),
            matching: find.byType(CustomPaint),
          )
          .first;
      expect(
        painted,
        paints..line(
          color: Colors.black,
          strokeWidth: 1.5,
          p1: Offset(box.left, box.bottom),
          p2: Offset(box.right, box.bottom),
        ),
      );
      await tester.tapAt(box.toRect().center);
      expect(opened, same(a));
      expect(turns, 0);
      await tester.tapAt(const Offset(350, 100));
      expect(turns, 1);
      await pumpBlock(tester, onTurn: () => turns++);
      expect(painted, isNot(paints..line()));
      await tester.tapAt(box.toRect().center);
      expect(turns, 2);
    },
  );

  testWidgets('page replacement dismisses selection controls', (tester) async {
    await pumpBlock(tester, onAnnotate: (_, _, _) async {});
    await tester.longPressAt(const Offset(20, 12));
    await tester.pump();
    expect(find.byType(SelectionToolbar), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(find.byType(SelectionToolbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typography rebuild safely dismisses an active selection', (
    tester,
  ) async {
    await pumpBlock(tester, onAnnotate: (_, _, _) async {});
    await tester.longPressAt(const Offset(20, 12));
    await tester.pump();
    expect(find.byType(SelectionToolbar), findsOneWidget);
    await pumpBlock(
      tester,
      options: settings.copyWith(fontSizeStep: 6),
      onAnnotate: (_, _, _) async {},
    );
    await tester.pump();
    expect(find.byType(SelectionToolbar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> pumpBlock(
  WidgetTester tester, {
  List<Annotation> annotations = const [],
  ReaderSettings options = settings,
  ValueChanged<Annotation>? onOpen,
  VoidCallback? onTurn,
  Future<void> Function(TextSelection, String, bool)? onAnnotate,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 360,
          height: 160,
          child: TapZoneLayer(
            onPrevious: onTurn ?? () {},
            onNext: onTurn ?? () {},
            onMenu: onTurn ?? () {},
            child: BlockSliceView(
              block: block,
              settings: options,
              pageHeight: 400,
              slice: const BlockSlice(
                blockIndex: 0,
                startCharOffset: 0,
                endCharOffset: 22,
                sourceTop: 0,
                height: 160,
              ),
              annotations: annotations,
              onOpenAnnotation: onOpen,
              onAnnotate: onAnnotate,
            ),
          ),
        ),
      ),
    ),
  ),
);
