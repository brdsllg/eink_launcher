import 'dart:async';

import 'package:eink_launcher/constants.dart';
import 'package:eink_launcher/controllers/file_browser_controller.dart';
import 'package:eink_launcher/screens/file_browser_screen.dart';
import 'package:eink_launcher/services/app_list_service.dart';
import 'package:eink_launcher/services/startup_health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppListService.invalidateCache();
    messenger.setMockMethodCallHandler(
      const MethodChannel('eink_launcher/battery_events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('eink_launcher/apps'),
      (_) async => [],
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('eink_launcher/battery_events'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('eink_launcher/apps'),
      null,
    );
  });

  testWidgets(
    'Back cannot list folders while permission is pending or denied',
    (tester) async {
      SharedPreferences.setMockInitialValues({'home_folder_path': '/books'});
      final permission = Completer<bool>();
      final paths = <String>[];
      final health = _Health(recover: false);
      final controller = FileBrowserController(
        listFolder: (path) async {
          paths.add(path);
          return [];
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserScreen(
            controller: controller,
            startupHealth: health,
            checkPermission: () => permission.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Starting launcher'), findsOneWidget);
      expect(health.healthyCalls, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(paths, isEmpty);
      permission.complete(false);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(paths, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'crash-loop recovery skips preferences and keeps the app drawer available',
    (tester) async {
      var preferencesLoaded = 0;
      final paths = <String>[];
      final controller = FileBrowserController(
        loadPreferences: () async {
          preferencesLoaded++;
          throw StateError('bad preferences');
        },
        listFolder: (path) async {
          paths.add(path);
          return [];
        },
      );
      final health = _Health(recover: true);
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserScreen(
            controller: controller,
            startupHealth: health,
            checkPermission: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Launcher recovery'), findsOneWidget);
      expect(preferencesLoaded, 0);
      expect(health.healthyCalls, greaterThan(0));
      await tester.tap(find.text('Open app drawer'));
      await tester.pumpAndSettle();
      expect(find.text('Apps'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry startup'));
      await tester.pumpAndSettle();
      expect(preferencesLoaded, 1);
      expect(find.text('Launcher recovery'), findsOneWidget);
      await tester.tap(find.text('Use storage root'));
      await tester.pumpAndSettle();
      expect(preferencesLoaded, 1);
      expect(paths, [kStorageRoot]);
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'permission failure renders recovery and Retry returns to browser',
    (tester) async {
      var failed = true;
      final controller = FileBrowserController(listFolder: (_) async => []);
      await tester.pumpWidget(
        MaterialApp(
          home: FileBrowserScreen(
            controller: controller,
            startupHealth: _Health(recover: false),
            checkPermission: () async {
              if (failed) throw PlatformException(code: 'permission');
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Launcher recovery'), findsOneWidget);
      failed = false;
      await tester.tap(find.text('Retry startup'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Health extends StartupHealthService {
  final bool recover;
  int healthyCalls = 0;
  _Health({required this.recover}) : super(isAndroid: false);
  @override
  Future<bool> shouldRecover() async => recover;
  @override
  Future<void> markHealthy() async {
    healthyCalls++;
  }
}
