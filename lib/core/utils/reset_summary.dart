import '../../models/match.dart';
import '../constants.dart';

/// What a sport reset would delete, per category, so the admin sees the
/// size of it before confirming.
class ResetSummary {
  final List<ResetLine> lines;

  const ResetSummary(this.lines);

  int get total => lines.fold(0, (s, l) => s + l.total);
  int get played => lines.fold(0, (s, l) => s + l.played);
  bool get isEmpty => total == 0;
}

class ResetLine {
  final String category;
  final int total;

  /// Matches with a saved result (completed).
  final int played;
  final int live;

  const ResetLine(this.category, this.total, this.played, this.live);

  /// "Boys: 28 matches — 20 with results, 1 live now"
  String get text {
    final parts = <String>[
      if (played > 0) '$played with results',
      if (live > 0) '$live live now',
    ];
    return '${categoryLabel(category)}: $total ${total == 1 ? 'match' : 'matches'}'
        '${parts.isEmpty ? '' : ' — ${parts.join(', ')}'}';
  }
}

ResetSummary summarizeReset(List<Match> matches) {
  final byCategory = <String, List<Match>>{};
  for (final m in matches) {
    byCategory.putIfAbsent(m.category, () => []).add(m);
  }
  // Boys, Girls, then anything else (e.g. the Test Lab's category).
  final order = [...Category.all, ...byCategory.keys.where((c) => !Category.all.contains(c)).toList()..sort()];
  return ResetSummary([
    for (final c in order)
      if (byCategory.containsKey(c))
        ResetLine(
          c,
          byCategory[c]!.length,
          byCategory[c]!.where((m) => m.status == MatchStatus.completed).length,
          byCategory[c]!.where((m) => m.status == MatchStatus.live).length,
        ),
  ]);
}
