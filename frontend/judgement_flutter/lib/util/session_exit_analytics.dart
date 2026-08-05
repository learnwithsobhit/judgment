/// Client-side exit / disconnect telemetry (localStorage on web).
///
/// Distinguishes intentional leaves from blocked accidents and network drops.
library;

import 'share_analytics.dart';

/// Surfaces where exit guards apply.
abstract final class ExitSurface {
  static const table = 'table';
  static const lobby = 'lobby';
}

/// How the user triggered the leave flow.
abstract final class ExitSource {
  static const back = 'back';
  static const leaveButton = 'leave_button';
  static const appBar = 'app_bar';
  static const unload = 'unload';
  static const network = 'network';
  static const hostEnd = 'host_end';
}

/// Intent classification for dashboards.
abstract final class ExitIntent {
  static const intentional = 'intentional';
  static const unintentional = 'unintentional';
  static const blocked = 'blocked';
}

void recordExitEvent(
  String name, {
  required String intent,
  required String surface,
  String? source,
  Map<String, String>? extra,
}) {
  recordShareEvent(name, {
    'intent': intent,
    'surface': surface,
    if (source != null) 'source': source,
    ...?extra,
  });
}

void recordExitDialogShown({
  required String surface,
  required String source,
}) {
  recordExitEvent(
    'exit_dialog_shown',
    intent: ExitIntent.blocked,
    surface: surface,
    source: source,
  );
}

void recordExitStay({
  required String surface,
  required String source,
}) {
  recordExitEvent(
    'exit_stay',
    intent: ExitIntent.blocked,
    surface: surface,
    source: source,
  );
}

void recordExitLeaveConfirmed({
  required String surface,
  required String source,
}) {
  recordExitEvent(
    'exit_leave_confirmed',
    intent: ExitIntent.intentional,
    surface: surface,
    source: source,
  );
}

void recordExitBeforeUnload() {
  recordExitEvent(
    'exit_beforeunload',
    intent: ExitIntent.unintentional,
    surface: ExitSurface.table,
    source: ExitSource.unload,
  );
}

void recordExitWsDisconnect({required bool willReconnect}) {
  recordExitEvent(
    'exit_ws_disconnect',
    intent: ExitIntent.unintentional,
    surface: ExitSurface.table,
    source: ExitSource.network,
    extra: {'will_reconnect': willReconnect ? '1' : '0'},
  );
}

void recordExitEndGameConfirmed() {
  recordExitEvent(
    'exit_end_game_confirmed',
    intent: ExitIntent.intentional,
    surface: ExitSurface.table,
    source: ExitSource.hostEnd,
  );
}
