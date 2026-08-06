import 'package:flutter/material.dart';

import 'app/app.dart';
import 'embed/judgement_embed_binding.dart';
import 'embed/judgement_embed_scope.dart';
import 'screens/landing_screen.dart';
import 'util/app_update.dart';

/// Embeddable Judgement entry for the Table Games shell (no nested MaterialApp).
///
/// Uses a nested [Navigator] so lobby/table pushes stay inside this module;
/// exiting to the shell disposes the whole stack.
class JudgementModule extends StatefulWidget {
  final VoidCallback onExitToShell;
  final String? initialJoinCode;
  final bool invalidJoinLink;
  final String? prefillNickname;
  final String? prefillAvatarId;
  final String sharePathPrefix;

  const JudgementModule({
    super.key,
    required this.onExitToShell,
    this.initialJoinCode,
    this.invalidJoinLink = false,
    this.prefillNickname,
    this.prefillAvatarId,
    this.sharePathPrefix = '/j',
  });

  @override
  State<JudgementModule> createState() => _JudgementModuleState();
}

class _JudgementModuleState extends State<JudgementModule> {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _activate();
  }

  @override
  void didUpdateWidget(covariant JudgementModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activate();
  }

  void _activate() {
    JudgementEmbedBinding.activate(
      embedded: true,
      onExitToShell: _exit,
      sharePathPrefix: widget.sharePathPrefix,
      prefillNickname: widget.prefillNickname,
      prefillAvatarId: widget.prefillAvatarId,
    );
  }

  void _exit() {
    // Drop lobby/table routes inside this module, then leave to shell.
    final nav = _navKey.currentState;
    if (nav != null) {
      nav.popUntil((route) => route.isFirst);
    }
    widget.onExitToShell();
  }

  @override
  void dispose() {
    JudgementEmbedBinding.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: feltGreen,
      brightness: Brightness.dark,
    );

    return JudgementEmbedScope(
      embedded: true,
      onExitToShell: _exit,
      sharePathPrefix: widget.sharePathPrefix,
      prefillNickname: widget.prefillNickname,
      prefillAvatarId: widget.prefillAvatarId,
      child: Theme(
        data: ThemeData(
          colorScheme: scheme,
          useMaterial3: true,
          scaffoldBackgroundColor: feltGreenDark,
          snackBarTheme:
              const SnackBarThemeData(behavior: SnackBarBehavior.floating),
          cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
        ),
        child: AppUpdateLifecycle(
          child: Navigator(
            key: _navKey,
            onGenerateRoute: (settings) {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => LandingScreen(
                  initialJoinCode: widget.initialJoinCode,
                  invalidJoinLink: widget.invalidJoinLink,
                  embedded: true,
                  onExitToShell: _exit,
                  prefillNickname: widget.prefillNickname,
                  prefillAvatarId: widget.prefillAvatarId,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
