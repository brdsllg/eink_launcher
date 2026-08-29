import 'package:eink_launcher/reader/widgets/no_momentum_scroll_physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never creates a ballistic fling simulation', () {
    const physics = NoMomentumScrollPhysics();
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 400,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(physics.createBallisticSimulation(metrics, 3000), isNull);
  });
}
