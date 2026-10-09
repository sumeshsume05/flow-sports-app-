import '../../models/match.dart';

/// One match doc's field changes needed after a team rename. [fields] uses
/// Firestore dotted-path keys (`teamA.name`) so only the name inside the
/// `teamA`/`teamB` map is touched, never the sibling `teamId`.
class MatchNameUpdate {
  final String matchId;
  final Map<String, dynamic> fields;

  const MatchNameUpdate(this.matchId, this.fields);
}

/// Match docs store a *copy* of each team's name (`teamA`/`teamB` are
/// `{teamId, name}`), plus tie-breaker `label`s that embed both names, so
/// renaming a team in Admin > Teams leaves every already-generated match
/// stale. Given the matches that reference [teamId], returns the writes that
/// bring them in line with [newName]. Matches whose stored name already
/// equals [newName] (and whose label is already current) are skipped, so the
/// result is empty — no writes — for a no-op rename.
///
/// Stale names are located by team id, not by matching the old name text, so
/// a name that happens to be a substring of another team's name can't cause
/// a wrong replacement.
List<MatchNameUpdate> matchesNeedingNameUpdate(
  List<Match> matches, {
  required String teamId,
  required String newName,
}) {
  final updates = <MatchNameUpdate>[];
  final seen = <String>{};
  for (final m in matches) {
    if (!seen.add(m.id)) continue; // same match returned by both side queries
    final isA = m.teamA.teamId == teamId;
    final isB = m.teamB.teamId == teamId;
    if (!isA && !isB) continue;

    final fields = <String, dynamic>{};
    if (isA && m.teamA.name != newName) fields['teamA.name'] = newName;
    if (isB && m.teamB.name != newName) fields['teamB.name'] = newName;

    // Tie-breaker labels end in "<A name> vs <B name>" (see
    // round_robin.generateTiebreakerMatches); rebuild just that tail.
    if (m.stage == MatchStage.tiebreaker) {
      final oldTail = '${m.teamA.name} vs ${m.teamB.name}';
      if (m.label.endsWith(oldTail)) {
        final newA = isA ? newName : m.teamA.name;
        final newB = isB ? newName : m.teamB.name;
        final newLabel =
            '${m.label.substring(0, m.label.length - oldTail.length)}$newA vs $newB';
        if (newLabel != m.label) fields['label'] = newLabel;
      }
    }

    if (fields.isNotEmpty) updates.add(MatchNameUpdate(m.id, fields));
  }
  return updates;
}
