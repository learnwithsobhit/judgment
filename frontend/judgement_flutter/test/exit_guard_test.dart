import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/widgets/exit_confirm_dialogs.dart';

void main() {
  testWidgets('leave table dialog Stay keeps route; Leave returns true',
      (tester) async {
    var leaveConfirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  leaveConfirmed = await showLeaveTableDialog(context);
                },
                child: const Text('Ask'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.text('Leave the table?'), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Leave the table?'), findsNothing);
    expect(leaveConfirmed, isFalse);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(leaveConfirmed, isTrue);
  });

  testWidgets('PopScope guard shows leave dialog and Stay blocks pop',
      (tester) async {
    var leaveCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => PopScope(
                      canPop: false,
                      onPopInvokedWithResult: (didPop, _) async {
                        if (didPop) return;
                        final leave = await showLeaveTableDialog(context);
                        if (leave && context.mounted) {
                          leaveCalls += 1;
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Scaffold(body: Text('Table')),
                    ),
                  ),
                );
              },
              child: const Text('Open table'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open table'));
    await tester.pumpAndSettle();
    expect(find.text('Table'), findsOneWidget);

    final blocked = await tester.binding.handlePopRoute();
    expect(blocked, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Leave the table?'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Table'), findsOneWidget);
    expect(leaveCalls, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Table'), findsNothing);
    expect(find.text('Open table'), findsOneWidget);
    expect(leaveCalls, 1);
  });

  testWidgets('leave lobby dialog confirms before leave', (tester) async {
    var confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                confirmed = await showLeaveLobbyDialog(context);
              },
              child: const Text('Ask lobby'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ask lobby'));
    await tester.pumpAndSettle();
    expect(find.text('Leave lobby?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await tester.tap(find.text('Ask lobby'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('end game dialog requires confirmation', (tester) async {
    var confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                confirmed = await showEndGameDialog(context);
              },
              child: const Text('Ask end'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ask end'));
    await tester.pumpAndSettle();
    expect(find.text('End game for everyone?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await tester.tap(find.text('Ask end'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'End game'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
