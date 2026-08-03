/// Versioned client-side legal consent (Terms + Privacy).
library;

import 'legal_storage.dart';

/// Bump this when Terms or Privacy text changes to force re-acceptance.
const String kLegalAgreementVersion = '2026-08-03';

/// Operator contact shown on legal pages (replace before public marketing).
const String kLegalOperatorName = 'Judgement';
const String kLegalOperatorEmail = 'shobhit.chaturvedi@zohomail.in';

bool hasAcceptedCurrentLegalAgreement() {
  return readLegalAcceptedVersion() == kLegalAgreementVersion;
}

void acceptCurrentLegalAgreement() {
  writeLegalAcceptedVersion(kLegalAgreementVersion);
}

void clearLegalAgreementAcceptance() {
  clearLegalAcceptedVersion();
}
