import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/screens/reader_toc_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('flattens nested entries and returns the selected target', (
    tester,
  ) async {
    TocEntry? selected;
    const child = TocEntry(
      title: 'Section',
      level: 1,
      position: TextReadingPosition(
        spineIndex: 0,
        blockIndex: 4,
        charOffset: 0,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await Navigator.of(context).push<TocEntry>(
                MaterialPageRoute(
                  builder: (_) => const ReaderTocScreen(
                    entries: [
                      TocEntry(
                        title: 'Chapter',
                        position: TextReadingPosition(
                          spineIndex: 0,
                          blockIndex: 0,
                          charOffset: 0,
                        ),
                        children: [child],
                      ),
                    ],
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

    expect(find.text('Chapter'), findsOneWidget);
    expect(find.text('Section'), findsOneWidget);
    await tester.tap(find.text('Section'));
    await tester.pumpAndSettle();

    expect(selected?.position, child.position);
  });
}
