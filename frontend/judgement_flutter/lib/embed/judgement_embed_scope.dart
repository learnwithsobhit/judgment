import 'package:flutter/material.dart';

import 'judgement_embed_binding.dart';

/// Embed / standalone session configuration for Judgement UI.
class JudgementEmbedScope extends InheritedWidget {
  final bool embedded;
  final VoidCallback? onExitToShell;
  final String sharePathPrefix;
  final String? prefillNickname;
  final String? prefillAvatarId;

  const JudgementEmbedScope({
    super.key,
    required this.embedded,
    this.onExitToShell,
    this.sharePathPrefix = '',
    this.prefillNickname,
    this.prefillAvatarId,
    required super.child,
  });

  static JudgementEmbedScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<JudgementEmbedScope>();
  }

  static void exitToHome(BuildContext context) {
    JudgementEmbedBinding.exitToHome(context);
  }

  static String backHomeLabel(BuildContext context) {
    return JudgementEmbedBinding.backHomeLabel();
  }

  @override
  bool updateShouldNotify(JudgementEmbedScope oldWidget) {
    return embedded != oldWidget.embedded ||
        sharePathPrefix != oldWidget.sharePathPrefix ||
        prefillNickname != oldWidget.prefillNickname ||
        prefillAvatarId != oldWidget.prefillAvatarId;
  }
}

/// Package name for [Image.asset] / [AssetImage] when Judgement runs as a
/// dependency of the Table Games shell (also works as standalone app).
const kJudgementAssetPackage = 'judgement_flutter';
