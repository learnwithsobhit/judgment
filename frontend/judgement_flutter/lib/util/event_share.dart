import '../models/protocol.dart';

/// WhatsApp / share blurb for a scheduled event.
///
/// Uses the current web origin (Flutter web port) so invite links match the
/// running app, and formats [startsAt] in the device local zone (same zone the
/// host used when picking the time).
String eventShareText(GameEventPublicView event, {String? webOrigin}) {
  final origin = webOrigin ?? Uri.base.origin;
  final when = formatEventWhenLocal(event.startsAt);
  return 'Judgement on $when (${event.timezone})\n'
      '${event.title}\n'
      'RSVP (up to ${event.maxPlayers} players, 5 waitlist): $origin/e/${event.slug}\n'
      'Add to calendar from that page for a reminder.';
}

String formatEventWhenLocal(DateTime startsAt) {
  final local = startsAt.toLocal();
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final wd = weekdays[local.weekday - 1];
  final mon = months[local.month - 1];
  final day = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$wd $day $mon ${local.year} $hh:$mm';
}
