import 'package:flutter/material.dart';

/// Process-wide embed binding (share URLs + exit) for call sites without context.
///
/// [JudgementEmbedScope] mirrors these for widget lookups; [JudgementModule]
/// and standalone [JudgementApp] activate/clear this.
abstract final class JudgementEmbedBinding {
  static bool embedded = false;
  static VoidCallback? onExitToShell;
  static String sharePathPrefix = '';
  static String? prefillNickname;
  static String? prefillAvatarId;

  static void activate({
    required bool embedded,
    VoidCallback? onExitToShell,
    String sharePathPrefix = '',
    String? prefillNickname,
    String? prefillAvatarId,
  }) {
    JudgementEmbedBinding.embedded = embedded;
    JudgementEmbedBinding.onExitToShell = onExitToShell;
    JudgementEmbedBinding.sharePathPrefix = sharePathPrefix;
    JudgementEmbedBinding.prefillNickname = prefillNickname;
    JudgementEmbedBinding.prefillAvatarId = prefillAvatarId;
  }

  static void clear() {
    activate(embedded: false);
  }

  static void exitToHome(BuildContext context) {
    if (embedded && onExitToShell != null) {
      onExitToShell!();
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static String backHomeLabel() =>
      embedded ? 'Back to Table Games' : 'Back to home';
}
