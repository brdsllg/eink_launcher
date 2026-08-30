enum BlockType {
  paragraph,
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  listItem,
  blockquote,
  preformatted,
  image,
  horizontalRule,
}

enum BlockTextDirection { ltr, rtl }

enum BlockAlignment { start, center, end, justify }

class InlineRun {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? href;
  final String? language;

  const InlineRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.href,
    this.language,
  });

  InlineRun copyWith({String? text}) => InlineRun(
    text: text ?? this.text,
    bold: bold,
    italic: italic,
    code: code,
    href: href,
    language: language,
  );
}

/// A semantic document block that is independent of Flutter's rendering types.
///
/// Keeping this model Dart-only allows parsed chapters to cross isolate
/// boundaries and lets pagination decide how the block should be painted later.
class ContentBlock {
  final BlockType type;
  final List<InlineRun> runs;
  final BlockTextDirection direction;
  final BlockAlignment alignment;
  final int nestingLevel;
  final bool orderedList;
  final String? id;
  final String? resourcePath;
  final String? alternateText;

  const ContentBlock({
    required this.type,
    this.runs = const [],
    this.direction = BlockTextDirection.ltr,
    this.alignment = BlockAlignment.start,
    this.nestingLevel = 0,
    this.orderedList = false,
    this.id,
    this.resourcePath,
    this.alternateText,
  });

  String get plainText => runs.map((run) => run.text).join();

  int get characterCount => plainText.length;
}
