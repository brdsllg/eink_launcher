import 'package:eink_launcher/reader/services/hebrew_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alef = '\u05D0';
  const bet = '\u05D1';
  const sheva = '\u05B0';
  const hatafPatah = '\u05B2';
  const hiriq = '\u05B4';
  const tsere = '\u05B5';
  const segol = '\u05B6';
  const patah = '\u05B7';
  const qamats = '\u05B8';
  const holam = '\u05B9';
  const qubuts = '\u05BB';
  const meteg = '\u05BD';
  const etnachta = '\u0591';
  const maqaf = '\u05BE';

  group('withoutOverlappingMeteg', () {
    test('drops the meteg on a letter with any vowel point', () {
      for (final vowel in [
        sheva,
        hatafPatah,
        hiriq,
        tsere,
        segol,
        patah,
        qamats,
        holam,
        qubuts,
      ]) {
        expect(withoutOverlappingMeteg('$bet$vowel$meteg'), '$bet$vowel');
      }
    });

    test('drops the meteg whichever way round the marks are stored', () {
      expect(withoutOverlappingMeteg('$bet$meteg$segol'), '$bet$segol');
    });

    test('drops the meteg when a cantillation accent sits in between', () {
      expect(
        withoutOverlappingMeteg('$bet$tsere$etnachta$meteg'),
        '$bet$tsere$etnachta',
      );
    });

    test('keeps a meteg on a letter that has no vowel point', () {
      final text = '$bet$meteg';
      expect(identical(withoutOverlappingMeteg(text), text), isTrue);
    });

    test('only touches letters that carry a vowel point', () {
      expect(
        withoutOverlappingMeteg('$alef$meteg $bet$patah$meteg'),
        '$alef$meteg $bet$patah',
      );
    });

    test('a vowel on the previous letter does not affect the next letter', () {
      final text = '$alef$patah$bet$meteg';
      expect(identical(withoutOverlappingMeteg(text), text), isTrue);
    });

    test('treats maqaf as the end of a letter group', () {
      final text = '$alef$patah$maqaf$bet$meteg';
      expect(identical(withoutOverlappingMeteg(text), text), isTrue);
    });

    test('returns text without a meteg unchanged', () {
      const text = 'Plain English, $bet$patah no marks.';
      expect(identical(withoutOverlappingMeteg(text), text), isTrue);
    });
  });

  group('metegPositionsToSkip', () {
    test('reports positions in the original string', () {
      expect(metegPositionsToSkip('$alef $bet$segol$meteg'), [4]);
    });

    test('is empty when nothing needs skipping', () {
      expect(metegPositionsToSkip('$bet$meteg'), isEmpty);
      expect(metegPositionsToSkip('$bet$patah'), isEmpty);
    });
  });
}
