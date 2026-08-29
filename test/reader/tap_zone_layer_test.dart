import 'package:eink_launcher/reader/widgets/tap_zone_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zoneForDx keeps right side forward regardless of text direction', () {
    expect(TapZoneLayer.zoneForDx(10, 100), ReaderTapZone.previous);
    expect(TapZoneLayer.zoneForDx(50, 100), ReaderTapZone.menu);
    expect(TapZoneLayer.zoneForDx(90, 100), ReaderTapZone.next);
  });

  test('free zoom uses narrow page-turn edges', () {
    expect(
      TapZoneLayer.zoneForDx(11, 100, zoomMode: true),
      ReaderTapZone.previous,
    );
    expect(TapZoneLayer.zoneForDx(13, 100, zoomMode: true), ReaderTapZone.menu);
    expect(TapZoneLayer.zoneForDx(89, 100, zoomMode: true), ReaderTapZone.next);
  });

  testWidgets('taps and horizontal swipes dispatch reader actions', (
    tester,
  ) async {
    var previous = 0;
    var menu = 0;
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: TapZoneLayer(
              onPrevious: () => previous++,
              onMenu: () => menu++,
              onNext: () => next++,
            ),
          ),
        ),
      ),
    );

    final bounds = tester.getRect(find.byType(TapZoneLayer));
    await tester.tapAt(bounds.topLeft + const Offset(20, 100));
    await tester.tapAt(bounds.topLeft + const Offset(150, 100));
    await tester.tapAt(bounds.topLeft + const Offset(280, 100));
    await tester.dragFrom(
      bounds.topLeft + const Offset(250, 200),
      const Offset(-100, 0),
    );
    await tester.dragFrom(
      bounds.topLeft + const Offset(50, 250),
      const Offset(100, 0),
    );

    expect(previous, 2);
    expect(menu, 1);
    expect(next, 2);
  });
}
