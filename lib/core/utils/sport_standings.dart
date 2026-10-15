import '../../models/match.dart';
import '../../models/standing_row.dart';
import '../../models/team.dart';
import '../constants.dart';
import '../cricket/cricket_table.dart';
import 'standings_calculator.dart';

/// The league table for [sport]: each sport ranks its own way (badminton by
/// points then points scored, cricket by points, wins, net run rate and
/// head-to-head), but every screen reads the same [StandingRow]s.
List<StandingRow> computeSportStandings({
  required String sport,
  required List<Team> teams,
  required List<Match> leagueMatches,
}) =>
    sport == Sport.cricket
        ? computeCricketStandingRows(teams: teams, leagueMatches: leagueMatches)
        : computeStandings(teams: teams, leagueMatches: leagueMatches);

/// The line under a team's name in a table: "P 5 · W 4 · T 0 · L 1 · Scored 96"
/// for badminton, "P 5 · W 4 · L 1 · T 0 · NRR +1.234" for cricket.
String standingDetail(StandingRow r) {
  if (r.nrr == null) {
    return 'P ${r.played} · W ${r.won} · T ${r.tied} · L ${r.lost} · Scored ${r.pointsScored}';
  }
  final nrr = '${r.nrr! >= 0 ? '+' : '−'}${r.nrr!.abs().toStringAsFixed(3)}';
  return 'P ${r.played} · W ${r.won} · L ${r.lost} · T ${r.tied}'
      '${r.noResult > 0 ? ' · NR ${r.noResult}' : ''} · NRR $nrr';
}
