import 'dart:async';
import 'dart:io';

import 'package:eink_launcher/controllers/file_browser_controller.dart';
import 'package:eink_launcher/models/file_entry.dart';
import 'package:eink_launcher/reader/controllers/reader_session_registry.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_tabs_state.dart';
import 'package:eink_launcher/reader/screens/reader_screen.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/screens/file_browser_screen.dart';
import 'package:eink_launcher/widgets/file_entry_tile.dart';
import 'package:eink_launcher/widgets/page_nav_bar.dart';
import 'package:eink_launcher/widgets/clock_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chooser = MethodChannel('eink_launcher/open_with');
  const battery = MethodChannel('eink_launcher/battery_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final entries = [
    FileEntry(path: '/books', name: 'Books', isDirectory: true),
    FileEntry(
      path: '/sample.epub',
      name: 'sample.epub',
      isDirectory: false,
      stat: FileStat.statSync('pubspec.yaml'),
    ),
  ];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(battery, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(battery, null);
    messenger.setMockMethodCallHandler(chooser, null);
  });

  testWidgets(
    'selection actions match selection and chooser receives exact path and MIME',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(chooser, (call) async {
        calls.add(call);
        return null;
      });
      final controller = FileBrowserController(
        listFolder: (_) async => entries,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserScreen(
            controller: controller,
            checkPermission: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('sample.epub'));
      await tester.pumpAndSettle();
      expect(find.text('Open with'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Paste'), findsNothing);
      await tester.tap(find.text('Open with'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'openWith');
      expect(calls.single.arguments, {
        'path': '/sample.epub',
        'mimeType': 'application/epub+zip',
      });
      controller.enterSelectionFor('/books');
      await tester.pumpAndSettle();
      expect(find.text('Open with'), findsNothing);
      expect(find.text('Rename'), findsOneWidget);
      controller.toggleSelect('/sample.epub');
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Paste'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('long-pressing disabled Paste opens the hidden app drawer', (
    tester,
  ) async {
    final controller = FileBrowserController(listFolder: (_) async => entries);
    await tester.pumpWidget(
      MaterialApp(
        home: FileBrowserScreen(
          controller: controller,
          checkPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.ops.hasClipboard, isFalse);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Paste')),
    );
    // Render the pressed feedback while the pointer remains down, matching
    // a physical long-press rather than advancing directly to pointer-up.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Apps'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'opening paints the inverted row before listing; bands survive rotation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nextFolder = Completer<List<FileEntry>>();
      var opening = false;
      final controller = FileBrowserController(
        listFolder: (path) async {
          if (path == '/books') {
            opening = true;
            final tile = tester.widget<FileEntryTile>(
              find.byType(FileEntryTile).first,
            );
            expect(tile.isOpening, isTrue);
            return nextFolder.future;
          }
          return entries;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserScreen(
            controller: controller,
            checkPermission: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PageNavBar)).height, 60);
      expect(tester.getSize(find.byType(FileEntryTile).first).height, 60);
      final homeWidth = tester
          .getSize(find.byKey(const Key('browser-home-cell')))
          .width;
      final clockWidth = tester
          .getSize(find.byKey(const Key('browser-clock-cell')))
          .width;
      final batteryWidth = tester
          .getSize(find.byKey(const Key('browser-battery-cell')))
          .width;
      final optionsWidth = tester
          .getSize(find.byKey(const Key('browser-options-cell')))
          .width;
      expect(homeWidth, 64);
      expect(batteryWidth, homeWidth);
      expect(optionsWidth, homeWidth);
      expect(clockWidth, batteryWidth * 2);
      expect(
        tester.widget<ClockText>(find.byType(ClockText)).fillAvailableSpace,
        isTrue,
      );
      await tester.tap(find.text('Books/'));
      expect(opening, isFalse);
      await tester.pump();
      expect(opening, isTrue);
      nextFolder.complete(entries);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(900, 600);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PageNavBar)).height, 50);
      expect(tester.getSize(find.byType(FileEntryTile).first).height, 50);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  group('Tabs action', () {
    late Directory directory;
    late BookStoreService store;
    late ReaderSessionRegistry registry;
    final opened = <DocRef>[];
    const recent = DocRef(
      id: 'recent',
      path: '/books/recent.txt',
      format: DocFormat.txt,
      title: 'Recent book',
      fileSize: 1,
    );
    const older = DocRef(
      id: 'older',
      path: '/books/older.txt',
      format: DocFormat.txt,
      title: 'Older book',
      fileSize: 1,
    );

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('browser-tabs-');
      store = BookStoreService.instance;
      await store.init(customFile: File('${directory.path}/library.json'));
      opened.clear();
      registry = ReaderSessionRegistry.forTesting(
        store: store,
        sessionFactory: (doc) {
          opened.add(doc);
          throw const FormatException('Test document cannot load');
        },
      );
    });

    tearDown(() async {
      registry.dispose();
      store.dispose();
      await directory.delete(recursive: true);
    });

    Future<void> openTabsAction(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserScreen(
            controller: FileBrowserController(listFolder: (_) async => entries),
            registry: registry,
            checkPermission: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tabs'));
      await tester.pumpAndSettle();
    }

    testWidgets('empty saved tabs show clear feedback', (tester) async {
      await openTabsAction(tester);
      expect(find.text('No open tabs'), findsOneWidget);
      expect(find.byType(ReaderScreen), findsNothing);
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('restores most recently read tab in a zero-transition reader', (
      tester,
    ) async {
      store.saveTabsState(
        ReaderTabsState(
          documents: [recent, older],
          selectedTabId: recent.id,
          recency: [older.id, recent.id],
        ),
      );
      await openTabsAction(tester);
      final readerFinder = find.byType(ReaderScreen);
      final reader = tester.widget<ReaderScreen>(readerFinder);
      expect(reader.doc.id, recent.id);
      expect(reader.registry, same(registry));
      expect(opened.map((doc) => doc.id), [recent.id]);
      expect(registry.tabs.map((doc) => doc.id), [recent.id, older.id]);
      final route = ModalRoute.of(tester.element(readerFinder))!;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      var flushed = false;
      store.flush().then((_) => flushed = true);
      // Route disposal starts IO in the fake test zone. Allow both real file
      // operations and fake microtasks to finish before removing the fixture.
      for (var attempt = 0; attempt < 200 && !flushed; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(flushed, isTrue);
    });
  });
}
