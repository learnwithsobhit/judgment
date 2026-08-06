import 'package:dehla_flutter/util/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('english and hindi expose create_room', () {
    dehlaLang = DehlaLang.en;
    expect(t('create_room'), 'Create room');
    dehlaLang = DehlaLang.hi;
    expect(t('create_room'), isNotEmpty);
    expect(t('create_room'), isNot(equals('Create room')));
  });
}
