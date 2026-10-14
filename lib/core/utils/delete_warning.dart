import '../../models/match.dart';
import '../constants.dart';

/// What deleting one match takes with it, one plain sentence each, so the
/// admin isn't surprised: a live match disappears from viewers, a played
/// league match changes the table, a knockout match leaves the bracket
/// incomplete, and the scoring record goes too.
List<String> deleteMatchConsequences(Match m) {
  final lines = <String>[];
  if (m.status == MatchStatus.live) {
    lines.add('It is live right now — viewers are watching it.');
  }
  if (m.hasFinalResult) {
    final result = m.sport == Sport.cricket && m.resultText != null
        ? m.resultText!
        : '${m.teamA.name ?? 'TBD'} ${m.scoreA ?? 0} – ${m.scoreB ?? 0} ${m.teamB.name ?? 'TBD'}';
    lines.add('Its saved result is lost: $result.');
    if (m.stage == MatchStage.league || m.stage == MatchStage.tiebreaker) {
      lines.add('The standings change, because this result no longer counts.');
    }
  }
  if (m.stage == MatchStage.knockout) {
    lines.add('It is part of the knockout bracket, so the bracket is left incomplete. Teams it already '
        'moved into later rounds are not removed — reset those matches too if needed, or use '
        'Generate Bracket to start the knockout over.');
  }
  if (m.status != MatchStatus.upcoming || m.innings.isNotEmpty) {
    lines.add(m.sport == Sport.cricket
        ? 'Its ball-by-ball scoring, edit history and commentary are deleted too.'
        : 'Its point-by-point log and commentary are deleted too.');
  }
  return lines;
}
