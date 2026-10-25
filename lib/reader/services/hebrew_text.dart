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

const int _meteg = 0x05BD;

/// Vowel points U+05B0..U+05BB (sheva, the chataf vowels, hiriq, tsere, segol,
/// patah, qamats, holam, qubuts) plus qamats qatan U+05C7.
bool _isVowelPoint(int unit) =>
    (unit >= 0x05B0 && unit <= 0x05BB) || unit == 0x05C7;

/// UTF-16 positions in [source] of every meteg that display must skip.
///
/// A meteg is the small vertical bar that belongs beside a vowel. Unicode does
/// not fix where it sits: each font decides, and several fonts draw it
/// directly under the vowel. The bar then merges with the vowel and makes a
/// different one (patah plus meteg looks like qamats; segol or tsere plus
/// meteg also turn into something that is not the vowel in the text). No
/// character sequence can force a font to move it, so display skips the meteg
/// on every letter that carries a vowel point. A meteg on a letter with no
/// vowel point is left alone.
///
/// Display only. The source text, search, copy and saved annotations keep the
/// meteg, so nothing stored changes. Returns an empty list when nothing needs
/// skipping, which is the case for almost all text.
List<int> metegPositionsToSkip(String source) {
  if (!source.contains('\u05BD')) return const [];
  final skip = <int>[];
  var k = 0;
  while (k < source.length) {
    if (!isHebrewCombiningMark(source.codeUnitAt(k))) {
      k++;
      continue;
    }
    // One run of marks stacked on a single letter.
    var hasVowel = false;
    final metegs = <int>[];
    var end = k;
    while (end < source.length &&
        isHebrewCombiningMark(source.codeUnitAt(end))) {
      final unit = source.codeUnitAt(end);
      if (_isVowelPoint(unit)) hasVowel = true;
      if (unit == _meteg) metegs.add(end);
      end++;
    }
    if (hasVowel) skip.addAll(metegs);
    k = end;
  }
  return skip;
}

/// [source] without the meteg characters listed by [metegPositionsToSkip].
/// Returns the same string object when there is nothing to remove.
String withoutOverlappingMeteg(String source) {
  final skip = metegPositionsToSkip(source);
  if (skip.isEmpty) return source;
  final buffer = StringBuffer();
  var from = 0;
  for (final position in skip) {
    buffer.write(source.substring(from, position));
    from = position + 1;
  }
  buffer.write(source.substring(from));
  return buffer.toString();
}
