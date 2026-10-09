import 'innings_replay.dart';

/// Which side won, as the match doc's `result` enum maps them
/// (`MatchResult.teamA` / `teamB` / `tie`), plus no-result.
enum CricketWinner { teamA, teamB, tie, noResult }

class CricketMatchResult {
  final CricketWinner winner;

  /// e.g. "Team B won by 3 wickets (7 balls left)".
  final String text;

  const CricketMatchResult(this.winner, this.text);
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// Result of a two-innings match once the chase has ended; null while the
/// second innings is still going (or the first hasn't finished).
///
/// [firstBattingSide] says which team ('A'/'B') batted first.
CricketMatchResult? computeMatchResult({
  required InningsResult first,
  required InningsResult second,
  required String firstBattingSide,
  required String teamAName,
  required String teamBName,
}) {
  if (!first.isEnded || !second.isEnded) return null;
  final firstIsA = firstBattingSide == 'A';
  final firstName = firstIsA ? teamAName : teamBName;
  final secondName = firstIsA ? teamBName : teamAName;
  final firstWinner = firstIsA ? CricketWinner.teamA : CricketWinner.teamB;
  final secondWinner = firstIsA ? CricketWinner.teamB : CricketWinner.teamA;

  if (second.runs > first.runs) {
    final wicketsLeft = second.maxWickets - second.wickets;
    final ballsLeft = second.ballsLeft;
    final tail = ballsLeft > 0 ? ' (${_plural(ballsLeft, 'ball')} left)' : '';
    return CricketMatchResult(
        secondWinner, '$secondName won by ${_plural(wicketsLeft, 'wicket')}$tail');
  }
  if (second.runs < first.runs) {
    return CricketMatchResult(
        firstWinner, '$firstName won by ${_plural(first.runs - second.runs, 'run')}');
  }
  return const CricketMatchResult(CricketWinner.tie, 'Match tied');
}

/// Live one-liner for the chasing side: "Team B need 23 runs in 18 balls".
/// Null when the innings has no target or has ended.
String? chaseText(InningsResult chase, String chasingTeamName) {
  final needed = chase.runsNeeded;
  if (needed == null || chase.isEnded) return null;
  return '$chasingTeamName need ${_plural(needed, 'run')} in ${_plural(chase.ballsLeft, 'ball')}';
}
