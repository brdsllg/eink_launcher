import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/screen_insets_service.dart';
import 'adaptive_grid.dart';

/// "Screen edges" dialog: keeps the app away from the cracked part of the
/// panel. The two numbers are physical pixels, measured with the tablet upright
/// (portrait): how much of the right edge and of the bottom edge is unusable.
/// Rotation is handled automatically.
Future<void> showScreenEdgesDialog(BuildContext context) {
  final service = ScreenInsetsService.instance;
  final current = service.settings.value;
  final rightController = TextEditingController(text: '${current.rightPx}');
  final bottomController = TextEditingController(text: '${current.bottomPx}');
  var enabled = current.enabled;

  return showDialog<void>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => GridDialog(
        title: const Text('Screen edges'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Keeps the app away from the damaged right and bottom edges. '
              'Sizes are in pixels, measured with the tablet upright.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => enabled = !enabled),
              child: Text(enabled ? 'On (tap to turn off)' : 'Off (tap to turn on)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rightController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Right edge (px)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bottomController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Bottom edge (px)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              rightController.text = '${ScreenInsetsService.defaultRightPx}';
              bottomController.text = '${ScreenInsetsService.defaultBottomPx}';
              setState(() => enabled = true);
            },
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () {
              final right = (int.tryParse(rightController.text) ?? 0).clamp(
                0,
                800,
              );
              final bottom = (int.tryParse(bottomController.text) ?? 0).clamp(
                0,
                800,
              );
              service.save(
                ScreenEdgeSettings(
                  enabled: enabled,
                  rightPx: right,
                  bottomPx: bottom,
                ),
              );
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
