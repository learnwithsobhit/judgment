/// Native (IO) legal consent persistence.
library;

import 'native_kv_store.dart';

const _key = 'judgement_legal_accepted_v';

String? readLegalAcceptedVersion() => NativeKvStore.getString(_key);

void writeLegalAcceptedVersion(String version) {
  NativeKvStore.setString(_key, version);
}

void clearLegalAcceptedVersion() {
  NativeKvStore.remove(_key);
}
