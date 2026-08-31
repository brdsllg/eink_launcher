import 'dart:async';
import 'dart:io';

import 'package:eink_launcher/main.dart' as app;
import 'package:eink_launcher/reader/services/pdf_document_service.dart';
import 'package:eink_launcher/reader/services/pdf_runtime_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'startup stays lazy; concurrent default opens and reopens initialize once',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const permissions = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      const battery = MethodChannel('eink_launcher/battery_events');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(permissions, (call) async {
        if (call.method == 'requestPermissions') {
          return {
            for (final permission in call.arguments as List) permission: 0,
          };
        }
        return 0;
      });
      messenger.setMockMethodCallHandler(battery, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(permissions, null);
        messenger.setMockMethodCallHandler(battery, null);
      });

      // Exercise the real Flutter initializer and default document opener,
      // replacing only pdfrx's native backend so no host PDFium is required.
      final originalBackend = PdfrxEntryFunctions.instance;
      final originalCachePath = Pdfrx.cacheDirectoryPath;
      final originalAssetLoader = Pdfrx.loadAsset;
      // Its completers must use the real async zone, where file I/O below runs.
      final backend = (await tester.runAsync(
        () async => _DelayedPdfBackend(),
      ))!;
      PdfrxEntryFunctions.instance = backend;
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
      addTearDown(() {
        PdfrxEntryFunctions.instance = originalBackend;
        Pdfrx.cacheDirectoryPath = originalCachePath;
        Pdfrx.loadAsset = originalAssetLoader;
      });

      // Call the actual entry point; pumping MyApp alone would miss eager
      // initialization accidentally restored in main().
      app.main();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(backend.initCalls, 0);
      await tester.pumpWidget(const SizedBox());

      await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp('pdf-runtime-');
        addTearDown(() => directory.delete(recursive: true));
        final fixture = await File('${directory.path}/book.pdf').writeAsString(
          'The backend is fake; only file existence is checked here.',
        );

        final missing = PdfDocumentService('${directory.path}/missing.pdf');
        await expectLater(
          missing.open(),
          throwsA(isA<PathNotFoundException>()),
        );
        expect(backend.initCalls, 0);

        final injected = PdfDocumentService(
          fixture.path,
          documentOpener: (_, _) async => _FakeDocument(),
        );
        await injected.open();
        await injected.close();
        expect(backend.initCalls, 0);

        final first = PdfDocumentService(fixture.path);
        final second = PdfDocumentService(fixture.path);
        addTearDown(first.close);
        addTearDown(second.close);
        FutureOr<String?> passwordProvider() => 'password';
        final openingFirst = first.open(passwordProvider: passwordProvider);
        final openingSecond = second.open();
        final cancelled = expectLater(openingSecond, throwsStateError);
        await backend.started.future;
        final initialization = PdfRuntimeService.ensureInitialized();
        expect(PdfRuntimeService.ensureInitialized(), same(initialization));
        expect(backend.initCalls, 1);
        expect(backend.opened, isEmpty);
        expect(first.isOpen, isFalse);

        // Closing while initialization is pending must not retain a late handle.
        await second.close();
        backend.ready.complete();
        await Future.wait([openingFirst, cancelled]);
        expect(first.isOpen, isTrue);
        expect(second.isOpen, isFalse);
        expect(backend.opened.length, 2);
        expect(backend.opened.where((doc) => doc.disposed).length, 1);
        expect(backend.passwordProviders, contains(same(passwordProvider)));

        await first.close();
        await first.open();
        await second.open();
        expect(backend.initCalls, 1);
        expect(PdfRuntimeService.ensureInitialized(), same(initialization));
        expect(first.isOpen, isTrue);
        expect(second.isOpen, isTrue);
        await first.close();
        await second.close();
        expect(backend.opened.every((doc) => doc.disposed), isTrue);
      });
      expect(tester.takeException(), isNull);
    },
  );
}

class _DelayedPdfBackend implements PdfrxEntryFunctions {
  final started = Completer<void>();
  final ready = Completer<void>();
  final opened = <_FakeDocument>[];
  final passwordProviders = <PdfPasswordProvider?>[];
  int initCalls = 0;

  @override
  Future<void> init() {
    initCalls++;
    if (!started.isCompleted) started.complete();
    return ready.future;
  }

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    expect(ready.isCompleted, isTrue);
    passwordProviders.add(passwordProvider);
    final document = _FakeDocument();
    opened.add(document);
    return document;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDocument implements PdfDocument {
  bool disposed = false;

  @override
  final List<PdfPage> pages = [_FakePage()];

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePage implements PdfPage {
  @override
  double get width => 200;

  @override
  double get height => 300;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
