/// Hebrew text helpers shared by search and cache code.
///
/// The Hebrew block is not one continuous run of combining marks. U+05BE
/// (maqaf), U+05C0 (paseq), U+05C3 (sof pasuq) and U+05C6 (nun hafukha) sit
/// inside the U+0591..U+05C7 range but are punctuation with their own advance
/// width. Stripping the whole range for *search* silently makes "אב־גד" match
/// "אבגד" and turns a literal query into a different one.
///
/// Display has the opposite, deliberately recorded rule: the Talmud "hide
/// vowels" setting strips the entire U+0591..U+05C7 range (TAL-013 in
/// docs/PLANNED_FEATURES_STATUS.md), punctuation included. Keep the two
/// policies separate.
library;

/// True for a Hebrew combining mark: a vowel point, a cantillation accent or
/// another zero-width mark in U+0591..U+05C7.
///
/// Punctuation that shares the range is deliberately excluded, so maqaf,
/// paseq, sof pasuq and nun hafukha survive search normalisation.
bool isHebrewCombiningMark(int rune) =>
    rune >= 0x0591 &&
    rune <= 0x05C7 &&
    rune != 0x05BE && // maqaf
    rune != 0x05C0 && // paseq
    rune != 0x05C3 && // sof pasuq
    rune != 0x05C6; // nun hafukha

/// True for Hebrew punctuation that must be kept when vowel points are ignored
/// during search.
bool isHebrewPunctuation(int rune) =>
    rune == 0x05BE || rune == 0x05C0 || rune == 0x05C3 || rune == 0x05C6;

/// Display order of the marks stacked on one Hebrew letter, or null when
/// [rune] is not a combining mark.
///
/// Hebrew fonts are built for the *logical* order: shin/sin dot, then
/// dagesh (or rafe), then the vowel, then meteg, then the cantillation
/// accents. Unicode canonical order (what normalised text and many text
/// sources use) sorts these differently: vowel before dagesh before shin dot.
/// A font that only handles the logical order then attaches the wrong vowel
/// glyph, or drops a mark.
int? _hebrewMarkRank(int rune) {
  if (!isHebrewCombiningMark(rune)) return null;
  if (rune == 0x05C1 || rune == 0x05C2) return 0; // shin dot, sin dot
  if (rune == 0x05BC || rune == 0x05BF) return 1; // dagesh/mapiq, rafe
  if ((rune >= 0x05B0 && rune <= 0x05BB) || rune == 0x05C7) {
    return 2; // vowel points, qamats qatan
  }
  if (rune == 0x05BD) return 3; // meteg
  return 4; // cantillation accents and the remaining marks
}

/// Puts every run of Hebrew marks on a letter into the font-friendly logical
/// order described at [_hebrewMarkRank]. Display only: the result has exactly
/// the same length and the same set of characters as [source], so source
/// offsets (annotations, bookmarks, search matches) stay valid. Marks of equal
/// rank keep their relative order, and text without out-of-order marks is
/// returned unchanged.
String reorderHebrewMarks(String source) {
  if (!_hebrewMarksOutOfOrder(source)) return source;
  final runes = source.runes.toList();
  var changed = false;
  var i = 0;
  while (i < runes.length) {
    if (_hebrewMarkRank(runes[i]) == null) {
      i++;
      continue;
    }
    var end = i;
    while (end < runes.length && _hebrewMarkRank(runes[end]) != null) {
      end++;
    }
    // Stable insertion sort; a letter carries at most a handful of marks.
    for (var a = i + 1; a < end; a++) {
      final value = runes[a];
      final rank = _hebrewMarkRank(value)!;
      var b = a - 1;
      while (b >= i && _hebrewMarkRank(runes[b])! > rank) {
        runes[b + 1] = runes[b];
        b--;
        changed = true;
      }
      runes[b + 1] = value;
    }
    i = end;
  }
  return changed ? String.fromCharCodes(runes) : source;
}

/// Cheap scan so the common case (marks already in logical order, or no
/// Hebrew at all) returns without allocating. Layout calls this for every
/// text run each time a block is measured or painted.
bool _hebrewMarksOutOfOrder(String source) {
  var previous = -1;
  for (var k = 0; k < source.length; k++) {
    final rank = _hebrewMarkRank(source.codeUnitAt(k));
    if (rank == null) {
      previous = -1;
      continue;
    }
    if (rank < previous) return true;
    previous = rank;
  }
  return false;
}
