import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF settings only persist user-configurable display choices', () {
    const settings = ReaderSettings();

    expect(settings.fitMode, PdfFitMode.fitHeight);
    expect(settings.toJson(), isNot(contains('pdfPageFlow')));
    expect(settings.toJson(), isNot(contains('scrollMomentum')));
    expect(settings.toJson(), isNot(contains('flashEveryNTurns')));
  });

  test('zoom / scroll mode survives JSON round-trip', () {
    const settings = ReaderSettings(fitMode: PdfFitMode.zoom);

    final restored = ReaderSettings.fromJson(settings.toJson());

    expect(restored.fitMode, PdfFitMode.zoom);
  });

  test(
    'legacy scroll and free-zoom settings migrate to unified zoom / scroll',
    () {
      final oldScroll = ReaderSettings.fromJson(const {
        'fitMode': 'continuousScroll',
        'pdfPageFlow': 'pageByPage',
        'scrollMomentum': false,
      });
      final oldZoom = ReaderSettings.fromJson(const {'fitMode': 'freeZoom'});

      expect(oldScroll.fitMode, PdfFitMode.zoom);
      expect(oldZoom.fitMode, PdfFitMode.zoom);
      expect(oldScroll.toJson(), isNot(contains('pdfPageFlow')));
      expect(oldScroll.toJson(), isNot(contains('scrollMomentum')));
    },
  );

  test('legacy flash interval is discarded', () {
    final restored = ReaderSettings.fromJson(const {'flashEveryNTurns': 5});

    expect(restored.toJson(), isNot(contains('flashEveryNTurns')));
  });
}
