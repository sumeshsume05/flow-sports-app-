import '../../models/match.dart';
import '../../models/standing_row.dart';
import '../../models/team.dart';

/// Generates a flat single round-robin schedule (every unordered pair once),
/// matching the source spreadsheet exactly: 6 teams -> 15 matches, 8 teams -> 28.
List<Match> generateLeagueMatches({
  required List<Team> teams,
  required String sport,
  required String category,
  required String season,
}) {
  final matches = <Match>[];
  var matchNumber = 1;
  for (var i = 0; i < teams.length; i++) {
    for (var j = i + 1; j < teams.length; j++) {
      matches.add(
        Match(
          id: '',
          sport: sport,
          category: category,
          season: season,
          stage: MatchStage.league,
          matchNumber: matchNumber,
          label: 'Match $matchNumber',
          matchCode: 'L$matchNumber',
          teamA: TeamRef(teamId: teams[i].id, name: teams[i].name),
          teamB: TeamRef(teamId: teams[j].id, name: teams[j].name),
          status: MatchStatus.upcoming,
          notifyTopic: '${sport}_$category',
        ),
      );
      matchNumber++;
    }
  }
  return matches;
}

/// Generates a round-robin among just a tied group of teams so the admin can
/// conduct a real tie-breaker instead of guessing seed order. Two tied teams
/// naturally produce a single match; three or more produce a full mini
/// round-robin among that group.
///
/// [round] identifies which tie-breaker round this is for the group (1 for
/// the first attempt). If a round itself ends in another tie among some or
/// all of the group, a fresh round is scheduled for just the still-tied
/// subset — [round] is what tells those apart later even when the exact same
/// teams end up playing a second round against each other (see
/// standings_calculator.resolveTieChain).
List<Match> generateTiebreakerMatches({
  required List<StandingRow> tiedTeams,
  required String sport,
  required String category,
  required String season,
  required int round,
}) {
  final matches = <Match>[];
  var matchNumber = 1;
  final roundLabel = round > 1 ? ' (Round $round)' : '';
  for (var i = 0; i < tiedTeams.length; i++) {
    for (var j = i + 1; j < tiedTeams.length; j++) {
      matches.add(
        Match(
          id: '',
          sport: sport,
          category: category,
          season: season,
          stage: MatchStage.tiebreaker,
          matchNumber: matchNumber,
          label: 'Tie-Breaker$roundLabel: ${tiedTeams[i].teamName} vs ${tiedTeams[j].teamName}',
          matchCode: 'TB${round}_$matchNumber',
          teamA: TeamRef(teamId: tiedTeams[i].teamId, name: tiedTeams[i].teamName),
          teamB: TeamRef(teamId: tiedTeams[j].teamId, name: tiedTeams[j].teamName),
          status: MatchStatus.upcoming,
          notifyTopic: '${sport}_$category',
          tiebreakerRound: round,
        ),
      );
      matchNumber++;
    }
  }
  return matches;
}
