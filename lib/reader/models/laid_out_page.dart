import 'reading_position.dart';

/// The portion of one laid-out block visible on a page.
///
/// [sourceTop] and [height] are measured in logical pixels in the complete
/// block layout. The renderer clips to [height] and translates by [sourceTop].
class BlockSlice {
  final int blockIndex;
  final int startCharOffset;
  final int endCharOffset;
  final double sourceTop;
  final double height;

  const BlockSlice({
    required this.blockIndex,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.sourceTop,
    required this.height,
  }) : assert(blockIndex >= 0),
       assert(startCharOffset >= 0),
       assert(endCharOffset >= startCharOffset),
       assert(sourceTop >= 0),
       assert(height >= 0);
}

class LaidOutPage {
  final int pageIndex;
  final List<BlockSlice> slices;
  final TextReadingPosition start;
  final TextReadingPosition end;

  const LaidOutPage({
    required this.pageIndex,
    required this.slices,
    required this.start,
    required this.end,
  }) : assert(pageIndex >= 0);
}
