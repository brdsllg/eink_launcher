import 'dart:async';

import 'package:flutter/material.dart';

/// A small, e-ink-friendly clock readout.
///
/// Ticks once a minute — aligned to the start of the next minute rather than
/// free-running 60s from whenever the widget happened to build — instead of
/// every second. E-ink panels are slow to refresh, so a per-second update
/// would cause visible ghosting for no benefit (seconds aren't shown anyway).
class ClockText extends StatefulWidget {
  final TextStyle? style;

  const ClockText({super.key, this.style});

  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleNextTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(_now),
      style: widget.style ?? const TextStyle(fontSize: 12, color: Colors.black),
    );
  }
}
