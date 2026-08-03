import 'package:flutter/material.dart';

import '../util/app_update.dart';

/// Shows running (and latest, when mismatched) build on Create/Join / lobby.
class AppVersionBar extends StatelessWidget {
  const AppVersionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return ListenableBuilder(
      listenable: AppUpdateController.instance,
      builder: (context, _) {
        final c = AppUpdateController.instance;
        if (!c.updateAvailable) {
          return Text(
            'Version ${c.runningLabel}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'You: ${c.runningLabel}\nLatest: ${c.latestLabel}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => c.switchToLatest(),
              icon: const Icon(Icons.system_update_alt, size: 18),
              label: const Text('Switch to latest version'),
            ),
          ],
        );
      },
    );
  }
}
