import 'package:eink_launcher/widgets/page_button_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page({
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    bool enabled = true,
    Widget child = const SizedBox.expand(),
  }) => MaterialApp(
    home: Scaffold(
      body: PageButtonScope(
        onPrevious: onPrevious,
        onNext: onNext,
        enabled: enabled,
        child: child,
      ),
    ),
  );

  testWidgets(
    'page, direction, and volume keys turn in the expected direction',
    (tester) async {
      final turns = <String>[];
      await tester.pumpWidget(
        page(
          onPrevious: () => turns.add('previous'),
          onNext: () => turns.add('next'),
        ),
      );

      for (final key in [
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.audioVolumeDown,
      ]) {
        expect(await tester.sendKeyDownEvent(key), isTrue);
        expect(await tester.sendKeyUpEvent(key), isTrue);
      }

      expect(turns, [
        'previous',
        'previous',
        'previous',
        'next',
        'next',
        'next',
      ]);
    },
  );

  testWidgets('holding a button turns once and consumes repeats and release', (
    tester,
  ) async {
    var turns = 0;
    await tester.pumpWidget(page(onNext: () => turns++));
    const key = LogicalKeyboardKey.audioVolumeDown;

    expect(await tester.sendKeyDownEvent(key), isTrue);
    expect(await tester.sendKeyRepeatEvent(key), isTrue);
    expect(await tester.sendKeyRepeatEvent(key), isTrue);
    expect(await tester.sendKeyUpEvent(key), isTrue);
    expect(turns, 1);

    await tester.sendKeyEvent(key);
    expect(turns, 2);
  });

  testWidgets('synthesized presses synchronize keys without turning pages', (
    tester,
  ) async {
    var turns = 0;
    await tester.pumpWidget(page(onNext: () => turns++));
    final keyboard = HardwareKeyboard.instance;
    expect(
      keyboard.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.audioVolumeDown,
          logicalKey: LogicalKeyboardKey.audioVolumeDown,
          timeStamp: Duration.zero,
          synthesized: true,
        ),
      ),
      isFalse,
    );
    expect(
      keyboard.handleKeyEvent(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.audioVolumeDown,
          logicalKey: LogicalKeyboardKey.audioVolumeDown,
          timeStamp: Duration(milliseconds: 1),
          synthesized: true,
        ),
      ),
      isFalse,
    );
    expect(turns, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    expect(turns, 1);
  });

  testWidgets('a captured release stays handled when paging is disabled', (
    tester,
  ) async {
    var turns = 0;
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return page(enabled: enabled, onNext: () => turns++);
        },
      ),
    );
    const key = LogicalKeyboardKey.audioVolumeDown;
    expect(await tester.sendKeyDownEvent(key), isTrue);
    update(() => enabled = false);
    await tester.pump();
    expect(await tester.sendKeyRepeatEvent(key), isTrue);
    expect(await tester.sendKeyUpEvent(key), isTrue);
    expect(turns, 1);
    expect(await tester.sendKeyEvent(key), isFalse);
    expect(turns, 1);
  });

  testWidgets('page boundaries still consume volume presses', (tester) async {
    await tester.pumpWidget(page());
    for (final key in [
      LogicalKeyboardKey.audioVolumeUp,
      LogicalKeyboardKey.audioVolumeDown,
    ]) {
      expect(await tester.sendKeyDownEvent(key), isTrue);
      expect(await tester.sendKeyUpEvent(key), isTrue);
    }
  });

  testWidgets('disabled scope does not acquire a key that is already held', (
    tester,
  ) async {
    var turns = 0;
    var enabled = false;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return page(enabled: enabled, onNext: () => turns++);
        },
      ),
    );
    const key = LogicalKeyboardKey.audioVolumeDown;

    expect(await tester.sendKeyDownEvent(key), isFalse);
    update(() => enabled = true);
    await tester.pump();
    expect(await tester.sendKeyRepeatEvent(key), isFalse);
    expect(await tester.sendKeyUpEvent(key), isFalse);
    expect(turns, 0);
    await tester.sendKeyEvent(key);
    expect(turns, 1);
  });

  testWidgets('focused text retains editing keys and prevents page turns', (
    tester,
  ) async {
    var turns = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      page(
        onPrevious: () => turns++,
        onNext: () => turns++,
        child: TextField(focusNode: focus),
      ),
    );
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isFalse,
    );
    expect(turns, 0);

    focus.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    expect(turns, 1);
  });

  testWidgets('modified shortcuts and unrelated hardware keys are untouched', (
    tester,
  ) async {
    var turns = 0;
    await tester.pumpWidget(
      page(onPrevious: () => turns++, onNext: () => turns++),
    );
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
        isFalse,
      );
      await tester.sendKeyUpEvent(modifier);
    }
    for (final key in [LogicalKeyboardKey.power, LogicalKeyboardKey.goBack]) {
      final physicalKey = key == LogicalKeyboardKey.goBack
          ? PhysicalKeyboardKey.browserBack
          : PhysicalKeyboardKey.power;
      expect(
        HardwareKeyboard.instance.handleKeyEvent(
          KeyDownEvent(
            physicalKey: physicalKey,
            logicalKey: key,
            timeStamp: Duration.zero,
          ),
        ),
        isFalse,
      );
      HardwareKeyboard.instance.handleKeyEvent(
        KeyUpEvent(
          physicalKey: physicalKey,
          logicalKey: key,
          timeStamp: Duration.zero,
        ),
      );
    }
    expect(turns, 0);
  });

  testWidgets('dialogs block the underlying page buttons', (tester) async {
    var turns = 0;
    late BuildContext pageContext;
    await tester.pumpWidget(
      page(
        onNext: () => turns++,
        child: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    showDialog<void>(
      context: pageContext,
      builder: (context) => const AlertDialog(title: Text('A dialog')),
    );
    await tester.pumpAndSettle();
    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
      isFalse,
    );
    expect(turns, 0);

    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    expect(turns, 1);
  });

  testWidgets(
    'only the current route pages and its handler is removed on pop',
    (tester) async {
      var homeTurns = 0;
      var readerTurns = 0;
      late BuildContext pageContext;
      await tester.pumpWidget(
        page(
          onNext: () => homeTurns++,
          child: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      Navigator.of(pageContext).push<void>(
        MaterialPageRoute(
          builder: (context) => PageButtonScope(
            onNext: () => readerTurns++,
            child: const Scaffold(body: Text('Reader')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      expect(homeTurns, 0);
      expect(readerTurns, 1);

      Navigator.of(pageContext).pop();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      expect(homeTurns, 1);
      expect(readerTurns, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
        isFalse,
      );
      expect(homeTurns, 1);
      expect(readerTurns, 1);
    },
  );

  testWidgets('rebuilds use current callbacks without adding another handler', (
    tester,
  ) async {
    var oldTurns = 0;
    var newTurns = 0;
    await tester.pumpWidget(page(onNext: () => oldTurns++));
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await tester.pumpWidget(page(onNext: () => newTurns++));
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    expect(oldTurns, 1);
    expect(newTurns, 1);
  });

  testWidgets('app inactivity stops paging and discards held buttons', (
    tester,
  ) async {
    var turns = 0;
    await tester.pumpWidget(page(onNext: () => turns++));
    const key = LogicalKeyboardKey.audioVolumeDown;
    await tester.sendKeyDownEvent(key);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(await tester.sendKeyRepeatEvent(key), isFalse);
    expect(await tester.sendKeyUpEvent(key), isFalse);
    expect(await tester.sendKeyEvent(key), isFalse);
    expect(turns, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyEvent(key);
    expect(turns, 2);
  });
}
