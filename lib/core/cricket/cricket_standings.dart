import 'cricket_rules.dart';
import 'match_result.dart';

/// One finished (or abandoned) league match, reduced to what the points
/// table needs. Super-over runs are never included here by construction —
/// only the two main innings.
class CricketMatchSummary {
  final String teamAId;
  final String teamBId;
  final CricketWinner winner;
  final int runsA;
  final int runsB;

  /// Legal balls each side actually faced.
  final int ballsFacedA;
  final int ballsFacedB;

  /// A side that was bowled out is charged its full quota of overs for NRR,
  /// not the overs it actually lasted.
  final bool allOutA;
  final bool allOutB;
  final int quotaBalls;
  final int ballsPerOver;

  /// False for walkovers/forfeits: points are awarded but the match doesn't
  /// feed net run rate. A no-result is never counted regardless.
  final bool countsForNrr;

  const CricketMatchSummary({
    required this.teamAId,
    required this.teamBId,
    required this.winner,
    this.runsA = 0,
    this.runsB = 0,
    this.ballsFacedA = 0,
    this.ballsFacedB = 0,
    this.allOutA = false,
    this.allOutB = false,
    this.quotaBalls = 0,
    this.ballsPerOver = 6,
    this.countsForNrr = true,
  });
}

class CricketStandingRow {
  final String teamId;
  final String teamName;
  int played = 0;
  int won = 0;
  int lost = 0;
  int tied = 0;
  int noResult = 0;
  int points = 0;
  double runsFor = 0;
  double oversFaced = 0;
  double runsAgainst = 0;
  double oversBowled = 0;

  /// Still level with a neighbour on points, wins and NRR after head-to-head
  /// — the admin settles it (tie-breaker match or draw).
  bool unresolvedTie = false;

  CricketStandingRow(this.teamId, this.teamName);

  /// (runs scored ÷ overs faced) − (runs conceded ÷ overs bowled).
  double get nrr {
    final forRate = oversFaced == 0 ? 0.0 : runsFor / oversFaced;
    final againstRate = oversBowled == 0 ? 0.0 : runsAgainst / oversBowled;
    return forRate - againstRate;
  }
}

const _nrrEpsilon = 1e-9;

/// Points table: ranked by points, then wins, then net run rate, then
/// head-to-head (only when exactly two teams are still level). Anything
/// still level after that is flagged [CricketStandingRow.unresolvedTie] and
/// left in a stable order for the admin to resolve.
List<CricketStandingRow> computeCricketStandings({
  required List<({String id, String name})> teams,
  required List<CricketMatchSummary> matches,
  required CricketRules rules,
}) {
  final rows = {for (final t in teams) t.id: CricketStandingRow(t.id, t.name)};

  for (final m in matches) {
    final a = rows[m.teamAId];
    final b = rows[m.teamBId];
    if (a == null || b == null) continue;
    a.played++;
    b.played++;
    switch (m.winner) {
      case CricketWinner.teamA:
        a.won++;
        b.lost++;
        a.points += rules.pointsWin;
      case CricketWinner.teamB:
        b.won++;
        a.lost++;
        b.points += rules.pointsWin;
      case CricketWinner.tie:
        a.tied++;
        b.tied++;
        a.points += rules.pointsTie;
        b.points += rules.pointsTie;
      case CricketWinner.noResult:
        a.noResult++;
        b.noResult++;
        a.points += rules.pointsNoResult;
        b.points += rules.pointsNoResult;
    }

    final decided = m.winner != CricketWinner.noResult;
    if (decided && m.countsForNrr && m.ballsPerOver > 0) {
      final bpo = m.ballsPerOver.toDouble();
      final facedA = (m.allOutA ? m.quotaBalls : m.ballsFacedA) / bpo;
      final facedB = (m.allOutB ? m.quotaBalls : m.ballsFacedB) / bpo;
      a.runsFor += m.runsA;
      a.oversFaced += facedA;
      a.runsAgainst += m.runsB;
      a.oversBowled += facedB;
      b.runsFor += m.runsB;
      b.oversFaced += facedB;
      b.runsAgainst += m.runsA;
      b.oversBowled += facedA;
    }
  }

  int compare(CricketStandingRow x, CricketStandingRow y) {
    if (x.points != y.points) return y.points.compareTo(x.points);
    if (x.won != y.won) return y.won.compareTo(x.won);
    if ((x.nrr - y.nrr).abs() > _nrrEpsilon) return y.nrr.compareTo(x.nrr);
    return 0;
  }

  // Stable base order: by the three table keys, then name.
  final sorted = rows.values.toList()
    ..sort((x, y) {
      final c = compare(x, y);
      return c != 0 ? c : x.teamName.compareTo(y.teamName);
    });

  // Walk runs of rows that are level on all three keys.
  final result = <CricketStandingRow>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i + 1;
    while (j < sorted.length && compare(sorted[i], sorted[j]) == 0) {
      j++;
    }
    final group = sorted.sublist(i, j);
    if (group.length == 2) {
      final winnerId = _headToHeadWinner(group[0].teamId, group[1].teamId, matches);
      if (winnerId == null) {
        for (final r in group) {
          r.unresolvedTie = true;
        }
      } else if (winnerId == group[1].teamId) {
        group.setAll(0, [group[1], group[0]]);
      }
    } else if (group.length > 2) {
      for (final r in group) {
        r.unresolvedTie = true;
      }
    }
    result.addAll(group);
    i = j;
  }
  return result;
}

/// The team that won the (single) meeting between [x] and [y], or null when
/// they didn't meet, met more than once with a split, tied, or no-resulted.
String? _headToHeadWinner(String x, String y, List<CricketMatchSummary> matches) {
  var xWins = 0;
  var yWins = 0;
  for (final m in matches) {
    final isXY = m.teamAId == x && m.teamBId == y;
    final isYX = m.teamAId == y && m.teamBId == x;
    if (!isXY && !isYX) continue;
    final winnerId = switch (m.winner) {
      CricketWinner.teamA => m.teamAId,
      CricketWinner.teamB => m.teamBId,
      _ => null,
    };
    if (winnerId == x) xWins++;
    if (winnerId == y) yWins++;
  }
  if (xWins > yWins) return x;
  if (yWins > xWins) return y;
  return null;
}
