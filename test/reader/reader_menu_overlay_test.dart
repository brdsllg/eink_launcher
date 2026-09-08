import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/widgets/reader_menu_overlay.dart';
import 'package:eink_launcher/reader/widgets/reader_tab_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const batteryChannel = MethodChannel('eink_launcher/battery_events');
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(batteryChannel, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(batteryChannel, null),
  );
  testWidgets('reader menu exposes direct modes without navigation or crop', (
    tester,
  ) async {
    PdfFitMode? selectedMode;
    var bookmarksOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderMenuOverlay(
            title: 'Document',
            currentPage: 2,
            pageCount: 10,
            settings: const ReaderSettings(),
            onCloseReader: () {},
            onDismiss: () {},
            onOpenBookmarks: () => bookmarksOpened = true,
            onJumpToPage: () {},
            onSelectFitMode: (mode) => selectedMode = mode,
            onToggleOrientation: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );

    expect(find.text('Previous'), findsNothing);
    expect(find.text('Next'), findsNothing);
    for (final label in ['Home', 'Bookmarks', 'Settings']) {
      expect(find.text(label), findsNothing);
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(find.byKey(const Key('reader-crop-button')), findsNothing);
    expect(find.byKey(const Key('reader-search-button')), findsNothing);
    expect(find.byKey(const Key('reader-fit-height-button')), findsOneWidget);
    expect(find.byKey(const Key('reader-fit-width-button')), findsOneWidget);
    expect(find.byKey(const Key('reader-zoom-scroll-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-fit-width-button')));
    expect(selectedMode, PdfFitMode.fitWidth);
    await tester.tap(find.byKey(const Key('reader-zoom-scroll-button')));
    expect(selectedMode, PdfFitMode.zoom);

    await tester.tap(find.byKey(const Key('reader-bookmarks-button')));
    expect(bookmarksOpened, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('text reader menu exposes search on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var searched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderMenuOverlay(
            title: 'Text book',
            currentPage: 1,
            pageCount: 10,
            settings: const ReaderSettings(),
            showPdfControls: false,
            onCloseReader: () {},
            onDismiss: () {},
            onOpenBookmarks: () {},
            onJumpToPage: () {},
            onSelectFitMode: (_) {},
            onToggleOrientation: () {},
            onOpenSettings: () {},
            onOpenToc: () {},
            onJumpToPercent: () {},
            onOpenSearch: () => searched = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('reader-search-button')));
    expect(searched, isTrue);
    expect(find.byKey(const Key('reader-fit-height-button')), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('Contents'), findsNothing);
    expect(find.byTooltip('Contents'), findsOneWidget);
    expect(find.byKey(const Key('reader-clock-cell')), findsOneWidget);
    expect(find.byKey(const Key('reader-battery-cell')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'loading leaves Back and tabs usable while book controls disable',
    (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var back = 0;
      var selections = 0;
      var closes = 0;
      void bookAction() =>
          fail('Book controls must be disabled during loading');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderMenuOverlay(
              title: 'Document',
              currentPage: 2,
              pageCount: 10,
              settings: const ReaderSettings(),
              controlsEnabled: false,
              onCloseReader: () => back++,
              onDismiss: () {},
              onOpenBookmarks: bookAction,
              onJumpToPage: bookAction,
              onSelectFitMode: (_) => bookAction(),
              onToggleOrientation: bookAction,
              onOpenSettings: bookAction,
              onOpenToc: bookAction,
              onJumpToPercent: bookAction,
              tabStrip: ReaderTabStrip(
                tabs: const [
                  DocRef(
                    id: 'book',
                    path: '/book.pdf',
                    format: DocFormat.pdf,
                    title: 'Open book',
                    fileSize: 1,
                  ),
                ],
                selectedTabId: 'book',
                onSelect: (_) => selections++,
                onClose: (_) => closes++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('reader-close-button')));
      await tester.tap(find.text('Open book'));
      await tester.tap(find.byKey(const Key('reader-tab-close-book')));
      expect(back, 1);
      expect(selections, 1);
      expect(closes, 1);
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        if (find
            .descendant(of: find.byWidget(button), matching: find.text('Back'))
            .evaluate()
            .isEmpty) {
          expect(button.onPressed, isNull);
        }
      }
      final stripBottom = tester
          .getBottomLeft(find.byKey(const Key('reader-tab-strip')))
          .dy;
      final backTop = tester
          .getTopLeft(find.byKey(const Key('reader-close-button')))
          .dy;
      final backBottom = tester
          .getBottomLeft(find.byKey(const Key('reader-close-button')))
          .dy;
      final pageTop = tester
          .getTopLeft(find.byKey(const Key('reader-page-jump-button')))
          .dy;
      expect(stripBottom, lessThanOrEqualTo(backTop));
      expect(backBottom, lessThan(pageTop));
      for (final key in [
        'reader-tab-strip',
        'reader-close-button',
        'reader-page-jump-button',
        'reader-fit-height-button',
      ]) {
        expect(tester.getSize(find.byKey(Key(key))).height, 56);
      }
      expect(
        tester.getSize(find.byKey(const Key('reader-tabs-next'))).width,
        56,
      );
      expect(
        tester.getSize(find.byKey(const Key('reader-close-button'))).width,
        56,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('reader-orientation-button')))
            .width,
        96,
      );
      expect(
        tester.getSize(find.byKey(const Key('reader-settings-button'))).width,
        closeTo(800 / 9, 0.01),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
