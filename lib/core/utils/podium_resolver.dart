import '../../models/match.dart';

/// Final placement for a completed knockout bracket, whatever its shape
/// (2/3/4 teams — see bracket_resolver.dart). [semifinalists] is the teams
/// who reached the knockout stage but never the Final — 2 of them for the
/// 4-team shape, 1 for the 3-team shape (Seed 1 had a bye), none for the
/// 2-team shape (just a Final, nobody else to show).
class Podium {
  final TeamRef champion;
  final TeamRef runnerUp;
  final List<TeamRef> semifinalists;

  Podium({required this.champion, required this.runnerUp, required this.semifinalists});
}

/// Derives final placement from whichever knockout bracket shape is
/// actually present (see bracket_resolver.dart's 2/3/4-team generators) —
/// 1st/2nd always come from the Final (KOF); who else counts as a
/// "semifinalist" (shown as 3rd place) depends on the shape:
///   - 4-team (KO1/KO2/KO3/KOF all present): semifinalists = KO3 loser +
///     KO2 loser (the two teams who never reached the Final) — unchanged
///     from the original fixed shape.
///   - 3-team (KO1 + KOF only, no KO2/KO3): semifinalists = [KO1 loser]
///     (the one team eliminated in the Semifinal; Seed 1 had a bye).
///   - 2-team (KOF only): semifinalists = [] — there's no 3rd place to
///     show when only 2 teams qualified at all.
/// Returns null until every match that actually exists in the shape has a
/// genuine (non-tied) result — same reasoning as resolveDependentSlots in
/// bracket_resolver.dart: a tied score can't legitimately happen in a
/// completed badminton game, so treating one as "not team A, so team B
/// must have won" would silently show the wrong podium instead of the
/// honest "not decided yet" state.
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
  final ko1 = byCode('KO1');
  bool decided(Match? m) => m != null && m.result != null && m.result != MatchResult.tie;

  TeamRef winnerOf(Match m) => m.result == MatchResult.teamA ? m.teamA : m.teamB;
  TeamRef loserOf(Match m) => m.result == MatchResult.teamA ? m.teamB : m.teamA;

  if (!decided(koF)) return null;

  final List<TeamRef> semifinalists;
  if (ko2 != null && ko3 != null) {
    // 4-team shape.
    if (!decided(ko3) || !decided(ko2)) return null;
    semifinalists = [loserOf(ko3), loserOf(ko2)];
  } else if (ko1 != null) {
    // 3-team shape — Seed 1 had a bye, so only KO1's loser is a "3rd place".
    if (!decided(ko1)) return null;
    semifinalists = [loserOf(ko1)];
  } else {
    // 2-team shape — nobody else to show.
    semifinalists = const [];
  }

  return Podium(
    champion: winnerOf(koF!),
    runnerUp: loserOf(koF),
    semifinalists: semifinalists,
  );
}
