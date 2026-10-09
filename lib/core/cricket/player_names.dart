/// Result of reading a pasted block of player names.
class ParsedNames {
  final List<String> names;
  final List<String> duplicates;

  const ParsedNames(this.names, this.duplicates);
}

final _listMarker = RegExp(r'^\s*(?:\d+\s*[.)\-:]|[-•*·])\s*');

/// Turns text pasted from WhatsApp / a sheet into clean player names: one
/// per line (commas also split, for a name list pasted on one line), leading
/// "1." / "-" / "•" markers removed, extra spaces collapsed, blanks dropped.
/// Names that repeat within the paste or already exist in [existing]
/// (case-insensitive) land in [ParsedNames.duplicates] instead of [names].
ParsedNames parsePlayerNames(String text, {Iterable<String> existing = const []}) {
  final seen = {for (final e in existing) e.trim().toLowerCase()};
  final names = <String>[];
  final duplicates = <String>[];
  for (final line in text.split(RegExp(r'[\n\r,;]+'))) {
    final cleaned = line.replaceFirst(_listMarker, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) continue;
    if (seen.add(cleaned.toLowerCase())) {
      names.add(cleaned);
    } else {
      duplicates.add(cleaned);
    }
  }
  return ParsedNames(names, duplicates);
}
