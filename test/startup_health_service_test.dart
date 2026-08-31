import 'dart:async';

import 'package:eink_launcher/services/launcher_error_service.dart';
import 'package:eink_launcher/services/startup_health_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('eink_launcher/startup_health');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'shouldRecover' ? true : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'queries existing native marker and deduplicates healthy writes',
    () async {
      final service = StartupHealthService(isAndroid: true);
      expect(await service.shouldRecover(), isTrue);
      await Future.wait([service.markHealthy(), service.markHealthy()]);
      await service.markHealthy();
      expect(calls.map((c) => c.method), ['shouldRecover', 'markHealthy']);
    },
  );

  test('hosts never invoke the Android channel', () async {
    final service = StartupHealthService(isAndroid: false);
    expect(await service.shouldRecover(), isFalse);
    await service.markHealthy();
    service.recordError(StateError('host'), StackTrace.current);
    expect(calls, isEmpty);
  });

  test(
    'unavailable and malformed Android health replies lead to recovery',
    () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(
        await StartupHealthService(isAndroid: true).shouldRecover(),
        isTrue,
      );
      messenger.setMockMethodCallHandler(channel, (_) async => 'invalid');
      expect(
        await StartupHealthService(isAndroid: true).shouldRecover(),
        isTrue,
      );
    },
  );

  test(
    'a stalled native channel times out without blocking the recovery screen',
    () async {
      final pending = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (_) => pending.future);
      final service = StartupHealthService(
        isAndroid: true,
        timeout: const Duration(milliseconds: 10),
      );
      expect(await service.shouldRecover(), isTrue);
      pending.complete(false);
    },
  );

  test(
    'diagnostics are bounded, coalesced, and tolerate channel failure',
    () async {
      final pending = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return pending.future;
      });
      final service = StartupHealthService(isAndroid: true);
      service.recordError('x' * 20000, StackTrace.current);
      service.recordError('second', StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      expect((calls.single.arguments as Map)['details'].length, 8192);
      expect(service.errorEpoch, 2);
      pending.completeError(PlatformException(code: 'unavailable'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('error handlers retain previous handlers and can be restored', () async {
    final oldFlutter = FlutterError.onError;
    final oldPlatform = PlatformDispatcher.instance.onError;
    var flutterErrors = 0;
    var platformErrors = 0;
    FlutterError.onError = (_) {
      flutterErrors++;
    };
    PlatformDispatcher.instance.onError = (_, _) {
      platformErrors++;
      return true;
    };
    final service = StartupHealthService(isAndroid: false);
    final restore = LauncherErrorService.install(health: service);
    try {
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('framework')),
      );
      expect(
        PlatformDispatcher.instance.onError!(
          StateError('async'),
          StackTrace.current,
        ),
        isTrue,
      );
      expect(flutterErrors, 1);
      expect(platformErrors, 1);
      expect(service.errorEpoch, 2);
    } finally {
      restore();
      FlutterError.onError = oldFlutter;
      PlatformDispatcher.instance.onError = oldPlatform;
    }
  });
}
