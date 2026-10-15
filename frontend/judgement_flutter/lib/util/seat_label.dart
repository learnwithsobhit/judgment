/// Table label: first word, plus the next word's initial.
/// `Ankit Sunil Chaturvedi` becomes `Ankit S`. A single word stays as typed.
String seatLabel(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Player';
  final first = parts.first;
  if (parts.length == 1) return _clip(first, 16);
  final letter = String.fromCharCode(parts[1].runes.first).toUpperCase();
  return _clip('$first $letter', 16);
}

String _clip(String value, int max) {
  final runes = value.runes;
  if (runes.length <= max) return value;
  return String.fromCharCodes(runes.take(max));
}
