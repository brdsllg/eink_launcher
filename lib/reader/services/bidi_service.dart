import '../models/content_block.dart';

/// Resolves a block's base direction using Unicode Bidirectional Algorithm
/// rules P2/P3: scan for the first strong directional character.
class BidiService {
  const BidiService();

  BlockTextDirection directionFor(String text) {
    for (final rune in text.runes) {
      if (_isRtlStrong(rune)) return BlockTextDirection.rtl;
      if (_isLtrStrong(rune)) return BlockTextDirection.ltr;
    }
    return BlockTextDirection.ltr;
  }

  bool _isRtlStrong(int rune) =>
      _between(rune, 0x05D0, 0x05F2) || // Hebrew letters
      _between(rune, 0x0620, 0x063F) ||
      _between(rune, 0x0641, 0x064A) ||
      _between(rune, 0x066E, 0x066F) ||
      _between(rune, 0x0671, 0x06D3) ||
      _between(rune, 0x06FA, 0x06FC) ||
      _between(rune, 0x0700, 0x074F) || // Syriac
      _between(rune, 0x0750, 0x077F) ||
      _between(rune, 0x0780, 0x07BF) || // Thaana
      _between(rune, 0x07C0, 0x085F) ||
      _between(rune, 0x0860, 0x086F) ||
      _between(rune, 0x0870, 0x088F) ||
      _between(rune, 0x08A0, 0x08C9) ||
      _between(rune, 0xFB1D, 0xFD3D) ||
      _between(rune, 0xFDF0, 0xFDFC) ||
      _between(rune, 0xFE70, 0xFEFC) ||
      _between(rune, 0x1EE00, 0x1EEBB);

  bool _isLtrStrong(int rune) =>
      _between(rune, 0x0041, 0x005A) ||
      _between(rune, 0x0061, 0x007A) ||
      _between(rune, 0x00C0, 0x02AF) || // Latin and IPA
      _between(rune, 0x0370, 0x052F) || // Greek and Cyrillic
      _between(rune, 0x0531, 0x0588) || // Armenian
      _between(rune, 0x0900, 0x1FFF) ||
      _between(rune, 0x2C00, 0xA7FF);

  bool _between(int value, int start, int end) =>
      value >= start && value <= end;
}
