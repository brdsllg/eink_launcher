import 'package:eink_launcher/reader/services/hebrew_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shin = '\u05E9';
  const bet = '\u05D1';
  const alef = '\u05D0';
  const shinDot = '\u05C1';
  const dagesh = '\u05BC';
  const patah = '\u05B7';
  const qamats = '\u05B8';
  const meteg = '\u05BD';
  const etnachta = '\u0591';
  const maqaf = '\u05BE';

  group('reorderHebrewMarks', () {
    test('turns canonical order into shin dot, dagesh, vowel', () {
      // Unicode canonical order: vowel, dagesh, shin dot.
      expect(
        reorderHebrewMarks('$shin$qamats$dagesh$shinDot'),
        '$shin$shinDot$dagesh$qamats',
      );
    });

    test('puts meteg after the vowel and accents last', () {
      expect(
        reorderHebrewMarks('$bet$etnachta$meteg$patah'),
        '$bet$patah$meteg$etnachta',
      );
    });

    test('leaves text already in logical order untouched', () {
      final text = '$shin$shinDot$dagesh$qamats $bet$patah$etnachta';
      expect(identical(reorderHebrewMarks(text), text), isTrue);
    });

    test('keeps maqaf in place and treats it as a run boundary', () {
      expect(
        reorderHebrewMarks('$alef$patah$maqaf$bet$patah$dagesh'),
        '$alef$patah$maqaf$bet$dagesh$patah',
      );
    });

    test('keeps the length and the characters unchanged', () {
      final source = '$shin$qamats$dagesh$shinDot$etnachta$bet$patah';
      final result = reorderHebrewMarks(source);
      expect(result.length, source.length);
      expect(result.codeUnits.toList()..sort(),
          source.codeUnits.toList()..sort());
    });

    test('does not touch non-Hebrew text', () {
      const text = 'Plain English, no marks.';
      expect(identical(reorderHebrewMarks(text), text), isTrue);
    });
  });
}
