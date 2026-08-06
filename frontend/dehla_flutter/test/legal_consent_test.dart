import 'package:dehla_flutter/util/legal_consent.dart';
import 'package:dehla_flutter/util/legal_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legal agreement version is non-empty', () {
    expect(kLegalAgreementVersion, isNotEmpty);
  });

  test('terms and privacy copy mention core topics', () {
    final terms = termsOfUseBody();
    expect(terms, contains('voice'));
    expect(terms, contains(kLegalAgreementVersion));

    final privacy = privacyPolicyBody();
    expect(privacy, contains('nickname'));
    expect(privacy.toLowerCase(), contains('sell'));
  });
}
