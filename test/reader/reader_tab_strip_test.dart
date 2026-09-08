import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/widgets/reader_tab_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final docs = List.generate(
    7,
    (index) => DocRef(
      id: '$index',
      path: '/books/$index.txt',
      format: DocFormat.txt,
      title: 'Book $index',
      fileSize: 1,
    ),
  );

  testWidgets('arrows page three tabs and clamp at each end', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderTabStrip(
            tabs: docs,
            selectedTabId: docs.first.id,
            onSelect: (_) {},
            onClose: (_) {},
          ),
        ),
      ),
    );

    IconButton arrow(String direction) => tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(Key('reader-tabs-$direction')),
        matching: find.byType(IconButton),
      ),
    );

    expect(find.text('Book 0'), findsOneWidget);
    expect(find.text('Book 2'), findsOneWidget);
    expect(find.text('Book 3'), findsNothing);
    expect(arrow('previous').onPressed, isNull);
    await tester.tap(find.byKey(const Key('reader-tabs-next')));
    await tester.pump();
    expect(find.text('Book 0'), findsNothing);
    expect(find.text('Book 3'), findsOneWidget);
    expect(find.text('Book 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-tabs-next')));
    await tester.pump();
    expect(find.text('Book 6'), findsOneWidget);
    expect(find.text('Book 5'), findsNothing);
    expect(arrow('next').onPressed, isNull);
    await tester.tap(find.byKey(const Key('reader-tabs-previous')));
    await tester.pump();
    expect(find.text('Book 3'), findsOneWidget);
    expect(find.text('Book 6'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting and closing tabs reveal selection without mis-taps', (
    tester,
  ) async {
    var tabs = docs.toList();
    var selectedId = docs[4].id;
    var selectionCount = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ReaderTabStrip(
                tabs: tabs,
                selectedTabId: selectedId,
                onSelect: (doc) => setState(() {
                  selectionCount++;
                  selectedId = doc.id;
                }),
                onClose: (doc) => setState(() {
                  tabs = tabs.where((tab) => tab.id != doc.id).toList();
                  if (doc.id == selectedId) selectedId = tabs.last.id;
                }),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Book 4'), findsOneWidget);
    expect(
      tester.widget<Material>(find.byKey(const Key('reader-tab-4'))).color,
      Colors.black,
    );
    await tester.tap(find.text('Book 3'));
    await tester.pump();
    expect(selectedId, '3');
    expect(selectionCount, 1);
    await tester.tap(find.byKey(const Key('reader-tab-close-3')));
    await tester.pump();
    expect(selectionCount, 1, reason: 'Close must not also select the tab');
    expect(selectedId, '6');
    expect(find.text('Book 6'), findsOneWidget);
    expect(find.text('Book 3'), findsNothing);

    update(() => selectedId = '0');
    await tester.pump();
    expect(find.text('Book 0'), findsOneWidget);
    expect(find.text('Book 6'), findsNothing);
    update(() => tabs = tabs.take(1).toList());
    await tester.pump();
    expect(find.text('Book 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(800, 360)]) {
    testWidgets('long titles fit in the compact full-width row at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderTabStrip(
              tabs: [
                for (final doc in docs.take(3))
                  DocRef(
                    id: doc.id,
                    path: doc.path,
                    format: doc.format,
                    title: 'A very long title with many words ${doc.id}',
                    fileSize: doc.fileSize,
                  ),
              ],
              selectedTabId: '0',
              onSelect: (_) {},
              onClose: (_) {},
            ),
          ),
        ),
      );
      final tabSize = tester.getSize(find.byKey(const Key('reader-tab-0')));
      expect(
        tester.getSize(find.byKey(const Key('reader-tab-strip'))).height,
        56,
      );
      expect(tabSize.height, 56);
      final arrowWidth = size.width < 360 ? 48 : 56;
      expect(
        tabSize.width,
        closeTo((size.width - 2 * arrowWidth - 4) / 3, 0.01),
      );
      for (var slot = 1; slot < 3; slot++) {
        expect(
          tester.getSize(find.byKey(Key('reader-tab-$slot'))).width,
          closeTo(tabSize.width, 0.01),
        );
      }
      final title = tester.widget<Text>(find.textContaining('many words 0'));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  }
}
