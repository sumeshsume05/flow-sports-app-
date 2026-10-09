import 'package:flow_sports_app/core/utils/manual_match.dart';
import 'package:flow_sports_app/core/utils/match_grouping.dart';
import 'package:flow_sports_app/core/utils/round_robin.dart';
import 'package:flow_sports_app/core/utils/sections.dart';
import 'package:flow_sports_app/core/utils/standings_calculator.dart';
import 'package:flow_sports_app/models/match.dart';
import 'package:flow_sports_app/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

Team team(String id, {String? section, String sport = 'badminton'}) => Team(
      id: id,
      sport: sport,
      category: 'boys',
      name: 'Team $id',
      season: '2026',
      section: section,
    );

Match match(
  String id,
  String a,
  String b, {
  MatchStage stage = MatchStage.league,
  int number = 1,
  String? section,
  String code = 'L1',
  MatchResult? result,
  int? scoreA,
  int? scoreB,
}) =>
    Match(
      id: id,
      sport: 'badminton',
      category: 'boys',
      season: '2026',
      stage: stage,
      matchNumber: number,
      label: 'M$number',
      matchCode: code,
      section: section,
      teamA: TeamRef(teamId: a, name: 'Team $a'),
      teamB: TeamRef(teamId: b, name: 'Team $b'),
      scoreA: scoreA,
      scoreB: scoreB,
      result: result,
      status: result == null ? MatchStatus.upcoming : MatchStatus.completed,
      notifyTopic: 'badminton_boys',
    );

