import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/util/table_place.dart';

PlayerScore _score(String id, int total) =>
    PlayerScore.fromJson({'player_id': id, 'total_score': total});

void main() {
  test('nothing until a round has finished', () {
    expect(
      TablePlace.marksFor(
        historyStarted: false,
        scores: [_score('a', 40), _score('b', 20)],
      ),
      isEmpty,
    );
  });

  test('1st is unmarked; 2nd and 3rd are marked', () {
    final marks = TablePlace.marksFor(
      historyStarted: true,
      scores: [
        _score('a', 40),
        _score('b', 22),
        _score('c', 10),
        _score('d', 4),
      ],
    );
    expect(marks['a'], isNull);
    expect(marks['b'], 2);
    expect(marks['c'], 3);
    expect(marks['d'], isNull);
  });

  test('anyone tied with the leader is also 1st', () {
    final marks = TablePlace.marksFor(
      historyStarted: true,
      scores: [_score('a', 30), _score('b', 30), _score('c', 12)],
    );
    expect(marks['a'], isNull);
    expect(marks['b'], isNull);
    expect(marks['c'], 2);
  });

  test('a tie for 2nd marks both and skips 3rd', () {
    final marks = TablePlace.marksFor(
      historyStarted: true,
      scores: [
        _score('lead', 50),
        _score('x', 30),
        _score('y', 30),
        _score('z', 10),
      ],
    );
    expect(marks['lead'], isNull);
    expect(marks['x'], 2);
    expect(marks['y'], 2);
    expect(marks.containsKey('z'), isFalse);
  });
}
