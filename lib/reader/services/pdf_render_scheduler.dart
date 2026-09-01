import 'dart:async';

/// Lower index means the reader needs this work sooner.
enum PdfRenderPriority { visiblePreview, visible, prefetch }

/// A cancelled or superseded render is normal navigation, not a broken PDF.
class PdfRenderCancelledException implements Exception {
  const PdfRenderCancelledException();

  @override
  String toString() => 'PDF render request was superseded.';
}

/// Demand for an image. Views cancel this when the image leaves their viewport.
/// Priority remains mutable so an existing look-ahead request can be promoted.
class PdfRenderRequest {
  PdfRenderRequest({PdfRenderPriority priority = PdfRenderPriority.visible}) {
    this.priority = priority;
  }

  PdfRenderPriority _priority = PdfRenderPriority.visible;
  bool _isCancelled = false;
  final Set<void Function()> _listeners = {};

  PdfRenderPriority get priority => _priority;
  bool get isCancelled => _isCancelled;

  set priority(PdfRenderPriority value) {
    if (_priority == value || _isCancelled) return;
    _priority = value;
    _notify();
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _notify();
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const PdfRenderCancelledException();
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in _listeners.toList(growable: false)) {
      listener();
    }
  }
}

/// Admission control BEFORE pdfrx allocates a native render buffer.
///
/// PDFium already uses one shared worker. Submitting many calls to it merely
/// builds up buffers and obsolete work. Keep one admitted operation across all
/// documents, plus a bounded, priority-ordered queue of closures. Cancellation
/// never releases the active slot before the native operation actually ends.
class PdfRenderScheduler {
  PdfRenderScheduler({this.maxPending = 64}) : assert(maxPending > 0);

  static final instance = PdfRenderScheduler();

  final int maxPending;
  final List<_ScheduledRender<dynamic>> _pending = [];
  bool _active = false;
  bool _pumpScheduled = false;
  int _peakPendingCount = 0;
  int _startedCount = 0;
  int _finishedCount = 0;
  int _cancelledCount = 0;

  int get pendingCount => _pending.length;
  int get activeCount => _active ? 1 : 0;
  int get peakPendingCount => _peakPendingCount;
  int get startedCount => _startedCount;

  /// Finished non-cancelled operations, including operations returning errors.
  int get finishedCount => _finishedCount;
  int get cancelledCount => _cancelledCount;

  Future<T> schedule<T>(
    Future<T> Function() operation, {
    PdfRenderRequest? request,
    void Function(T value)? discard,
  }) {
    final demand = request ?? PdfRenderRequest();
    if (demand.isCancelled) {
      return Future<T>.error(const PdfRenderCancelledException());
    }
    final job = _ScheduledRender<T>(operation, demand, discard);
    void changed() {
      if (demand.isCancelled && _pending.remove(job)) {
        _cancelledCount++;
        job.cancel();
      }
      _schedulePump();
    }

    job.onDetach = () => demand.removeListener(changed);
    demand.addListener(changed);
    if (_pending.length >= maxPending) {
      // Old speculative work must not prevent a newly visible page appearing.
      var victim = _pending.first;
      for (final candidate in _pending) {
        if (candidate.request.priority.index > victim.request.priority.index) {
          victim = candidate;
        }
      }
      if (victim.request.priority.index < demand.priority.index) {
        _cancelledCount++;
        job.cancel();
        return job.completer.future;
      }
      _pending.remove(victim);
      _cancelledCount++;
      victim.cancel();
    }
    _pending.add(job);
    if (_pending.length > _peakPendingCount) {
      _peakPendingCount = _pending.length;
    }
    _schedulePump();
    return job.completer.future;
  }

  void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      if (_active || _pending.isEmpty) return;
      var next = _pending.first;
      for (final candidate in _pending) {
        if (candidate.request.priority.index < next.request.priority.index) {
          next = candidate;
        }
      }
      _pending.remove(next);
      if (next.request.isCancelled) {
        _cancelledCount++;
        next.cancel();
        _schedulePump();
        return;
      }
      _active = true;
      _startedCount++;
      unawaited(
        next.run().whenComplete(() {
          if (next.request.isCancelled) {
            _cancelledCount++;
          } else {
            _finishedCount++;
          }
          _active = false;
          _schedulePump();
        }),
      );
    });
  }
}

class _ScheduledRender<T> {
  _ScheduledRender(this.operation, this.request, this.discard);

  final Future<T> Function() operation;
  final PdfRenderRequest request;
  final void Function(T value)? discard;
  final Completer<T> completer = Completer<T>();
  void Function()? onDetach;

  void cancel() {
    onDetach?.call();
    if (!completer.isCompleted) {
      completer.completeError(const PdfRenderCancelledException());
    }
  }

  Future<void> run() async {
    try {
      final value = await operation();
      if (request.isCancelled) {
        discard?.call(value);
        cancel();
      } else {
        completer.complete(value);
      }
    } catch (error, stack) {
      if (!completer.isCompleted) {
        completer.completeError(
          request.isCancelled ? const PdfRenderCancelledException() : error,
          stack,
        );
      }
    } finally {
      onDetach?.call();
    }
  }
}
