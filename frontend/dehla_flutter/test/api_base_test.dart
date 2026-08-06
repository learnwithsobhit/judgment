import 'package:dehla_flutter/networking/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default dehlaApiBase is local dehla port', () {
    expect(dehlaApiBase(), 'http://localhost:8081');
  });
}
