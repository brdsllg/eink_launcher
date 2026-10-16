import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Bounded, opt-in diagnostics for the text-reader ANR investigation.
///
/// Dormant unless enabled: every recording method returns immediately when
/// [enabled] is false, so normal builds pay one branch and no allocations.
/// Enable for one investigation run without touching code or settings UI:
///
/// ```bash
/// flutter run --release --dart-define=READER_DIAGNOSTICS=1
/// ```
///
/// When enabled, phase durations are kept in fixed-size buffers and
/// summarized as count / p50 / p95 / max, and [dumpToLog] prints the summary
/// to logcat (captured by `adb logcat`) when a book finishes laying out.
///
/// Privacy: record durations and counts only. Never pass source text,
/// document paths, excerpts, or annotation contents here.
class ReaderDiagnostics {
  ReaderDiagnostics._();

  /// Shared instance used by paginator, session, and cache services.
  static final ReaderDiagnostics instance = ReaderDiagnostics._();

  /// Master switch. Defaults to the READER_DIAGNOSTICS build flag so
  /// investigation builds enable it with `--dart-define`, no code change.
  bool enabled = const bool.fromEnvironment(
    'READER_DIAGNOSTICS',
    defaultValue: false,
  );

  /// Maximum recent events kept globally.
  static const int maxEvents = 64;

  /// Maximum per-phase duration samples kept for p50/p95.
  static const int maxPhaseSamples = 256;

  final List<_DiagnosticEvent> _recent = <_DiagnosticEvent>[];
  final Map<String, List<int>> _phaseSamples = <String, List<int>>{};
  int _heartbeatGaps = 0;
  int _maxHeartbeatGapMicros = 0;

  /// Records one phase duration. [count] carries a size signal (for example
  /// characters measured or pages published), never text.
  void record(String phase, Duration duration, {int count = 1}) {
    if (!enabled) return;
    final micros = duration.inMicroseconds;
    final samples = _phaseSamples.putIfAbsent(phase, () => <int>[]);
    samples.add(micros);
    if (samples.length > maxPhaseSamples) {
      samples.removeRange(0, samples.length - maxPhaseSamples);
    }
    _recent.add(
      _DiagnosticEvent(phase, micros, count, DateTime.now()),
    );
    if (_recent.length > maxEvents) {
      _recent.removeRange(0, _recent.length - maxEvents);
    }
  }

  /// Records an event-loop heartbeat gap (foreground only; see
  /// [ReaderHeartbeat]). A delayed heartbeat shows delayed callback service,
  /// not the responsible function.
  void recordHeartbeatGap(Duration gap) {
    if (!enabled) return;
    _heartbeatGaps++;
    _maxHeartbeatGapMicros = math.max(
      _maxHeartbeatGapMicros,
      gap.inMicroseconds,
    );
  }

  /// Per-phase summary: sample count, p50, p95, and max in microseconds.
  Map<String, PhaseSummary> summary() {
    final result = <String, PhaseSummary>{};
    _phaseSamples.forEach((phase, samples) {
      if (samples.isEmpty) return;
      final sorted = List<int>.of(samples)..sort();
      int at(double quantile) =>
          sorted[(quantile * (sorted.length - 1)).round().clamp(
            0,
            sorted.length - 1,
          )];
      result[phase] = PhaseSummary(
        count: sorted.length,
        p50Micros: at(0.5),
        p95Micros: at(0.95),
        maxMicros: sorted.last,
      );
    });
    return result;
  }

  /// Bounded tail of recent phase events (oldest first).
  List<Map<String, Object>> recent() => List<Map<String, Object>>.unmodifiable(
    _recent.map(
      (event) => <String, Object>{
        'phase': event.phase,
        'micros': event.micros,
        'count': event.count,
        'at': event.at.toIso8601String(),
      },
    ),
  );

  int get heartbeatGapCount => _heartbeatGaps;
  int get maxHeartbeatGapMicros => _maxHeartbeatGapMicros;

  /// Prints the bounded summary to logcat (prefix `READER-DX`). No-op unless
  /// enabled. Callers capture it with `adb logcat`; nothing is written to
  /// app storage and no book content is included.
  void dumpToLog() {
    if (!enabled) return;
    final summary = this.summary();
    if (summary.isEmpty && _heartbeatGaps == 0) {
      debugPrint('READER-DX no samples collected');
      return;
    }
    final names = summary.keys.toList()..sort();
    for (final name in names) {
      final s = summary[name]!;
      debugPrint(
        'READER-DX $name count=${s.count} '
        'p50=${s.p50Micros}us p95=${s.p95Micros}us max=${s.maxMicros}us',
      );
    }
    if (_heartbeatGaps > 0) {
      debugPrint(
        'READER-DX heartbeat gaps=$_heartbeatGaps '
        'max=${_maxHeartbeatGapMicros}us',
      );
    }
  }

  void reset() {
    _recent.clear();
    _phaseSamples.clear();
    _heartbeatGaps = 0;
    _maxHeartbeatGapMicros = 0;
  }
}

/// Summary of one phase's bounded duration samples.
class PhaseSummary {
  final int count;
  final int p50Micros;
  final int p95Micros;
  final int maxMicros;

  const PhaseSummary({
    required this.count,
    required this.p50Micros,
    required this.p95Micros,
    required this.maxMicros,
  });
}

class _DiagnosticEvent {
  final String phase;
  final int micros;
  final int count;
  final DateTime at;

  _DiagnosticEvent(this.phase, this.micros, this.count, this.at);
}

/// Lifecycle-aware event-loop heartbeat for the ANR investigation.
///
/// A [Timer] ticks every [interval]; when a tick arrives later than
/// [reportAbove], the gap is reported to [ReaderDiagnostics] as a
/// foreground timing gap. The owner must call [dispose] on suspend/teardown
/// so background gaps are never reported as foreground stalls. Not started
/// automatically; investigation builds start it explicitly.
class ReaderHeartbeat {
  ReaderHeartbeat({
    ReaderDiagnostics? diagnostics,
    this.interval = const Duration(milliseconds: 500),
    this.reportAbove = const Duration(milliseconds: 1000),
  }) : _diagnostics = diagnostics ?? ReaderDiagnostics.instance;

  final ReaderDiagnostics _diagnostics;
  final Duration interval;
  final Duration reportAbove;
  Timer? _timer;
  Stopwatch? _stopwatch;

  void start() {
    if (!_diagnostics.enabled) return;
    stop();
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(interval, (_) {
      final watch = _stopwatch;
      if (watch == null) return;
      final gap = watch.elapsed;
      watch.reset();
      if (gap >= reportAbove) {
        _diagnostics.recordHeartbeatGap(gap);
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch?.stop();
    _stopwatch = null;
  }

  void dispose() => stop();
}
