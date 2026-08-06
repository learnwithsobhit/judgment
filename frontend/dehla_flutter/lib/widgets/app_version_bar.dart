import 'package:flutter/material.dart';

/// Soft version line (full update polling can ride shell later).
class AppVersionBar extends StatelessWidget {
  const AppVersionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    const version = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
    const buildId = String.fromEnvironment('APP_BUILD_ID', defaultValue: 'dev');
    return Text(
      'Version $version ($buildId)',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
    );
  }
}
