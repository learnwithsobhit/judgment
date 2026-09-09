import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/game_socket.dart';

void main() {
  test('keepAlivePayload matches server wire shape', () {
    expect(GameSocket.keepAlivePayload, '{"type":"keep_alive"}');
  });
}
