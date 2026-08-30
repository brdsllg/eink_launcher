import 'package:eink_launcher/services/app_list_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('eink_launcher/apps');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    AppListService.invalidateCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'launchApp') return null;
          final apps = [
            {
              'name': 'Zulu',
              'packageName': 'dev.example.zulu',
              'isSystemApp': false,
            },
            {
              'name': 'alpha',
              'packageName': 'dev.example.alpha',
              'isSystemApp': true,
            },
          ];
          final arguments = call.arguments as Map<Object?, Object?>;
          return arguments['includeSystemApps'] == true ? apps : [apps.first];
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps, sorts, and separately caches app queries', () async {
    final userApps = await AppListService.getLaunchableApps();
    final cachedUserApps = await AppListService.getLaunchableApps();
    final allApps = await AppListService.getLaunchableApps(
      includeSystemApps: true,
    );

    expect(userApps.map((app) => app.name), ['Zulu']);
    expect(userApps.first.isSystemApp, isFalse);
    expect(cachedUserApps, same(userApps));
    expect(allApps, isNot(same(userApps)));
    expect(allApps.map((app) => app.name), ['alpha', 'Zulu']);
    expect(
      calls.where((call) => call.method == 'getLaunchableApps'),
      hasLength(2),
    );
    expect(calls.last.arguments, containsPair('includeSystemApps', true));
  });

  test('launch forwards the package name', () async {
    await AppListService.launch('dev.example.alpha');

    expect(calls.single.method, 'launchApp');
    expect(calls.single.arguments, {'packageName': 'dev.example.alpha'});
  });
}
