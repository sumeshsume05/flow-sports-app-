import '../../models/match.dart';
import '../../models/standing_row.dart';
import '../../models/team.dart';

/// Computes standings (Rank | Team | Played | Won | Tied | Lost | Points |
/// Scored) from league-stage matches only. Win = 2 pts, Tie = 1 pt, Loss = 0
/// pts, matching the source spreadsheet's formulas exactly. Purely in-memory
/// — never stored.
///
/// Ranking is by points first, then by total points scored (sum of the
/// team's own game score across all their matches) as the tiebreaker — the
/// same idea as run-rate/goal-difference in other sports. Only when teams are
/// level on *both* is it a genuine tie: those are surfaced via
/// [StandingRow.tiedWithAnother] rather than broken by a further guessed
/// rule. The admin screen requires manual confirmation of seed order before
/// generating a knockout bracket when any of the top 4 rows are still tied
/// at that point.
List<StandingRow> computeStandings({
  required List<Team> teams,
  required List<Match> leagueMatches,
}) {
  final rows = {for (final t in teams) t.id: StandingRow(teamId: t.id, teamName: t.name)};

  for (final m in leagueMatches) {
    if (m.result == null) continue; // not yet played
    final aId = m.teamA.teamId;
    final bId = m.teamB.teamId;
    if (aId == null || bId == null) continue;
    final a = rows[aId];
    final b = rows[bId];
    if (a == null || b == null) continue;

    a.played++;
    b.played++;
    a.pointsScored += m.scoreA ?? 0;
    b.pointsScored += m.scoreB ?? 0;

    switch (m.result!) {
      case MatchResult.tie:
        a.tied++;
        b.tied++;
        a.points += 1;
        b.points += 1;
        break;
      case MatchResult.teamA:
        a.won++;
        b.lost++;
        a.points += 2;
        break;
      case MatchResult.teamB:
        b.won++;
        a.lost++;
        b.points += 2;
        break;
    }
  }

  final sorted = rows.values.toList()
    ..sort((a, b) {
      final byPoints = b.points.compareTo(a.points);
      if (byPoints != 0) return byPoints;
      return b.pointsScored.compareTo(a.pointsScored);
    });

  for (var i = 0; i < sorted.length; i++) {
    sorted[i].rank = i + 1;
    bool sameAs(StandingRow other) =>
        other.points == sorted[i].points && other.pointsScored == sorted[i].pointsScored;
    sorted[i].tiedWithAnother =
        (i > 0 && sameAs(sorted[i - 1])) || (i < sorted.length - 1 && sameAs(sorted[i + 1]));
  }

  return sorted;
}

/// True if any genuine tie (same points AND same points scored) affects who
/// occupies the top-4 cutoff — i.e. the seeding order used for knockout
/// generation is ambiguous and needs manual admin confirmation.
bool topFourHasAmbiguousTie(List<StandingRow> standings, {int cutoffCount = 4}) {
  if (standings.length < cutoffCount) return standings.any((r) => r.tiedWithAnother);
  final cutoffIndex = cutoffCount - 1;
  final cutoffTied = standings.length > cutoffCount &&
      standings[cutoffIndex].points == standings[cutoffIndex + 1].points &&
      standings[cutoffIndex].pointsScored == standings[cutoffIndex + 1].pointsScored;
  return standings.take(cutoffCount).any((r) => r.tiedWithAnother) || cutoffTied;
}

/// Everyone who could plausibly claim a top-4 spot: the true top 4 by full
/// rank (points, then points-scored) plus anyone else still level with
/// 4th place on *both* points and points-scored — i.e. only a genuine tie
/// widens the list.
///
/// Reported bug this guards against: an earlier version filtered by
/// `points == cutoff.points` alone before checking points-scored, which
/// wrongly dropped a 3rd-place team that merely *shared* the cutoff's point
/// total but had already beaten it outright on points-scored (e.g. 3rd on
/// 5 pts/85 scored, 4th on 5 pts/69 scored — 3rd clearly qualifies and isn't
/// tied with anyone, but was being excluded entirely instead of kept ahead
/// of 4th). Taking the already-correctly-sorted top 4 unconditionally, and
/// only *adding* rows genuinely tied with the cutoff, avoids that.
///
/// [cutoffCount] generalizes this beyond exactly 4 — e.g. 2, for a league
/// section that qualifies its top 2 into a shared knockout stage alongside
/// another section's top 2 (see round_robin.generateSectionedLeagueMatches).
/// The "TopFour" name is kept for the default/common case and because it's
/// already used throughout the tests and the single-table admin screen.
List<StandingRow> candidatesForTopFour(List<StandingRow> standings, {int cutoffCount = 4}) {
  if (standings.length <= cutoffCount) return List.of(standings);
  final cutoff = standings[cutoffCount - 1];
  final extras = standings
      .skip(cutoffCount)
      .where((r) => r.points == cutoff.points && r.pointsScored == cutoff.pointsScored);
  return [...standings.take(cutoffCount), ...extras];
}

