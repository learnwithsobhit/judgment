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

/// Ephemeral reaction / cheer for the blast overlays.
class EmoteBurst {
  final String id;
  final String from;
  final String? target;
  final List<String> emojis;
  final String? text;
  final String? mood;
  final String? stickerId;
  final int ttlMs;
  final DateTime createdAt;

  EmoteBurst({
    required this.id,
    required this.from,
    required this.target,
    required this.emojis,
    this.text,
    required this.mood,
    this.stickerId,
    required this.ttlMs,
  }) : createdAt = DateTime.now();
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

  /// Held last-trick cards for min 1.6s presentation pause.
  CompletedTrickView? heldCompletedTrick;
  DateTime? _holdUntil;
  Timer? _holdTimer;

  /// Transient "X takes the trick" / last-round strip.
  String? trickBanner;
  String? roundResultBanner;
  Timer? _bannerTimer;

  /// Active emoji bursts (auto-pruned).
  final List<EmoteBurst> activeBursts = [];

  /// playerId → latest flash mood for avatar bounce.
  final Map<String, String> avatarFlashes = {};

  bool muteReactions = false;

  final _uuid = const Uuid();

  static const _minTrickHold = Duration(milliseconds: 1600);

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

  /// Cards shown in the trick area (live trick or held completed overlay).
  List<PlayedCard> get displayTrick {
    final v = view;
    if (v == null) return const [];
    // Prefer the held completed trick until the min pause elapses, even if the
    // next lead has already arrived underneath.
    if (_holdActive && heldCompletedTrick != null) {
      return heldCompletedTrick!.plays;
    }
    if (v.currentTrick.isNotEmpty) return v.currentTrick;
    return heldCompletedTrick?.plays ??
        v.lastCompletedTrick?.plays ??
        const [];
  }

  bool get showingCompletedTrick {
    if (_holdActive && heldCompletedTrick != null) return true;
    final v = view;
    if (v == null) return false;
    if (v.currentTrick.isNotEmpty) return false;
    return heldCompletedTrick != null || v.lastCompletedTrick != null;
  }

  bool get _holdActive =>
      _holdUntil != null && DateTime.now().isBefore(_holdUntil!);

  String? avatarOf(String playerId) {
    if (playerId == myPlayerId) return view?.ownAvatarId;
    final o = view?.opponents.where((e) => e.playerId == playerId);
    if (o == null || o.isEmpty) return null;
    return o.first.avatarId;
  }

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

  static const _maxReconnectAttempts = 5;

  /// True when auto-reconnect gave up and the user can retry manually.
  bool get canManualReconnect =>
      connection == GameConnectionState.disconnected &&
      _reconnectAttempts >= _maxReconnectAttempts &&
      !(view?.isFinished ?? false);

  /// Reset attempt counter and reconnect after auto-retry exhaustion.
  Future<void> manualReconnect() async {
    if (_disposed) return;
    _reconnectAttempts = 0;
    pendingActionId = null;
    await connect();
  }

  void _handleDisconnect() {
    if (_disposed) return;
    // Unstick bid/play if the socket died before CommandAccepted.
    pendingActionId = null;
    connection = GameConnectionState.disconnected;
    _notify();
    if (_reconnectAttempts < _maxReconnectAttempts &&
        !(view?.isFinished ?? false)) {
      _reconnectAttempts += 1;
      final delay =
          Duration(milliseconds: 500 * pow(2, _reconnectAttempts).toInt());
      Timer(delay, () {
        if (!_disposed) connect();
      });
    }
  }

