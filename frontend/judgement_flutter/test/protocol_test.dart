import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';

void main() {
  group('CardModel', () {
    test('parses and produces canonical wire id', () {
      final card = CardModel.fromJson({'suit': 'hearts', 'rank': 'ace'});
      expect(card.id, 'ace-of-hearts');
      expect(card.rankLabel, 'A');
      expect(card.suitSymbol, '\u2665');
      expect(card.isRed, isTrue);
    });

    test('rank ordering puts ace highest', () {
      final ace = CardModel.fromJson({'suit': 'spades', 'rank': 'ace'});
      final two = CardModel.fromJson({'suit': 'spades', 'rank': 'two'});
      final king = CardModel.fromJson({'suit': 'spades', 'rank': 'king'});
      expect(ace.rankValue, greaterThan(king.rankValue));
      expect(king.rankValue, greaterThan(two.rankValue));
    });
  });

  group('PlayerGameView', () {
    test('parses a mid-game snapshot', () {
      final json = {
        'game_id': '00000000-0000-0000-0000-000000000001',
        'state_version': 42,
        'phase': 'playing',
        'own_hand': [
          {'suit': 'hearts', 'rank': 'ace'},
          {'suit': 'spades', 'rank': 'two'},
        ],
        'own_seat': 4,
        'own_bid': 2,
        'own_tricks_won': 1,
        'opponents': [
          {
            'player_id': '00000000-0000-0000-0000-000000000002',
            'nickname': 'Beth',
            'seat': 1,
            'card_count': 2,
            'bid': 0,
            'tricks_won': 0,
            'connection_status': 'connected',
          },
        ],
        'current_trick': [
          {
            'player_id': '00000000-0000-0000-0000-000000000002',
            'card': {'suit': 'spades', 'rank': 'king'},
          },
        ],
        'trump': 'spades',
        'trump_card': {'suit': 'spades', 'rank': 'nine'},
        'current_turn': '00000000-0000-0000-0000-000000000003',
        'bids': [
          {'player_id': '00000000-0000-0000-0000-000000000002', 'bid': 0},
        ],
        'scores': [
          {'player_id': '00000000-0000-0000-0000-000000000002', 'total_score': 11},
        ],
        'round': {
          'round_index': 3,
          'total_rounds': 8,
          'cards_per_player': 5,
          'dealer': '00000000-0000-0000-0000-000000000002',
          'tricks_completed': 2,
        },
        'legal_actions': {
          'legal_bids': [],
          'playable_cards': ['two-of-spades'],
        },
      };

      final view = PlayerGameView.fromJson(json);
      expect(view.stateVersion, 42);
      expect(view.phase, 'playing');
      expect(view.ownHand, hasLength(2));
      expect(view.ownSeat, 4);
      expect(view.ownBid, 2);
      expect(view.ownTricksWon, 1);
      expect(view.opponents.single.nickname, 'Beth');
      expect(view.currentTrick.single.card.id, 'king-of-spades');
      expect(view.trump, 'spades');
      expect(view.round!.cardsPerPlayer, 5);
      expect(view.legalActions.playableCards, ['two-of-spades']);
      expect(view.finalRanking, isNull);
      expect(view.isFinished, isFalse);
    });

    test('parses a finished snapshot with final ranking', () {
      final json = {
        'game_id': '00000000-0000-0000-0000-000000000001',
        'state_version': 500,
        'phase': 'finished',
        'own_hand': <dynamic>[],
        'own_seat': 0,
        'own_bid': null,
        'own_tricks_won': 0,
        'opponents': <dynamic>[],
        'current_trick': <dynamic>[],
        'trump': null,
        'trump_card': null,
        'current_turn': null,
        'bids': <dynamic>[],
        'scores': <dynamic>[],
        'round': null,
        'legal_actions': {'legal_bids': <dynamic>[], 'playable_cards': <dynamic>[]},
        'final_ranking': [
          {
            'player_id': '00000000-0000-0000-0000-000000000002',
            'rank': 1,
            'total_score': 88,
            'exact_bid_rounds': 6,
            'total_tricks_missed': 3,
          },
        ],
      };

      final view = PlayerGameView.fromJson(json);
      expect(view.isFinished, isTrue);
      expect(view.finalRanking!.single.rank, 1);
      expect(view.finalRanking!.single.exactBidRounds, 6);
      expect(view.finalRanking!.single.totalTricksMissed, 3);
    });
  });

  group('ServerMessage', () {
    ServerMessage parse(String raw) =>
        ServerMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);

    test('command_accepted', () {
      final message = parse(
          '{"type":"command_accepted","action_id":"a1","new_state_version":7}');
      expect(message, isA<CommandAccepted>());
      expect((message as CommandAccepted).newStateVersion, 7);
    });

    test('command_rejected with game error', () {
      final message = parse(
          '{"type":"command_rejected","action_id":"a1","reason":{"kind":"game","error":{"code":"must_follow_suit","lead_suit":"spades","attempted":"ace-of-hearts"}},"retryable":false,"message":"You must follow spades"}');
      expect(message, isA<CommandRejected>());
      final rejected = message as CommandRejected;
      expect(rejected.errorCode, 'must_follow_suit');
      expect(rejected.retryable, isFalse);
      expect(rejected.message, contains('follow'));
    });

    test('timer_updated', () {
      final message = parse(
          '{"type":"timer_updated","timer":{"deadline_id":3,"remaining_ms":25000,"server_now_ms":1700000000000}}');
      expect(message, isA<TimerUpdated>());
      expect((message as TimerUpdated).timer.remainingMs, 25000);
    });

    test('unknown message type does not throw', () {
      expect(parse('{"type":"future_thing"}'), isA<UnknownMessage>());
    });
  });

  group('RoomView', () {
    test('parses room options (ADR 0003)', () {
      final room = RoomView.fromJson({
        'room_id': 'r1',
        'code': 'ABC123',
        'phase': 'lobby',
        'max_players': 8,
        'min_players': 3,
        'turn_timeout_seconds': null,
        'first_trump': 'clubs',
        'seats': <dynamic>[],
      });
      expect(room.maxPlayers, 8);
      expect(room.minPlayers, 3);
      expect(room.turnTimeoutSeconds, isNull, reason: 'no timer configured');
      expect(room.firstTrump, 'clubs');
      expect(room.roundSchedule.mode, 'automatic');
    });

    test('parses manual round schedule summary', () {
      final room = RoomView.fromJson({
        'room_id': 'r1',
        'code': 'ABC123',
        'phase': 'lobby',
        'max_players': 4,
        'min_players': 4,
        'round_schedule': {
          'mode': 'manual',
          'steps': [
            {'cards': 12, 'repeat': 2},
            {'cards': 1, 'repeat': 1},
          ],
        },
        'round_schedule_summary': 'Manual: 3 rounds',
        'seats': <dynamic>[],
      });
      expect(room.roundSchedule.mode, 'manual');
      expect(room.roundSchedule.expandPreview(), [12, 12, 1]);
      expect(room.roundScheduleSummary, 'Manual: 3 rounds');
    });
  });

  group('RoundSchedule', () {
    test('default manual for 4 players matches double-descent example', () {
      final schedule = RoundSchedule.defaultManualForPlayers(4);
      expect(
        schedule.expandPreview(),
        [12, 12, 11, 11, 10, 10, 9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 3, 2, 1],
      );
    });
  });

  group('GameEventPublicView', () {
    test('parses scheduled event summary without mobiles', () {
      final event = GameEventPublicView.fromJson({
        'event_id': 'e1',
        'slug': 'abc12345',
        'title': 'Friday night',
        'host_nickname': 'Host',
        'starts_at': '2026-08-01T18:00:00Z',
        'timezone': 'Asia/Kolkata',
        'duration_minutes': 90,
        'max_players': 8,
        'status': 'open',
        'going_count': 1,
        'seats_left': 7,
        'waitlisted_count': 0,
        'waitlist_left': 5,
        'going_names': ['Ada'],
        'waitlisted_names': <dynamic>[],
        'round_schedule_summary': 'Automatic (8→1)',
      });
      expect(event.slug, 'abc12345');
      expect(event.goingNames, ['Ada']);
      expect(event.seatsLeft, 7);
      expect(event.waitlistLeft, 5);
      expect(event.canRsvp, isTrue);
    });
  });

  test('client envelope shape matches protocol', () {
    final envelope = buildEnvelope(
      actionId: 'abc',
      gameId: 'g1',
      expectedStateVersion: 9,
      action: {'type': 'place_bid', 'bid': 3},
    );
    expect(envelope['protocol_version'], protocolVersion);
    expect(envelope['expected_state_version'], 9);
    expect((envelope['action'] as Map)['type'], 'place_bid');
  });
}
