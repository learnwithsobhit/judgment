import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/widgets/bid_panel.dart';

void main() {
  testWidgets('selecting a number does not confirm the bid', (tester) async {
    final confirmed = <int>[];

    await tester.pumpWidget(_host(
      cards: 3,
      legalBids: {0, 1, 2, 3},
      onConfirm: confirmed.add,
    ));

    expect(find.text('Confirm bid'), findsNothing);

    await tester.tap(find.text('2'));
    await tester.pump();

    expect(confirmed, isEmpty);
    expect(find.text('Bid 2 tricks?'), findsOneWidget);
    expect(find.text('Confirm bid'), findsOneWidget);
  });

  testWidgets('changing the number then confirming sends only the last bid',
      (tester) async {
    final confirmed = <int>[];

    await tester.pumpWidget(_host(
      cards: 3,
      legalBids: {0, 1, 2, 3},
      onConfirm: confirmed.add,
    ));

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();

    expect(find.text('Bid 1 tricks?'), findsNothing);
    expect(find.text('Bid 3 tricks?'), findsOneWidget);

    await tester.tap(find.text('Confirm bid'));
    await tester.pump();

    expect(confirmed, [3]);
  });

  testWidgets('an illegal number cannot be selected', (tester) async {
    final confirmed = <int>[];

    await tester.pumpWidget(_host(
      cards: 3,
      legalBids: {0, 1, 3},
      dealerRestricted: true,
      onConfirm: confirmed.add,
    ));

    expect(find.text('Your bid — as dealer, the total cannot equal 3'),
        findsOneWidget);

    final illegal = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '2'),
    );
    expect(illegal.onPressed, isNull);

    await tester.tap(find.text('2'));
    await tester.pump();

    expect(confirmed, isEmpty);
    expect(find.text('Confirm bid'), findsNothing);
    expect(find.text('Bid 2 tricks?'), findsNothing);
  });

  testWidgets('pending locks numbers and confirm', (tester) async {
    final confirmed = <int>[];
    var pending = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => BidPanel(
            cards: 3,
            legalBids: const {0, 1, 2, 3},
            dealerRestricted: false,
            pending: pending,
            onConfirm: (bid) {
              confirmed.add(bid);
              setState(() => pending = true);
            },
          ),
        ),
      ),
    ));

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('Confirm bid'));
    await tester.pump();

    expect(confirmed, [1]);

    await tester.tap(find.text('Confirm bid'));
    await tester.pump();
    await tester.tap(find.text('0'));
    await tester.pump();

    expect(confirmed, [1]);
    expect(find.text('Bid 1 tricks?'), findsOneWidget);
    expect(find.text('Bid 0 tricks?'), findsNothing);
  });

  testWidgets('selection clears when the bid is no longer legal',
      (tester) async {
    final confirmed = <int>[];
    var legalBids = {0, 1, 2};

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              BidPanel(
                cards: 2,
                legalBids: legalBids,
                dealerRestricted: false,
                pending: false,
                onConfirm: confirmed.add,
              ),
              TextButton(
                onPressed: () => setState(() => legalBids = {0, 1}),
                child: const Text('Drop'),
              ),
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.text('Confirm bid'), findsOneWidget);

    await tester.tap(find.text('Drop'));
    await tester.pump();

    expect(find.text('Confirm bid'), findsNothing);
    expect(find.text('Bid 2 tricks?'), findsNothing);
    expect(confirmed, isEmpty);
  });
}

Widget _host({
  required int cards,
  required Set<int> legalBids,
  required ValueChanged<int> onConfirm,
  bool dealerRestricted = false,
  bool pending = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BidPanel(
        cards: cards,
        legalBids: legalBids,
        dealerRestricted: dealerRestricted,
        pending: pending,
        onConfirm: onConfirm,
      ),
    ),
  );
}
