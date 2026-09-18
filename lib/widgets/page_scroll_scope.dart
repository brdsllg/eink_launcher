import 'package:flutter/widgets.dart';

import 'page_button_scope.dart';

/// Makes a scrolling screen respond to an e-reader's physical page buttons.
///
/// [PaginatedList] already covers the fixed-page lists (files, Apps, bookmark,
/// Contents, and book-search results). This covers the surfaces that are one
/// continuous scroll view instead of discrete pages: a press moves the view by
/// exactly one screenful, so the same buttons behave the same way on a
/// search-result panel or a long settings screen.
///
/// The press is delegated to [PageButtonScope], so dialogs, inactive routes,
/// focused editors, holds, and volume consumption at the bounds all behave
/// exactly as they do for a paginated list.
class PageScrollScope extends StatefulWidget {
  const PageScrollScope({
    super.key,
    required this.controller,
    this.enabled = true,
    this.allowWhileEditingText = false,
    required this.child,
  });

  /// The controller of the scroll view this scope drives. The view must use
  /// this controller, so one press moves exactly what is on screen.
  final ScrollController controller;

  /// When false the buttons are left to the platform and to any other scope.
  final bool enabled;

  /// See [PageButtonScope.allowWhileEditingText]. Set this on a scrolling
  /// results panel whose search field keeps focus, so page and volume presses
  /// still move the results while the field owns the caret keys.
  final bool allowWhileEditingText;

  final Widget child;

  @override
  State<PageScrollScope> createState() => _PageScrollScopeState();
}

class _PageScrollScopeState extends State<PageScrollScope> {
  void _scrollByScreenful(int direction) {
    final controller = widget.controller;
    // The scope can outlive the scroll view during a rebuild, and a press at a
    // bound is still consumed by PageButtonScope.
    if (!controller.hasClients) return;
    final position = controller.position;
    final target = (position.pixels + direction * position.viewportDimension)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == position.pixels) return;
    // A jump is one repaint; animating a scroll on an e-ink panel would just
    // read as motion blur.
    controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return PageButtonScope(
      enabled: widget.enabled,
      allowWhileEditingText: widget.allowWhileEditingText,
      onPrevious: () => _scrollByScreenful(-1),
      onNext: () => _scrollByScreenful(1),
      child: widget.child,
    );
  }
}
