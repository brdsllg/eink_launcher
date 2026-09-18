import 'package:eink_launcher/controllers/file_browser_controller.dart';
import 'package:eink_launcher/models/file_entry.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/models/toc_entry.dart';
import 'package:eink_launcher/reader/screens/reader_search_screen.dart';
import 'package:eink_launcher/reader/screens/reader_toc_screen.dart';
import 'package:eink_launcher/reader/services/text_search_service.dart';
import 'package:eink_launcher/screens/app_drawer_screen.dart';
import 'package:eink_launcher/screens/file_browser_screen.dart';
import 'package:eink_launcher/services/app_list_service.dart';
import 'package:eink_launcher/services/search_service.dart';
import 'package:eink_launcher/widgets/page_nav_bar.dart';
import 'package:eink_launcher/widgets/search_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end button coverage for the screens that page on a physical press.
///
/// `page_button_scope_test.dart` and `page_button_navigation_test.dart` cover
/// the shared handler, and this file proves each real screen is wired to it:
/// the file browser, the Apps drawer, Contents, reader search results, and the
/// file-search results panel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const apps = MethodChannel('eink_launcher/apps');
  const battery = MethodChannel('eink_launcher/battery_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(AppListService.invalidateCache);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUp(() => messenger.setMockMethodCallHandler(battery, (_) async => null));
  tearDown(() {
    messenger.setMockMethodCallHandler(battery, null);
    messenger.setMockMethodCallHandler(apps, null);
  });

  testWidgets('physical buttons page the file browser', (tester) async {
    _usePortraitBands(tester);
    final controller = FileBrowserController(
      listFolder: (_) async => _files(40),
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
    expect(find.text('Page 1 of 4'), findsOneWidget);

    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isTrue,
    );
    await tester.pump();
    expect(controller.currentPage, 1);
    expect(find.text('Page 2 of 4'), findsOneWidget);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.pageUp), isTrue);
    await tester.pump();
    expect(controller.currentPage, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('physical buttons page the Apps drawer', (tester) async {
    messenger.setMockMethodCallHandler(
      apps,
      (_) async => [
        for (var i = 0; i < 40; i++)
          {
            'name': 'App ${i.toString().padLeft(2, '0')}',
            'packageName': 'app.$i',
            'isSystemApp': false,
          },
      ],
    );
    _usePortraitBands(tester);
    await tester.pumpWidget(const MaterialApp(home: AppDrawerScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 4'), findsOneWidget);

    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isTrue,
    );
    await tester.pump();
    expect(find.text('Page 2 of 4'), findsOneWidget);
    expect(find.text('App 13'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('physical buttons page the table of contents', (tester) async {
    _usePortraitBands(tester);
    await tester.pumpWidget(
      MaterialApp(home: ReaderTocScreen(entries: _chapters(40))),
    );
    await tester.pumpAndSettle();
    int bar() =>
        tester.widget<PageNavBar>(find.byType(PageNavBar)).currentPage;
    expect(bar(), 0);
    expect(find.text('Chapter 0'), findsOneWidget);

    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isTrue,
    );
    await tester.pump();
    expect(bar(), 1);
    expect(find.text('Chapter 0'), findsNothing);
    expect(find.text('Chapter 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('physical buttons page reader search results', (tester) async {
    _usePortraitBands(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderSearchScreen(
          spine: const [],
          searchService: _FixedSearch(List.generate(30, _match)),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'שלום');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reader-search-submit')));
    await tester.pumpAndSettle();
    int bar() =>
        tester.widget<PageNavBar>(find.byType(PageNavBar)).currentPage;
    expect(bar(), 0);
    expect(find.text('Chapter 0'), findsOneWidget);

    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isTrue,
    );
    await tester.pump();
    expect(bar(), 1);
    expect(find.text('Chapter 0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('physical buttons move the file-search results panel', (
    tester,
  ) async {
    _usePortraitBands(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchOverlay(
            initialPath: '/books',
            searchService: _FixedStreamingSearch(_files(40)),
            onClose: () {},
            onEntrySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'match');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.text('40 matches'), findsOneWidget);

    final controller = tester
        .widget<CustomScrollView>(find.byKey(const Key('file-search-panel')))
        .controller!;
    expect(controller.offset, 0);

    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isTrue,
    );
    await tester.pump();
    final moved = controller.offset;
    expect(moved, greaterThan(0));

    // The field keeps focus while results are listed, so page and volume still
    // move the panel while its caret keys stay the field's own.
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.widget is EditableText ||
          focused?.findAncestorWidgetOfExactType<EditableText>() != null,
      isTrue,
      reason: 'the search field keeps focus while results are listed',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

/// The file browser and app drawer divide a portrait display into 15 bands of
/// 60px, which makes the expected page counts exact.
void _usePortraitBands(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(600, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

List<FileEntry> _files(int count) => [
  for (var i = 0; i < count; i++)
    FileEntry(path: '/match_$i.txt', name: 'match_$i.txt', isDirectory: false),
];

List<TocEntry> _chapters(int count) => [
  for (var i = 0; i < count; i++)
    TocEntry(
      title: 'Chapter $i',
      position: TextReadingPosition(
        spineIndex: 0,
        blockIndex: i,
        charOffset: 0,
      ),
    ),
];

TextSearchMatch _match(int index) => TextSearchMatch(
  position: TextReadingPosition(
    spineIndex: 0,
    blockIndex: index,
    charOffset: 0,
  ),
  endCharOffset: 4,
  chapterTitle: 'Chapter $index',
  snippet: 'שָׁלוֹם עולם',
  direction: BlockTextDirection.rtl,
);

class _FixedSearch extends TextSearchService {
  _FixedSearch(this.matches);

  final List<TextSearchMatch> matches;

  @override
  Future<TextSearchResults> search(
    List<ParsedSpineItem> spine,
    String query, {
    int maxResults = 1000,
  }) async => TextSearchResults(matches: matches);
}

/// Stands in for the streaming isolate walk so results arrive without real I/O.
class _FixedStreamingSearch extends StreamingSearchService {
  _FixedStreamingSearch(this.entries);

  final List<FileEntry> entries;

  @override
  Future<void> search({
    required SearchParams params,
    required void Function(FileEntry entry) onResult,
    required void Function() onDone,
  }) async {
    for (final entry in entries) {
      onResult(entry);
    }
    onDone();
  }

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}