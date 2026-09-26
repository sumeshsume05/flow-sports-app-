/// Short "how long ago" label for a recent timestamp — used where showing
/// the exact clock time (as `DateFormat.Hm()` does elsewhere) is less useful
/// than freshness, e.g. a commentary preview on the match list.
String relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
