import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/services/bidi_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = BidiService();

  test('detects English and Hebrew base directions', () {
    expect(
      service.directionFor('An English paragraph.'),
      BlockTextDirection.ltr,
    );
    expect(service.directionFor('שלום עולם'), BlockTextDirection.rtl);
  });

  test('combining nikud does not hide the first Hebrew strong character', () {
    expect(service.directionFor('שָׁלוֹם'), BlockTextDirection.rtl);
  });

  test('uses the first strong character in mixed text', () {
    expect(service.directionFor('שלום, then English'), BlockTextDirection.rtl);
    expect(service.directionFor('English ואז עברית'), BlockTextDirection.ltr);
  });

  test('ignores leading numbers and punctuation', () {
    expect(service.directionFor('123 — שלום'), BlockTextDirection.rtl);
    expect(service.directionFor('(42) English'), BlockTextDirection.ltr);
    expect(service.directionFor('123?!'), BlockTextDirection.ltr);
  });
}
