import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/protocol.dart';

typedef ViewHandler = void Function(PlayerGameView view);
typedef TokenHandler = void Function(String token);
typedef RejectHandler = void Function(String reason);
typedef GameEndedHandler = void Function(String reason, bool aborted);
typedef GameRestartedHandler = void Function(String gameId);

class DehlaGameSocket {
  DehlaGameSocket({
    required this.urlBuilder,
    required this.onView,
    this.onToken,
    this.onReject,
    this.onGameEnded,
    this.onGameRestarted,
  });

  /// Rebuilds WS URL (token may rotate).
  final String Function() urlBuilder;
  final ViewHandler onView;
  final TokenHandler? onToken;
  final RejectHandler? onReject;
  final GameEndedHandler? onGameEnded;
  final GameRestartedHandler? onGameRestarted;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _reconnect;
  bool _closed = false;
  int _backoffMs = 500;
  String? _lastGameId;
  int? _lastVersion;

  void connect() {
    _closed = false;
    _open();
  }

  void _open() {
    if (_closed) return;
    try {
      _ch = WebSocketChannel.connect(Uri.parse(urlBuilder()));
      _sub = _ch!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _backoffMs = 500;
      if (_lastGameId != null && _lastVersion != null) {
        requestStateSync(_lastGameId!, _lastVersion!);
      }
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _sub?.cancel();
    _reconnect?.cancel();
    final delay = _backoffMs;
    _backoffMs = (_backoffMs * 2).clamp(500, 8000);
    _reconnect = Timer(Duration(milliseconds: delay), _open);
  }

  void _onMessage(dynamic raw) {
    final map = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (map['type'] as String?) {
      case 'state_snapshot':
        final view =
            PlayerGameView.fromJson(map['view'] as Map<String, dynamic>);
        _lastGameId = view.gameId;
        _lastVersion = view.stateVersion;
        onView(view);
      case 'token_rotated':
        onToken?.call(map['token'] as String);
      case 'reject':
        onReject?.call(map['reason'] as String? ?? 'rejected');
      case 'game_ended':
        onGameEnded?.call(
          map['reason'] as String? ?? 'game ended',
          map['aborted'] as bool? ?? true,
        );
      case 'game_restarted':
        onGameRestarted?.call(map['game_id'] as String);
    }
  }

  void sendAction({
    required String gameId,
    required int expectedStateVersion,
    required Map<String, dynamic> action,
  }) {
    final envelope = {
      'protocol_version': protocolVersion,
      'action_id': const Uuid().v4(),
      'game_id': gameId,
      'expected_state_version': expectedStateVersion,
      'action': action,
    };
    _ch?.sink.add(jsonEncode(envelope));
  }

  void requestStateSync(String gameId, int version) {
    sendAction(
      gameId: gameId,
      expectedStateVersion: version,
      action: {'type': 'request_state_sync'},
    );
  }

  void playCard(String gameId, int version, CardModel card) {
    sendAction(
      gameId: gameId,
      expectedStateVersion: version,
      action: {'type': 'play_card', 'card': card.toJson()},
    );
  }

  void announceTrump(String gameId, int version, String suit) {
    sendAction(
      gameId: gameId,
      expectedStateVersion: version,
      action: {'type': 'announce_trump', 'suit': suit},
    );
  }

  void startNextHand(String gameId, int version) {
    sendAction(
      gameId: gameId,
      expectedStateVersion: version,
      action: {'type': 'start_next_hand'},
    );
  }

  void rematch(String gameId, int version) {
    sendAction(
      gameId: gameId,
      expectedStateVersion: version,
      action: {'type': 'rematch'},
    );
  }

  Future<void> close() async {
    _closed = true;
    _reconnect?.cancel();
    await _sub?.cancel();
    await _ch?.sink.close();
  }
}
