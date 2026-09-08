import 'package:flutter/material.dart';

import '../constants.dart';

/// Equal-height controls with permanent full-height cell dividers.
class ControlBarRow extends StatelessWidget {
  final List<Widget> children;
  final double height;

  /// Relative cell widths. Borders paint inside cells so different rows share
  /// exact fractional boundaries, regardless of their number of dividers.
  final List<int>? spans;

  const ControlBarRow({
    super.key,
    required this.children,
    this.height = kReaderChromeRowHeight,
    this.spans,
  }) : assert(spans == null || spans.length == children.length);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++)
          if (spans != null)
            Expanded(
              flex: spans![index],
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: index == 0
                      ? null
                      : const Border(left: BorderSide(color: Colors.black)),
                ),
                child: children[index],
              ),
            )
          else ...[
            if (index > 0)
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.black,
              ),
            children[index],
          ],
      ],
    ),
  );
}
