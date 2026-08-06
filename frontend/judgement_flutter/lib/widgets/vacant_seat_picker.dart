/// Dialog to pick which vacant seat to reclaim when identity is ambiguous.
library;

import 'package:flutter/material.dart';

import '../models/protocol.dart';

/// Returns chosen vacant `player_id`, or `null` for “new player / first vacant”.
Future<String?> showVacantSeatPicker(
  BuildContext context, {
  required List<SeatView> vacantSeats,
}) async {
  if (vacantSeats.isEmpty) return null;
  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Which seat are you reclaiming?'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pick your previous seat so your cards and scores stay with you.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            for (final seat in vacantSeats)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  child: Text('${seat.seat + 1}'),
                ),
                title: Text(seat.nickname),
                subtitle: Text('Seat ${seat.seat + 1}'),
                onTap: () => Navigator.of(context).pop(seat.playerId),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text("I'm a new player"),
        ),
      ],
    ),
  );
}
