import 'package:flutter/material.dart';

Future<bool> showLeaveLobbyDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Leave lobby?'),
      content: const Text(
        'You will leave this room. You can rejoin with the room code '
        'if a seat is still open.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stay'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B2E2E)),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  return result == true;
}

Future<bool> showLeaveTableDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Leave the table?'),
      content: const Text(
        'Leaving vacates your seat. Others will pause until someone '
        'rejoins or the host ends or restarts the game.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stay'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B2E2E)),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  return result == true;
}

/// Returns `true` if the host confirmed ending the game for everyone.
Future<bool> showEndGameDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('End game for everyone?'),
      content: const Text(
        'This ends the game for all players at the table. '
        'Remaining players return to the lobby. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style:
              FilledButton.styleFrom(backgroundColor: const Color(0xFF8B2E2E)),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('End game'),
        ),
      ],
    ),
  );
  return result == true;
}
