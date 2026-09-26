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
/// Returns null until KOF, KO3 and KO2 all have a genuine (non-tied) result
/// — same reasoning as resolveDependentSlots in bracket_resolver.dart: a
/// tied score can't legitimately happen in a completed badminton game, so
/// treating one as "not team A, so team B must have won" would silently
/// show the wrong podium instead of the honest "not decided yet" state.
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
  bool decided(Match? m) => m != null && m.result != null && m.result != MatchResult.tie;
  if (!decided(koF) || !decided(ko3) || !decided(ko2)) {
    return null;
  }

  TeamRef winnerOf(Match m) => m.result == MatchResult.teamA ? m.teamA : m.teamB;
  TeamRef loserOf(Match m) => m.result == MatchResult.teamA ? m.teamB : m.teamA;

  return Podium(
    champion: winnerOf(koF!),
    runnerUp: loserOf(koF),
    semifinalists: [loserOf(ko3!), loserOf(ko2!)],
  );
}
