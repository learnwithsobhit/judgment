/// Authoritative-state mirror plus command lifecycle for one game.
///
/// The UI may optimistically indicate a pending action, but never mutates
/// authoritative state before server acknowledgement (PLAN.md §10).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../networking/game_socket.dart';

enum GameConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
}

class GameController extends ChangeNotifier {
  final ApiClient api;
  final String gameId;
  final String myPlayerId;
  final String myNickname;

  GameSocket? _socket;
  StreamSubscription<ServerMessage>? _subscription;
  bool _disposed = false;
  int _reconnectAttempts = 0;

  PlayerGameView? view;
  GameConnectionState connection = GameConnectionState.connecting;

  /// action_id of the command awaiting acknowledgement, if any.
  String? pendingActionId;

  /// Most recent rejection to surface to the user (cleared after display).
  String? lastRejection;

  /// Engine reason code from the last rejection, for the rules assistant.
  String? lastRejectionCode;

  /// Turn timer: deadline expressed in local wall-clock time.
  DateTime? turnDeadline;

  /// The full duration of the current turn, for progress display.
  int turnTotalMs = 1;
  int? _timerDeadlineId;

  /// Pause banner while a peer is within reconnect grace.
  String? pauseReason;
  DateTime? pauseUntil;

  final _uuid = const Uuid();

  GameController({
    required this.api,
    required this.gameId,
    required this.myPlayerId,
    required this.myNickname,
  });

  bool get isPaused =>
      pauseUntil != null && DateTime.now().isBefore(pauseUntil!);

  bool get isMyTurn =>
      view != null &&
      view!.currentTurn == myPlayerId &&
      !view!.isFinished &&
      !isPaused;

  String nicknameOf(String playerId) {
    if (playerId == myPlayerId) return myNickname;
    final opponent = view?.opponents.where((o) => o.playerId == playerId);
    return (opponent != null && opponent.isNotEmpty)
        ? opponent.first.nickname
        : 'Player';
  }

  Future<void> connect() async {
    connection = _reconnectAttempts == 0
        ? GameConnectionState.connecting
        : GameConnectionState.reconnecting;
    _notify();
    try {
      final socket = await GameSocket.connect(
        api.gameSocketUri(gameId),
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );
      _socket = socket;
      _subscription = socket.messages.listen(_handleMessage);
      connection = GameConnectionState.connected;
      _reconnectAttempts = 0;
      // A fresh personalised snapshot is pushed on connect; ask explicitly
      // as well in case this is a resumed session.
      _sendAction({'type': 'request_state_sync'});
      _notify();
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (_disposed) return;
    connection = GameConnectionState.disconnected;
    _notify();
    if (_reconnectAttempts < 5 && !(view?.isFinished ?? false)) {
      _reconnectAttempts += 1;
      final delay = Duration(milliseconds: 500 * pow(2, _reconnectAttempts).toInt());
      Timer(delay, () {
        if (!_disposed) connect();
      });
    }
  }

  void _handleMessage(ServerMessage message) {
    switch (message) {
      case StateSnapshot(:final view):
        this.view = view;
        _notify();
      case CommandAccepted(:final actionId):
        if (pendingActionId == actionId) {
          pendingActionId = null;
          _notify();
        }
      case CommandRejected(
          :final actionId,
          :final message,
          :final retryable,
          :final errorCode
        ):
        if (actionId == null || actionId == pendingActionId) {
          pendingActionId = null;
        }
        lastRejection = retryable ? '$message (retrying may help)' : message;
        lastRejectionCode = errorCode;
        _notify();
      case TimerUpdated(:final timer):
        if (_timerDeadlineId != timer.deadlineId) {
          _timerDeadlineId = timer.deadlineId;
          turnTotalMs = timer.remainingMs.clamp(1, 1 << 31);
          turnDeadline =
              DateTime.now().add(Duration(milliseconds: timer.remainingMs));
          _notify();
        }
      case GamePaused(:final reason, :final remainingMs):
        pauseReason = reason;
        pauseUntil = DateTime.now().add(Duration(milliseconds: remainingMs));
        turnDeadline = null;
        _notify();
      case GameResumed():
        pauseReason = null;
        pauseUntil = null;
        _notify();
      case TokenRotated(:final token):
        api.token = token;
      case BotTookOver() ||
            PlayerResumedControl() ||
            PlayerConnected() ||
            PlayerDisconnected() ||
            HostChanged():
        _notify();
      case UnknownMessage():
        break;
    }
  }

  void placeBid(int bid) {
    _sendCommand({'type': 'place_bid', 'bid': bid});
  }

  void playCard(String cardId) {
    _sendCommand({'type': 'play_card', 'card_id': cardId});
  }

  /// Why a card is not currently playable, for user feedback
  /// (server remains the authority; this only echoes its published
  /// legal-action list).
  String? cardBlockedReason(CardModel card) {
    final v = view;
    if (v == null || v.phase != 'playing') return 'Card play has not started yet';
    if (v.currentTurn != myPlayerId) return 'It is not your turn';
    if (v.legalActions.playableCards.contains(card.id)) return null;
    final lead = v.currentTrick.isNotEmpty ? v.currentTrick.first.card.suit : null;
    if (lead != null) return 'You must follow $lead';
    return 'This card cannot be played right now';
  }

  void _sendCommand(Map<String, dynamic> action) {
    final v = view;
    if (v == null || pendingActionId != null) return;
    final actionId = _uuid.v4();
    pendingActionId = actionId;
    _notify();
    _send(actionId: actionId, stateVersion: v.stateVersion, action: action);
  }

  void _sendAction(Map<String, dynamic> action) {
    _send(
      actionId: _uuid.v4(),
      stateVersion: view?.stateVersion ?? 0,
      action: action,
    );
  }

  void _send({
    required String actionId,
    required int stateVersion,
    required Map<String, dynamic> action,
  }) {
    _socket?.sendEnvelope(buildEnvelope(
      actionId: actionId,
      gameId: gameId,
      expectedStateVersion: stateVersion,
      action: action,
    ));
  }

  void clearRejection() {
    lastRejection = null;
    lastRejectionCode = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _socket?.close();
    super.dispose();
  }
}
