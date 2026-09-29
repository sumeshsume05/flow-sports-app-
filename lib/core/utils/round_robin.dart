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

/// Generates a round-robin *within each league section separately* — teams
/// in Section A only ever play other Section A teams, Section B only other
/// Section B teams, and so on. Used when a category qualifies a fixed number
/// of teams out of each section into a shared knockout stage (rather than
/// one flat table for the whole category — see [generateLeagueMatches] for
/// that simpler case).
///
/// [teams] must ALL have a non-null [Team.section] — the caller (the
/// Generate Schedule screen) is responsible for checking that first and
/// blocking with a clear message otherwise, the same way it already blocks
/// on existing matches. Sections are processed in alphabetical order purely
/// for a stable, predictable match numbering; it has no bearing on seeding.
List<Match> generateSectionedLeagueMatches({
  required List<Team> teams,
  required String sport,
  required String category,
  required String season,
}) {
  final bySection = <String, List<Team>>{};
  for (final t in teams) {
    final section = t.section;
    assert(section != null, 'generateSectionedLeagueMatches requires every team to have a section');
    bySection.putIfAbsent(section!, () => []).add(t);
  }

  final sections = bySection.keys.toList()..sort();
  final matches = <Match>[];
  var matchNumber = 1;
  for (final section in sections) {
    final sectionTeams = bySection[section]!;
    for (var i = 0; i < sectionTeams.length; i++) {
      for (var j = i + 1; j < sectionTeams.length; j++) {
        matches.add(
          Match(
            id: '',
            sport: sport,
            category: category,
            season: season,
            stage: MatchStage.league,
            matchNumber: matchNumber,
            label: 'Section $section — Match $matchNumber',
            matchCode: '$section-L$matchNumber',
            section: section,
            teamA: TeamRef(teamId: sectionTeams[i].id, name: sectionTeams[i].name),
            teamB: TeamRef(teamId: sectionTeams[j].id, name: sectionTeams[j].name),
            status: MatchStatus.upcoming,
            notifyTopic: '${sport}_$category',
          ),
        );
        matchNumber++;
      }
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
/// [section] tags the tie-breaker as belonging to one league section (see
/// [generateSectionedLeagueMatches]) purely for a clearer label and
/// matchCode when two sections both happen to have a tie at the same round
/// — resolveTieChain itself never needs this, since it already scopes by
/// the tied teams' own ids, which can't collide across sections.
List<Match> generateTiebreakerMatches({
  required List<StandingRow> tiedTeams,
  required String sport,
  required String category,
  required String season,
  required int round,
  String? section,
}) {
  final matches = <Match>[];
  var matchNumber = 1;
  final roundLabel = round > 1 ? ' (Round $round)' : '';
  final sectionLabel = section == null ? '' : 'Section $section — ';
  final sectionCode = section == null ? '' : '$section-';
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
          label:
              '${sectionLabel}Tie-Breaker$roundLabel: ${tiedTeams[i].teamName} vs ${tiedTeams[j].teamName}',
          matchCode: '${sectionCode}TB${round}_$matchNumber',
          section: section,
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
