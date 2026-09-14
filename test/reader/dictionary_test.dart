import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eink_launcher/reader/services/dictionary_service.dart';
import 'package:eink_launcher/reader/widgets/dictionary_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const entry = DictionaryEntry('hello', [
  DictionaryMeaning('noun', 'A greeting.', 'A warm hello.'),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled assets resolve English words and regular/irregular forms offline',
    () async {
      final service = DictionaryService();
      for (final word in [
        ' Hel\u00adlo ',
        'dictionary',
        'children',
        'went',
        'books',
        'happier',
        'running',
        'reader’s',
      ]) {
        expect((await service.lookup(word)).meanings, isNotEmpty, reason: word);
      }
      await expectLater(
        service.lookup('zzzzqwerty'),
        throwsA(isA<DictionaryException>()),
      );
      for (final word in ['', 'two words', 'שלום', 'word/other']) {
        await expectLater(
          service.lookup(word),
          throwsA(isA<DictionaryException>()),
        );
      }
    },
  );

  test('loads small shards once, and evicts the oldest after four', () async {
    final loads = <String>[];
    final service = DictionaryService(
      loadAsset: (path) async {
        loads.add(path);
        return File(path).readAsBytes();
      },
    );
    await service.lookup('hello');
    await service.lookup('hello');
    expect(loads.length, 1);
    for (final word in ['book', 'cat', 'dog', 'apple', 'hello']) {
      await service.lookup(word);
    }
    expect(loads.where((path) => path.endsWith('/he.json.gz')).length, 2);
  });

  test('a failed asset load can be retried', () async {
    var calls = 0;
    final service = DictionaryService(
      loadAsset: (_) async {
        if (++calls == 1) throw const FormatException('broken');
        return Uint8List.fromList(
          gzip.encode(
            utf8.encode(
              jsonEncode({
                'hello': [
                  ['noun', 'A greeting.; "A warm hello."'],
                ],
              }),
            ),
          ),
        );
      },
    );
    await expectLater(
      service.lookup('hello'),
      throwsA(isA<DictionaryException>()),
    );
    final result = await service.lookup('hello');
    expect(result.meanings.single.definition, 'A greeting.');
    expect(result.meanings.single.example, '"A warm hello."');
  });

  testWidgets('loading, failure, retry, definition and close', (tester) async {
    var pending = Completer<DictionaryEntry>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DictionaryDialog(
                word: 'hello',
                lookup: (_) => pending.future,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Looking up definition…'), findsOneWidget);
    pending.completeError(
      const DictionaryException('Could not load dictionary'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load dictionary'), findsOneWidget);
    pending = Completer<DictionaryEntry>();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    pending.complete(entry);
    await tester.pumpAndSettle();
    expect(find.text('A greeting.'), findsOneWidget);
    expect(find.text('A warm hello.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(DictionaryDialog), findsNothing);
  });

  testWidgets('closing during lookup safely ignores its eventual result', (
    tester,
  ) async {
    final pending = Completer<DictionaryEntry>();
    await tester.pumpWidget(
      MaterialApp(
        home: DictionaryDialog(word: 'hello', lookup: (_) => pending.future),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete(entry);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long definitions fit a narrow landscape dialog', (tester) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DictionaryDialog(
          word: 'hello',
          lookup: (_) async =>
              DictionaryEntry('hello', List.filled(30, entry.meanings.single)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Close').hitTestable(), findsOneWidget);
  });
}
