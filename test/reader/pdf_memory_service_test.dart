import 'dart:async';

import 'package:eink_launcher/reader/services/pdf_memory_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('eink_launcher/pdf_memory');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const mib = 1024 * 1024;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('quarter-heap budgets are bounded, including extreme reports', () {
    for (final entry in {
      1: 4,
      16: 4,
      64: 16,
      128: 32,
      192: 48,
      256: 64,
      384: 96,
      512: 128,
      1024: 128,
      0x7fffffffffffffff: 128,
    }.entries) {
      expect(
        PdfMemoryService.budgetForMemoryClass(entry.key),
        entry.value * mib,
      );
    }
    expect(
      PdfMemoryService.budgetForMemoryClass(1),
      PdfMemoryService.minCacheBytes,
    );
    expect(
      PdfMemoryService.budgetForMemoryClass(1024),
      PdfMemoryService.maxCacheBytes,
    );
  });

  for (final report in <Object?>[
    null,
    0,
    -1,
    256.0,
    '256',
    true,
    <String, int>{},
  ]) {
    test('invalid report $report uses the fixed fallback', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => report);
      expect(
        await PdfMemoryService(isAndroid: true).cacheBudgetBytes(),
        PdfMemoryService.fallbackCacheBytes,
      );
    });
  }

  test('lookup is lazy, memoized, and shared by concurrent callers', () async {
    var calls = 0;
    final gate = Completer<int>();
    messenger.setMockMethodCallHandler(channel, (call) {
      expect(call.method, 'getMemoryClass');
      expect(call.arguments, isNull);
      calls++;
      return gate.future;
    });
    final service = PdfMemoryService(isAndroid: true);
    expect(calls, 0);
    final first = service.cacheBudgetBytes();
    final second = service.cacheBudgetBytes();
    expect(identical(first, second), isTrue);
    gate.complete(256);
    expect(await first, 64 * mib);
    expect(await service.cacheBudgetBytes(), 64 * mib);
    expect(calls, 1);
  });

  test('non-Android never invokes the channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return 512;
    });
    expect(
      await PdfMemoryService(isAndroid: false).cacheBudgetBytes(),
      PdfMemoryService.fallbackCacheBytes,
    );
    expect(calls, 0);
  });

  test('missing native handler does not prevent PDF opening', () async {
    expect(
      await PdfMemoryService(isAndroid: true).cacheBudgetBytes(),
      PdfMemoryService.fallbackCacheBytes,
    );
  });

  test(
    'platform failure is cached, without repeatedly querying Android',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        throw PlatformException(code: 'memory_unavailable');
      });
      final service = PdfMemoryService(isAndroid: true);
      expect(
        await service.cacheBudgetBytes(),
        PdfMemoryService.fallbackCacheBytes,
      );
      expect(
        await service.cacheBudgetBytes(),
        PdfMemoryService.fallbackCacheBytes,
      );
      expect(calls, 1);
    },
  );

  testWidgets('timeout falls back and ignores a late native response', (
    tester,
  ) async {
    final gate = Completer<int>();
    messenger.setMockMethodCallHandler(channel, (_) => gate.future);
    final service = PdfMemoryService(isAndroid: true);
    final budget = service.cacheBudgetBytes();
    await tester.pump(const Duration(seconds: 2));
    expect(await budget, PdfMemoryService.fallbackCacheBytes);
    gate.complete(512);
    await tester.pump();
    expect(
      await service.cacheBudgetBytes(),
      PdfMemoryService.fallbackCacheBytes,
    );
  });
}
