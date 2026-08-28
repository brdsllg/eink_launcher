import 'package:flutter/material.dart';

import '../constants.dart';
import 'page_nav_bar.dart';

/// A reusable paginated list widget designed for e-ink devices.
///
/// Automatically calculates the number of items that fit into the available
/// vertical space using [kRowHeight] and [kNavBarHeight], preventing any
/// smooth scrolling and providing page-by-page navigation.
class PaginatedList<T> extends StatelessWidget {
  final List<T> items;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final double rowHeight;
  final double navBarHeight;
  final int? preferredItemsPerPage;
  final WidgetBuilder? emptyItemBuilder;

  /// Called after every layout with the real number of rows that fit in the
  /// available height. Optional — callers that don't need to know the page
  /// size (e.g. the app drawer) can leave it unset. The file browser uses it
  /// to scope background stat-loading to what's actually on screen.
  final ValueChanged<int>? onItemsPerPageChanged;

  const PaginatedList({
    super.key,
    required this.items,
    required this.currentPage,
    required this.onPageChanged,
    required this.itemBuilder,
    this.onItemsPerPageChanged,
    this.rowHeight = kRowHeight,
    this.navBarHeight = kNavBarHeight,
    this.preferredItemsPerPage,
    this.emptyItemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final listHeight = (constraints.maxHeight - navBarHeight).clamp(
          0.0,
          double.infinity,
        );
        // Only claim room for a row if a full row actually fits — flooring to
        // a minimum of 1 regardless of available space used to be able to
        // force a row into less height than it needs, overflowing into the
        // nav bar (e.g. with a keyboard open eating most of the screen).
        final fittingItems = listHeight < rowHeight
            ? 0
            : ((listHeight / rowHeight) + 0.000001).floor();
        final itemsPerPage = preferredItemsPerPage == null
            ? fittingItems
            : (preferredItemsPerPage! < fittingItems
                  ? preferredItemsPerPage!
                  : fittingItems);

        if (onItemsPerPageChanged != null) {
          final reportedValue = itemsPerPage;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onItemsPerPageChanged!(reportedValue);
          });
        }

        if (itemsPerPage == 0) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Not enough room to show items',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          );
        }

        final totalPages = (items.length / itemsPerPage).ceil().clamp(
          1,
          1000000,
        );
        final page = currentPage.clamp(0, totalPages - 1);
        final start = page * itemsPerPage;
        final end = (start + itemsPerPage).clamp(0, items.length);
        final pageItems = items.sublist(start, end);

        return Column(
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final item in pageItems) itemBuilder(context, item),
                  if (emptyItemBuilder != null)
                    for (var i = pageItems.length; i < itemsPerPage; i++)
                      emptyItemBuilder!(context),
                ],
              ),
            ),
            PageNavBar(
              currentPage: page,
              totalPages: totalPages,
              onFirst: page > 0 ? () => onPageChanged(0) : null,
              onPrevious: page > 0 ? () => onPageChanged(page - 1) : null,
              onNext: page < totalPages - 1
                  ? () => onPageChanged(page + 1)
                  : null,
              onLast: page < totalPages - 1
                  ? () => onPageChanged(totalPages - 1)
                  : null,
              height: navBarHeight,
            ),
          ],
        );
      },
    );
  }
}
