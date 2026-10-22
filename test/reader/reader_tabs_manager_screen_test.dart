import 'dart:io';

import 'package:eink_launcher/constants.dart';
import 'package:eink_launcher/reader/controllers/reader_session_registry.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/screens/reader_tabs_screen.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ReaderSessionRegistry registry;
  late DocRef delta;
  ReaderTabsResult? result;
  var popped = false;

  DocRef docFor(String id, String title, {String? path}) => DocRef(
    id: id,
    path: path ?? '/missing/$id.txt',
    format: DocFormat.txt,
    title: title,
    fileSize: 1,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reader-tabs-list-');
    await BookStoreService.instance.init(
      customFile: File('${directory.path}/library.json'),
    );
    registry = ReaderSessionRegistry.forTesting();
    await registry.restoreTabs();
    delta = docFor('delta', 'Delta', path: '${directory.path}/delta.txt');
    // Delta ends up in the recently closed list; the rest stay open.
    registry.selectTab(delta);
    registry.closeTab(delta.id);
    registry.selectTab(docFor('alpha', 'Alpha'));
    registry.selectTab(docFor('beta', 'Beta'));
    registry.selectTab(docFor('gamma', 'Gamma'));
    result = null;
    popped = false;
  });

  tearDown(() async {
    registry.dispose();
    BookStoreService.instance.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, {String current = 'alpha'}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ReaderTabsResult>(
                noTransitionRoute(
                  ReaderTabsScreen(registry: registry, currentTabId: current),
                ),
              );
              popped = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    registry.dispose();
    var flushed = false;
    BookStoreService.instance.flush().then((_) => flushed = true);
    for (var n = 0; n < 200 && !flushed; n++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(flushed, isTrue);
    expect(tester.takeException(), isNull);
  }

  double top(WidgetTester tester, String key) =>
      tester.getTopLeft(find.byKey(ValueKey(key))).dy;

  testWidgets('lists open tabs and recently closed tabs', (tester) async {
    await mount(tester);
    expect(find.text('Open tabs (3)'), findsOneWidget);
    expect(find.text('Recently closed (1)'), findsOneWidget);
    for (final title in ['Alpha', 'Beta', 'Gamma', 'Delta']) {
      expect(find.text(title), findsOneWidget);
    }
    await finish(tester);
  });

  testWidgets('move buttons reorder tabs and are disabled at the ends', (
    tester,
  ) async {
    await mount(tester);
    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));
    expect(button('reader-tabs-up-alpha').onPressed, isNull);
    expect(button('reader-tabs-down-gamma').onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('reader-tabs-down-alpha')));
    await tester.pumpAndSettle();
    expect(registry.tabs.map((doc) => doc.id), ['beta', 'alpha', 'gamma']);
    expect(
      top(tester, 'reader-tabs-open-beta'),
      lessThan(top(tester, 'reader-tabs-open-alpha')),
    );
    expect(button('reader-tabs-up-beta').onPressed, isNull);
    expect(button('reader-tabs-up-alpha').onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('reader-tabs-up-gamma')));
    await tester.pumpAndSettle();
    expect(registry.tabs.map((doc) => doc.id), ['beta', 'gamma', 'alpha']);
    expect(BookStoreService.instance.tabsState.documents.map((doc) => doc.id), [
      'beta',
      'gamma',
      'alpha',
    ]);
    await finish(tester);
  });

  testWidgets('tapping an open tab returns it to the reader', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('reader-tabs-open-beta')));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result?.tabToOpen?.id, 'beta');
    expect(result?.closesCurrentTab, isFalse);
    await finish(tester);
  });

  testWidgets('closing another tab keeps the list up and remembers it', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('reader-tabs-close-gamma')));
    await tester.pumpAndSettle();
    expect(popped, isFalse);
    expect(registry.tabs.map((doc) => doc.id), ['alpha', 'beta']);
    expect(registry.recentlyClosedTabs.first.id, 'gamma');
    expect(find.text('Open tabs (2)'), findsOneWidget);
    expect(find.text('Recently closed (2)'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('closing the tab being read hands the close to the reader', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('reader-tabs-close-alpha')));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result?.closesCurrentTab, isTrue);
    expect(result?.tabToOpen, isNull);
    expect(registry.tabs.any((doc) => doc.id == 'alpha'), isTrue);
    await finish(tester);
  });

  testWidgets('tapping a recently closed tab reopens it and stays here', (
    tester,
  ) async {
    await tester.runAsync(() => File(delta.path).writeAsString('x'));
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('reader-tabs-closed-delta')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(popped, isFalse);
    expect(registry.tabs.last.id, 'delta');
    expect(registry.recentlyClosedTabs, isEmpty);
    expect(find.text('Open tabs (4)'), findsOneWidget);
    expect(find.text('Recently closed (0)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reader-tabs-open-delta')),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('a missing file can be kept or removed from the closed list', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('reader-tabs-closed-delta')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('File not found'), findsOneWidget);
    expect(registry.tabs.any((doc) => doc.id == 'delta'), isFalse);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(registry.recentlyClosedTabs.map((doc) => doc.id), ['delta']);
    await tester.tap(find.byKey(const ValueKey('reader-tabs-reopen-delta')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(registry.recentlyClosedTabs, isEmpty);
    expect(find.text('Nothing closed recently'), findsOneWidget);
    await finish(tester);
  });
}
