import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eink_launcher/widgets/file_action_dialogs.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('New Folder dialog opens, validates, and dismisses cleanly', (
    WidgetTester tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showNewFolderDialog(context, const [
                'existing.txt',
              ]);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('New Folder'), findsOneWidget);

    // Empty / invalid names are rejected with an inline error, no pop.
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('New Folder'), findsOneWidget);
    expect(find.text("Name can't be empty"), findsOneWidget);

    // Slash is rejected.
    await tester.enterText(find.byType(TextField), 'a/b');
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('New Folder'), findsOneWidget);
    expect(find.text("Name can't contain / or \\"), findsOneWidget);

    // A valid name pops and resolves.
    await tester.enterText(find.byType(TextField), 'My Folder');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle(); // run the route exit animation fully

    expect(find.text('New Folder'), findsNothing);
    expect(result, 'My Folder');
  });

  testWidgets('Rename dialog pre-fills and pops with the trimmed name', (
    WidgetTester tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showRenameDialog(context, 'old.txt', ['old.txt']);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    // Pre-filled with the current name.
    expect(find.text('old.txt'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' new.txt ');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(result, 'new.txt');
  });
}
