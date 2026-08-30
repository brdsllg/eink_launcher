import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/services/hyphenation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = HyphenationService();

  test('inserts discretionary hyphens into eligible Latin words', () {
    final result = service.hyphenateLatinText('extraordinary typography');
    expect(result, contains('\u00ad'));
    expect(result.replaceAll('\u00ad', ''), 'extraordinary typography');
  });

  test('leaves Hebrew and run styling intact', () {
    const runs = [
      InlineRun(text: 'שלום '),
      InlineRun(text: 'extraordinary', bold: true, href: '#note'),
    ];
    final result = service.hyphenateRuns(runs);
    expect(result.first.text, 'שלום ');
    expect(result.last.text, contains('\u00ad'));
    expect(result.last.bold, isTrue);
    expect(result.last.href, '#note');
  });
}
