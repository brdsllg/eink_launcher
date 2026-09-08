import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'control_bar_row.dart';

/// A content-first header: bounded icon cells and a title that takes the rest.
class GridAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final Widget? leading;
  final List<Widget> actions;
  final double height;
  final double actionWidth;
  final bool automaticallyImplyLeading;

  const GridAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.height = 56,
    this.actionWidth = 56,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final back =
        leading ??
        (automaticallyImplyLeading && Navigator.of(context).canPop()
            ? const BackButton()
            : null);
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: height,
      titleSpacing: 0,
      centerTitle: false,
      shape: const Border(bottom: BorderSide(color: Colors.black)),
      title: ControlBarRow(
        height: height,
        children: [
          if (back != null) SizedBox(width: actionWidth, child: back),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: DefaultTextStyle.merge(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20),
                  child: title,
                ),
              ),
            ),
          ),
          for (final action in actions)
            SizedBox(width: actionWidth, child: action),
        ],
      ),
    );
  }
}

/// Related actions share equal tracks, with fewer columns on narrow surfaces.
/// A final partial row keeps the same track widths as the rows above it.
class GridActions extends StatelessWidget {
  final List<Widget> children;
  final double minCellWidth;
  final int maxColumns;
  final double cellHeight;

  const GridActions({
    super.key,
    required this.children,
    this.minCellWidth = 144,
    this.maxColumns = 3,
    this.cellHeight = 56,
  }) : assert(minCellWidth > 0),
       assert(maxColumns > 0);

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minCellWidth)
            .floor()
            .clamp(1, math.min(maxColumns, children.length))
            .toInt();
        final rows = (children.length / columns).ceil();
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border.all(color: Colors.black)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var row = 0; row < rows; row++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0; column < columns; column++)
                        Expanded(
                          child: Container(
                            constraints: BoxConstraints(minHeight: cellHeight),
                            foregroundDecoration: BoxDecoration(
                              border: Border(
                                left: column > 0
                                    ? const BorderSide(color: Colors.black)
                                    : BorderSide.none,
                                top: row > 0
                                    ? const BorderSide(color: Colors.black)
                                    : BorderSide.none,
                              ),
                            ),
                            child: row * columns + column < children.length
                                ? children[row * columns + column]
                                : const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Dialogs use one readable content column and equal, boxed footer actions.
class GridDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final bool scrollable;

  const GridDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final width = math.min(480.0, MediaQuery.sizeOf(context).width - 48);
    return AlertDialog(
      constraints: BoxConstraints.tightFor(width: width),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Colors.black),
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrollable: scrollable,
      titlePadding: const EdgeInsets.all(16),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actionsPadding: EdgeInsets.zero,
      title: title,
      content: content == null
          ? null
          : SizedBox(width: width - 32, child: content),
      actions: actions.isEmpty
          ? null
          : [
              SizedBox(
                width: width,
                child: GridActions(
                  minCellWidth: 112,
                  maxColumns: 2,
                  children: actions,
                ),
              ),
            ],
    );
  }
}
