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
/// 1st/2nd normally come straight from the Final (KOF), or from a best-of-3
/// series (KOF1/KOF2[/KOF3] — see bracket_resolver.dart's _finalGames and
/// generateFinalGame3) when the admin picked that format instead. Who counts
/// as a "semifinalist" (shown as 3rd place) depends on the qualifier shape,
/// independently of the Final format:
///   - 4-team (KO1/KO2/KO3 all present): semifinalists = KO3 loser + KO2
///     loser (the two teams who never reached the Final) — unchanged from
///     the original fixed shape.
///   - 3-team (KO1 present, no KO2/KO3): semifinalists = [KO1 loser] (the
///     one team eliminated in the Semifinal; Seed 1 had a bye).
///   - 2-team (neither KO1 nor KO2/KO3): semifinalists = [] — there's no
///     3rd place to show when only 2 teams qualified at all.
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
  final kof1 = byCode('KOF1');
  final kof2 = byCode('KOF2');
  final kof3 = byCode('KOF3');
  final ko3 = byCode('KO3');
  final ko2 = byCode('KO2');
  final ko1 = byCode('KO1');
  bool decided(Match? m) => m != null && m.hasFinalResult && m.result != MatchResult.tie;

  TeamRef winnerOf(Match m) => m.result == MatchResult.teamA ? m.teamA : m.teamB;
  TeamRef loserOf(Match m) => m.result == MatchResult.teamA ? m.teamB : m.teamA;

  TeamRef champion;
  TeamRef runnerUp;
  if (kof1 != null) {
    // Best-of-3 Final: whoever wins 2 of the (up to 3) games is champion.
    // teamA/teamB are identical across all games in the series (shared
    // teamASource/teamBSource at generation time), so either game's refs
    // name the two sides consistently.
    if (!decided(kof1) || !decided(kof2)) return null;
    final aWins = [kof1, kof2!].where((m) => m.result == MatchResult.teamA).length;
    final bWins = [kof1, kof2].where((m) => m.result == MatchResult.teamB).length;
    if (aWins == 2) {
      champion = kof1.teamA;
      runnerUp = kof1.teamB;
    } else if (bWins == 2) {
      champion = kof1.teamB;
      runnerUp = kof1.teamA;
    } else {
      // Split 1-1 — needs the decider (Game 3).
      if (!decided(kof3)) return null;
      champion = winnerOf(kof3!);
      runnerUp = loserOf(kof3);
    }
  } else {
    // Single Final.
    if (!decided(koF)) return null;
    champion = winnerOf(koF!);
    runnerUp = loserOf(koF);
  }

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
    champion: champion,
    runnerUp: runnerUp,
    semifinalists: semifinalists,
  );
}
