import 'package:eink_launcher/widgets/battery_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('eink_launcher/battery_events');
  const codec = StandardMethodCodec();
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'battery events update level and charging, ignore malformed data, and cancel',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BatteryStatus())),
      );
      await tester.pump();
      expect(find.text('--%'), findsOneWidget);
      Future<void> emit(Object? event) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          codec.encodeSuccessEnvelope(event),
          (_) {},
        );
        await tester.pump();
      }

      await emit({'level': 50, 'charging': false});
      expect(find.text('50%'), findsOneWidget);
      expect(find.byIcon(Icons.battery_4_bar), findsOneWidget);
      await emit({'level': 51, 'charging': true});
      expect(find.byIcon(Icons.battery_charging_full), findsOneWidget);
      await emit({'level': 'bad', 'charging': 1});
      await emit(null);
      expect(find.text('51%'), findsOneWidget);
      await emit({'level': 150, 'charging': false});
      expect(find.text('100%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(calls, ['listen', 'cancel']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unavailable stream leaves a static fallback and can receive later data',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BatteryStatus())),
      );
      await tester.pump();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeErrorEnvelope(code: 'unavailable'),
        (_) {},
      );
      await tester.pump();
      expect(find.text('--%'), findsOneWidget);
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeSuccessEnvelope({'level': 10, 'charging': false}),
        (_) {},
      );
      await tester.pump();
      expect(find.text('10%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
