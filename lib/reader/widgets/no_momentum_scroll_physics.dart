import 'package:flutter/widgets.dart';

/// Allows direct dragging but stops immediately when the pointer is released.
class NoMomentumScrollPhysics extends ClampingScrollPhysics {
  const NoMomentumScrollPhysics({super.parent});

  @override
  NoMomentumScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return NoMomentumScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    return null;
  }
}
