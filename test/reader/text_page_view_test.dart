import 'package:eink_launcher/reader/controllers/text_reader_session.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/doc_ref.dart';
import 'package:eink_launcher/reader/models/laid_out_page.dart';
import 'package:eink_launcher/reader/models/parsed_book.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/models/reading_position.dart';
import 'package:eink_launcher/reader/widgets/block_slice_view.dart';
import 'package:eink_launcher/reader/widgets/text_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the supplied clip-and-offset page slices', (
    tester,
  ) async {
    final session = _TextPageSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: 180,
              child: TextPageView(session: session),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BlockSliceView), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('A rendered paragraph'),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(BlockSliceView)).height, 72);
    expect(tester.takeException(), isNull);
  });
}

class _TextPageSession extends TextReaderSession {
  static const _block = ContentBlock(
    type: BlockType.paragraph,
    runs: [
      InlineRun(
        text:
            'A rendered paragraph with enough words to exercise the exact '
            'clip-and-offset page widget.',
      ),
    ],
  );
  static final _parsedBook = ParsedBook(
    title: 'View test',
    spine: [
      ParsedSpineItem(
        id: 'chapter',
        href: 'chapter.xhtml',
        blocks: const [_block],
      ),
    ],
  );
  static const _page = LaidOutPage(
    pageIndex: 0,
    slices: [
      BlockSlice(
        blockIndex: 0,
        startCharOffset: 0,
        endCharOffset: 94,
        sourceTop: 0,
        height: 72,
      ),
    ],
    start: TextReadingPosition(spineIndex: 0, blockIndex: 0, charOffset: 0),
    end: TextReadingPosition(spineIndex: 0, blockIndex: 0, charOffset: 94),
  );

  _TextPageSession()
    : super(
        doc: const DocRef(
          id: 'text-view-test',
          path: '/books/view.epub',
          format: DocFormat.epub,
          title: 'View test',
          fileSize: 10,
        ),
        bookLoader: (_, _) async => _parsedBook,
      );

  @override
  ParsedBook get book => _parsedBook;

  @override
  LaidOutPage get currentLaidOutPage => _page;

  @override
  ReaderSettings get settings => const ReaderSettings(hyphenate: false);

  @override
  bool get isPaginating => false;

  @override
  void updateViewport(Size viewport) {}
}
