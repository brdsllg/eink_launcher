import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eink_launcher/services/screen_insets_service.dart';
import 'package:eink_launcher/widgets/screen_insets_frame.dart';

class _FakeInsetsService implements ScreenInsetsService {
  _FakeInsetsService(this._rotation, ScreenEdgeSettings initial)
    : settings = ValueNotifier(initial);

  final int _rotation;

  @override
  final ValueNotifier<ScreenEdgeSettings> settings;

  @override
  Future<int> rotation() async => _rotation;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const settings = ScreenEdgeSettings(
    enabled: true,
    rightPx: 253,
    bottomPx: 340,
  );
  // Density 300 gives a pixel ratio of 1.875.
  const ratio = 300 / 160;

  group('insetsFor', () {
    test('upright: right and bottom', () {
      final inset = ScreenInsetsService.insetsFor(settings, 0, ratio);
      expect(inset.left, 0);
      expect(inset.top, 0);
      expect(inset.right, closeTo(253 / ratio, 0.001));
      expect(inset.bottom, closeTo(340 / ratio, 0.001));
    });

    test('turned counter-clockwise (browser Landscape): top and right', () {
      final inset = ScreenInsetsService.insetsFor(settings, 1, ratio);
      expect(inset.left, 0);
      expect(inset.bottom, 0);
      expect(inset.top, closeTo(253 / ratio, 0.001));
      expect(inset.right, closeTo(340 / ratio, 0.001));
    });

    test('upside down: left and top', () {
      final inset = ScreenInsetsService.insetsFor(settings, 2, ratio);
      expect(inset.right, 0);
      expect(inset.bottom, 0);
      expect(inset.left, closeTo(253 / ratio, 0.001));
      expect(inset.top, closeTo(340 / ratio, 0.001));
    });

    test('turned clockwise: bottom and left', () {
      final inset = ScreenInsetsService.insetsFor(settings, 3, ratio);
      expect(inset.right, 0);
      expect(inset.top, 0);
      expect(inset.bottom, closeTo(253 / ratio, 0.001));
      expect(inset.left, closeTo(340 / ratio, 0.001));
    });

    test('off means no inset', () {
      final inset = ScreenInsetsService.insetsFor(
        settings.copyWith(enabled: false),
        0,
        ratio,
      );
      expect(inset, EdgeInsets.zero);
    });

    test('pixel values from the owner measurements at density 300', () {
      final inset = ScreenInsetsService.insetsFor(settings, 0, ratio);
      expect(inset.right, closeTo(134.9, 0.05));
      expect(inset.bottom, closeTo(181.3, 0.05));
    });
  });

  testWidgets('frame shrinks the screen seen by its child', (tester) async {
    tester.view.physicalSize = const Size(1264, 1680);
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);

    Size? seen;
    await tester.pumpWidget(
      MediaQuery.fromView(
        view: tester.view,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ScreenInsetsFrame(
            service: _FakeInsetsService(0, settings),
            child: Builder(
              builder: (context) {
                seen = MediaQuery.sizeOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 1264 / 1.875 = 674.13 and 1680 / 1.875 = 896 logical pixels in total.
    expect(seen!.width, closeTo(1264 / ratio - 253 / ratio, 0.01));
    expect(seen!.height, closeTo(1680 / ratio - 340 / ratio, 0.01));
  });

  testWidgets('frame moves the strips when the tablet is turned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1680, 1264);
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);

    Size? seen;
    await tester.pumpWidget(
      MediaQuery.fromView(
        view: tester.view,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ScreenInsetsFrame(
            service: _FakeInsetsService(1, settings),
            child: Builder(
              builder: (context) {
                seen = MediaQuery.sizeOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Rotation 1: top loses 253 px and right loses 340 px.
    expect(seen!.width, closeTo(1680 / ratio - 340 / ratio, 0.01));
    expect(seen!.height, closeTo(1264 / ratio - 253 / ratio, 0.01));
  });
}
