import '../../models/match.dart';
import '../../models/standing_row.dart';

/// Generates the 4-match "page playoff" knockout bracket from the top-4 league
/// standings, mirroring the source spreadsheet exactly:
///   KO1: Seed 1 vs Seed 2 -> winner advances DIRECTLY to the Final
///   KO2: Seed 3 vs Seed 4 -> winner advances to KO3
///   KO3: loser of KO1 vs winner of KO2 -> winner advances to the Final
///   KOF: winner of KO1 vs winner of KO3
///
/// Call this once the league stage is complete for a category, after the admin
/// has confirmed seed order (see standings_calculator.topFourHasAmbiguousTie).
///
/// This exact 4-team shape is specific to this sport's rules. A future sport
/// with a different bracket size/format should get its own generator
/// function alongside this one rather than trying to parametrize this one —
/// keeps each sport's rules contained and this function simple. See also
/// podium_resolver.dart, which derives final placement from this same shape.
List<Match> generateKnockoutMatches({
  required List<StandingRow> top4Seeds, // exactly 4, in seed order (1..4)
  required String sport,
  required String category,
  required String season,
}) {
  assert(top4Seeds.length == 4);
  final seed1 = top4Seeds[0];
  final seed2 = top4Seeds[1];
  final seed3 = top4Seeds[2];
  final seed4 = top4Seeds[3];

  final ko1 = Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: MatchStage.knockout,
    matchNumber: 1,
    label: 'Semifinal 1',
    matchCode: 'KO1',
    teamA: TeamRef(teamId: seed1.teamId, name: seed1.teamName),
    teamB: TeamRef(teamId: seed2.teamId, name: seed2.teamName),
    teamASource: const MatchSource.seed(1),
    teamBSource: const MatchSource.seed(2),
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );

  final ko2 = Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: MatchStage.knockout,
    matchNumber: 2,
    label: 'Semifinal 2',
    matchCode: 'KO2',
    teamA: TeamRef(teamId: seed3.teamId, name: seed3.teamName),
    teamB: TeamRef(teamId: seed4.teamId, name: seed4.teamName),
    teamASource: const MatchSource.seed(3),
    teamBSource: const MatchSource.seed(4),
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );

  final ko3 = Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: MatchStage.knockout,
    matchNumber: 3,
    // Winner qualifies for the Final (the 2nd finalist spot); loser finishes
    // 3rd — not a traditional 3rd-place decider, since the winner keeps
    // playing, so it's named for what it actually determines.
    label: 'Final Qualifier',
    matchCode: 'KO3',
    teamA: TeamRef.tbd,
    teamB: TeamRef.tbd,
    teamASource: const MatchSource.loserOf('KO1'),
    teamBSource: const MatchSource.winnerOf('KO2'),
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );

  final koFinal = Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: MatchStage.knockout,
    matchNumber: 4,
    label: 'Final',
    matchCode: 'KOF',
    teamA: TeamRef.tbd,
    teamB: TeamRef.tbd,
    teamASource: const MatchSource.winnerOf('KO1'),
    teamBSource: const MatchSource.winnerOf('KO3'),
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );

  return [ko1, ko2, ko3, koFinal];
}

/// Generates a 2-team bracket — just the Final, both teams already known
/// (no TBD slots, nothing for [resolveDependentSlots] to do here). For when
/// the admin picks a 2-team qualifier count instead of the default 4 — see
/// [generateKnockoutMatches]'s doc comment on why each shape gets its own
/// function rather than one parametrized generator.
List<Match> generateKnockoutMatchesForTwo({
  required List<StandingRow> twoSeeds, // exactly 2, in seed order (1..2)
  required String sport,
  required String category,
  required String season,
}) {
  assert(twoSeeds.length == 2);
  final seed1 = twoSeeds[0];
  final seed2 = twoSeeds[1];

  final koFinal = Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: MatchStage.knockout,
    matchNumber: 1,
    label: 'Final',
    matchCode: 'KOF',
    teamA: TeamRef(teamId: seed1.teamId, name: seed1.teamName),
    teamB: TeamRef(teamId: seed2.teamId, name: seed2.teamName),
    teamASource: const MatchSource.seed(1),
    teamBSource: const MatchSource.seed(2),
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );

  return [koFinal];
}

