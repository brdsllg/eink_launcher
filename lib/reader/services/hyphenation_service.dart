import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/language_en_us.dart';

import '../models/content_block.dart';

/// Inserts discretionary soft hyphens into Latin words only.
class HyphenationService {
  static final Hyphenator _english = Hyphenator(Language_en_us());
  static final RegExp _latinWord = RegExp(r"[A-Za-z][A-Za-z'’-]{4,}");

  const HyphenationService();

  String hyphenateLatinText(String text) {
    return text.replaceAllMapped(_latinWord, (match) {
      final word = match.group(0)!;
      if (word.contains('\u00ad')) return word;
      return _english.hyphenateWord(word);
    });
  }

  List<InlineRun> hyphenateRuns(List<InlineRun> runs) {
    return List<InlineRun>.unmodifiable(
      runs.map((run) => run.copyWith(text: hyphenateLatinText(run.text))),
    );
  }
}
