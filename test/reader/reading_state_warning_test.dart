import 'dart:io';

import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/book_store_service.dart';
import 'package:eink_launcher/reader/widgets/reading_state_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a failed save remains visible and Retry clears it after persistence',
    (tester) async {
      late Directory dir;
      late BookStoreService store;
      await tester.runAsync(() async {
        store = BookStoreService.instance;
        dir = await Directory.systemTemp.createTemp('state-warning-');
        await store.init(customFile: File('${dir.path}/library.json'));
        await Directory('${dir.path}/library.json.tmp').create();
        store.saveGlobalSettings(const ReaderSettings(fontSizeStep: 5));
        await store.flush();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingStateWarning(store: store, child: const Text('Reader')),
        ),
      );
      expect(find.textContaining('have not been saved'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.runAsync(() async {
        await Directory('${dir.path}/library.json.tmp').delete();
        tester.widget<TextButton>(find.byType(TextButton)).onPressed!();
        await store.flush();
      });
      await tester.pump();
      expect(find.text('Retry'), findsNothing);
      expect(store.hasUnsavedChanges, isFalse);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