/// The *only* tie that actually decides who qualifies out of [candidates]
/// (the widened top-4-or-more list a caller like the Generate Bracket screen
/// builds once teams are tied at the cutoff): the group of teams tied with
/// whoever sits at the 4th-place cutoff (index 3). A tie entirely above that
/// — e.g. 3 teams tied for 1st-3rd, all safely qualifying regardless of their
/// mutual order — or entirely below it doesn't change who advances, so it
/// must not be treated the same as this one. Returns null when
/// `candidates.length <= 4` (no team below the cutoff is tied with it, so
/// there's no qualification ambiguity at all).
///
/// [cutoffCount] must match whatever was passed to [candidatesForTopFour] to
/// build [candidates] — see that function's doc for the section use case.
List<StandingRow>? decidingTieCluster(List<StandingRow> candidates, {int cutoffCount = 4}) {
  if (candidates.length <= cutoffCount) return null;
  final cutoffIndex = cutoffCount - 1;
  final cutoff = candidates[cutoffIndex];
  bool sameAsCutoff(StandingRow r) =>
      r.points == cutoff.points && r.pointsScored == cutoff.pointsScored;

  var start = cutoffIndex;
  // Extend left in case the place just above the cutoff (or earlier) is
  // also tied with the cutoff value, not just teams pulled in from below it.
  while (start > 0 && sameAsCutoff(candidates[start - 1])) {
    start--;
  }
  var end = cutoffIndex;
  while (end + 1 < candidates.length && sameAsCutoff(candidates[end + 1])) {
    end++;
  }
  if (end <= cutoffIndex) return null; // nobody below the cutoff is actually tied with it
  return candidates.sublist(start, end + 1);
}

/// Re-ranks a tied group using only their head-to-head tie-breaker matches
/// (same win=2/tie=1/loss=0 + pointsScored rule as the league stage), fresh —
/// this does not add onto the group's league totals. Returns new rows in
/// resolved order. If the group is still genuinely level after the
/// tie-breaker, `tiedWithAnother` stays true so the admin's manual reorder
/// remains available as a last resort.
List<StandingRow> resolveTiebreakerOrder({
  required List<StandingRow> tiedGroup,
  required List<Match> tiebreakerMatches,
}) {
  final rows = {
    for (final r in tiedGroup) r.teamId: StandingRow(teamId: r.teamId, teamName: r.teamName),
  };

  for (final m in tiebreakerMatches) {
    if (m.result == null) continue;
    final aId = m.teamA.teamId;
    final bId = m.teamB.teamId;
    if (aId == null || bId == null) continue;
    final a = rows[aId];
    final b = rows[bId];
    if (a == null || b == null) continue;

    a.played++;
    b.played++;
    a.pointsScored += m.scoreA ?? 0;
    b.pointsScored += m.scoreB ?? 0;

    switch (m.result!) {
      case MatchResult.tie:
        a.tied++;
        b.tied++;
        a.points += 1;
        b.points += 1;
        break;
      case MatchResult.teamA:
        a.won++;
        b.lost++;
        a.points += 2;
        break;
      case MatchResult.teamB:
        b.won++;
        a.lost++;
        b.points += 2;
        break;
    }
  }

  final sorted = rows.values.toList()
    ..sort((a, b) {
      final byPoints = b.points.compareTo(a.points);
      if (byPoints != 0) return byPoints;
      return b.pointsScored.compareTo(a.pointsScored);
    });

  for (var i = 0; i < sorted.length; i++) {
    bool sameAs(StandingRow other) =>
        other.points == sorted[i].points && other.pointsScored == sorted[i].pointsScored;
    sorted[i].tiedWithAnother =
        (i > 0 && sameAs(sorted[i - 1])) || (i < sorted.length - 1 && sameAs(sorted[i + 1]));
  }

  return sorted;
}

