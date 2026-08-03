import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/app/app.dart';

Future<void> _acceptLegal(WidgetTester tester) async {
  final checkbox = find.byType(Checkbox).first;
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('landing screen renders create and join flows', (tester) async {
    // Tall enough for create-mode options including the manual step editor.
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const JudgementApp());

    expect(find.textContaining('Judgement'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create room'), findsOneWidget);
    expect(find.textContaining('I agree to the'), findsOneWidget);
    expect(find.text('Terms'), findsWidgets);
    expect(find.text('Privacy'), findsWidgets);
    expect(find.text('Players'), findsOneWidget);
    expect(find.text('Round schedule'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Turn timer'), findsOneWidget);
    expect(find.text('First trump'), findsOneWidget);
    expect(find.text('Schedule a game for later'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // nickname only

    // Create stays disabled until legal consent.
    final createBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create room'),
    );
    expect(createBtn.onPressed, isNull);

    // Manual schedule: step editor + live preview appear.
    await tester.ensureVisible(find.text('Manual'));
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Preview'));
    expect(find.textContaining('Preview'), findsOneWidget);
    expect(find.text('Add step'), findsOneWidget);

    // Switch to join mode: room-code field appears; host options hide.
    await tester.tap(find.text('Join room').first);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Join game'), findsOneWidget);
    expect(find.text('Players'), findsNothing);
    expect(find.text('Round schedule'), findsNothing);
  });

  testWidgets('empty nickname shows validation feedback after consent',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const JudgementApp());
    await _acceptLegal(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Create room'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create room'));
    await tester.pump();
    expect(find.text('Pick a nickname first'), findsOneWidget);
  });
}