void main() {
  group('sections helpers', () {
    test('a category is sectioned only when every team has a section', () {
      expect(isSectionedCategory([team('a', section: 'A'), team('b', section: 'B')]), isTrue);
      expect(isSectionedCategory([team('a', section: 'A'), team('b')]), isFalse);
      expect(isSectionedCategory([team('a'), team('b')]), isFalse);
      expect(isSectionedCategory(const []), isFalse);
    });

    test('a league match with no section is attributed to the section both teams share', () {
      final teams = [team('a', section: 'A'), team('b', section: 'A'), team('c', section: 'B')];
      final byId = {for (final t in teams) t.id: t};
      expect(effectiveLeagueSection(match('m', 'a', 'b'), byId), 'A');
      expect(effectiveLeagueSection(match('m', 'a', 'c'), byId), isNull); // cross-section
      expect(effectiveLeagueSection(match('m', 'a', 'b', section: 'B'), byId), 'B'); // own value wins
      expect(effectiveLeagueSection(match('m', 'a', 'zzz'), byId), isNull);
      expect(effectiveLeagueSection(match('m', 'x', 'y'), {'x': team('x'), 'y': team('y')}), isNull);
    });

    test('the old "hidden manual match" now counts in its section table', () {
      final teams = [
        team('a', section: 'A'),
        team('b', section: 'A'),
        team('c', section: 'B'),
        team('d', section: 'B'),
      ];
      final generated = generateSectionedLeagueMatches(
        teams: teams,
        sport: 'badminton',
        category: 'boys',
        season: '2026',
      );
      // A manual match from before this fix: stage league, section null.
      final legacy = match('legacy', 'a', 'b', number: 99, code: 'L99', result: MatchResult.teamA, scoreA: 21, scoreB: 10);
      final forA = leagueMatchesForSection([...generated, legacy], teams, 'A');
      expect(forA.contains(legacy), isTrue);
      expect(forA.length, 2); // the generated A-section match + the legacy one
      final rows = computeStandings(teams: teams.where((t) => t.section == 'A').toList(), leagueMatches: forA);
      final a = rows.firstWhere((r) => r.teamId == 'a');
      expect(a.played, 1);
      expect(a.points, 2);
      expect(leagueMatchesForSection([...generated, legacy], teams, 'B').contains(legacy), isFalse);
    });
  });

  group('checkManualMatch', () {
    final flat = [team('a'), team('b'), team('c')];
    final sectioned = [team('a', section: 'A'), team('b', section: 'A'), team('c', section: 'B')];

    test('needs two different teams', () {
      expect(checkManualMatch(type: ManualMatchType.league, teamA: null, teamB: flat[1], teams: flat, existing: const []).error,
          'Choose two different teams.');
      expect(checkManualMatch(type: ManualMatchType.friendly, teamA: flat[0], teamB: flat[0], teams: flat, existing: const []).ok,
          isFalse);
    });

    test('league match in a flat category is fine and has no section', () {
      final c = checkManualMatch(type: ManualMatchType.league, teamA: flat[0], teamB: flat[1], teams: flat, existing: const []);
      expect(c.ok, isTrue);
      expect(c.section, isNull);
      expect(c.duplicateOf, isNull);
    });

    test('league match in a sectioned category: same section gets that section', () {
      final c = checkManualMatch(
          type: ManualMatchType.league, teamA: sectioned[0], teamB: sectioned[1], teams: sectioned, existing: const []);
      expect(c.ok, isTrue);
      expect(c.section, 'A');
    });

    test('league match across sections is blocked with a clear message', () {
      final c = checkManualMatch(
          type: ManualMatchType.league, teamA: sectioned[0], teamB: sectioned[2], teams: sectioned, existing: const []);
      expect(c.ok, isFalse);
      expect(c.error, contains('Team a is in Section A but Team c is in Section B'));
      expect(c.error, contains('Friendly'));
    });

    test('a friendly across sections is always allowed and never gets a section', () {
      final c = checkManualMatch(
          type: ManualMatchType.friendly, teamA: sectioned[0], teamB: sectioned[2], teams: sectioned, existing: const []);
      expect(c.ok, isTrue);
      expect(c.section, isNull);
    });

    test('a second league match between the same teams is reported (either order), friendlies are not', () {
      final existing = [match('m1', 'b', 'a')];
      final dup = checkManualMatch(
          type: ManualMatchType.league, teamA: flat[0], teamB: flat[1], teams: flat, existing: existing);
      expect(dup.ok, isTrue); // never blocks
      expect(dup.duplicateOf?.id, 'm1');
      final friendly = checkManualMatch(
          type: ManualMatchType.friendly, teamA: flat[0], teamB: flat[1], teams: flat, existing: existing);
      expect(friendly.duplicateOf, isNull);
      // A friendly between the same teams doesn't count as a league duplicate either.
      final friendlyExisting = [match('f1', 'a', 'b', stage: MatchStage.friendly, code: 'F1')];
      expect(
          checkManualMatch(type: ManualMatchType.league, teamA: flat[0], teamB: flat[1], teams: flat, existing: friendlyExisting)
              .duplicateOf,
          isNull);
    });
  });

  group('buildManualMatch', () {
    final a = team('a');
    final b = team('b');

    Match build(ManualMatchType t, {String label = '', List<Match> existing = const [], String? section}) =>
        buildManualMatch(
          type: t,
          teamA: a,
          teamB: b,
          label: label,
          sport: 'badminton',
          category: 'boys',
          season: '2026',
          existing: existing,
          section: section,
        );

    test('league match: next league number, default label, L code', () {
      final m = build(ManualMatchType.league, existing: [match('1', 'a', 'b', number: 4), match('2', 'a', 'b', number: 2)]);
      expect(m.stage, MatchStage.league);
      expect(m.matchNumber, 5);
      expect(m.matchCode, 'L5');
      expect(m.label, 'Extra Match');
      expect(m.section, isNull);
      expect(m.teamA.teamId, 'a');
      expect(m.status, MatchStatus.upcoming);
    });

    test('sectioned league match carries its section in the code, like generated ones', () {
      final m = build(ManualMatchType.league, section: 'B', existing: [match('1', 'a', 'b', number: 6, section: 'A')]);
      expect(m.section, 'B');
      expect(m.matchCode, 'B-L7');
    });

    test('friendly: its own F numbering, never touches league numbering, never has a section', () {
      final existing = [match('1', 'a', 'b', number: 9)];
      final first = build(ManualMatchType.friendly, existing: existing, section: 'A');
      expect(first.stage, MatchStage.friendly);
      expect(first.matchNumber, 1);
      expect(first.matchCode, 'F1');
      expect(first.label, 'Friendly');
      expect(first.section, isNull);
      final second = build(ManualMatchType.friendly, label: '  Warm-up  ', existing: [...existing, first]);
      expect(second.matchNumber, 2);
      expect(second.label, 'Warm-up');
    });
  });

  group('friendly matches never count', () {
    test('stage round-trips, and unknown stages still fall back to league', () {
      expect(stageFromString('friendly'), MatchStage.friendly);
      expect(stageFromString('league'), MatchStage.league);
      expect(stageFromString('something-new'), MatchStage.league); // legacy fallback (old apps)
    });

    test('a friendly is excluded by the stage filters standings/bracket/schedule use', () {
      final all = [
        match('l', 'a', 'b'),
        match('f', 'a', 'b', stage: MatchStage.friendly, code: 'F1', result: MatchResult.teamA, scoreA: 21, scoreB: 5),
      ];
      final league = all.where((m) => m.stage == MatchStage.league).toList();
      final rows = computeStandings(teams: [team('a'), team('b')], leagueMatches: league);
      expect(rows.every((r) => r.played == 0 && r.points == 0), isTrue);
    });
  });

  group('grouping', () {
    test('friendlies get their own group after the league', () {
      final groups = groupMatchesForDisplay([
        match('l', 'a', 'b'),
        match('f', 'a', 'c', stage: MatchStage.friendly, code: 'F1'),
      ]);
      expect(groups.map((g) => g.title), ['League (Round 1)', 'Friendly matches (not counted)']);
      expect(groups.last.matches.single.id, 'f');
    });

    test('a league match without a section is shown, not hidden, in a sectioned league', () {
      final sectionedMatch = match('s', 'a', 'b', section: 'A');
      final legacy = match('legacy', 'a', 'c', number: 9, code: 'L9');
      final groups = groupMatchesForDisplay([sectionedMatch, legacy]);
      expect(groups.map((g) => g.title), ['League — Section A', 'League — Other matches']);
      expect(groups.last.matches.single.id, 'legacy');
      // Every match appears exactly once.
      expect(groups.expand((g) => g.matches).length, 2);
    });

    test('every match appears exactly once across all stages', () {
      final all = [
        match('1', 'a', 'b'),
        match('2', 'a', 'b', stage: MatchStage.knockout, code: 'KO1'),
        match('3', 'a', 'b', stage: MatchStage.tiebreaker, code: 'TB1_1'),
        match('4', 'a', 'b', stage: MatchStage.friendly, code: 'F1'),
      ];
      expect(groupMatchesForDisplay(all).expand((g) => g.matches).length, all.length);
    });
  });
}
