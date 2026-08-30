import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/widgets/reader_menu_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.byKey(const Key('reader-crop-button')), findsNothing);
    expect(find.byKey(const Key('reader-fit-height-button')), findsOneWidget);
    expect(find.byKey(const Key('reader-fit-width-button')), findsOneWidget);
    expect(find.byKey(const Key('reader-zoom-scroll-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-fit-width-button')));
    expect(selectedMode, PdfFitMode.fitWidth);
    await tester.tap(find.byKey(const Key('reader-zoom-scroll-button')));
    expect(selectedMode, PdfFitMode.zoom);

    await tester.tap(find.byKey(const Key('reader-bookmarks-button')));
    expect(bookmarksOpened, isTrue);
  });
}
