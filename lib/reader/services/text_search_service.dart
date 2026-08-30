import 'dart:isolate';
import 'dart:math' as math;

import '../models/content_block.dart';
import '../models/parsed_book.dart';
import '../models/reading_position.dart';

/// A match in the original block text, independent of pagination/typography.
class TextSearchMatch {
  final TextReadingPosition position;
  final int endCharOffset;
  final String chapterTitle;
  final String snippet;
  final BlockTextDirection direction;

  const TextSearchMatch({
    required this.position,
    required this.endCharOffset,
    required this.chapterTitle,
    required this.snippet,
    required this.direction,
  });
}

class TextSearchResults {
  final List<TextSearchMatch> matches;
  final bool truncated;

  const TextSearchResults({this.matches = const [], this.truncated = false});
}

/// Searches parsed text on a worker isolate. Only the spine is transferred:
/// embedded images and other resources never need to be copied for search.
class TextSearchService {
  const TextSearchService();

  Future<TextSearchResults> search(
    List<ParsedSpineItem> spine,
    String query, {
    int maxResults = 1000,
  }) {
    if (maxResults < 1) throw ArgumentError.value(maxResults, 'maxResults');
    return Isolate.run(() => _search(spine, query, maxResults));
  }
}

TextSearchResults _search(
  List<ParsedSpineItem> spine,
  String query,
  int maxResults,
) {
  final needle = _normalize(query).text.trim();
  if (needle.isEmpty) return const TextSearchResults();
  final matches = <TextSearchMatch>[];
  for (var spineIndex = 0; spineIndex < spine.length; spineIndex++) {
    final chapter = spine[spineIndex];
    for (var blockIndex = 0; blockIndex < chapter.blocks.length; blockIndex++) {
      final block = chapter.blocks[blockIndex];
      final source = block.plainText;
      final normalized = _normalize(source);
      var offset = normalized.text.indexOf(needle);
      while (offset >= 0) {
        // Check for one extra match so exactly maxResults is not called partial.
        if (matches.length == maxResults) {
          return TextSearchResults(
            matches: List.unmodifiable(matches),
            truncated: true,
          );
        }
        final start = normalized.starts[offset];
        final end = normalized.ends[offset + needle.length - 1];
        matches.add(
          TextSearchMatch(
            position: TextReadingPosition(
              spineIndex: spineIndex,
              blockIndex: blockIndex,
              charOffset: start,
            ),
            endCharOffset: end,
            chapterTitle: chapter.title?.trim().isNotEmpty == true
                ? chapter.title!
                : 'Chapter ${spineIndex + 1}',
            snippet: _snippet(source, start),
            direction: block.direction,
          ),
        );
        offset = normalized.text.indexOf(needle, offset + needle.length);
      }
    }
  }
  return TextSearchResults(matches: List.unmodifiable(matches));
}

class _NormalizedText {
  final String text;
  final List<int> starts;
  final List<int> ends;

  const _NormalizedText(this.text, this.starts, this.ends);
}

/// Map every normalized UTF-16 code unit back to its original source range.
/// Removing nikud, collapsing whitespace, and lowercasing must never change
/// the logical offsets passed to TextPainter/the reader session.
_NormalizedText _normalize(String source) {
  final text = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  var sourceOffset = 0;
  var wasSpace = false;
  for (final rune in source.runes) {
    final character = String.fromCharCode(rune);
    final end = sourceOffset + character.length;
    if (_isHebrewMark(rune) || rune == 0x00ad) {
      if (ends.isNotEmpty) ends[ends.length - 1] = end;
    } else {
      final isSpace = character.trim().isEmpty;
      if (isSpace && wasSpace) {
        ends[ends.length - 1] = end;
      } else {
        final normalized = isSpace ? ' ' : character.toLowerCase();
        text.write(normalized);
        for (var i = 0; i < normalized.length; i++) {
          starts.add(sourceOffset);
          ends.add(end);
        }
      }
      wasSpace = isSpace;
    }
    sourceOffset = end;
  }
  return _NormalizedText(text.toString(), starts, ends);
}

// Hebrew combining marks only; maqaf and other Hebrew punctuation are retained.
bool _isHebrewMark(int rune) =>
    (rune >= 0x0591 && rune <= 0x05bd) ||
    rune == 0x05bf ||
    rune == 0x05c1 ||
    rune == 0x05c2 ||
    rune == 0x05c4 ||
    rune == 0x05c5 ||
    rune == 0x05c7;

String _snippet(String source, int matchStart) {
  var start = math.max(0, matchStart - 40);
  var end = math.min(source.length, matchStart + 120);
  // A preview must not split a UTF-16 surrogate pair.
  if (start > 0 && _isLowSurrogate(source.codeUnitAt(start))) start--;
  if (end < source.length && _isLowSurrogate(source.codeUnitAt(end))) end++;
  final preview = source.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
  return '${start > 0 ? '…' : ''}$preview${end < source.length ? '…' : ''}';
}

bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
