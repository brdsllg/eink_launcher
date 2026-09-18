import 'package:eink_launcher/widgets/page_scroll_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 200px viewport over ten 100px rows: one screenful is 200px and the last
  // screenful is 800px.
  Widget host({
    required ScrollController controller,
    bool enabled = true,
    bool allowWhileEditingText = false,
    Widget? extra,
  }) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: 200,
            child: PageScrollScope(
              controller: controller,
              enabled: enabled,
              allowWhileEditingText: allowWhileEditingText,
              child: ListView.builder(
                controller: controller,
                itemExtent: 100,
                itemCount: 10,
                itemBuilder: (context, index) => Text('Row $index'),
              ),
            ),
          ),
          ?extra,
        ],
      ),
    ),
  );

  testWidgets('page, direction, and volume keys move one screenful and clamp', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller: controller));
    expect(controller.offset, 0);

    for (final (key, expected) in <(LogicalKeyboardKey, double)>[
      (LogicalKeyboardKey.pageDown, 200),
      (LogicalKeyboardKey.audioVolumeDown, 400),
      (LogicalKeyboardKey.arrowRight, 600),
      (LogicalKeyboardKey.pageUp, 400),
      (LogicalKeyboardKey.arrowLeft, 200),
      (LogicalKeyboardKey.audioVolumeUp, 0),
    ]) {
      expect(await tester.sendKeyEvent(key), isTrue);
      expect(controller.offset, expected);
    }

    // A press that cannot move any further is still consumed, so a
    // volume-mapped button never leaks through to the system volume.
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp), isTrue);
    expect(controller.offset, 0);
    for (var i = 0; i < 6; i++) {
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.pageDown), isTrue);
    }
    expect(controller.offset, 800);
  });

  testWidgets('a hold moves once and a disabled scope leaves the view alone', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return host(controller: controller, enabled: enabled);
        },
      ),
    );
    const key = LogicalKeyboardKey.audioVolumeDown;

    expect(await tester.sendKeyDownEvent(key), isTrue);
    expect(await tester.sendKeyRepeatEvent(key), isTrue);
    expect(await tester.sendKeyUpEvent(key), isTrue);
    expect(controller.offset, 200);

    update(() => enabled = false);
    await tester.pump();
    expect(await tester.sendKeyEvent(key), isFalse);
    expect(controller.offset, 200);
  });

  testWidgets('an opted-in panel pages while its field keeps the caret keys', (
    tester,
  ) async {
    final controller = ScrollController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(
        controller: controller,
        allowWhileEditingText: true,
        extra: TextField(focusNode: focus, autofocus: true),
      ),
    );
    expect(focus.hasFocus, isTrue);

    // Left and right are the caret keys of the focused field, not page turns.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.offset, 0);

    // Page and volume type nothing into the field, so they still page.
    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isTrue,
    );
    expect(controller.offset, 200);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.pageUp), isTrue);
    expect(controller.offset, 0);
  });

  testWidgets('a press is consumed before the scroll view is attached', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageScrollScope(
            controller: controller,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
