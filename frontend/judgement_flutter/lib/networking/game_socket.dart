/// WebSocket wrapper for the live game connection.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/protocol.dart';

class GameSocket {
  final WebSocketChannel _channel;
  final StreamController<ServerMessage> _messages = StreamController.broadcast();
  final void Function()? onDone;
  final void Function(Object error)? onError;

  GameSocket._(this._channel, {this.onDone, this.onError}) {
    _channel.stream.listen(
      (data) {
        if (data is! String) {
          return;
        }
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map<String, dynamic>) {
            return;
          }
          _messages.add(ServerMessage.fromJson(decoded));
        } catch (_) {
          // Unknown or malformed server frames must not kill the listen loop.
        }
      },
      onDone: () {
        _messages.close();
        onDone?.call();
      },
      onError: (Object error) {
        onError?.call(error);
      },
    );
  }

  static Future<GameSocket> connect(
    Uri uri, {
    void Function()? onDone,
    void Function(Object error)? onError,
  }) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return GameSocket._(channel, onDone: onDone, onError: onError);
  }

  Stream<ServerMessage> get messages => _messages.stream;

  /// Inbound proxy keepalive — not a [ClientEnvelope]; must match server wire shape.
  static const keepAlivePayload = '{"type":"keep_alive"}';

  void sendKeepAlive() {
    try {
      _channel.sink.add(keepAlivePayload);
    } catch (error) {
      // Dead or half-open socket — surface through the same path as read errors.
      onError?.call(error);
    }
  }

  void sendEnvelope(Map<String, dynamic> envelope) {
    _channel.sink.add(jsonEncode(envelope));
  }

  void close() {
    _channel.sink.close();
  }
}
