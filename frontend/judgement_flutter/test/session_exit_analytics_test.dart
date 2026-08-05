import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/util/session_exit_analytics.dart';

void main() {
  test('exit telemetry helpers accept intentional and unintentional intents', () {
    // Stub path (VM): must not throw; debugPrint only.
    recordExitDialogShown(
      surface: ExitSurface.table,
      source: ExitSource.back,
    );
    recordExitStay(
      surface: ExitSurface.table,
      source: ExitSource.back,
    );
    recordExitLeaveConfirmed(
      surface: ExitSurface.table,
      source: ExitSource.leaveButton,
    );
    recordExitBeforeUnload();
    recordExitWsDisconnect(willReconnect: true);
    recordExitWsDisconnect(willReconnect: false);
    recordExitEndGameConfirmed();
    recordExitLeaveConfirmed(
      surface: ExitSurface.lobby,
      source: ExitSource.appBar,
    );

    expect(ExitIntent.intentional, 'intentional');
    expect(ExitIntent.unintentional, 'unintentional');
    expect(ExitIntent.blocked, 'blocked');
  });
}
