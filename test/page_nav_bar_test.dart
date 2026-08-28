import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eink_launcher/widgets/page_nav_bar.dart';
import 'package:eink_launcher/widgets/paginated_list.dart';

void main() {
  Widget buildNavBar({
    required int currentPage,
    required int totalPages,
    VoidCallback? onFirst,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    VoidCallback? onLast,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PageNavBar(
          currentPage: currentPage,
          totalPages: totalPages,
          onFirst: onFirst,
          onPrevious: onPrevious,
          onNext: onNext,
          onLast: onLast,
        ),
      ),
    );
  }

  testWidgets('shows first, previous, next, and last page controls', (
    tester,
  ) async {
    await tester.pumpWidget(buildNavBar(currentPage: 1, totalPages: 3));

    expect(find.byIcon(Icons.keyboard_double_arrow_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_double_arrow_right), findsOneWidget);
  });

  testWidgets('first and last page controls call their callbacks', (
    tester,
  ) async {
    var firstTaps = 0;
    var lastTaps = 0;
    await tester.pumpWidget(
      buildNavBar(
        currentPage: 1,
        totalPages: 3,
        onFirst: () => firstTaps++,
        onLast: () => lastTaps++,
      ),
    );

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_right));

    expect(firstTaps, 1);
    expect(lastTaps, 1);
  });

  testWidgets('paginated list jump controls request its boundary pages', (
    tester,
  ) async {
    final requestedPages = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaginatedList<int>(
            items: List.generate(20, (index) => index),
            currentPage: 1,
            onPageChanged: requestedPages.add,
            itemBuilder: (context, item) => const SizedBox(height: 60),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_right));

    expect(requestedPages, [0, 2]);
  });
}
