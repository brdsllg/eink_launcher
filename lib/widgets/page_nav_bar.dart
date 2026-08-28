import 'package:flutter/material.dart';
import '../constants.dart';

class PageNavBar extends StatelessWidget {
  final int currentPage; // 0-indexed
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const PageNavBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kNavBarHeight,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            iconSize: 28,
            onPressed: onPrevious,
          ),
          Text('Page ${currentPage + 1} of $totalPages'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            iconSize: 28,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