/// Generates a 3-team bracket: Seed 1 gets a bye straight to the Final;
/// Seed 2 vs Seed 3 play a Semifinal for the other Final spot. For when the
/// admin picks a 3-team qualifier count instead of the default 4 — see
/// [generateKnockoutMatches]'s doc comment on why each shape gets its own
/// function rather than one parametrized generator. Reuses
/// [resolveDependentSlots] unchanged for the Final's TBD slot — that
/// function is already generic over match codes, not hardcoded to KO1-KOF.
List<Match> generateKnockoutMatchesForThree({
  required List<StandingRow> threeSeeds, // exactly 3, in seed order (1..3)
  required String sport,
  required String category,
  required String season,
}) {
  assert(threeSeeds.length == 3);
  final seed1 = threeSeeds[0];
  final seed2 = threeSeeds[1];
  final seed3 = threeSeeds[2];

  final semifinal = Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: MatchStage.knockout,
    matchNumber: 1,
    label: 'Semifinal',
    matchCode: 'KO1',
    teamA: TeamRef(teamId: seed2.teamId, name: seed2.teamName),
    teamB: TeamRef(teamId: seed3.teamId, name: seed3.teamName),
    teamASource: const MatchSource.seed(2),
    teamBSource: const MatchSource.seed(3),
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );

  final koFinal = Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: MatchStage.knockout,
    matchNumber: 2,
    label: 'Final',
    matchCode: 'KOF',
    // Seed 1 has a bye — known directly, not a TBD slot.
    teamA: TeamRef(teamId: seed1.teamId, name: seed1.teamName),
    teamB: TeamRef.tbd,
    teamASource: const MatchSource.seed(1),
    teamBSource: const MatchSource.winnerOf('KO1'),
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );

  return [semifinal, koFinal];
}

/// Given a just-completed match and the other knockout matches for its
/// category, returns updated copies of any matches whose TBD slot should now
/// resolve to a winner/loser. Caller is expected to write [completed] and the
/// returned list in a single Firestore batch so two admins editing at once
/// can't race into a partial update.
///
/// Reported bug: [completed.result] being [MatchResult.tie] used to fall
/// through a `== MatchResult.teamA ? teamA : teamB` ternary as if it meant
/// "not team A, so team B" — silently advancing team B on a tied score
/// instead of refusing to resolve anything. The caller (admin's score-entry
/// screen) is expected to reject a tied result for a knockout match before
/// it ever reaches here — badminton games can't legitimately finish level —
/// but this throws instead of guessing if one somehow does, since a wrong
/// silent guess corrupts the bracket for every later round.
List<Match> resolveDependentSlots({
  required Match completed,
  required List<Match> otherKnockoutMatches,
}) {
  if (completed.result == null) return const [];
  if (completed.result == MatchResult.tie) {
    throw StateError(
        'A knockout match cannot resolve dependent slots on a tied result (${completed.matchCode}).');
  }

  final winner = completed.result == MatchResult.teamA ? completed.teamA : completed.teamB;
  final loser = completed.result == MatchResult.teamA ? completed.teamB : completed.teamA;

  final updated = <Match>[];
  for (final m in otherKnockoutMatches) {
    var teamA = m.teamA;
    var teamB = m.teamB;
    var changed = false;

    if (m.teamASource?.type == 'winner' && m.teamASource?.matchCode == completed.matchCode) {
      teamA = winner;
      changed = true;
    } else if (m.teamASource?.type == 'loser' && m.teamASource?.matchCode == completed.matchCode) {
      teamA = loser;
      changed = true;
    }

    if (m.teamBSource?.type == 'winner' && m.teamBSource?.matchCode == completed.matchCode) {
      teamB = winner;
      changed = true;
    } else if (m.teamBSource?.type == 'loser' && m.teamBSource?.matchCode == completed.matchCode) {
      teamB = loser;
      changed = true;
    }

    if (changed) {
      updated.add(
        Match(
          id: m.id,
          sport: m.sport,
          category: m.category,
          season: m.season,
          stage: m.stage,
          matchNumber: m.matchNumber,
          label: m.label,
          matchCode: m.matchCode,
          section: m.section,
          teamA: teamA,
          teamB: teamB,
          teamASource: m.teamASource,
          teamBSource: m.teamBSource,
          scoreA: m.scoreA,
          scoreB: m.scoreB,
          result: m.result,
          status: m.status,
          scheduledAt: m.scheduledAt,
          venue: m.venue,
          court: m.court,
          notes: m.notes,
          notifyTopic: m.notifyTopic,
          tiebreakerRound: m.tiebreakerRound,
        ),
      );
    }
  }
  return updated;
}
