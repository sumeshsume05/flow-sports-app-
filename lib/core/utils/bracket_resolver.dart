import '../../models/match.dart';
import '../../models/standing_row.dart';

/// Builds the Final — one `KOF` match normally, or two (`KOF1`/`KOF2`) when
/// [bestOfThreeFinal] is set, sharing identical team refs/sources so the
/// generic [resolveDependentSlots] resolves both in a single pass with no
/// changes needed there. A possible decider `KOF3` is never created here —
/// see [generateFinalGame3], triggered explicitly by the admin only if Games
/// 1 and 2 split 1-1.
List<Match> _finalGames({
  required TeamRef teamA,
  required TeamRef teamB,
  required MatchSource teamASource,
  required MatchSource teamBSource,
  required String sport,
  required String category,
  required String season,
  required int startMatchNumber,
  required bool bestOfThreeFinal,
}) {
  if (!bestOfThreeFinal) {
    return [
      Match(
        id: '',
        sport: sport,
        category: category,
        season: season,
        stage: MatchStage.knockout,
        matchNumber: startMatchNumber,
        label: 'Final',
        matchCode: 'KOF',
        teamA: teamA,
        teamB: teamB,
        teamASource: teamASource,
        teamBSource: teamBSource,
        status: MatchStatus.upcoming,
        notifyTopic: '${sport}_$category',
      ),
    ];
  }

  return [
    Match(
      id: '',
      sport: sport,
      category: category,
      season: season,
      stage: MatchStage.knockout,
      matchNumber: startMatchNumber,
      label: 'Final — Game 1',
      matchCode: 'KOF1',
      teamA: teamA,
      teamB: teamB,
      teamASource: teamASource,
      teamBSource: teamBSource,
      status: MatchStatus.upcoming,
      notifyTopic: '${sport}_$category',
    ),
    Match(
      id: '',
      sport: sport,
      category: category,
      season: season,
      stage: MatchStage.knockout,
      matchNumber: startMatchNumber + 1,
      label: 'Final — Game 2',
      matchCode: 'KOF2',
      teamA: teamA,
      teamB: teamB,
      teamASource: teamASource,
      teamBSource: teamBSource,
      status: MatchStatus.upcoming,
      notifyTopic: '${sport}_$category',
    ),
  ];
}

/// Generates the 3rd Final game — only needed when a best-of-3 Final (see
/// [_finalGames]) splits 1-1 after Games 1 and 2. Admin-triggered explicitly
/// (mirrors round_robin.generateTiebreakerMatches' "schedule one more match
/// on demand" pattern) rather than auto-created, since it's only sometimes
/// needed. Teams are passed in directly, not as a [MatchSource] lookup,
/// because by the time Game 3 is needed Game 1 has already completed and
/// resolved exactly who's playing — there's nothing left to resolve.
Match generateFinalGame3({
  required TeamRef teamA,
  required TeamRef teamB,
  required String sport,
  required String category,
  required String season,
  required int matchNumber,
}) {
  return Match(
    id: '',
    sport: sport,
    category: category,
    season: season,
    stage: MatchStage.knockout,
    matchNumber: matchNumber,
    label: 'Final — Game 3 (Decider)',
    matchCode: 'KOF3',
    teamA: teamA,
    teamB: teamB,
    status: MatchStatus.upcoming,
    notifyTopic: '${sport}_$category',
  );
}

/// Generates the 4-match "page playoff" knockout bracket from the top-4 league
/// standings, mirroring the source spreadsheet exactly:
///   KO1: Seed 1 vs Seed 2 -> winner advances DIRECTLY to the Final
///   KO2: Seed 3 vs Seed 4 -> winner advances to KO3
///   KO3: loser of KO1 vs winner of KO2 -> winner advances to the Final
///   KOF: winner of KO1 vs winner of KO3 (or KOF1/KOF2[/KOF3] — see
///   [_finalGames] — when the admin picked a best-of-3 Final)
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
  bool bestOfThreeFinal = false,
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

  final finalGames = _finalGames(
    teamA: TeamRef.tbd,
    teamB: TeamRef.tbd,
    teamASource: const MatchSource.winnerOf('KO1'),
    teamBSource: const MatchSource.winnerOf('KO3'),
    sport: sport,
    category: category,
    season: season,
    startMatchNumber: 4,
    bestOfThreeFinal: bestOfThreeFinal,
  );

  return [ko1, ko2, ko3, ...finalGames];
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
  bool bestOfThreeFinal = false,
}) {
  assert(twoSeeds.length == 2);
  final seed1 = twoSeeds[0];
  final seed2 = twoSeeds[1];

  return _finalGames(
    teamA: TeamRef(teamId: seed1.teamId, name: seed1.teamName),
    teamB: TeamRef(teamId: seed2.teamId, name: seed2.teamName),
    teamASource: const MatchSource.seed(1),
    teamBSource: const MatchSource.seed(2),
    sport: sport,
    category: category,
    season: season,
    startMatchNumber: 1,
    bestOfThreeFinal: bestOfThreeFinal,
  );
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
  bool bestOfThreeFinal = false,
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

  final finalGames = _finalGames(
    // Seed 1 has a bye — known directly, not a TBD slot.
    teamA: TeamRef(teamId: seed1.teamId, name: seed1.teamName),
    teamB: TeamRef.tbd,
    teamASource: const MatchSource.seed(1),
    teamBSource: const MatchSource.winnerOf('KO1'),
    sport: sport,
    category: category,
    season: season,
    startMatchNumber: 2,
    bestOfThreeFinal: bestOfThreeFinal,
  );

  return [semifinal, ...finalGames];
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


// ---- keeping the bracket consistent when a result is corrected -----------

/// Knockout matches whose team slot is fed by [code]'s winner or loser.
List<Match> dependentsOf(String code, List<Match> others) => [
      for (final m in others)
        if (m.teamASource?.matchCode == code || m.teamBSource?.matchCode == code) m,
    ];

/// A dependent that has been played or started must not have its teams
/// silently swapped underneath its result.
bool isStarted(Match m) => m.result != null || m.status != MatchStatus.upcoming;

/// Of the updates [resolveDependentSlots] produced for a corrected result,
/// those that would change which teams play in a match that has *already
/// been started or played* — saving would leave that match's result
/// attached to the wrong teams, and the podium wrong. Re-saving the same
/// winner (a score correction) changes no team, so it is never reported.
List<Match> staleDependentUpdates(List<Match> updates, List<Match> current) {
  final byId = {for (final m in current) m.id: m};
  return [
    for (final u in updates)
      if (byId[u.id] case final old?
          when isStarted(old) &&
              (old.teamA.teamId != u.teamA.teamId || old.teamB.teamId != u.teamB.teamId))
        old,
  ];
}

/// Resets the slots fed by [code] back to TBD — used when a completed
/// knockout match is reset, so nobody stays advanced on a result that no
/// longer exists. Only dependents that haven't started should be passed.
List<Match> unresolveDependentSlots(String code, List<Match> dependents) {
  return [
    for (final m in dependents)
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
        teamA: m.teamASource?.matchCode == code ? TeamRef.tbd : m.teamA,
        teamB: m.teamBSource?.matchCode == code ? TeamRef.tbd : m.teamB,
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
  ];
}
