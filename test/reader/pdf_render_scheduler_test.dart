import 'dart:async';

import 'package:eink_launcher/reader/services/pdf_render_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Object> outcome(Future<int> future) async {
  try {
    return await future;
  } catch (error) {
    return error;
  }
}

Future<void> nextEvent() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'rapid supersession admits only active work and the final target',
    () async {
      final scheduler = PdfRenderScheduler(maxPending: 4);
      final gate = Completer<void>();
      final started = <int>[];
      final discarded = <int>[];
      final results = <Future<Object>>[];
      var request = PdfRenderRequest();
      results.add(
        outcome(
          scheduler.schedule(
            () async {
              started.add(0);
              await gate.future;
              return 0;
            },
            request: request,
            discard: discarded.add,
          ),
        ),
      );
      await nextEvent();

      for (var page = 1; page <= 30; page++) {
        request.cancel();
        request = PdfRenderRequest();
        final target = page;
        results.add(
          outcome(
            scheduler.schedule(() async {
              started.add(target);
              return target;
            }, request: request),
          ),
        );
        expect(scheduler.activeCount, 1);
        expect(scheduler.pendingCount, 1);
      }
      // Cancelling the active request must not admit another native buffer yet.
      expect(started, [0]);
      gate.complete();
      final values = await Future.wait(results);
      expect(started, [0, 30]);
      expect(discarded, [0]);
      expect(values.take(30), everyElement(isA<PdfRenderCancelledException>()));
      expect(values.last, 30);
      expect(scheduler.peakPendingCount, lessThanOrEqualTo(1));
    },
  );

  test(
    'visible previews and promoted look-ahead overtake queued detail',
    () async {
      final scheduler = PdfRenderScheduler();
      final gate = Completer<void>();
      final first = scheduler.schedule(() async {
        await gate.future;
        return 0;
      });
      await nextEvent();
      final started = <int>[];
      Future<int> add(int id, PdfRenderRequest request) =>
          scheduler.schedule(() async {
            started.add(id);
            return id;
          }, request: request);
      final speculative = PdfRenderRequest(
        priority: PdfRenderPriority.prefetch,
      );
      final promoted = add(1, speculative);
      final visible = add(2, PdfRenderRequest());
      final preview = add(
        3,
        PdfRenderRequest(priority: PdfRenderPriority.visiblePreview),
      );
      final background = add(
        4,
        PdfRenderRequest(priority: PdfRenderPriority.prefetch),
      );
      speculative.priority = PdfRenderPriority.visiblePreview;
      gate.complete();
      await Future.wait([first, promoted, visible, preview, background]);
      expect(started, [1, 3, 2, 4]);
    },
  );

  test('queue capacity evicts speculative work before visible work', () async {
    final scheduler = PdfRenderScheduler(maxPending: 2);
    final gate = Completer<void>();
    final active = scheduler.schedule(() async {
      await gate.future;
      return 0;
    });
    await nextEvent();
    final started = <int>[];
    Future<Object> add(int id, PdfRenderPriority priority) => outcome(
      scheduler.schedule(() async {
        started.add(id);
        return id;
      }, request: PdfRenderRequest(priority: priority)),
    );
    final speculative = add(1, PdfRenderPriority.prefetch);
    final visible = add(2, PdfRenderPriority.visible);
    final preview = add(3, PdfRenderPriority.visiblePreview);
    final rejected = add(4, PdfRenderPriority.prefetch);
    expect(scheduler.pendingCount, 2);
    expect(scheduler.peakPendingCount, 2);
    gate.complete();
    await active;
    expect(await speculative, isA<PdfRenderCancelledException>());
    expect(await rejected, isA<PdfRenderCancelledException>());
    expect(await visible, 2);
    expect(await preview, 3);
    expect(started, [3, 2]);
  });

  test(
    'a failed native operation releases its slot without hiding the error',
    () async {
      final scheduler = PdfRenderScheduler();
      final failure = outcome(
        scheduler.schedule<int>(() async {
          throw StateError('bad PDF');
        }),
      );
      final recovery = scheduler.schedule(() async => 7);
      expect(await failure, isA<StateError>());
      expect(await recovery, 7);
      await nextEvent();
      expect(scheduler.activeCount, 0);
      expect(scheduler.pendingCount, 0);
    },
  );

  test(
    'cancelled demand never invokes a buffer-allocating operation',
    () async {
      final scheduler = PdfRenderScheduler();
      final request = PdfRenderRequest()..cancel();
      var allocated = false;
      final result = await outcome(
        scheduler.schedule(() async {
          allocated = true;
          return 1;
        }, request: request),
      );
      expect(result, isA<PdfRenderCancelledException>());
      expect(allocated, isFalse);
      expect(scheduler.startedCount, 0);
    },
  );
}
