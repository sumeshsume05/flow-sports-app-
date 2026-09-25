import '../../models/match.dart';

/// Final placement for a completed 4-team knockout bracket.
class Podium {
  final TeamRef champion;
  final TeamRef runnerUp;
  final List<TeamRef> semifinalists; // the two teams who never reached the Final

  Podium({required this.champion, required this.runnerUp, required this.semifinalists});
}

/// Derives final placement from the 4 fixed knockout matches — no new data
/// needed, since the "page playoff" format (see bracket_resolver.dart)
/// already determines it exactly once the Final is played:
///   1st = KOF winner, 2nd = KOF loser,
///   Semifinalists = KO3 loser + KO2 loser (the two teams who never reached
///   the Final).
/// Returns null until KOF has a result.
Podium? computePodium(List<Match> knockoutMatches) {
  Match? byCode(String code) {
    for (final m in knockoutMatches) {
      if (m.matchCode == code) return m;
    }
    return null;
  }

  final koF = byCode('KOF');
  final ko3 = byCode('KO3');
  final ko2 = byCode('KO2');
  if (koF == null || koF.result == null || ko3 == null || ko3.result == null || ko2 == null || ko2.result == null) {
    return null;
  }

  TeamRef winnerOf(Match m) => m.result == MatchResult.teamA ? m.teamA : m.teamB;
  TeamRef loserOf(Match m) => m.result == MatchResult.teamA ? m.teamB : m.teamA;

  return Podium(
    champion: winnerOf(koF),
    runnerUp: loserOf(koF),
    semifinalists: [loserOf(ko3), loserOf(ko2)],
  );
}