  void _handleMessage(ServerMessage message) {
    switch (message) {
      case StateSnapshot(:final view):
        _applySnapshot(view);
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
      case TableEventMessage(
          :final kind,
          :final from,
          :final target,
          :final emojis,
          :final text,
          :final mood,
          :final stickerId,
          :final ttlMs
        ):
        _onTableEvent(
          kind: kind,
          from: from,
          target: target,
          emojis: emojis,
          text: text,
          mood: mood,
          stickerId: stickerId,
          ttlMs: ttlMs,
        );
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

  void _applySnapshot(PlayerGameView next) {
    final prev = view;
    final prevHistoryLen = prev?.roundHistory.length ?? 0;

    // Trick reveal hold: when a completed trick appears (or persists), ensure
    // the client keeps showing it for at least 1.6s.
    if (next.lastCompletedTrick != null && next.currentTrick.isEmpty) {
      final incoming = next.lastCompletedTrick!;
      final same = heldCompletedTrick?.trickIndex == incoming.trickIndex &&
          heldCompletedTrick?.winnerId == incoming.winnerId;
      if (!same) {
        heldCompletedTrick = incoming;
        trickBanner =
            '${nicknameOf(incoming.winnerId)} takes the trick';
        _armHold();
      }
    } else if (next.currentTrick.isNotEmpty) {
      // New lead arrived — keep hold until min duration elapses.
      if (heldCompletedTrick != null &&
          _holdUntil != null &&
          DateTime.now().isBefore(_holdUntil!)) {
        // Keep overlay; live lead waits underneath until hold ends.
      } else if (heldCompletedTrick != null &&
          (_holdUntil == null || !DateTime.now().isBefore(_holdUntil!))) {
        heldCompletedTrick = null;
        trickBanner = null;
      }
    } else if (next.lastCompletedTrick == null &&
        (heldCompletedTrick == null ||
            _holdUntil == null ||
            !DateTime.now().isBefore(_holdUntil!))) {
      heldCompletedTrick = null;
      trickBanner = null;
    }

    if (next.roundHistory.length > prevHistoryLen &&
        next.roundHistory.isNotEmpty) {
      final last = next.roundHistory.last;
      final lines = last.entries
          .map((e) =>
              '${nicknameOf(e.playerId)} ${e.score} (bid ${e.bid}→${e.tricksWon})')
          .join(' · ');
      roundResultBanner = 'Round ${last.roundIndex + 1} scores: $lines';
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 5), () {
        roundResultBanner = null;
        _notify();
      });
    }

    view = next;
    _notify();
  }

  void _armHold() {
    _holdUntil = DateTime.now().add(_minTrickHold);
    _holdTimer?.cancel();
    _holdTimer = Timer(_minTrickHold, () {
      // Drop hold only once the server no longer needs it OR live trick started
      // after the min hold.
      final v = view;
      if (v != null && v.currentTrick.isNotEmpty) {
        heldCompletedTrick = null;
        trickBanner = null;
      } else if (v == null || v.lastCompletedTrick == null) {
        heldCompletedTrick = null;
        trickBanner = null;
      }
      // If last_completed_trick still present, keep showing server projection
      // (heldCompletedTrick can stay synced).
      heldCompletedTrick = v?.lastCompletedTrick;
      if (heldCompletedTrick == null) trickBanner = null;
      _notify();
    });
  }

  void _onTableEvent({
    required String kind,
    required String from,
    required String? target,
    required List<String> emojis,
    required String? text,
    required String? mood,
    required String? stickerId,
    required int ttlMs,
  }) {
    if (muteReactions && kind != 'auto_cheer') return;
    if (mood != null) {
      avatarFlashes[from] = '$mood-${DateTime.now().millisecondsSinceEpoch}';
    }
    final hasText = text != null && text.trim().isNotEmpty;
    if (emojis.isNotEmpty || kind == 'avatar_flash' || hasText) {
      final burst = EmoteBurst(
        id: _uuid.v4(),
        from: from,
        target: target,
        emojis: emojis.isEmpty
            ? switch (mood) {
                'laugh' => ['😂'],
                'facepalm' || 'oops' => ['😤'],
                'fire' || 'roast' => ['🔥'],
                _ => ['🙌'],
              }
            : emojis,
        text: text,
        mood: mood,
        stickerId: stickerId,
        ttlMs: ttlMs,
      );
      activeBursts.add(burst);
      Timer(Duration(milliseconds: ttlMs + 50), () {
        activeBursts.removeWhere((b) => b.id == burst.id);
        _notify();
      });
    }
    _notify();
  }

  void placeBid(int bid) {
    _sendCommand({'type': 'place_bid', 'bid': bid});
  }

  void playCard(String cardId) {
    _sendCommand({'type': 'play_card', 'card_id': cardId});
  }

  void setAvatar(String avatarId) {
    _sendAction({'type': 'set_avatar', 'avatar_id': avatarId});
  }

  void sendReaction(String emoji, {String? target}) {
    _sendAction({
      'type': 'send_reaction',
      'emoji': emoji,
      'target': ?target,
    });
  }

  void sendEmoteText(String text) {
    _sendAction({'type': 'send_emote_text', 'text': text});
  }

  void sendAvatarFlash(String mood) {
    _sendAction({'type': 'avatar_flash', 'mood': mood});
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
    _holdTimer?.cancel();
    _bannerTimer?.cancel();
    _subscription?.cancel();
    _socket?.close();
    super.dispose();
  }
}
