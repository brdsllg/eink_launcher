import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Live Android battery level with a discrete bar icon suitable for e-ink.
class BatteryStatus extends StatefulWidget {
  final TextStyle? style;
  final double iconSize;

  const BatteryStatus({super.key, this.style, this.iconSize = 24});

  @override
  State<BatteryStatus> createState() => _BatteryStatusState();
}

class _BatteryStatusState extends State<BatteryStatus> {
  static const _events = EventChannel('eink_launcher/battery_events');

  StreamSubscription<dynamic>? _subscription;
  int? _level;
  bool _charging = false;

  @override
  void initState() {
    super.initState();
    _subscription = _events.receiveBroadcastStream().listen(
      _onBatteryEvent,
      onError: (_) {},
    );
  }

  void _onBatteryEvent(dynamic event) {
    if (!mounted || event is! Map) return;
    final level = event['level'];
    final charging = event['charging'];
    if (level is! int || charging is! bool) return;
    setState(() {
      _level = level.clamp(0, 100).toInt();
      _charging = charging;
    });
  }

  IconData _levelIcon(int level) {
    if (level < 8) return Icons.battery_0_bar;
    if (level < 22) return Icons.battery_1_bar;
    if (level < 36) return Icons.battery_2_bar;
    if (level < 50) return Icons.battery_3_bar;
    if (level < 64) return Icons.battery_4_bar;
    if (level < 78) return Icons.battery_5_bar;
    if (level < 92) return Icons.battery_6_bar;
    return Icons.battery_full;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = _level;
    final label = level == null ? '--%' : '$level%';
    final icon = _charging
        ? Icons.battery_charging_full
        : _levelIcon(level ?? 0);
    return Semantics(
      label: level == null
          ? 'Battery status unavailable'
          : 'Battery $level percent${_charging ? ', charging' : ''}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: widget.iconSize, color: Colors.black),
          const SizedBox(width: 2),
          Text(
            label,
            style:
                widget.style ??
                const TextStyle(fontSize: 12, color: Colors.black),
          ),
        ],
      ),
    );
  }
}
