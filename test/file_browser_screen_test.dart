import 'dart:async';
import 'dart:io';

import 'package:eink_launcher/controllers/file_browser_controller.dart';
import 'package:eink_launcher/models/file_entry.dart';
import 'package:eink_launcher/screens/file_browser_screen.dart';
import 'package:eink_launcher/widgets/file_entry_tile.dart';
import 'package:eink_launcher/widgets/page_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chooser = MethodChannel('eink_launcher/open_with');
  const battery = MethodChannel('eink_launcher/battery_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final entries = [
    FileEntry(path: '/books', name: 'Books', isDirectory: true),
    FileEntry(
      path: '/sample.epub',
      name: 'sample.epub',
      isDirectory: false,
      stat: FileStat.statSync('pubspec.yaml'),
    ),
  ];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(battery, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(battery, null);
    messenger.setMockMethodCallHandler(chooser, null);
  });

  testWidgets(
    'selection actions match selection and chooser receives exact path and MIME',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(chooser, (call) async {
        calls.add(call);
        return null;
      });
      final controller = FileBrowserController(
        listFolder: (_) async => entries,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserScreen(
            controller: controller,
            checkPermission: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('sample.epub'));
      await tester.pumpAndSettle();
      expect(find.text('Open with'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Paste'), findsNothing);
      await tester.tap(find.text('Open with'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'openWith');
      expect(calls.single.arguments, {
        'path': '/sample.epub',
        'mimeType': 'application/epub+zip',
      });
      controller.enterSelectionFor('/books');
      await tester.pumpAndSettle();
      expect(find.text('Open with'), findsNothing);
      expect(find.text('Rename'), findsOneWidget);
      controller.toggleSelect('/sample.epub');
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Paste'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'opening paints the inverted row before listing; bands survive rotation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nextFolder = Completer<List<FileEntry>>();
      var opening = false;
      final controller = FileBrowserController(
        listFolder: (path) async {
          if (path == '/books') {
            opening = true;
            final tile = tester.widget<FileEntryTile>(
              find.byType(FileEntryTile).first,
            );
            expect(tile.isOpening, isTrue);
            return nextFolder.future;
          }
          return entries;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserScreen(
            controller: controller,
            checkPermission: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PageNavBar)).height, 60);
      expect(tester.getSize(find.byType(FileEntryTile).first).height, 60);
      await tester.tap(find.text('Books/'));
      expect(opening, isFalse);
      await tester.pump();
      expect(opening, isTrue);
      nextFolder.complete(entries);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(900, 600);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PageNavBar)).height, 50);
      expect(tester.getSize(find.byType(FileEntryTile).first).height, 50);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
