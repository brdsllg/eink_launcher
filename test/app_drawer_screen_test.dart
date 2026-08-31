import 'package:eink_launcher/screens/app_drawer_screen.dart';
import 'package:eink_launcher/services/app_list_service.dart';
import 'package:eink_launcher/widgets/page_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('eink_launcher/apps');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(AppListService.invalidateCache);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'app query failures can be refreshed and launch failures stay in the drawer',
    (tester) async {
      var failed = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (failed || call.method == 'launchApp') {
          throw PlatformException(code: 'unavailable');
        }
        return [
          {'name': 'Reader', 'packageName': 'reader', 'isSystemApp': false},
        ];
      });
      await tester.pumpWidget(const MaterialApp(home: AppDrawerScreen()));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load apps. Tap Refresh to retry.'),
        findsOneWidget,
      );
      failed = false;
      await tester.tap(find.byTooltip('Refresh apps'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reader'));
      await tester.pumpAndSettle();
      expect(find.text('Could not open this app.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'live search resets pagination and the app bands match both orientations',
    (tester) async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => [
          for (var i = 0; i < 30; i++)
            {
              'name': 'App ${i.toString().padLeft(2, '0')}',
              'packageName': 'app.$i',
              'isSystemApp': false,
            },
        ],
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpWidget(const MaterialApp(home: AppDrawerScreen()));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PageNavBar)).height, 60);
      expect(tester.getSize(find.byType(AppBar)).height, 60);
      tester.widget<PageNavBar>(find.byType(PageNavBar)).onNext!();
      await tester.pumpAndSettle();
      expect(tester.widget<PageNavBar>(find.byType(PageNavBar)).currentPage, 1);
      await tester.tap(find.byTooltip('Search apps'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'App 29');
      await tester.pumpAndSettle();
      expect(find.text('App 29'), findsNWidgets(2));
      expect(tester.widget<PageNavBar>(find.byType(PageNavBar)).currentPage, 0);
      await tester.enterText(find.byType(TextField), 'App 28');
      await tester.pumpAndSettle();
      expect(find.text('App 29'), findsNothing);
      await tester.tap(find.byTooltip('Close search'));
      tester.view.physicalSize = const Size(900, 600);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PageNavBar)).height, 50);
      expect(tester.getSize(find.byType(AppBar)).height, 50);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
