import 'package:eink_launcher/widgets/paginated_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('physical buttons page a real list and clamp at its bounds', (
    tester,
  ) async {
    var page = 0;
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                height: 296,
                child: PaginatedList<int>(
                  items: List.generate(9, (i) => i),
                  currentPage: page,
                  pageButtonsEnabled: enabled,
                  onPageChanged: (value) => setState(() => page = value),
                  itemBuilder: (_, item) =>
                      SizedBox(height: 60, child: Text('Item $item')),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(page, 1);
    expect(find.text('Item 4'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await tester.pump();
    expect(page, 2);
    expect(find.text('Item 8'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(page, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await tester.pump();
    expect(page, 1);
    update(() => enabled = false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(page, 1, reason: 'A search overlay disables the underlying list');
    update(() => enabled = true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(page, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
