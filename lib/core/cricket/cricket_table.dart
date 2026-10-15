import '../../models/match.dart';
import '../../models/standing_row.dart';
import '../../models/team.dart';
import 'cricket_rules.dart';
import 'cricket_standings.dart';
import 'match_result.dart';
import 'match_scoring.dart';

/// The points table for cricket, built from the matches' cached innings (no
/// ball logs are read). Points → wins → net run rate → head-to-head; whatever
/// is still level after that is flagged for the admin (a tie-breaker match).

/// One finished league match reduced to what the table needs, or null when it
/// isn't finished or a team is still unknown.
///
/// Net run rate needs both innings' totals. A finished match that lacks them
/// (e.g. a result entered without ball-by-ball scoring) still earns its
/// points but doesn't feed NRR.
CricketMatchSummary? summaryOfMatch(Match m) {
  if (!m.hasFinalResult) return null;
  final aId = m.teamA.teamId;
  final bId = m.teamB.teamId;
  if (aId == null || bId == null) return null;

  final winner = switch (m.result!) {
    MatchResult.teamA => CricketWinner.teamA,
    MatchResult.teamB => CricketWinner.teamB,
    MatchResult.tie => CricketWinner.tie,
  };

  InningsRecord? innings(String side) {
    for (final r in m.innings) {
      if (r.batting == side) return r;
    }
    return null;
  }

  final a = innings('A');
  final b = innings('B');
  final rules = m.rules;
  if (a == null || b == null || rules == null) {
    return CricketMatchSummary(
      teamAId: aId,
      teamBId: bId,
      winner: winner,
      runsA: m.scoreA ?? 0,
      runsB: m.scoreB ?? 0,
      countsForNrr: false,
    );
  }
  final bpo = rules.ballsPerOver;
  return CricketMatchSummary(
    teamAId: aId,
    teamBId: bId,
    winner: winner,
    runsA: a.runs,
    runsB: b.runs,
    ballsFacedA: a.legalBalls,
    ballsFacedB: b.legalBalls,
    allOutA: a.allOut,
    allOutB: b.allOut,
    quotaBallsA: (a.start.maxOvers ?? rules.overs) * bpo,
    quotaBallsB: (b.start.maxOvers ?? rules.overs) * bpo,
    ballsPerOver: bpo,
  );
}

/// The table as [StandingRow]s, so the existing screens, qualifier highlight
/// and bracket tie handling work unchanged: rank order from the cricket
/// rules, NRR on each row, and rows that are dead level (after head-to-head)
/// sharing a tie key so they are treated as a genuine tie.
List<StandingRow> computeCricketStandingRows({
  required List<Team> teams,
  required List<Match> leagueMatches,
}) {
  CricketRules rules = const CricketRules();
  for (final m in leagueMatches) {
    if (m.rules != null) {
      rules = m.rules!;
      break;
    }
  }
  final summaries = [
    for (final m in leagueMatches) ?summaryOfMatch(m),
  ];
  final table = computeCricketStandings(
    teams: [for (final t in teams) (id: t.id, name: t.name)],
    matches: summaries,
    rules: rules,
  );

  final rows = <StandingRow>[];
  var group = 0;
  for (var i = 0; i < table.length; i++) {
    final r = table[i];
    final prev = i > 0 ? table[i - 1] : null;
    final sameGroupAsPrev = prev != null && prev.unresolvedTie && r.unresolvedTie && cricketRowsLevel(prev, r);
    if (r.unresolvedTie && !sameGroupAsPrev) group++;
    rows.add(StandingRow(teamId: r.teamId, teamName: r.teamName)
      ..rank = i + 1
      ..played = r.played
      ..won = r.won
      ..lost = r.lost
      ..tied = r.tied
      ..noResult = r.noResult
      ..points = r.points
      ..pointsScored = r.runsFor.round()
      ..nrr = r.nrr
      ..tiedWithAnother = r.unresolvedTie
      ..tieKey = r.unresolvedTie ? 'tie$group' : 'team-${r.teamId}');
  }
  return rows;
}
