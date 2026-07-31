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
        if (data is String) {
          final json = jsonDecode(data) as Map<String, dynamic>;
          _messages.add(ServerMessage.fromJson(json));
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

  void sendEnvelope(Map<String, dynamic> envelope) {
    _channel.sink.add(jsonEncode(envelope));
  }

  void close() {
    _channel.sink.close();
  }
}
