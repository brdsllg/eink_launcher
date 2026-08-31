import 'dart:async';
import 'dart:io';

import 'package:eink_launcher/constants.dart';
import 'package:eink_launcher/controllers/file_browser_controller.dart';
import 'package:eink_launcher/models/file_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late List<String> listings;
  late FileBrowserController controller;
  Future<List<FileEntry>> list(String path) async {
    listings.add(path);
    return [];
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'home_folder_path': '/books',
      'unrelated': 'keep',
    });
    prefs = await SharedPreferences.getInstance();
    listings = [];
    controller = FileBrowserController(
      loadPreferences: () async => prefs,
      listFolder: list,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'saved preferences finish before permissions and exactly one listing',
    () async {
      final preferences = Completer<SharedPreferences>();
      controller.dispose();
      controller = FileBrowserController(
        loadPreferences: () => preferences.future,
        listFolder: list,
      );
      var permissionCalls = 0;
      final opening = controller.initialize(
        checkPermission: () async {
          permissionCalls++;
          expect(controller.homeFolder, '/books');
          return true;
        },
      );
      expect(permissionCalls, 0);
      expect(listings, isEmpty);
      preferences.complete(prefs);
      await opening;
      expect(permissionCalls, 1);
      expect(listings, ['/books']);
      expect(controller.startupState, LauncherStartupState.ready);
    },
  );

  test(
    'duplicate initialization does not issue overlapping permission requests',
    () async {
      final permission = Completer<bool>();
      var calls = 0;
      Future<bool> check() {
        calls++;
        return permission.future;
      }

      final first = controller.initialize(checkPermission: check);
      await controller.initialize(checkPermission: check);
      permission.complete(true);
      await first;
      expect(calls, 1);
      expect(listings, ['/books']);
    },
  );

  for (final invalid in [42, '', 'relative/path', '/bad\u0000path']) {
    test('invalid home preference $invalid clears only that key', () async {
      SharedPreferences.setMockInitialValues({
        'home_folder_path': invalid,
        'unrelated': 'keep',
      });
      prefs = await SharedPreferences.getInstance();
      await controller.initialize(checkPermission: () async => true);
      expect(listings, [kStorageRoot]);
      expect(prefs.containsKey('home_folder_path'), isFalse);
      expect(prefs.getString('unrelated'), 'keep');
      expect(
        controller.startupMessage,
        contains('Saved home folder unavailable'),
      );
    });
  }

  test(
    'missing or unreadable home falls back to root and clears only home',
    () async {
      controller.dispose();
      controller = FileBrowserController(
        loadPreferences: () async => prefs,
        listFolder: (path) async {
          listings.add(path);
          if (path == '/books') throw const FileSystemException('denied');
          return [];
        },
      );
      await controller.initialize(checkPermission: () async => true);
      expect(listings, ['/books', kStorageRoot]);
      expect(controller.startupState, LauncherStartupState.ready);
      expect(prefs.containsKey('home_folder_path'), isFalse);
      expect(prefs.getString('unrelated'), 'keep');
    },
  );

  test(
    'denied permission does not list or clear a potentially valid home',
    () async {
      await controller.initialize(checkPermission: () async => false);
      expect(listings, isEmpty);
      expect(prefs.getString('home_folder_path'), '/books');
      expect(controller.startupState, LauncherStartupState.ready);
      expect(controller.permissionGranted, isFalse);
    },
  );

  test(
    'preferences failure enters recovery; use root bypasses broken preferences',
    () async {
      controller.dispose();
      controller = FileBrowserController(
        loadPreferences: () async => throw StateError('preferences'),
        listFolder: list,
      );
      var permissionCalls = 0;
      Future<bool> check() async {
        permissionCalls++;
        return true;
      }

      await controller.initialize(checkPermission: check);
      expect(controller.startupState, LauncherStartupState.recovery);
      expect(permissionCalls, 0);
      await controller.initialize(checkPermission: check, useStorageRoot: true);
      expect(controller.startupState, LauncherStartupState.ready);
      expect(listings, [kStorageRoot]);
      expect(prefs.getString('home_folder_path'), '/books');
    },
  );

  test('permission errors can be retried without unhandled failures', () async {
    await controller.initialize(
      checkPermission: () async => throw StateError('permission'),
    );
    expect(controller.startupState, LauncherStartupState.recovery);
    await controller.initialize(checkPermission: () async => true);
    expect(controller.startupState, LauncherStartupState.ready);
  });

  test('failed home and root listings leave recovery available', () async {
    controller.dispose();
    controller = FileBrowserController(
      loadPreferences: () async => prefs,
      listFolder: (_) async => throw const FileSystemException('denied'),
    );
    await controller.initialize(checkPermission: () async => true);
    expect(controller.startupState, LauncherStartupState.recovery);
  });

  test(
    'disposal during preferences prevents later permission or folder work',
    () async {
      final preferences = Completer<SharedPreferences>();
      final disposed = FileBrowserController(
        loadPreferences: () => preferences.future,
        listFolder: list,
      );
      final opening = disposed.initialize(
        checkPermission: () async => fail('late permission check'),
      );
      disposed.dispose();
      preferences.complete(prefs);
      await opening;
      expect(listings, isEmpty);
    },
  );

  test(
    'disposal during listing discards completion without notifying listeners',
    () async {
      final listing = Completer<List<FileEntry>>();
      final disposed = FileBrowserController(
        loadPreferences: () async => prefs,
        listFolder: (_) => listing.future,
      );
      final opening = disposed.initialize(checkPermission: () async => true);
      await Future<void>.delayed(Duration.zero);
      disposed.dispose();
      listing.complete([]);
      await opening;
      expect(disposed.entries, isEmpty);
    },
  );
}
