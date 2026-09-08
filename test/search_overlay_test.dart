import 'package:eink_launcher/widgets/search_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search scopes remain explicit and reachable above a keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Files')),
          body: SearchOverlay(
            initialPath: '/books',
            onClose: () => closed = true,
            onEntrySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final folder = find.byKey(const ValueKey('search-scope-false'));
    final wholeDevice = find.byKey(const ValueKey('search-scope-true'));
    expect(tester.getSize(folder).width, tester.getSize(wholeDevice).width);

    await tester.ensureVisible(wholeDevice);
    await tester.pumpAndSettle();
    await tester.tap(wholeDevice);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(wholeDevice)
          .style!
          .backgroundColor!
          .resolve({}),
      Colors.black,
    );
    expect(
      tester.widget<TextButton>(folder).style!.backgroundColor!.resolve({}),
      Colors.white,
    );

    // Selecting an already selected scope must not toggle back to the other.
    await tester.tap(wholeDevice);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(wholeDevice)
          .style!
          .backgroundColor!
          .resolve({}),
      Colors.black,
    );
    await tester.ensureVisible(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close search'));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