/// The outcome of walking a tied group through however many tie-breaker
/// rounds have actually been played. See [resolveTieChain].
class TieChainResult {
  /// Every member of the original cluster, best-known order: resolved
  /// members in their resolved order, with any still-contested members
  /// grouped together wherever they currently sit.
  final List<StandingRow> order;

  /// The subset still needing a tie-breaker action (unscheduled or
  /// in-progress), or null if the whole cluster is now a strict order.
  final List<StandingRow>? contestedGroup;

  /// The round number to use if scheduling a NEW tie-breaker for
  /// [contestedGroup] (irrelevant when [contestedGroup] is null).
  final int nextRound;

  /// [contestedGroup]'s most recently scheduled round of matches, if any —
  /// empty means nothing has been scheduled for it yet at all.
  final List<Match> contestedGroupMatches;

  /// Each team's own record (points/pointsScored, tie-breaker-only, never
  /// merged with their league stats) from the last tie-breaker round they
  /// actually played, for showing "Tie-breaker: 2 pts · 31 scored" next to a
  /// team without it ever being confused with their league Points column.
  final Map<String, StandingRow> lastRoundStats;

  const TieChainResult({
    required this.order,
    required this.contestedGroup,
    required this.nextRound,
    required this.contestedGroupMatches,
    required this.lastRoundStats,
  });
}

/// Walks [originalCluster] (a group tied at the qualification cutoff, by
/// league stats) through as many tie-breaker rounds as have actually been
/// played, using [allTiebreakerMatches] (every tiebreaker-stage match ever
/// recorded for the category — any round, any sub-group). A round that still
/// leaves 2+ teams level recurses into a fresh round for just that narrower,
/// still-tied subset — including the case where an entire group remains
/// tied and needs to replay each other again, which [Match.tiebreakerRound]
/// disambiguates from the round that already happened.
TieChainResult resolveTieChain({
  required List<StandingRow> originalCluster,
  required List<Match> allTiebreakerMatches,
}) {
  final order = List<StandingRow>.of(originalCluster);
  final lastRoundStats = <String, StandingRow>{};
  var currentGroup = originalCluster;
  var round = 1;

  while (true) {
    final ids = currentGroup.map((r) => r.teamId).toSet();
    final roundMatches = allTiebreakerMatches
        .where((m) =>
            m.tiebreakerRound == round &&
            ids.contains(m.teamA.teamId) &&
            ids.contains(m.teamB.teamId))
        .toList();

    if (roundMatches.isEmpty) {
      return TieChainResult(
        order: order,
        contestedGroup: currentGroup,
        nextRound: round,
        contestedGroupMatches: const [],
        lastRoundStats: lastRoundStats,
      );
    }
    if (roundMatches.any((m) => m.status != MatchStatus.completed)) {
      return TieChainResult(
        order: order,
        contestedGroup: currentGroup,
        nextRound: round,
        contestedGroupMatches: roundMatches,
        lastRoundStats: lastRoundStats,
      );
    }

    final resolved = resolveTiebreakerOrder(tiedGroup: currentGroup, tiebreakerMatches: roundMatches);
    final byId = {for (final r in currentGroup) r.teamId: r};
    for (final r in resolved) {
      lastRoundStats[r.teamId] = r;
    }
    final startIndex = order.indexWhere((r) => r.teamId == currentGroup.first.teamId);
    for (var k = 0; k < resolved.length; k++) {
      final row = byId[resolved[k].teamId]!;
      row.tiedWithAnother = resolved[k].tiedWithAnother;
      order[startIndex + k] = row;
    }

    final stillTied = resolved.where((r) => r.tiedWithAnother).map((r) => byId[r.teamId]!).toList();
    if (stillTied.length <= 1) {
      return TieChainResult(
        order: order,
        contestedGroup: null,
        nextRound: round + 1,
        contestedGroupMatches: roundMatches,
        lastRoundStats: lastRoundStats,
      );
    }
    currentGroup = stillTied;
    round++;
  }
}
