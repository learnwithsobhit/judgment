import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shell_flutter/screens/home_screen.dart';
import 'package:shell_flutter/theme/table_games_theme.dart';

void main() {
  testWidgets('home shows brand and Judgement Play', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTableGamesTheme(),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Table Games'), findsOneWidget);
    expect(find.text('Judgement'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Hazari'), findsOneWidget);
    expect(find.text('Notify me'), findsWidgets);
  });
}
