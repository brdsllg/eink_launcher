import 'dart:async';

import 'package:eink_launcher/constants.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/screens/reader_search_screen.dart';
import 'package:eink_launcher/reader/services/text_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'searches on submission, paginates, and returns a logical match',
    (tester) async {
      final service = _ControlledSearch();
      TextSearchMatch? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  selected = await Navigator.of(context).push<TextSearchMatch>(
                    noTransitionRoute(
                      ReaderSearchScreen(
                        spine: const [],
                        searchService: service,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'שלום');
      expect(service.queries, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(service.queries, ['שלום']);
      expect(find.text('Searching…'), findsOneWidget);
      final matches = List.generate(12, (i) => _match(i));
      service.pending.single.complete(TextSearchResults(matches: matches));
      await tester.pumpAndSettle();
      expect(find.text('12 matches'), findsOneWidget);
      expect(find.text('Chapter 0'), findsOneWidget);
      expect(find.text('Chapter 11'), findsNothing);
      await tester.tap(find.byTooltip('Last page'));
      await tester.pump();
      expect(find.text('Chapter 11'), findsOneWidget);
      await tester.tap(find.text('Chapter 11'));
      await tester.pumpAndSettle();
      expect(selected?.position, matches.last.position);
    },
  );

  testWidgets('discards stale searches and runs only the latest queued query', (
    tester,
  ) async {
    final service = _ControlledSearch();
    await _open(tester, service);
    await _submit(tester, 'old');
    await _submit(tester, 'middle');
    await _submit(tester, 'new');
    expect(service.queries, ['old']);
    service.pending.first.complete(TextSearchResults(matches: [_match(0)]));
    await tester.pump();
    expect(service.queries, ['old', 'new']);
    expect(find.text('Chapter 0'), findsNothing);
    service.pending.last.complete(TextSearchResults(matches: [_match(1)]));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.pump();
    expect(find.text('Chapter 1'), findsNothing);
  });

  testWidgets('clear invalidates pending work and errors can be retried', (
    tester,
  ) async {
    final service = _ControlledSearch();
    await _open(tester, service);
    await _submit(tester, 'old');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    service.pending.first.complete(TextSearchResults(matches: [_match(0)]));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 0'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('reader-search-submit')))
          .onPressed,
      isNull,
    );
    await _submit(tester, 'retry');
    service.pending.last.completeError(StateError('test failure'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not search this book. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('reader-search-submit')));
    await tester.pump();
    service.pending.last.complete(const TextSearchResults());
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets(
    'shows partial counts and RTL snippets without overflowing a small viewport',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _ControlledSearch();
      await _open(tester, service);
      await _submit(tester, 'שלום');
      service.pending.last.complete(
        TextSearchResults(matches: [_match(0)], truncated: true),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('First 1 matches'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('שָׁלוֹם עולם')).textDirection,
        TextDirection.rtl,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a completed worker cannot update a disposed search screen', (
    tester,
  ) async {
    final service = _ControlledSearch();
    await _open(tester, service);
    await _submit(tester, 'late');
    await tester.pumpWidget(const SizedBox());
    service.pending.single.complete(TextSearchResults(matches: [_match(0)]));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _open(WidgetTester tester, TextSearchService service) =>
    tester.pumpWidget(
      MaterialApp(
        home: ReaderSearchScreen(spine: const [], searchService: service),
      ),
    );

Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump();
  await tester.tap(find.byKey(const Key('reader-search-submit')));
  await tester.pump();
}

TextSearchMatch _match(int index) => TextSearchMatch(
  position: TextReadingPosition(
    spineIndex: index,
    blockIndex: 2,
    charOffset: 13,
  ),
  endCharOffset: 20,
  chapterTitle: 'Chapter $index',
  snippet: 'שָׁלוֹם עולם',
  direction: BlockTextDirection.rtl,
);

class _ControlledSearch extends TextSearchService {
  final queries = <String>[];
  final pending = <Completer<TextSearchResults>>[];

  @override
  Future<TextSearchResults> search(
    List<ParsedSpineItem> spine,
    String query, {
    int maxResults = 1000,
  }) {
    queries.add(query);
    final completer = Completer<TextSearchResults>();
    pending.add(completer);
    return completer.future;
  }
}
