import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../util/app_update.dart';

/// Shows running build; on landing can auto-reload and block entry when stale.
class AppVersionBar extends StatefulWidget {
  /// When true (landing), auto-reload shortly after a newer deploy is detected.
  final bool autoReload;

  /// When true, show a blocking “update required” panel instead of a soft button.
  final bool blockWhenStale;

  const AppVersionBar({
    super.key,
    this.autoReload = false,
    this.blockWhenStale = false,
  });

  @override
  State<AppVersionBar> createState() => _AppVersionBarState();
}

class _AppVersionBarState extends State<AppVersionBar> {
  var _autoReloadScheduled = false;

  @override
  void initState() {
    super.initState();
    AppUpdateController.instance.addListener(_onUpdate);
  }

  @override
  void dispose() {
    AppUpdateController.instance.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    _maybeAutoReload();
  }

  void _maybeAutoReload() {
    if (!widget.autoReload || !kIsWeb) return;
    final c = AppUpdateController.instance;
    if (!c.updateAvailable || _autoReloadScheduled) return;
    _autoReloadScheduled = true;
    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (AppUpdateController.instance.updateAvailable) {
        unawaited(AppUpdateController.instance.switchToLatest());
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final c = AppUpdateController.instance;

    if (c.awaitingInitialCheck) {
      return Text(
        'Checking for updates…',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      );
    }

    if (!c.updateAvailable) {
      return Text(
        'Version ${c.runningLabel}',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      );
    }

    if (widget.blockWhenStale || widget.autoReload) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'New version available',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Updating to latest…\n${c.latestLabel ?? ''}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => c.switchToLatest(),
                  child: const Text('Update now'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A newer version is available\nYou: ${c.runningLabel}\nLatest: ${c.latestLabel}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.tertiary,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => c.switchToLatest(),
          icon: const Icon(Icons.system_update_alt, size: 18),
          label: const Text('Refresh to update'),
        ),
      ],
    );
  }
}
