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
