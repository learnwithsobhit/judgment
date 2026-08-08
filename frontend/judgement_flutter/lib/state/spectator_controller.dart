/// Audience watch-session controller (read-only table + engagement rail).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../networking/game_socket.dart';
import 'game_controller.dart' show GameConnectionState;

class AudienceComment {
  final String nickname;
  final String text;
  final DateTime at;
  AudienceComment({required this.nickname, required this.text, required this.at});
}

class SpectatorController extends ChangeNotifier {
  final ApiClient api;
  final String gameId;
  final String roomCode;
  final String nickname;

  GameSocket? _socket;
  StreamSubscription<ServerMessage>? _subscription;
  bool _disposed = false;
  final _uuid = const Uuid();

  SpectatorGameView? view;
  CrowdPredictionView? crowdPrediction;
  GameConnectionState connection = GameConnectionState.connecting;
  String? lastError;
  /// Non-null for abort/revoke/restart — UI should dismiss watch.
  String? closedReason;
  /// Natural finish — keep snapshot and show celebration/results.
  bool gameFinished = false;
  final List<AudienceComment> comments = [];
  DateTime? commentCooldownUntil;
  DateTime? reactionCooldownUntil;
  DateTime? predictionCooldownUntil;

  SpectatorController({
    required this.api,
    required this.gameId,
    required this.roomCode,
    required this.nickname,
  });

  String nicknameOf(String playerId) {
    final seat = view?.seats.where((s) => s.playerId == playerId).firstOrNull;
    return seat?.nickname ?? 'Player';
  }

  String? avatarOf(String playerId) {
    return view?.seats
        .where((s) => s.playerId == playerId)
        .map((s) => s.avatarId)
        .firstOrNull;
  }

  Future<void> connect() async {
    if (_disposed) return;
    connection = GameConnectionState.connecting;
    lastError = null;
    notifyListeners();
    try {
      final socket = await GameSocket.connect(
        api.watchSocketUri(gameId),
        onDone: _onSocketDone,
        onError: (e) {
          lastError = e.toString();
          notifyListeners();
        },
      );
      if (_disposed) {
        socket.close();
        return;
      }
      _socket = socket;
      connection = GameConnectionState.connected;
      _subscription = socket.messages.listen(_handle);
      notifyListeners();
    } catch (e) {
      connection = GameConnectionState.disconnected;
      lastError = e.toString();
      notifyListeners();
    }
  }

  void _onSocketDone() {
    if (_disposed) return;
    if (closedReason != null || gameFinished) return;
    connection = GameConnectionState.disconnected;
    notifyListeners();
  }

  bool _isNaturalFinishReason(String reason) {
    final r = reason.trim().toLowerCase();
    return r == 'game_finished' || r == 'game finished';
  }

  void _markGameFinished() {
    gameFinished = true;
    closedReason = null;
    connection = GameConnectionState.disconnected;
    _closeSocket();
  }

  void _handle(ServerMessage message) {
    switch (message) {
      case SpectatorStateSnapshot(:final view):
        this.view = view;
        if (view.isFinished && view.finalRanking != null) {
          gameFinished = true;
        }
        notifyListeners();
      case CrowdPredictionUpdated(:final prediction):
        crowdPrediction = prediction;
        notifyListeners();
      case AudienceCommentEvent(:final fromNickname, :final text):
        comments.add(AudienceComment(
          nickname: fromNickname,
          text: text,
          at: DateTime.now(),
        ));
        while (comments.length > 50) {
          comments.removeAt(0);
        }
        notifyListeners();
      case SpectatingClosed(:final reason):
        final finishedAlready =
            gameFinished || (view?.isFinished == true && view?.finalRanking != null);
        if (_isNaturalFinishReason(reason) || finishedAlready) {
          _markGameFinished();
          notifyListeners();
          return;
        }
        closedReason = reason;
        connection = GameConnectionState.disconnected;
        _closeSocket();
        notifyListeners();
      case TokenRotated(:final token):
        api.token = token;
      case CommandRejected(:final message):
        lastError = message;
        notifyListeners();
      case CommandAccepted():
        lastError = null;
      default:
        break;
    }
  }

  void sendComment(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || gameFinished) return;
    if (commentCooldownUntil != null &&
        DateTime.now().isBefore(commentCooldownUntil!)) {
      lastError = 'Slow down — wait a moment before commenting';
      notifyListeners();
      return;
    }
    commentCooldownUntil = DateTime.now().add(const Duration(seconds: 2));
    _send({'type': 'audience_comment', 'text': trimmed});
    notifyListeners();
  }

  void sendReaction(String emoji) {
    if (gameFinished) return;
    if (reactionCooldownUntil != null &&
        DateTime.now().isBefore(reactionCooldownUntil!)) {
      lastError = 'Slow down — reactions cooling down';
      notifyListeners();
      return;
    }
    reactionCooldownUntil = DateTime.now().add(const Duration(seconds: 2));
    _send({'type': 'audience_reaction', 'emoji': emoji});
    notifyListeners();
  }

  void setWinnerPrediction(String playerId) {
    if (gameFinished) return;
    if (crowdPrediction?.locked == true) {
      lastError = 'Predictions locked — final round';
      notifyListeners();
      return;
    }
    if (predictionCooldownUntil != null &&
        DateTime.now().isBefore(predictionCooldownUntil!)) {
      return;
    }
    predictionCooldownUntil = DateTime.now().add(const Duration(seconds: 1));
    _send({'type': 'set_winner_prediction', 'player_id': playerId});
    notifyListeners();
  }

  void _send(Map<String, dynamic> action) {
    final socket = _socket;
    if (socket == null || view == null) return;
    socket.sendEnvelope({
      'protocol_version': protocolVersion,
      'action_id': _uuid.v4(),
      'game_id': gameId,
      'expected_state_version': view!.stateVersion,
      'action': action,
    });
  }

  void _closeSocket() {
    _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _closeSocket();
    super.dispose();
  }
}
