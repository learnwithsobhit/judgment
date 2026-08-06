/// Versioned client-side legal consent (Terms + Privacy) for Dehla.
library;

import 'legal_storage.dart';

/// Bump when Terms or Privacy text changes to force re-acceptance.
const String kLegalAgreementVersion = '2026-08-06';

const String kLegalOperatorName = 'Judgement / Dehla Pakad';
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
