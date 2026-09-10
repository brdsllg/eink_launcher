import 'package:flutter/material.dart';

import '../constants.dart';
import 'control_bar_row.dart';

class PageNavBar extends StatelessWidget {
  final int currentPage; // 0-indexed
  final int totalPages;
  final VoidCallback? onFirst;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onLast;
  final double height;
  final bool boxed;

  const PageNavBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onFirst,
    required this.onPrevious,
    required this.onNext,
    required this.onLast,
    this.height = kNavBarHeight,
    this.boxed = true,
  });

  @override
  Widget build(BuildContext context) {
    if (boxed) {
      Widget arrow(IconData icon, String label, VoidCallback? onPressed) =>
          SizedBox(
            width: 64,
            child: IconButton(
              icon: Icon(icon, size: kReaderChromeIconSize),
              disabledColor: Colors.grey,
              padding: EdgeInsets.zero,
              tooltip: label,
              onPressed: onPressed,
            ),
          );
      return DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black)),
        ),
        child: ControlBarRow(
          height: height,
          children: [
            arrow(Icons.keyboard_double_arrow_left, 'First page', onFirst),
            arrow(Icons.chevron_left, 'Previous page', onPrevious),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Page ${currentPage + 1} of $totalPages',
                      style: const TextStyle(fontSize: 14, height: 1),
                    ),
                  ),
                ),
              ),
            ),
            arrow(Icons.chevron_right, 'Next page', onNext),
            arrow(Icons.keyboard_double_arrow_right, 'Last page', onLast),
          ],
        ),
      );
    }
    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_double_arrow_left),
            iconSize: (height * 0.48).clamp(22.0, 30.0).toDouble(),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: height * 0.8,
              height: height,
            ),
            tooltip: 'First page',
            onPressed: onFirst,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            iconSize: (height * 0.48).clamp(22.0, 30.0).toDouble(),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: height * 0.8,
              height: height,
            ),
            tooltip: 'Previous page',
            onPressed: onPrevious,
          ),
          Flexible(
            child: Text(
              'Page ${currentPage + 1} of $totalPages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: (height * 0.32).clamp(14.0, 20.0).toDouble(),
                height: 1,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            iconSize: (height * 0.48).clamp(22.0, 30.0).toDouble(),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: height * 0.8,
              height: height,
            ),
            tooltip: 'Next page',
            onPressed: onNext,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_double_arrow_right),
            iconSize: (height * 0.48).clamp(22.0, 30.0).toDouble(),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: height * 0.8,
              height: height,
            ),
            tooltip: 'Last page',
            onPressed: onLast,
          ),
        ],
      ),
    );
  }
}
